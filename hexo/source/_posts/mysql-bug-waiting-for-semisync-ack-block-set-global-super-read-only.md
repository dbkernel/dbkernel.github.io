---
title: 问题分析 | 为什么主库Waiting for semi-sync ACK from slave会阻塞set global super_read_only=ON的执行
date: 2023-12-03 21:33:21
categories:
  - MySQL
tags:
  - MySQL
  - 复制
toc: true
---

**作者：卢文双 资深数据库内核研发**

> **本文首发于 2023-12-03 21:33:21**
>
> https://dbkernel.com

## 问题描述

为什么主库上有`Waiting for semi-sync ACK from slave`的时候，执行`set global super_read_only=ON`会导致等待全局读锁？

<!-- more -->

## 问题复现

MySQL 主从高可用集群，semi-sync 超时无限大：

```sql
set global rpl_semi_sync_master_timeout=10000000000;
```

在主从 semi-sync 复制正常运行时，`kill -9 从库mysqld`进程，之后在主库执行的新事务会处于`Waiting for semi-sync ACK from slave`状态。

一、如果主库执行的是`flush xxx`等非事务型语句，则不会阻塞`set global super_read_only=on`的执行：

![](./no-block.png "未阻塞的情况")

二、如果主库执行的是事务型的语句，比如`create database`、`insert into`，则会阻塞`set global super_read_only=on`的执行：

![](./has-block.png "阻塞的情况")

## 问题分析

### 初步分析

由于`set global super_read_only=on`修改变量时会调用`fix_super_read_only`函数，进而调用`thd->global_read_lock.lock_global_read_lock(thd)`，此时，由于全局读锁被其他事务型语句占用，导致阻塞：

```c++
/**
Setting super_read_only to ON triggers read_only to also be set to ON.
*/
static Sys_var_bool Sys_super_readonly(
    "super_read_only",
    "Make all non-temporary tables read-only, with the exception for "
    "replication applier threads.  Users with the SUPER privilege are "
    "affected, unlike read_only.  Setting super_read_only to ON "
    "also sets read_only to ON.",
    GLOBAL_VAR(super_read_only), CMD_LINE(OPT_ARG), DEFAULT(false),
    NO_MUTEX_GUARD, NOT_IN_BINLOG, ON_CHECK(nullptr),
    ON_UPDATE(fix_super_read_only));

static bool fix_super_read_only(sys_var *, THD *thd, enum_var_type type) {
  DBUG_TRACE;

  /* return if no changes: */
  if (super_read_only == opt_super_readonly) return false;

  /* return immediately if turning super_read_only OFF: */
  if (super_read_only == false) {
    opt_super_readonly = false;

    // Do this last as it temporarily releases the global sys-var lock.
    event_scheduler_restart(thd);

    return false;
  }
  bool result = true;
  bool new_super_read_only =
      super_read_only; /* make a copy before releasing a mutex */

  /* set read_only to ON if it is OFF, letting fix_read_only()
     handle its own locking needs
  */
  if (!opt_readonly) {
    read_only = true;
    if ((result = fix_read_only(nullptr, thd, type))) goto end;
  }

  /* if we already have global read lock, set super_read_only
     and return immediately:
  */
  if (thd->global_read_lock.is_acquired()) {
    opt_super_readonly = super_read_only;
    return false;
  }

  /* now we're turning ON super_read_only: */
  super_read_only = opt_super_readonly;
  mysql_mutex_unlock(&LOCK_global_system_variables);

  if (thd->global_read_lock.lock_global_read_lock(thd)) // ====> 阻塞位置
    goto end_with_mutex_unlock;

  if ((result = thd->global_read_lock.make_global_read_lock_block_commit(thd)))
    goto end_with_read_lock;
  opt_super_readonly = new_super_read_only;
  result = false;

end_with_read_lock:
  /* Release the lock */
  thd->global_read_lock.unlock_global_read_lock(thd);
end_with_mutex_unlock:
  mysql_mutex_lock(&LOCK_global_system_variables);
end:
  super_read_only = opt_super_readonly;
  return result;
}
```

`lock_global_read_lock`函数定义如下：

