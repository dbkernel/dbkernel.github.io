---
title: 问题定位 | PostgreSQL 报错 requested WAL segment has already been removed
date: 2016-04-25 20:59:52
categories:
- PostgreSQL
tags:
- PostgreSQL
- 问题定位
- WAL
toc: true
---

<!-- more -->


# 问题描述

在使用配置了热备的 PostgreSQL 数据库时，在执行大量事务时，尤其是一个需要插入几千万条数据的 insert 事务时（典型的做法是持续 `insert into t select * from t;`），后台 csv log 中报错如下：

```verilog
2015-07-01 13:25:29.430 CST,,,27738,,51d112c8.6c5a,1,,2015-07-01 13:25:28 CST,,0,LOG,00000,"streaming replication successfully connected to primary",,,,,,,,"libpqrcv_connect, libpqwalreceiver.c:171",""
2015-07-01 13:25:29.430 CST,,,27738,,51d112c8.6c5a,2,,2015-07-01 13:25:28 CST,,0,FATAL,XX000,"could not receive data from WAL stream:FATAL:  requested WAL segment 0000000800002A0000000000 has already been removed
",,,,,,,,"libpqrcv_receive, libpqwalreceiver.c:389",""
```

# 问题分析

根据报错信息分析，推测是主库大事务产生了大量 xlog，这是因为 PostgreSQL 在执行事务过程中，直到提交时才会发送到备库。

由于该事务需要执行的时间过长，超过了 checkpoint 的默认间隔，所以导致有的 xlog 还未发送到备库却被 remove 掉了。

# 解决方法

要解决该问题，一般可用的方案有：

## 方法一：调大参数 wal_keep_segments 的值

将 GUC 参数 `wal_keep_segments` 设大一些，比如设置为2000，而每个 segment 默认值为16MB，就相当于有 32000MB，那么，最多可保存 30GB 的 xlog ，超过则删除最早的 xlog 。

不过，**该方法并不能从根本上解决该问题**。毕竟，在生产环境中或TPCC等测试灌数时，如果某条事务需要插入几十亿条记录，有可能还是会出现该问题。

## 方法二：启用归档

归档，就是将未发送到备库的 xlog 备份到某个目录下，待重启数据库时再将其恢复到备库中去。

GUC 参数设置示例如下：

- 主库的 postgresql.conf 文件中：
```ini
wal_level = hot_standby
archive_mode = on
archive_command = 'rsync -zaq %p postgres@pg-slave:/var/lib/pgsql/wal_restore/%f && test ! -f /var/lib/pgsql/backup/wal_archive/%f && cp %p /var/lib/pgsql/backup/wal_archive/'
archive_timeout = 300
max_wal_senders = 5
wal_keep_segments = 0
```

- 备库的 postgresql.conf 文件中：
```ini
wal_level = hot_standby
archive_mode = on
archive_command = 'test ! -f /var/lib/pgsql/backup/wal_archive/%f && cp -i %p /var/lib/pgsql/backup/wal_archive/%f < /dev/null'
hot_standby = on
wal_keep_segments = 1
```

- 备库的 recovery.conf 文件中：
```ini
standby_mode = 'on'
primary_conninfo = 'host=pg-master port=5432 user=replicator'
restore_command = 'cp /var/lib/psql/wal_restore/%f %p'
archive_cleanup_command = 'pg_archivecleanup /var/lib/pgsql/wal_restore/ %r'
```

## 方法三：启用 replication slot（PG 9.4 开始支持）

**该方法是根本解决方法，不会造成xlog的丢失**。也就是说，在 xlog 被拷贝到从库之前，主库不会删除。

**启用方法：**

1. 在 postgresql.conf 中添加：
```ini
max_replication_slots = 2000
```

2. 在拷贝到备库之前，主库要创建一个 slot：
```sql
postgres=# SELECT * FROM pg_create_physical_replication_slot('node_a_slot');
  slot_name  | xlog_position
-------------+---------------
 node_a_slot |

postgres=# SELECT * FROM pg_replication_slots;
  slot_name  | slot_type | datoid | database | active | xmin | restart_lsn
-------------+-----------+--------+----------+--------+------+-------------
 node_a_slot | physical  |        |          | f      |      |
(1 row)
```

3. 在备库的 recovery.conf 文件中添加一行：
```ini
standby_mode = 'on'
primary_conninfo = 'host=192.168.4.225 port=19000 user=wslu password=xxxx'
primary_slot_name = 'node_a_slot'
```

# 参考

https://www.postgresql.org/docs/9.4/static/runtime-config-replication.html

https://www.postgresql.org/docs/9.4/static/warm-standby.html#CASCADING-REPLICATION
http://blog.2ndquadrant.com/postgresql-9-4-slots/

http://grokbase.com/t/postgresql/pgsql-general/13654jchy3/trouble-with-replication

http://stackoverflow.com/questions/28201475/how-do-i-fix-a-postgresql-9-3-slave-that-cannot-keep-up-with-the-master


----

欢迎关注我的微信公众号【MySQL数据库技术】。

<img src="https://dbkernel-1306518848.cos.ap-beijing.myqcloud.com/wechat/my-wechat-official-account.png" width="400" height="400" alt="MySQL数据库技术" align="left"/>


| 标题                 | 网址                                                  |
| -------------------- | ----------------------------------------------------- |
| GitHub               | https://dbkernel.github.io                            |
| 知乎                 | https://www.zhihu.com/people/dbkernel/posts           |
| 思否（SegmentFault） | https://segmentfault.com/u/dbkernel                   |
| 掘金                 | https://juejin.im/user/5e9d3ed251882538083fed1f/posts |
| 开源中国（oschina）  | https://my.oschina.net/dbkernel                       |
| 博客园（cnblogs）    | https://www.cnblogs.com/dbkernel                      |


