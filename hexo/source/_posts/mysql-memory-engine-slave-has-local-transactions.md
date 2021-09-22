---
title: 引擎特性 | MySQL MEMORY(HEAP) 存储引擎导致 Slave 节点有本地事务
date: 2019-04-22 20:56:52
categories:
- MySQL
tags:
- MySQL
- MEMORY引擎
- HEAP引擎
- 本地事务
toc: true
---


<!-- more -->


>**本文首发于 2019-04-22 20:56:52**

## 1. MEMORY 引擎简介

可能有的朋友对MEMORY存储引擎不太了解，首先介绍一下（以下描述来自[官方](https://dev.mysql.com/doc/refman/5.7/en/memory-storage-engine.html)）：

1. MEMROY存储引擎（以前称为HEAP）的表**把表结构存放到磁盘上，而把数据放在内存中**。
2. 每个Memory表只实际对应一个磁盘文件，在磁盘中表现为.frm文件。因为它的数据是放在内存中的，并且默认使用`hash索引`（也支持B-Tree索引），因此Memory类型的表访问速度非常快（比使用B-Tree索引的MyISAM表快），但是`一旦服务关闭，表中的数据就会丢失`。
3. 由于MEMRORY表在mysqld重启后数据会丢失，为了获得稳定的数据源，可以在启动mysqld时添加`--init-file`选项，把类似`insert into ... select`或`load data`的语句放进去。
4. MEMROY存储引擎的典型适用场景包含如下特征：
    1. 涉及瞬态非关键数据的操作，如会话管理或缓存。
    2. 数据可以完全放入内存而不会导致操作系统交换虚拟内存页，并且要求快速访问。
    3. 只读或以读为主的数据访问模式（有限的更新）。
5. 关于性能：
    1. 在处理更新时，单线程执行和表锁开销导致的争用会限制MEMORY性能。
    2. 尽管MEMORY表在内存中进行处理，但是对于繁忙的服务器、通用查询或读/写工作负载，它们并不一定比InnoDB表快。特别是，执行更新所涉及的表锁定会降低多个会话中内存表的并发使用速度。
6. MEMORY表具有以下特征：
    1. MEMORY表的空间以小块形式分配。表对插入使用100%动态哈希，不需要占用额外的内存。
    2. 被删除的行并未释放，而是放在链表中，并在插入新数据时重用。
    3. MEMORY表使用固定长度的行存储数据。（即使是VARCHAR也不例外）
    4. MEMORY表不支持 BLOB、TEXT 列。
    5. MEMORY表支持 AUTO_INCREMENT 列。
7. MEMORY表是有大小限制的，主要受限于两个参数：` max_heap_table_size` 和 `MAX_ROWS`（默认情况下`MAX_ROWS`依赖于`max_heap_table_size`，可执行`ALTER TABLE tbl_name MAX_ROWS= MAX_ROWS`修改`MAX_ROWS`）。

**问：MEMORY表和临时表有什么区别？**

>1. 临时表默认使用的存储引擎是服务器指定的存储引擎（对于5.7是InnoDB），由于临时表定义和数据都放在内存中，未放到磁盘，因此用`show tables`招不到临时表。
>2. 如果临时表占用空间太大，MySQL会将其转为磁盘存储。而对于用户创建的MEMORY表，则不会转为磁盘存储。
```sql
mysql> create temporary table temp_t1(a int primary key, b int);
Query OK, 0 rows affected (0.00 sec)

mysql> show tables;
+---------------+
| Tables_in_db4 |
+---------------+
| t1            |
+---------------+
1 row in set (0.00 sec)
```


## 2. 故障分析
**现象：**

最近碰到有用户使用 MEMORY 存储引擎，引发主从 GTID 不一致、从节点 GTID 比主节点多一条的情况。

**分析：**

1. 检查日志，确认没有发生过主从切换，也就排除了`主节点有 prepare 的事务然后故障（从节点变为主）、重启导致 local commit`的情况。
2. 在从节点 binlog 中找到那条本地事务，发现是 MEMORY 表的 `DELETE FROM` 。
3. 该从节点发生过重启，根据 MEMORY 引擎的特性，确认是 MEMORY 表生成的。

向用户反馈问题原因后，用户将 MEMORY 表改为了 InnoDB 表。

## 3. 疑问

### 3.1. 何时生成 `DELETE FROM`？

>A server's `MEMORY` tables become empty when it is shut down and restarted. If the server is a replication master, its slaves are not aware that these tables have become empty, so you see out-of-date content if you select data from the tables on the slaves. To synchronize master and slave `MEMORY` tables, when a `MEMORY` table is used on a master for the first time since it was started, a [`DELETE`](https://dev.mysql.com/doc/refman/5.7/en/delete.html) statement is written to the master's binary log, to empty the table on the slaves also. The slave still has outdated data in the table during the interval between the master's restart and its first use of the table. To avoid this interval when a direct query to the slave could return stale data, use the [`--init-file`](https://dev.mysql.com/doc/refman/5.7/en/server-options.html#option_mysqld_init-file) option to populate the `MEMORY` table on the master at startup.


这段描述的含义是：
>1. 服务器的 MEMORY 表在关闭和重新启动时会变为空。
>2. 为了防止主服务器重启、从服务器未重启导致从服务器上有过期的 MEMORY 表数据，会在重启服务器时向 binlog 写入一条 `DELETE FROM` 语句，这条语句会复制到从节点，以达到主从数据一致的目的。


### 3.2. 对于主从复制的 MySQL 集群，主或从故障重启有什么问题？

>**PS：不想看过程的朋友，请跳到最后看总结。**

举例来说，集群有三个节点A、B、C，节点A为主节点。

**情形一：MEMORY 表有数据的情况下，重启主节点、触发主从切换：**

1. 创建 `MEMORY` 表 `mdb.t1` ，执行 `insert into mdb.t1 values(1,1),(2,2),(3,3),(4,4)` 插入一些数据。
2. 关闭节点A的 MySQL，节点B变为主，之后节点A以从节点启动，此时：
- **节点A无数据：**
```sql
mysql> select * from mdb.t1;
Empty set (0.00 sec)
```

- **节点B、C有数据：**
```sql
mysql> select * from mdb.t1;
+------+------+
| a    | b    |
+------+------+
|    1 |    1 |
|    2 |    2 |
|    3 |    3 |
|    4 |    4 |
+------+------+
4 rows in set (0.00 sec)
```
并且，节点A的 GTID 为 `uuid_a:1-11`，节点B、C的 GTID 为 `uuid_a:1-10`，节点A的 binlog 比另外两个节点多一条 `DELTE FROM mdb.t1`。


**情形二：MEMORY 表无数据的情况下，重启主节点、触发主从切换：**

1. 将节点A切换为主节点，节点B、C同步了 `uuid_a:1-11` 这条事务，三个节点的 `mdb.t1` 数据为空。
2. 关闭节点A的 MySQL，节点B变为主，之后节点A以从节点启动，此时，节点A生成了一条本地 `DELETE FROM` 事务 `uuid_b:1-12`。

**情形三：MEMORY 表无数据的情况下，重启从节点：**

1.  将节点A切换为主节点，节点B、C同步了 `uuid_a:1-12` 这条事务
2. 重启节点A的MySQL，节点A生成一条本地 `DELETE FROM` 事务 `uuid_a:1-13`。

**情形四：MEMORY 表有数据的情况下，重启从节点：**

1. 将节点A切换为主节点，另外两个节点同步节点A的本地事务，三个节点 GTID 为 `uuid_a:1-13` 。
2. 执行 `INSERT` 语句向 `mdb.t1` 插入一些数据，三个节点 GTID 为 `uuid_a:1-14`。
3. 重启节点B，其生成了一条本地 `DELETE FROM` 事务 `uuid_b:1`。

### 3.3. 总结

1. 测试发现，无论什么情况下，MEMORY存储引擎都会生成一条本地 `DELETE FROM` 事务。
2. 在某些情况下，必须主动访问（比如 `SELECT`）MEMORY 表，才会触发生成 `DELETE FROM`。
3. 最重要的一点，`在生产环境中千万不要使用MEMORY存储引擎`。


----

欢迎关注我的微信公众号【数据库内核】：分享主流开源数据库和存储引擎相关技术。

<img src="https://dbkernel-1306518848.cos.ap-beijing.myqcloud.com/wechat/my-wechat-official-account.png" width="400" height="400" alt="欢迎关注公众号数据库内核" align="center"/>


| 标题                 | 网址                                                  |
| -------------------- | ----------------------------------------------------- |
| GitHub               | https://dbkernel.github.io                            |
| 知乎                 | https://www.zhihu.com/people/dbkernel/posts           |
| 思否（SegmentFault） | https://segmentfault.com/u/dbkernel                   |
| 掘金                 | https://juejin.im/user/5e9d3ed251882538083fed1f/posts |
| 开源中国（oschina）  | https://my.oschina.net/dbkernel                       |
| 博客园（cnblogs）    | https://www.cnblogs.com/dbkernel                      |