```c++
/**
  Take global read lock, wait if there is protection against lock.

  If the global read lock is already taken by this thread, then nothing is done.

  See also "Handling of global read locks" above.

  @param thd     Reference to thread.

  @retval False  Success, global read lock set, commits are NOT blocked.
  @retval True   Failure, thread was killed.
*/

bool Global_read_lock::lock_global_read_lock(THD *thd) {
  DBUG_TRACE;

  if (!m_state) {
    MDL_request mdl_request;

    assert(!thd->mdl_context.owns_equal_or_stronger_lock(MDL_key::GLOBAL, "",
                                                         "", MDL_SHARED));
    MDL_REQUEST_INIT(&mdl_request, MDL_key::GLOBAL, "", "", MDL_SHARED, // ====> 注意此处是 MDL_key::GLOBAL，且是共享锁
                     MDL_EXPLICIT);

    /* Increment static variable first to signal innodb memcached server
       to release mdl locks held by it */
    Global_read_lock::m_atomic_active_requests++;
    if (thd->mdl_context.acquire_lock(&mdl_request,
                                      thd->variables.lock_wait_timeout)) {
      Global_read_lock::m_atomic_active_requests--;
      return true;
    }

    m_mdl_global_shared_lock = mdl_request.ticket;
    m_state = GRL_ACQUIRED;
  }
  /*
    We DON'T set global_read_lock_blocks_commit now, it will be set after
    tables are flushed (as the present function serves for FLUSH TABLES WITH
    READ LOCK only). Doing things in this order is necessary to avoid
    deadlocks (we must allow COMMIT until all tables are closed; we should not
    forbid it before, or we can have a 3-thread deadlock if 2 do SELECT FOR
    UPDATE and one does FLUSH TABLES WITH READ LOCK).
  */
  return false;
}
```

可见获取全局读锁主要指的是调用`thd->mdl_context.acquire_lock`函数 。

> 调用 Global_read_lock::lock_global_read_lock 函数的其他位置与事务提交没太大关系，应与此无关。

### 继续分析

那问题就在于事务型语句是否会获取 MDL 锁。

跟踪代码，发现一处可疑点：`ha_commit_trans`函数（位于`sql/handler.cc`文件）中的如下调用：

```c++
    DBUG_EXECUTE_IF("dbug.enabled_commit", {
      const char act[] = "now signal Reached wait_for signal.commit_continue";
      assert(!debug_sync_set_action(thd, STRING_WITH_LEN(act)));
    };);
    DEBUG_SYNC(thd, "ha_commit_trans_before_acquire_commit_lock");
    if (rw_trans && !ignore_global_read_lock) {
      /*
        Acquire a metadata lock which will ensure that COMMIT is blocked
        by an active FLUSH TABLES WITH READ LOCK (and vice versa:
        COMMIT in progress blocks FTWRL).

        We allow the owner of FTWRL to COMMIT; we assume that it knows
        what it does.
      */
      MDL_REQUEST_INIT(&mdl_request, MDL_key::COMMIT, "", "", // ====> 注意此处是 MDL_key::COMMIT，且是意向排他锁
                       MDL_INTENTION_EXCLUSIVE, MDL_EXPLICIT);

      DBUG_PRINT("debug", ("Acquire MDL commit lock"));
      if (thd->mdl_context.acquire_lock(&mdl_request,
                                        thd->variables.lock_wait_timeout)) {
        ha_rollback_trans(thd, all);
        return 1;
      }
      release_mdl = true;

      DEBUG_SYNC(thd, "ha_commit_trans_after_acquire_commit_lock");
    }
```

跟踪一条`create database`事务，堆栈如下：

