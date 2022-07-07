---
title: 实用工具 | PostgreSQL 数据库压力测试工具 pgbench 使用示例
date: 2015-12-23 21:04:17
categories:
  - PostgreSQL
tags:
  - PostgreSQL
  - pgbench
toc: true
---

<!-- more -->

> **本文首发于 2015-12-23 21:04:17**

# 环境

PG 数据库提供了一款轻量级的压力测试工具叫 `pgbench`，其实就是一个编译好后的扩展性的可执行文件。

**测试环境：**

> CentOS 5.7 in VMWare 8.0
>
> PG：9.1.2

**数据库参数：**

> max_connection=100
>
> 其他默认
>
> **注意：** 本文只为说明 `pgbench` 的使用方法，因此，并未对数据库参数调优。

# 安装

进入源码安装包，编译、安装：

```bash
cd postgresql-9.1.2/contrib/pgbench/
make all
make install
```

安装完毕以后可以在 bin 文件夹下看到新生成的 pgbench 文件：

```bash
$ ll $PGHOME/bin/pgbench
-rwxr-xr-x. 1 postgres postgres 50203 Jul  8 20:28 pgbench
```

# 参数介绍

```bash
[postgres@localhost  bin]$ pgbench --help
pgbench is a benchmarking tool for PostgreSQL.

Usage:
  pgbench [OPTIONS]... [DBNAME]

Initialization options:
  -i           invokes initialization mode
  -F NUM       fill factor
  -s NUM       scaling factor

Benchmarking options:
  -c NUM       number of concurrent database clients (default: 1)
  -C           establish new connection for each transaction
  -D VARNAME=VALUE
               define variable for use by custom script
  -f FILENAME  read transaction script from FILENAME
  -j NUM       number of threads (default: 1)
  -l           write transaction times to log file
  -M {simple|extended|prepared}
               protocol for submitting queries to server (default: simple)
  -n           do not run VACUUM before tests
  -N           do not update tables "pgbench_tellers" and "pgbench_branches"
  -r           report average latency per command
  -s NUM       report this scale factor in output
  -S           perform SELECT-only transactions
  -t NUM       number of transactions each client runs (default: 10)
  -T NUM       duration of benchmark test in seconds
  -v           vacuum all four standard tables before tests

Common options:
  -d           print debugging output
  -h HOSTNAME  database server host or socket directory
  -p PORT      database server port number
  -U USERNAME  connect as specified database user
  --help       show this help, then exit
  --version    output version information, then exit
```

部分参数中文含义：

```
-c, --client=NUM
数据库客户端数量, 可以理解为数据库会话数量(postgres进程数), 默认为1

-C, --connect
每个事务创建一个连接,由于PG使用进程模型, 可以测试频繁Kill/Create进程的性能表现

-j, --jobs=NUM
pgbench的工作线程数

-T, --time=NUM
以秒为单位的压测时长

-v, --vacuum-all
每次测试前执行vacuum命令, 避免"垃圾"空间的影响

-M, --protocol=simple|extended|prepared
提交查询命令到服务器使用的协议, simple是默认选项, prepared是类似绑定

-r, --report-latencies
报告每条命令(SQL语句)的平均延时

-S, --select-only
只执行查询语句
```

# 初始化测试数据

初始化数据：

```bash
[postgres@localhost  ~]$ pgbench -i pgbench
creating tables...
10000 tuples done.
20000 tuples done.
30000 tuples done.
40000 tuples done.
50000 tuples done.
60000 tuples done.
70000 tuples done.
80000 tuples done.
90000 tuples done.
100000 tuples done.
set primary key...
NOTICE:  ALTER TABLE / ADD PRIMARY KEY will create implicit index "pgbench_branches_pkey" for table "pgbench_branches"
NOTICE:  ALTER TABLE / ADD PRIMARY KEY will create implicit index "pgbench_tellers_pkey" for table "pgbench_tellers"
NOTICE:  ALTER TABLE / ADD PRIMARY KEY will create implicit index "pgbench_accounts_pkey" for table "pgbench_accounts"
vacuum...done.
```

查看表数据：

```sql
[postgres@localhost  ~]$ psql -d pgbench
psql (9.1.2)
Type "help" for help.

pgbench=# select count(1) from pgbench_accounts;
 count
--------
 100000
(1 row)

pgbench=# select count(1) from pgbench_branches;
 count
-------
     1
(1 row)

pgbench=# select count(1) from pgbench_history;
 count
-------
     0
(1 row)

pgbench=# select count(1) from pgbench_tellers;
 count
-------
    10
(1 row)
```

查看表结构：

```sql
pgbench=# \d+ pgbench_accounts
                Table "public.pgbench_accounts"
  Column  |     Type      | Modifiers | Storage  | Description
----------+---------------+-----------+----------+-------------
 aid      | integer       | not null  | plain    |
 bid      | integer       |           | plain    |
 abalance | integer       |           | plain    |
 filler   | character(84) |           | extended |
Indexes:
    "pgbench_accounts_pkey" PRIMARY KEY, btree (aid)
Has OIDs: no
Options: fillfactor=100

pgbench=# \d+ pgbench_branches
                Table "public.pgbench_branches"
  Column  |     Type      | Modifiers | Storage  | Description
----------+---------------+-----------+----------+-------------
 bid      | integer       | not null  | plain    |
 bbalance | integer       |           | plain    |
 filler   | character(88) |           | extended |
Indexes:
    "pgbench_branches_pkey" PRIMARY KEY, btree (bid)
Has OIDs: no
Options: fillfactor=100

pgbench=# \d+ pgbench_history
                      Table "public.pgbench_history"
 Column |            Type             | Modifiers | Storage  | Description
--------+-----------------------------+-----------+----------+-------------
 tid    | integer                     |           | plain    |
 bid    | integer                     |           | plain    |
 aid    | integer                     |           | plain    |
 delta  | integer                     |           | plain    |
 mtime  | timestamp without time zone |           | plain    |
 filler | character(22)               |           | extended |
Has OIDs: no

pgbench=# \d+ pgbench_tellers
                Table "public.pgbench_tellers"
  Column  |     Type      | Modifiers | Storage  | Description
----------+---------------+-----------+----------+-------------
 tid      | integer       | not null  | plain    |
 bid      | integer       |           | plain    |
 tbalance | integer       |           | plain    |
 filler   | character(84) |           | extended |
Indexes:
    "pgbench_tellers_pkey" PRIMARY KEY, btree (tid)
Has OIDs: no
Options: fillfactor=100
```

