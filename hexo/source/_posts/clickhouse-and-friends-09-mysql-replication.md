---
title: 源码分析 | ClickHouse和他的朋友们（9）MySQL实时复制与实现
date: 2020-07-28 21:50:10
categories:
- ClickHouse
tags:
- ClickHouse和他的朋友们
- ClickHouse
- MySQL
- 源码分析
toc: true
---

<!-- more -->

**本文首发于 2020-07-28 21:50:10**

>《ClickHouse和他的朋友们》系列文章转载自圈内好友 [BohuTANG](https://bohutang.me/) 的博客，原文链接：
>https://bohutang.me/2020/07/25/clickhouse-and-friends-parser/
>以下为正文。


![clickhouse-map-2020-materialzemysql.png](clickhouse-map-2020-materialzemysql.png)

很多人看到标题还以为自己走错了夜场，其实没有。

ClickHouse 可以挂载为 MySQL 的一个从库 ，先全量再增量的实时同步 MySQL 数据，这个功能可以说是今年最亮眼、最刚需的功能，基于它我们可以轻松的打造一套企业级解决方案，让 OLTP 和 OLAP 的融合从此不再头疼。

目前支持 MySQL 5.6/5.7/8.0 版本，兼容 Delete/Update 语句，及大部分常用的 DDL 操作。

[代码](https://github.com/ClickHouse/ClickHouse/pull/10851)已经合并到 upstream master 分支，预计在20.8版本作为experimental 功能发布。

毕竟是两个异构生态的融合，仍然有不少的工作要做，同时也期待着社区用户的反馈，以加速迭代。

### 代码获取

获取 [clickhouse/master](https://github.com/ClickHouse/ClickHouse) 代码编译即可，方法见 [ClickHouse和他的朋友们（1）编译、开发、测试](https://bohutang.me/2020/06/05/clickhouse-and-friends-development/)…

### MySQL Master

我们需要一个开启 binlog 的 MySQL 作为 master:

```
docker run -d -e MYSQL_ROOT_PASSWORD=123 mysql:5.7 mysqld --datadir=/var/lib/mysql --server-id=1 --log-bin=/var/lib/mysql/mysql-bin.log --gtid-mode=ON --enforce-gtid-consistency
```

创建数据库和表，并写入数据:

```sql
mysql> create database ckdb;
mysql> use ckdb;
mysql> create table t1(a int not null primary key, b int);
mysql> insert into t1 values(1,1),(2,2);
mysql> select * from t1;
+---+------+
| a | b    |
+---+------+
| 1 |    1 |
| 2 |    2 |
+---+------+
2 rows in set (0.00 sec)
```

### ClickHouse Slave

目前以 database 为单位进行复制，不同的 database 可以来自不同的 MySQL master，这样就可以实现多个 MySQL 源数据同步到一个 ClickHouse 做 OLAP 分析功能。

首先开启体验开关:

```sql
clickhouse :) SET allow_experimental_database_materialize_mysql=1;
```

创建一个复制通道：

```sql
clickhouse :) CREATE DATABASE ckdb ENGINE = MaterializeMySQL('172.17.0.2:3306', 'ckdb', 'root', '123');
clickhouse :) use ckdb;
clickhouse :) show tables;
┌─name─┐
│ t1   │
└──────┘
clickhouse :) select * from t1;
┌─a─┬─b─┐
│ 1 │ 1 │
└───┴───┘
┌─a─┬─b─┐
│ 2 │ 2 │
└───┴───┘

2 rows in set. Elapsed: 0.017 sec.
```

看下 ClickHouse 的同步位点：

```bash
$ cat ckdatas/metadata/ckdb/.metadata
Version:	1
Binlog File:	mysql-bin.000001
Binlog Position:	913
Data Version:	0
```

### Delete

首先在 MySQL Master 上执行一个删除操作：

```sql
mysql> delete from t1 where a=1;
Query OK, 1 row affected (0.01 sec)
```

然后在 ClickHouse Slave 侧查看记录：

```sql
clickhouse :) select * from t1;

SELECT *
FROM t1

┌─a─┬─b─┐
│ 2 │ 2 │
└───┴───┘

1 rows in set. Elapsed: 0.032 sec.
```

此时的 metadata 里 Data Version 已经递增到 2:

```sql
cat ckdatas/metadata/ckdb/.metadata
Version:	1
Binlog File:	mysql-bin.000001
Binlog Position:	1171
Data Version:	2
```

### Update

MySQL Master:

```sql
mysql> select * from t1;
+---+------+
| a | b    |
+---+------+
| 2 |    2 |
+---+------+
1 row in set (0.00 sec)

mysql> update t1 set b=b+1;

mysql> select * from t1;
+---+------+
| a | b    |
+---+------+
| 2 |    3 |
+---+------+
1 row in set (0.00 sec)
```

ClickHouse Slave:

```sql
clickhouse :) select * from t1;

SELECT *
FROM t1

┌─a─┬─b─┐
│ 2 │ 3 │
└───┴───┘

1 rows in set. Elapsed: 0.023 sec.
```

### 性能测试

#### 测试环境

```
MySQL          8C16G 云主机, 192.168.0.3，基础数据 10188183 条记录
ClickHouse     8C16G 云主机, 192.168.0.4
benchyou       8C8G  云主机, 192.168.0.5, 256并发写, https://github.com/xelabs/benchyou
```

性能测试跟硬件环境有较大关系，这里使用的是云主机模式，数据供参考。

#### 全量性能

```sql
8c16G-vm :) create database sbtest engine=MaterializeMySQL('192.168.0.3:3306', 'sbtest', 'test', '123');

8c16G-vm :) watch lv1;

WATCH lv1

┌─count()─┬───────────────now()─┬─_version─┐
│       0 │ 2020-07-29 06:36:04 │        1 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│ 1113585 │ 2020-07-29 06:36:05 │        2 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│ 2227170 │ 2020-07-29 06:36:07 │        3 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│ 3340755 │ 2020-07-29 06:36:10 │        4 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│ 4454340 │ 2020-07-29 06:36:13 │        5 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│ 5567925 │ 2020-07-29 06:36:16 │        6 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│ 6681510 │ 2020-07-29 06:36:18 │        7 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│ 7795095 │ 2020-07-29 06:36:22 │        8 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│ 8908680 │ 2020-07-29 06:36:25 │        9 │
└─────────┴─────────────────────┴──────────┘
┌──count()─┬───────────────now()─┬─_version─┐
│ 10022265 │ 2020-07-29 06:36:28 │       10 │
└──────────┴─────────────────────┴──────────┘
┌──count()─┬───────────────now()─┬─_version─┐
│ 10188183 │ 2020-07-29 06:36:28 │       11 │
└──────────┴─────────────────────┴──────────┘
← Progress: 11.00 rows, 220.00 B (0.16 rows/s., 3.17 B/s.)
```

在这个硬件环境下，全量同步性能大概是 **424507/s**，**42w** 事务每秒。

因为全量的数据之间没有依赖关系，可以进一步优化成并行，加速同步。

全量的性能直接决定 ClickHouse slave 坏掉后重建的速度，如果你的 MySQL 有 **10 亿**条数据，大概 **40 分钟**就可以重建完成。

#### 增量性能(实时同步)

在当前配置下，ClickHouse slave 单线程回放消费能力大于 MySQL master 256 并发下生产能力，通过测试可以看到它们保持**实时同步**。

benchyou 压测数据，**2.1w** 事务/秒(MySQL 在当前环境下TPS上不去):

```
./bin/benchyou --mysql-host=192.168.0.3 --mysql-user=test --mysql-password=123 --oltp-tables-count=1 --write-threads=256 --read-threads=0

time            thds               tps     wtps    rtps
[13s]        [r:0,w:256,u:0,d:0]  19962    19962   0

time            thds               tps     wtps    rtps
[14s]        [r:0,w:256,u:0,d:0]  20415    20415   0

time            thds               tps     wtps    rtps
[15s]        [r:0,w:256,u:0,d:0]  21131    21131   0

time            thds               tps     wtps    rtps
[16s]        [r:0,w:256,u:0,d:0]  21606    21606   0

time            thds               tps     wtps    rtps
[17s]        [r:0,w:256,u:0,d:0]  22505    22505   0
```

ClickHouse 侧单线程回放能力，**2.1w** 事务/秒，实时同步：

```sql
┌─count()─┬───────────────now()─┬─_version─┐
│  150732 │ 2020-07-30 05:17:15 │       17 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│  155477 │ 2020-07-30 05:17:16 │       18 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│  160222 │ 2020-07-30 05:17:16 │       19 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│  164967 │ 2020-07-30 05:17:16 │       20 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│  169712 │ 2020-07-30 05:17:16 │       21 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│  174457 │ 2020-07-30 05:17:16 │       22 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│  179202 │ 2020-07-30 05:17:17 │       23 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│  183947 │ 2020-07-30 05:17:17 │       24 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│  188692 │ 2020-07-30 05:17:17 │       25 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│  193437 │ 2020-07-30 05:17:17 │       26 │
└─────────┴─────────────────────┴──────────┘
┌─count()─┬───────────────now()─┬─_version─┐
│  198182 │ 2020-07-30 05:17:17 │       27 │
└─────────┴─────────────────────┴──────────┘
```

### 实现机制

在探讨机制之前，首先需要了解下 MySQL 的 binlog event ，主要有以下几种类型：

```
1. MYSQL_QUERY_EVENT　　　　-- DDL
2. MYSQL_WRITE_ROWS_EVENT　-- insert数据
3. MYSQL_UPDATE_ROWS_EVENT -- update数据
4. MYSQL_DELETE_ROWS_EVENT -- delete数据
```

当一个事务提交后，MySQL 会把执行的 SQL 处理成相应的 binlog event，并持久化到 binlog 文件。

binlog 是 MySQL 对外输出的重要途径，只要你实现 MySQL Replication Protocol，就可以流式的消费MySQL 生产的 binlog event，具体协议见 [Replication Protocol](https://dev.mysql.com/doc/internals/en/replication-protocol.html)。

由于历史原因，协议繁琐而诡异，这不是本文重点。

对于 ClickHouse 消费 MySQL binlog 来说，主要有以下３个难点：

- DDL 兼容
- Delete/Update 支持
- Query 过滤

#### DDL

DDL 兼容花费了大量的代码去实现。

首先，我们看看 MySQL 的表复制到 ClickHouse 后会变成什么样子。

MySQL master:

```sql
mysql> show create table t1\G;
*************************** 1. row ***************************
       Table: t1
Create Table: CREATE TABLE `t1` (
  `a` int(11) NOT NULL,
  `b` int(11) DEFAULT NULL,
  PRIMARY KEY (`a`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
```

ClickHouse slave:

```sql
ATTACH TABLE t1
(
    `a` Int32,
    `b` Nullable(Int32),
    `_sign` Int8,
    `_version` UInt64
)
ENGINE = ReplacingMergeTree(_version)
PARTITION BY intDiv(a, 4294967)
ORDER BY tuple(a)
SETTINGS index_granularity = 8192
```

可以看到：

- 默认增加了 2 个隐藏字段：`_sign`(-1删除, 1写入) 和 `_version`(数据版本)
- 引擎转换成了 ReplacingMergeTree，以 _version 作为 column version
- 原主键字段 a 作为排序和分区键

这只是一个表的复制，其他还有非常多的DDL处理，比如增加列、索引等，感兴趣可以观摩 Parsers/MySQL 下代码。

#### Update和Delete

当我们在 MySQL master 执行：

```sql
mysql> delete from t1 where a=1;
mysql> update t1 set b=b+1;
```

ClickHouse t1数据（把 `_sign` 和 `_version` 一并查询）：

```sql
clickhouse :) select a,b,_sign, _version from t1;

SELECT
    a,
    b,
    _sign,
    _version
FROM t1

┌─a─┬─b─┬─_sign─┬─_version─┐
│ 1 │ 1 │     1 │        1 │
│ 2 │ 2 │     1 │        1 │
└───┴───┴───────┴──────────┘
┌─a─┬─b─┬─_sign─┬─_version─┐
│ 1 │ 1 │    -1 │        2 │
└───┴───┴───────┴──────────┘
┌─a─┬─b─┬─_sign─┬─_version─┐
│ 2 │ 3 │     1 │        3 │
└───┴───┴───────┴──────────┘
```

根据返回结果，可以看到是由 3 个 part 组成。

part1 由 `mysql> insert into t1 values(1,1),(2,2)` 生成：

```
┌─a─┬─b─┬─_sign─┬─_version─┐
│ 1 │ 1 │     1 │        1 │
│ 2 │ 2 │     1 │        1 │
└───┴───┴───────┴──────────┘
```

part2 由 `mysql> delete from t1 where a=1` 生成：

```
┌─a─┬─b─┬─_sign─┬─_version─┐
│ 1 │ 1 │    -1 │        2 │
└───┴───┴───────┴──────────┘
说明：
_sign = -1表明处于删除状态
```

part3 由 `update t1 set b=b+1` 生成：

```
┌─a─┬─b─┬─_sign─┬─_version─┐
│ 2 │ 3 │     1 │        3 │
└───┴───┴───────┴──────────┘
```

使用 final 查询：

```sql
clickhouse :) select a,b,_sign,_version from t1 final;

SELECT
    a,
    b,
    _sign,
    _version
FROM t1
FINAL

┌─a─┬─b─┬─_sign─┬─_version─┐
│ 1 │ 1 │    -1 │        2 │
└───┴───┴───────┴──────────┘
┌─a─┬─b─┬─_sign─┬─_version─┐
│ 2 │ 3 │     1 │        3 │
└───┴───┴───────┴──────────┘

2 rows in set. Elapsed: 0.016 sec.
```

可以看到 ReplacingMergeTree 已经根据 `_version` 和 OrderBy 对记录进行去重。

#### Query

MySQL master:

```sql
mysql> select * from t1;
+---+------+
| a | b    |
+---+------+
| 2 |    3 |
+---+------+
1 row in set (0.00 sec)
```

ClickHouse slave:

```sql
clickhouse :) select * from t1;

SELECT *
FROM t1

┌─a─┬─b─┐
│ 2 │ 3 │
└───┴───┘

clickhouse :) select *,_sign,_version from t1;

SELECT
    *,
    _sign,
    _version
FROM t1

┌─a─┬─b─┬─_sign─┬─_version─┐
│ 1 │ 1 │    -1 │        2 │
│ 2 │ 3 │     1 │        3 │
└───┴───┴───────┴──────────┘
说明：这里还有一条删除记录，_sign为-1
```

MaterializeMySQL 被定义成一种存储引擎，所以在读取的时候，会根据 `_sign` 状态进行判断，如果是-1则是已经删除，进行过滤。

### 并行回放

为什么 MySQL 需要并行回放？

假设 MySQL master 有 1024 个并发同时写入、更新数据，瞬间产生大量的 binlog event ，MySQL slave 上只有一个线程一个 event 接着一个 event 式回放，于是 MySQL 实现了并行回放功能！

那么，MySQL slave 回放时能否完全(或接近)模拟出 master 当时的 1024 并发行为呢？

要想并行首先要解决的就是依赖问题：我们需要 master 标记出哪些 event 可以并行，哪些 event 有先后关系，因为它是第一现场。

MySQL 通过在 binlog 里增加:

- last_committed，相同则可以并行
- sequece_number，较小先执行，描述先后依赖

```
last_committed=3   sequece_number=4   -- event1
last_committed=4   sequece_number=5   -- event2
last_committed=4   sequece_number=6   -- event3
last_committed=5   sequece_number=7   -- event4
```

event2 和 event3 则可以并行，event4 需要等待前面 event 完成才可以回放。

以上只是一个大体原理，目前 MySQL 有３种并行模式可以选择：

1. 基于 database 并行
2. 基于 group commit 并行
3. 基于主键不冲突的 write set 并行

最大程度上让 MySQL slave加速回放，整套机制还是异常复杂的。

回到 ClickHouse slave 问题，我们采用的单线程回放，延迟已经不是主要问题，这是由它们的机制决定的：

- MySQL slave 回放时，需要把 binlog event 转换成 SQL，然后模拟 master 的写入，这种逻辑复制是导致性能低下的最重要原因。
- 而 ClickHouse 在回放上，直接把 binlog event 转换成 底层 block 结构，然后直接写入底层的存储引擎，接近于物理复制，可以理解为把 binlog event 直接回放到 InnoDB 的 page。

### 读取最新

虽然 ClickHouse slave 回放非常快，接近于实时，如何在ClickHouse slave上总是读取到最新的数据呢？

其实非常简单，借助 MySQL binlog GTID 特性，每次读的时候，我们跟 ｍaster 做一次 executed_gtid 同步，然后等待这些 executed_gtid 回放完毕即可。

### 数据一致性

对一致性要求较高的场景，我们怎么验证 MySQL master 的数据和 ClickHouse slave 的数据一致性呢？

这块初步想法是提供一个兼容 MySQL checksum 算法的函数，我们只需对比两边的 checksum 值即可。

### 总结

ClickHouse 实时复制同步 MySQL 数据是 upstream 2020 的一个 roadmap，在整体构架上比较有挑战一直无人接单，挑战主要来自两方面：

- 对 MySQL 复制通道与协议非常熟悉
- 对 ClickHouse 整体机制非常熟悉

这样，在两个本来有点遥远的山头中间架起了一座高速，这条 [10851号](https://github.com/ClickHouse/ClickHouse/pull/10851) 高速由 zhang1024(ClickHouse侧) 和 BohuTANG(MySQL复制) 两个修路工联合承建，目前已经合并到 upstream 分支。

关于同步 MySQL 的数据，目前大家的方案基本都是在中间安置一个 binlog 消费工具，这个工具对 event 进行解析，然后再转换成 ClickHouse 的 SQL 语句，写到 ClickHouse server，链路较长，性能损耗较大。

[10851号](https://github.com/ClickHouse/ClickHouse/pull/10851) 高速是在 ClickHouse 内部实现一套 binlog 消费方案，然后根据 event 解析成 ClickHouse 内部的 block 结构，再直接回写到底层存储引擎，几乎是最高效的一种实现方式，实现与 MySQL 实时同步的能力，让分析更接近现实。

基于 database 级的复制，实现了多源复制的功能，如果复制通道坏掉，我们只需在 ClickHouse 侧删掉 database 再重建一次即可，非常快速、方便，OLTP+OLAP 就是这么简单！

要想富，先修路！

----

欢迎关注我的微信公众号【数据库内核】：分享主流开源数据库和存储引擎相关技术。

<img src="https://dbkernel-1306518848.cos.ap-beijing.myqcloud.com/wechat/my-wechat-official-account.png" width="400" height="400" alt="欢迎关注公众号数据库内核" align="center"/>


| 标题 | 网址 |
| -------------------- | --------------------------------- |
| GitHub | https://dbkernel.github.io |
| 知乎 | https://www.zhihu.com/people/dbkernel/posts |
| 思否（SegmentFault） | https://segmentfault.com/u/dbkernel |
| 掘金 | https://juejin.im/user/5e9d3ed251882538083fed1f/posts |
| 开源中国（oschina） | https://my.oschina.net/dbkernel |
| 博客园（cnblogs） | https://www.cnblogs.com/dbkernel |