```c++
#0  MDL_context::acquire_lock (this=0xaaaab5e21090, mdl_request=0xffffe021c4c0, lock_wait_timeout=31536000) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/mdl.cc:3383
#1  0x0000aaaaae48224c in ha_commit_trans (thd=0xaaaab5e20d00, all=true, ignore_global_read_lock=false) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/handler.cc:1627
#2  0x0000aaaaae24a3f0 in trans_commit (thd=0xaaaab5e20d00, ignore_global_read_lock=false) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/transaction.cc:246
#3  0x0000aaaaae0121c0 in mysql_create_db (thd=0xaaaab5e20d00, db=0xffffb401e8c8 "db6", create_info=0xffffe021d030) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_db.cc:498
#4  0x0000aaaaae095ccc in mysql_execute_command (thd=0xaaaab5e20d00, first_level=true) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_parse.cc:3761
#5  0x0000aaaaae09a1d4 in dispatch_sql_command (thd=0xaaaab5e20d00, parser_state=0xffffe021e308) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_parse.cc:5278
#6  0x0000aaaaae0911e4 in dispatch_command (thd=0xaaaab5e20d00, com_data=0xffffe021ec20, command=COM_QUERY) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_parse.cc:1960
#7  0x0000aaaaae08f5ec in do_command (thd=0xaaaab5e20d00) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_parse.cc:1363
#8  0x0000ffffe9245c4c in threadpool_process_request (thd=0xaaaab5e20d00) at /home/wslu/work/mysql/cmss-mac-mysql-server/plugin/thread_pool/threadpool_common.cc:251
#9  0x0000ffffe924ba10 in handle_event (connection=0xaaaab5e1b3d0) at /home/wslu/work/mysql/cmss-mac-mysql-server/plugin/thread_pool/threadpool_unix.cc:1528
#10 0x0000ffffe924be48 in worker_main (param=0xffffe926bd00 <all_groups+512>) at /home/wslu/work/mysql/cmss-mac-mysql-server/plugin/thread_pool/threadpool_unix.cc:1621
#11 0x0000aaaab01956f0 in pfs_spawn_thread (arg=0xaaaab5e12550) at /home/wslu/work/mysql/cmss-mac-mysql-server/storage/perfschema/pfs.cc:2942
#12 0x0000fffff767d5c8 in start_thread (arg=0x0) at ./nptl/pthread_create.c:442
#13 0x0000fffff76e5d1c in thread_start () at ../sysdeps/unix/sysv/linux/aarch64/clone.S:79
```

可见确实获取了 MDL 锁。

那么，问题来了，**为何连续两条【create database db4; create database db5;】语句都能成功获取 MDL 锁，而 fix_super_read_only 函数中获取 MDL 锁时却会阻塞呢**？

在 MDL 中 MDL_KEY 按照 namespace+DB+OBJECT_NAME 的方式进行表示，所谓的 namespace 也比较重要，**下面是 namespace 的分类（也就是 MDL_key 的类型）**：

先来看`MDL_key`的类型：

```c++
  /**
    Object namespaces.
    Sic: when adding a new member to this enum make sure to
    update m_namespace_to_wait_state_name array in mdl.cc!

    Different types of objects exist in different namespaces
     - GLOBAL is used for the global read lock.
     - BACKUP_LOCK is to block any operations that could cause
       inconsistent backup. Such operations are most DDL statements,
       and some administrative statements.
     - TABLESPACE is for tablespaces.
     - SCHEMA is for schemas (aka databases).
     - TABLE is for tables and views.
     - FUNCTION is for stored functions.
     - PROCEDURE is for stored procedures.
     - TRIGGER is for triggers.
     - EVENT is for event scheduler events.
     - COMMIT is for enabling the global read lock to block commits.
     - USER_LEVEL_LOCK is for user-level locks.
     - LOCKING_SERVICE is for the name plugin RW-lock service
     - SRID is for spatial reference systems
     - ACL_CACHE is for ACL caches
     - COLUMN_STATISTICS is for column statistics, such as histograms
     - RESOURCE_GROUPS is for resource groups.
     - FOREIGN_KEY is for foreign key names.
     - CHECK_CONSTRAINT is for check constraint names.
    Note that requests waiting for user-level locks get special
    treatment - waiting is aborted if connection to client is lost.
  */
  enum enum_mdl_namespace {
    GLOBAL = 0,
    BACKUP_LOCK,
    TABLESPACE,
    SCHEMA,
    TABLE,
    FUNCTION,
    PROCEDURE,
    TRIGGER,
    EVENT,
    COMMIT,
    USER_LEVEL_LOCK,
    LOCKING_SERVICE,
    SRID,
    ACL_CACHE,
    COLUMN_STATISTICS,
    RESOURCE_GROUPS,
    FOREIGN_KEY,
    CHECK_CONSTRAINT,
    /* This should be the last ! */
    NAMESPACE_END
  };
```

