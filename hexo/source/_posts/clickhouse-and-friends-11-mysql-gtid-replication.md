---
title: 源码分析 | ClickHouse和他的朋友们（11）MySQL实时复制之GTID模式
date: 2020-08-28 20:40:14
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

**本文首发于 2020-08-28 20:40:14**

>《ClickHouse和他的朋友们》系列文章转载自圈内好友 [BohuTANG](https://bohutang.me/) 的博客，原文链接：
>https://bohutang.me/2020/08/26/clickhouse-and-friends-mysql-gtid-replication/
>以下为正文。

![clickhouse-map-2020-materialzemysql.png](clickhouse-map-2020-materialzemysql.png)

[MySQL实时复制原理篇](https://bohutang.me/2020/07/26/clickhouse-and-friends-mysql-replication/)

几天前 ClickHouse 官方发布了 [v20.8.1.4447-testing](https://github.com/ClickHouse/ClickHouse/releases/tag/v20.8.1.4447-testing)，这个版本已经包含了 MaterializeMySQL 引擎，实现了 ClickHouse 实时复制 MySQL 数据的能力，感兴趣的朋友可以通过官方安装包来做体验，安装方式参考 <https://clickhouse.tech/#quick-start>，需要注意的是要选择 testing 分支。

## 基于位点同步

MaterializeMySQL 在 v20.8.1.4447-testing 版本是基于 binlog 位点模式进行同步的。

每次消费完一批 binlog event，就会记录 event 的位点信息到 .metadata 文件:

```
Version:	1
Binlog File:	mysql-bin.000002
Binlog Position:	328
Data Version:	1
```

这样当 ClickHouse 再次启动时，它会把 `{‘mysql-bin.000002’, 328}` 二元组通过协议告知 MySQL Server，MySQL 从这个位点开始发送数据：

```
s1> ClickHouse 发送 {'mysql-bin.000002', 328} 位点信息给 MySQL
s2> MySQL 找到本地 mysql-bin.000002 文件并定位到 328 偏移位置，读取下一个 event 发送给 ClickHouse
s3> ClickHouse 接收 binlog event 并更新 .metadata位点
```

看起来不错哦，但是有个问题：
如果 MySQL Server 是一个集群(比如１主２从)，通过 VIP 对外服务，MaterializeMySQL 的 host 指向的是这个 vip。
当集群主从发生切换后，`{binlog-name, binlog-position}` 二元组其实是不准确的，因为集群里主从 binlog 不一定是完全一致的(binlog 可以做 reset 操作)。

```
s1> ClickHouse 发送 {'mysql-bin.000002', 328} 给集群新主 MySQL
s2> 新主 MySQL 发现本地没有 mysql-bin.000002 文件，因为它做过 reset master 操作，binlog 文件是 mysql-bin.000001
... oops ...
```

为了解决这个问题，我们开发了 GTID 同步模式，废弃了不安全的位点同步模式，目前已被 upstream merged [#PR13820](https://github.com/ClickHouse/ClickHouse/pull/13820)，下一个 testing 版本即可体验。

着急的话可以自己编译或通过 [ClickHouse Build Check for master-20.9.1](https://clickhouse-builds.s3.yandex.net/0/2b8ad576cc3892d2d760f3f8b670adf17db0c2a0/clickhouse_build_check/report.html) 下载安装。

## 基于GTID同步

GTID 是 MySQL 复制增强版，从 MySQL 5.6 版本开始支持，目前已经是 MySQL 主流复制模式。

它为每个 event 分配一个全局唯一ID和序号，我们可以不用关心 MySQL 集群主从拓扑结构，直接告知 MySQL 这个 GTID 即可，.metadata变为:

```
Version:	2
Executed GTID:	f4aee41e-e36f-11ea-8b37-0242ac110002:1-5
Data Version:	1
```

`f4aee41e-e36f-11ea-8b37-0242ac110002` 是生成 event的主机UUID，`1-5`是已经同步的event区间。

这样流程就变为:

```
s1> ClickHouse 发送 GTID:f4aee41e-e36f-11ea-8b37-0242ac110002:1-5 给 MySQL
s2> MySQL 根据 GTID:f4aee41e-e36f-11ea-8b37-0242ac110002:1-5 找到本地位点，读取下一个 event 发送给 ClickHouse
s3> ClickHouse 接收 binlog event 并更新 .metadata GTID信息
```

## MySQL开启GTID

那么，MySQL 侧怎么开启 GTID 呢？增加以下两个参数即可:

```sql
--gtid-mode=ON --enforce-gtid-consistency
```

比如启动一个启用 GTID 的 MySQL docker：

```sql
docker run -d -e MYSQL_ROOT_PASSWORD=123 mysql:5.7 mysqld --datadir=/var/lib/mysql --server-id=1 --log-bin=/var/lib/mysql/mysql-bin.log --gtid-mode=ON --enforce-gtid-consistency
```

## 注意事项

启用 GTID 复制模式后，metadata Version 会变为 2，也就是老版本启动时会直接报错，database 需要重建。

## 总结

MaterializeMySQL 引擎还处于不停迭代中，对于它我们有一个初步的规划：

- **稳定性保证**
  这块需要更多测试，更多试用反馈
- **索引优化**
  OLTP 索引一般不是为 OLAP 设计，目前索引转换还是依赖 MySQL 表结构，需要更加智能化
- **可观测性**
  在 ClickHouse 侧可以方便的查看当前同步信息，类似 MySQL `show slave status`
- **数据一致性校验**
  需要提供方式可以校验 MySQL 和 ClickHouse 数据一致性

MaterializeMySQL 已经是社区功能，仍然有不少的工作要做。期待更多的力量加入，我们的征途不止星辰大海。

----

欢迎关注我的微信公众号【数据库内核】：分享主流开源数据库和存储引擎相关技术。

<img src="https://dbkernel-1306518848.cos.ap-beijing.myqcloud.com/wechat/my-wechat-official-account.png" width="400" height="400" alt="欢迎关注公众号数据库内核" align="center"/>

| 标题                 | 网址                                                  |
| -------------------- | ----------------------------------------------------- |
| GitHub                 | https://dbkernel.github.io           |
| 知乎                 | https://www.zhihu.com/people/dbkernel/posts           |
| 思否（SegmentFault） | https://segmentfault.com/u/dbkernel                   |
| 掘金                 | https://juejin.im/user/5e9d3ed251882538083fed1f/posts |
| 开源中国（oschina）  | https://my.oschina.net/dbkernel                       |
| 博客园（cnblogs）    | https://www.cnblogs.com/dbkernel                      |