**说明：**

1. 这里使用的是默认的参数值，`-s`参数时可指定测试数据的数据量，`-f`可以指定测试的脚本，这里用的是默认脚本。
2. 不要在生产的库上做，新建一个测试库（当生产上有同名的测试表时将被重置）。

# 测试

## 1 个 session

```bash
[postgres@localhost  ~]$ nohup pgbench -c 1 -T 20 -r pgbench > file.out  2>&1
[postgres@localhost  ~]$ more file.out
nohup: ignoring input
starting vacuum...end.
transaction type: TPC-B (sort of)
scaling factor: 1
query mode: simple
number of clients: 1
number of threads: 1
duration: 20 s
number of transactions actually processed: 12496                                                                                     tps = 624.747958 (including connections establishing)                                                                                tps = 625.375564 (excluding connections establishing)
statement latencies in milliseconds:
        0.005299        \set nbranches 1 * :scale
        0.000619        \set ntellers 10 * :scale
        0.000492        \set naccounts 100000 * :scale
        0.000700        \setrandom aid 1 :naccounts
        0.000400        \setrandom bid 1 :nbranches
        0.000453        \setrandom tid 1 :ntellers
        0.000430        \setrandom delta -5000 5000
        0.050707        BEGIN;
        0.200909        UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;
        0.098718        SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
        0.111621        UPDATE pgbench_tellers SET tbalance = tbalance + :delta WHERE tid = :tid;
        0.107297        UPDATE pgbench_branches SET bbalance = bbalance + :delta WHERE bid = :bid;
        0.095156        INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (:tid, :bid, :aid, :delta, CURRENT_TIMESTAMP);
        0.919101        END;
```

## 2. 50 个 session

```bash
[postgres@localhost  ~]$nohup pgbench -c 50 -T 20 -r pgbench > file.out  2>&1
[postgres@localhost  ~]$ more file.out
nohup: ignoring input
starting vacuum...end.
transaction type: TPC-B (sort of)
scaling factor: 1
query mode: simple
number of clients: 50
number of threads: 1
duration: 20 s
number of transactions actually processed: 7504                                                                                      tps = 370.510431 (including connections establishing)                                                                               tps = 377.964565 (excluding connections establishing)
statement latencies in milliseconds:
        0.004291        \set nbranches 1 * :scale
        0.000769        \set ntellers 10 * :scale
        0.000955        \set naccounts 100000 * :scale
        0.000865        \setrandom aid 1 :naccounts
        0.000513        \setrandom bid 1 :nbranches
        0.000580        \setrandom tid 1 :ntellers
        0.000522        \setrandom delta -5000 5000
        0.604671        BEGIN;
        1.480723        UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;
        0.401148        SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
        104.713566      UPDATE pgbench_tellers SET tbalance = tbalance + :delta WHERE tid = :tid;
        21.562787       UPDATE pgbench_branches SET bbalance = bbalance + :delta WHERE bid = :bid;
        0.412209        INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (:tid, :bid, :aid, :delta, CURRENT_TIMESTAMP);
        2.243497        END;
```

## 3. 100 个 session

超过 100 个会报错，因为数据库当前设置最大 session 是 100。

```bash
[postgres@localhost  ~]$ nohup pgbench -c 100 -T 20 -r pgbench> file.out  2>&1
[postgres@localhost  ~]$ more file.out
nohup: ignoring input
starting vacuum...end.
transaction type: TPC-B (sort of)
scaling factor: 1
query mode: simple
number of clients: 100
number of threads: 1
duration: 20 s
number of transactions actually processed: 6032                                                                                      tps = 292.556692 (including connections establishing)                                                                                tps = 305.595090 (excluding connections establishing)
statement latencies in milliseconds:
        0.004508        \set nbranches 1 * :scale
        0.000787        \set ntellers 10 * :scale
        0.000879        \set naccounts 100000 * :scale
        0.001620        \setrandom aid 1 :naccounts
        0.000485        \setrandom bid 1 :nbranches
        0.000561        \setrandom tid 1 :ntellers
        0.000656        \setrandom delta -5000 5000
        3.660809        BEGIN;
        4.198062        UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;
        1.727076        SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
        281.955832      UPDATE pgbench_tellers SET tbalance = tbalance + :delta WHERE tid = :tid;
        27.054125       UPDATE pgbench_branches SET bbalance = bbalance + :delta WHERE bid = :bid;
        0.524155        INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (:tid, :bid, :aid, :delta, CURRENT_TIMESTAMP);
        2.710619        END;
```

# 参考

http://www.postgresql.org/docs/9.1/static/pgbench.html

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