其中：

- `GLOBAL` is used for the global read lock.
- `COMMIT` is for enabling the global read lock to block commits.

根据「八怪」的文章《[MySQL：理解 MDL Lock](https://juejin.cn/post/7238814783597723704 "MySQL：理解MDL Lock - 掘金 (juejin.cn)")》的说法：

- "Waiting for table metadata lock"：通常就是 namespace TABLE 级别的 MDL Lock。
- "Waiting for global read lock"：通常就是 namespace GLOBAL 级别的 MDL Lock，通常和 flush table with read lock 有关。
- "Waiting for commit lock"：**通常就是 namespace COMMIT 级别的 MDL Lock，通常和 flush table with read lock 有关**。

如 flush table with read lock 会获取`namespace space:GLOBAL type:S`和`namespace space:COMMIT type:S`的 MDL Lock。它包含**GLOBAL, COMMIT, TABLESPACE 和 SCHEMA**。

但是**MDL_key::GLOBAL 与 MDL_key::COMMIT 之间是不存在冲突的，此路不通**。

### 换一种思路

是否在执行 INSERT/UPDATE 等事务语句期间有获取 MDL_key::GLOBAL 呢？

继续调试，重新模拟执行`insert into`语句时出现 Waiting semi-sync ACK 的情况，跟踪代码如下：

```c++
#0  open_table (thd=0xaaaab5e633b0, table_list=0xffffd8004c98, ot_ctx=0xffffb0395b60) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_base.cc:3057
#1  0x0000aaaaadf826d0 in open_and_process_table (thd=0xaaaab5e633b0, lex=0xaaaab5e66710, tables=0xffffd8004c98, counter=0xaaaab5e66768, prelocking_strategy=0xffffb0395be8, has_prelocking_list=false, ot_ctx=0xffffb0395b60) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_base.cc:5051
#2  0x0000aaaaadf84060 in open_tables (thd=0xaaaab5e633b0, start=0xffffb0395bd0, counter=0xaaaab5e66768, flags=0, prelocking_strategy=0xffffb0395be8) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_base.cc:5854
#3  0x0000aaaaadf85b14 in open_tables_for_query (thd=0xaaaab5e633b0, tables=0xffffd8004c98, flags=0) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_base.cc:6736
#4  0x0000aaaaae11c248 in Sql_cmd_dml::prepare (this=0xffffd8005300, thd=0xaaaab5e633b0) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_select.cc:372
#5  0x0000aaaaae11cc10 in Sql_cmd_dml::execute (this=0xffffd8005300, thd=0xaaaab5e633b0) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_select.cc:533
#6  0x0000aaaaae095404 in mysql_execute_command (thd=0xaaaab5e633b0, first_level=true) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_parse.cc:3578
#7  0x0000aaaaae09a1d4 in dispatch_sql_command (thd=0xaaaab5e633b0, parser_state=0xffffb0397308) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_parse.cc:5278
#8  0x0000aaaaae0911e4 in dispatch_command (thd=0xaaaab5e633b0, com_data=0xffffb0397c20, command=COM_QUERY) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_parse.cc:1960
#9  0x0000aaaaae08f5ec in do_command (thd=0xaaaab5e633b0) at /home/wslu/work/mysql/cmss-mac-mysql-server/sql/sql_parse.cc:1363
#10 0x0000ffffe9245c4c in threadpool_process_request (thd=0xaaaab5e633b0) at /home/wslu/work/mysql/cmss-mac-mysql-server/plugin/thread_pool/threadpool_common.cc:251
#11 0x0000ffffe924ba10 in handle_event (connection=0xaaaab5e67df0) at /home/wslu/work/mysql/cmss-mac-mysql-server/plugin/thread_pool/threadpool_unix.cc:1528
#12 0x0000ffffe924be48 in worker_main (param=0xffffe926bb00 <all_groups>) at /home/wslu/work/mysql/cmss-mac-mysql-server/plugin/thread_pool/threadpool_unix.cc:1621
#13 0x0000aaaab01956f0 in pfs_spawn_thread (arg=0xaaaab5e69a90) at /home/wslu/work/mysql/cmss-mac-mysql-server/storage/perfschema/pfs.cc:2942
#14 0x0000fffff767d5c8 in start_thread (arg=0x0) at ./nptl/pthread_create.c:442
#15 0x0000fffff76e5d1c in thread_start () at ../sysdeps/unix/sysv/linux/aarch64/clone.S:79
```

在`open_table(THD *thd, TABLE_LIST *table_list, Open_table_context *ot_ctx)`函数中有申请 IX 模式的 MDL_key::GLOBAL 锁：

```c++
     if (thd->global_read_lock.can_acquire_protection()) return true;

      MDL_REQUEST_INIT(&protection_request, MDL_key::GLOBAL, "", "",
                       MDL_INTENTION_EXCLUSIVE, MDL_STATEMENT); // ====> 意向排他的 GLOBAL 锁

      /*
        Install error handler which if possible will convert deadlock error
        into request to back-off and restart process of opening tables.

        Prefer this context as a victim in a deadlock when such a deadlock
        can be easily handled by back-off and retry.
      */
      thd->push_internal_handler(&mdl_deadlock_handler);
      thd->mdl_context.set_force_dml_deadlock_weight(ot_ctx->can_back_off());

      bool result = thd->mdl_context.acquire_lock(&protection_request,
                                                  ot_ctx->get_timeout()); // ====> 加锁
```

而`set global super_read_only=ON`申请的 S 模式的 MDL_key::GLOBAL 锁，查阅手册（[MySQL :: MySQL 8.0 Reference Manual :: 15.7.1 InnoDB Locking](https://dev.mysql.com/doc/refman/8.0/en/innodb-locking.html "MySQL :: MySQL 8.0 Reference Manual :: 15.7.1 InnoDB Locking")），IX 与 S 模式是冲突的：

> 下表是表级锁，全局锁应该也是如此：

|      | `X`      | `IX`       | `S`        | `IS`       |
| ---- | -------- | ---------- | ---------- | ---------- |
| `X`  | Conflict | Conflict   | Conflict   | Conflict   |
| `IX` | Conflict | Compatible | Conflict   | Compatible |
| `S`  | Conflict | Conflict   | Compatible | Compatible |
| `IS` | Conflict | Compatible | Compatible | Compatible |

## 结论

MySQL 8.0 `open_tables`函数 会加 `MDL_key::GLOBAL`锁，IX 模式，而 `set global super_read_only=on` 也会加 `MDL_key::GLOBAL`锁，S 模式，这两种模式是冲突的，

而`insert into`语句在 Semi-Sync 的 AFTER_SYNC 模式下是先等待从库接收完成后自己才提交，在提交后才 close table、释放`MDL_key::GLOBAL`锁。

由于处于`Waiting for semi-sync ACK from slave`状态的事务还未提交，也就未释放`MDL_key::GLOBAL`锁，因此，才会阻塞`set global super_read_only=on`语句。

> 实际上，**DELTE/UPDATE/INSERT/FOR UPDATE 等 DML 操作会在 GLOBAL 上加 IX 锁，然后才会在本对象上加锁。而 DDL 语句至少会在 GLOBAL 上加 IX 锁，对象所属 SCHEMA 上加 IX 锁，本对象加锁**。

---

欢迎关注我的微信公众号【数据库内核】：分享主流开源数据库和存储引擎相关技术。

<img src="https://dbkernel-1306518848.cos.ap-beijing.myqcloud.com/wechat/my-wechat-official-account.png" width="400" height="400" alt="欢迎关注公众号数据库内核" align="center"/>

| 标题                 | 网址                                                  |
| -------------------- | ----------------------------------------------------- |
| GitHub               | https://dbkernel.github.io                            |
| 知乎                 | https://www.zhihu.com/people/dbkernel/posts           |
| 思否（SegmentFault） | https://segmentfault.com/u/dbkernel                   |
| 掘金                 | https://juejin.im/user/5e9d3ed251882538083fed1f/posts |
| CSDN                 | https://blog.csdn.net/dbkernel                        |
| 博客园（cnblogs）    | https://www.cnblogs.com/dbkernel                      |
