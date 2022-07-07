---
title: 源码分析 | ClickHouse和他的朋友们（14）存储计算分离方案与实现
date: 2020-09-21 22:01:12
categories:
  - ClickHouse
tags:
  - ClickHouse和他的朋友们
  - ClickHouse
  - 存储计算分离
  - 源码分析
toc: true
---

<!-- more -->

**本文首发于 2020-09-21 22:01:12**

> 《ClickHouse 和他的朋友们》系列文章转载自圈内好友 [BohuTANG](https://bohutang.me/) 的博客，原文链接：
> https://bohutang.me/2020/09/18/clickhouse-and-friends-compute-storage/
> 以下为正文。

![clickhouse-map-2020-replicatedmergetree.png](clickhouse-map-2020-replicatedmergetree.png)

如果多个 ClickHouse server 可以挂载同一份数据(分布式存储等)，并且每个 server 都可写，这样会有什么好处呢？

首先，我们可以把副本机制交给分布式存储来保障，上层架构变得简单朴素；

其次，clickhouse-server 可以在任意机器上增加、减少，使存储和计算能力得到充分发挥。

本文就来探讨一下 ClickHouse 的存储计算分离方案，实现上并不复杂。

## 1. 问题

ClickHouse 运行时数据由两部分组成：**内存元数据**和**磁盘数据**。

我们先看写流程：

```
w1. 开始写入数据
w2. 生成内存part信息，并维护part metadata列表
w3. 把part数据写到磁盘
```

再来看读流程：

```
r1. 从part metadata定位需要读取的part
r2. 从磁盘读取part数据
r3. 返回给上层数据
```

这样，如果 server1 写了一条数据，只会更新自己内存的 part metadata，其他 server 是感知不到的，这样也就无法查询到刚写入的数据。

存储计算分离，首先要解决的就是内存状态数据的同步问题。

在 ClickHouse 里，我们需要解决的是内存中 part metadata 同步问题。

## 2. 内存数据同步

在上篇 [<ReplicatedMergeTree 表引擎及同步机制>](https://bohutang.me/2020/09/13/clickhouse-and-friends-replicated-merge-tree/) 中，我们知道副本间的数据同步机制：
首先同步元数据，再通过元数据获取相应 part 数据。

这里，我们借用 ReplicatedMergeTree 同步通道，然后再做减法，同步完元数据后跳过 part 数据的同步，因为磁盘数据只需一个 server 做更新(需要 fsync 语义)即可。

核心代码：
`MergeTreeData::renameTempPartAndReplace`

```cpp
if (!share_storage)
    part->renameTo(part_name, true);
```

## 3. 演示 demo

<iframe src="https://bohutang-1253727613.cos.ap-beijing.myqcloud.com/video/clickhouse-storage-compute.mp4" frameborder="0" allowfullscreen="true" style="box-sizing: border-box;"></iframe>

script：

1. 首先起 2 个 clickhouse-server，它们都挂载同一份数据 `<path>/home/bohu/work/cluster/d1/datas/</path>`
2. 通过 clickhouse-server1(port 9101) 写入一条记录:(111, 3333)
3. 通过 clickhouse-server2(port 9102) 进行查询正常
4. 通过 clickhouse-server2(port 9102) truncate 表
5. 通过 clickhouse-server1(port 9101) 查询正常

## 4. 代码实现

[原型](https://github.com/BohuTANG/ClickHouse/commit/f67d98ef408fda1a359e4fb17848619ef1f6e59b)

需要注意的是，这里只实现了写入数据同步，而且是非常 tricky 的方式。

由于 DDL 没有实现，所以在 zookeeper 上的注册方式也比较 tricky，demo 里的 replicas 都是手工注册的。

## 5. 总结

本文提供一个思路，算是抛砖引玉，同时也期待更加系统的工程实现。

**ClickHouse 暂时还不支持 Distributed Query 功能，如果这个能力支持，ClickHouse 存储计算分离就是一个威力无比的小氢弹。**

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
