---
title: 特性分析 | GreenPlum Primary/Mirror 同步机制
date: 2016-01-21 20:02:26
categories:
  - GreenPlum
tags:
  - PostgreSQL
  - GreenPlum
  - 主从同步
toc: true
---

<!-- more -->

> **本文首发于 2016-01-21 20:02:26**

## 引言

PostgreSQL 主备同步机制是通过流复制实现，其原理见 [PG 主备流复制机制](http://mysql.taobao.org/monthly/2015/10/04/)。

Greenplum 是基于 PostgreSQL 开发的，它的主备也是通过流复制实现，但是 **Segment 节点中的 Primary 和 Mirror 之间的数据同步是基于文件级别的同步实现的**。

`为什么Primary和Mirror不能再使用流复制实现呢？`

> 主要有两个原因:
>
> 1.  `Append Only` 表不写 WAL 日志，所以 Append Only 表的数据就不能通过 XLOG 发送到 Mirror 再 Apply 。
> 2.  `pg_control`等文件也是不写 WAL 日志，也只能通过文件方式同步到 Mirror 。

## GreenPlum 总体结构

Greenplum 的架构采用了 MPP 无共享体系。在 MPP 系统中，每个数据节点有自己的 CPU、磁盘和内存(Share nothing)，每个节点内的 CPU 不能访问另一个节点的内存。节点之间的信息交互是通过节点互联网络实现的，这个过程一般称为**数据重分配**(Data Redistribution)。

Master 负责协调整个集群 ，一个数据节点可以配置多个节点实例(Segment Instances)，节点实例并行处理查询(SQL)。

![GreenPlum 总体架构](greenplum-architecture-overview.jpg)

## Primary 和 Mirror 同步机制

Primary 和 Mirror 同步的内容主要有两部分，即**文件**和**数据**。之所以 Primary 和 Mirror 要同步文件，是 Primary 和 Mirror 之间可以自动 failover，只有两者保持同步才能相互替代。如果只把数据同步过去，`pg_control、pg_clog、pg_subtrans` 没有同步，那么从 Primary 切换到 Mirror 会出现问题。

Master 和 slave 却不用担心这些问题，Append Only 表的数据只会存在 Segment，所以 **WAL 日志足够保持 Master 和 slave 同步**(只要是流复制，pg_control、pg_clog、pg_subtrans 这些文件 Slave 会自动更新，无需从 Master 同步)。

### 1. 数据同步

当 Master 向 Primary 下发执行计划后，Primary 开始执行，如果是 DML 操作，那么 Primary 会产生 XLOG 及更新 page。会在 `SlruPhysicalWritePage` 函数中(写数据页)产生`FileRepOperationOpen、FileRepOperationWrite、FileRepOperationFlush、FileRepOperationClose`等指令消息(消息中包含具体要更新的文件 page 及内容)，通过 `primary sender` 进程向 Mirror 发送 Message，然后 Mirror 的 `mirror consumer` 等进程解析消息，执行变更。XLOG 通过`XLogWrite`函数(写 XLOG)执行同样的操作，把 XLOG 更新同步过去。

### 2. 文件同步

Primary 会有个 `recovery` 进程，这个进程会循环把 Primary 的 `pg_control、pg_clog、pg_subtrans` 等文件覆盖到 Mirror。同时检查 XLOG 是否一致，如果不一致以 Primary 为主，对 Mirror 进行覆盖。除了把 Primary 部分文件同步到 Mirror 之外，`recovery` 进程还会将 Mirror 上面的临时文件删掉。

![GreenPlum 主从同步机制](greenplum-primary-mirror-sync.jpg)

## 总结

Primary 和 Mirror 同步数据的时候，Primary 对于每一次写 page 都会通过消息发送到 Mirror，如果 Primary 大量的更新 page，那么 Primary 和 Mirror 同步将有可能成为瓶颈。

> 本文转自：http://mysql.taobao.org/monthly/2016/01/02/

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
