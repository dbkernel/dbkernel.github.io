---
title: 源码分析 | ClickHouse和他的朋友们（2）MySQL Protocol和Read调用栈
date: 2020-06-07 17:17:10
categories:
- ClickHouse
tags:
- ClickHouse和他的朋友们
- ClickHouse
- 源码分析
toc: true
---

<!-- more -->

**本文首发于 2020-06-07 17:17:10**

>《ClickHouse和他的朋友们》系列文章转载自圈内好友 [BohuTANG](https://bohutang.me/) 的博客，原文链接：
>https://bohutang.me/2020/06/07/clickhouse-and-friends-mysql-protocol-read-stack/
>以下为正文。

作为一个 OLAP 的 DBMS 来说，有2个端非常重要：

- 用户如何方便的链进来，这是入口端
  - ClickHouse 除了自己的 client 外，还提供了 MySQL/PG/GRPC/HTTP 等接入方式
- 数据如何方便的挂上去，这是数据源端
  - ClickHouse 除了自己的引擎外，还可以挂载 MySQL/Kafka 等外部数据源

这样内外互通，多条朋友多条路，以实现“数据”级的编排能力。

今天谈的是入口端的 MySQL 协议，也是本系列 ClickHouse 的第一个好朋友，用户可通过 MySQL 客户端或相关 Driver 直接链接到 ClickHouse，进行数据读写等操作。

本文通过 MySQL的 Query 请求，借用调用栈来了解下 ClickHouse 的数据读取全过程。

## **如何实现？**

入口文件在:
[MySQLHandler.cpp](https://github.com/ClickHouse/ClickHouse/blob/master/src/Server/MySQLHandler.cpp)

### **握手协议**

1. MySQLClient 发送 Greeting 数据报文到 MySQLHandler
2. MySQLHandler 回复一个 Greeting-Response 报文
3. MySQLClient 发送认证报文
4. MySQLHandler 对认证报文进行鉴权，并返回鉴权结果

MySQL Protocol 实现在: [Core/MySQLProtocol.h](https://github.com/ClickHouse/ClickHouse/blob/master/src/Core/MySQLProtocol.h)

>最近的代码中调整为了 [Core/MySQL/PacketsProtocolText.h](https://github.com/ClickHouse/ClickHouse/blob/master/src/Core/MySQL/PacketsProtocolText.h)

### **Query请求**

当认证通过后，就可以进行正常的数据交互了。

1. 当 MySQLClient 发送请求:

   ```sql
   mysql> SELECT * FROM system.numbers LIMIT 5;
   ```

2. MySQLHandler 的调用栈：

   ```
   ->MySQLHandler::comQuery -> executeQuery -> pipeline->execute -> MySQLOutputFormat::consume
   ```

3. MySQLClient 接收到结果

在步骤2里，executeQuery(executeQuery.cpp)非常重要。
它是所有前端 Server 和 ClickHouse 内核的接入口，第一个参数是 SQL 文本(‘select 1’)，第二个参数是结果集要发送到哪里去(socket net)。

## **调用栈分析**

```
SELECT * FROM system.numbers LIMIT 5
```

### 1. 获取数据源

StorageSystemNumbers 数据源：

```cpp
DB::StorageSystemNumbers::read(std::__1::vector<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> >, std::__1::allocator<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > > > const&, std::__1::shared_ptr<DB::StorageInMemoryMetadata const> const&, DB::SelectQueryInfo const&, DB::Context const&, DB::QueryProcessingStage::Enum, unsigned long, unsigned int) StorageSystemNumbers.cpp:135
DB::ReadFromStorageStep::ReadFromStorageStep(std::__1::shared_ptr<DB::RWLockImpl::LockHolderImpl>, std::__1::shared_ptr<DB::StorageInMemoryMetadata const>&, DB::SelectQueryOptions,
DB::InterpreterSelectQuery::executeFetchColumns(DB::QueryProcessingStage::Enum, DB::QueryPlan&, std::__1::shared_ptr<DB::PrewhereInfo> const&, std::__1::vector<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> >, std::__1::allocator<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > > > const&) memory:3028
DB::InterpreterSelectQuery::executeFetchColumns(DB::QueryProcessingStage::Enum, DB::QueryPlan&, std::__1::shared_ptr<DB::PrewhereInfo> const&, std::__1::vector<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> >, std::__1::allocator<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > > > const&) InterpreterSelectQuery.cpp:1361
DB::InterpreterSelectQuery::executeImpl(DB::QueryPlan&, std::__1::shared_ptr<DB::IBlockInputStream> const&, std::__1::optional<DB::Pipe>) InterpreterSelectQuery.cpp:791
DB::InterpreterSelectQuery::buildQueryPlan(DB::QueryPlan&) InterpreterSelectQuery.cpp:472
DB::InterpreterSelectWithUnionQuery::buildQueryPlan(DB::QueryPlan&) InterpreterSelectWithUnionQuery.cpp:183
DB::InterpreterSelectWithUnionQuery::execute() InterpreterSelectWithUnionQuery.cpp:198
DB::executeQueryImpl(const char *, const char *, DB::Context &, bool, DB::QueryProcessingStage::Enum, bool, DB::ReadBuffer *) executeQuery.cpp:385
DB::executeQuery(DB::ReadBuffer&, DB::WriteBuffer&, bool, DB::Context&, std::__1::function<void (std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&,
DB::MySQLHandler::comQuery(DB::ReadBuffer&) MySQLHandler.cpp:307
DB::MySQLHandler::run() MySQLHandler.cpp:141
```

这里最主要的是 ReadFromStorageStep 函数，从不同 storage 里获取数据源 pipe:

```cpp
Pipes pipes = storage->read(required_columns, metadata_snapshot, query_info, *context, processing_stage, max_block_size, max_streams);
```

### 2. Pipeline构造

```cpp
DB::LimitTransform::LimitTransform(DB::Block const&, unsigned long, unsigned long, unsigned long, bool, bool, std::__1::vector<DB::SortColumnDescription, std::__1::allocator<DB::SortColumnDescription> >) LimitTransform.cpp:21
DB::LimitStep::transformPipeline(DB::QueryPipeline&) memory:2214
DB::LimitStep::transformPipeline(DB::QueryPipeline&) memory:2299
DB::LimitStep::transformPipeline(DB::QueryPipeline&) memory:3570
DB::LimitStep::transformPipeline(DB::QueryPipeline&) memory:4400
DB::LimitStep::transformPipeline(DB::QueryPipeline&) LimitStep.cpp:33
DB::ITransformingStep::updatePipeline(std::__1::vector<std::__1::unique_ptr<DB::QueryPipeline, std::__1::default_delete<DB::QueryPipeline> >, std::__1::allocator<std::__1::unique_ptr<DB::QueryPipeline, std::__1::default_delete<DB::QueryPipeline> > > >) ITransformingStep.cpp:21
DB::QueryPlan::buildQueryPipeline() QueryPlan.cpp:154
DB::InterpreterSelectWithUnionQuery::execute() InterpreterSelectWithUnionQuery.cpp:200
DB::executeQueryImpl(const char *, const char *, DB::Context &, bool, DB::QueryProcessingStage::Enum, bool, DB::ReadBuffer *) executeQuery.cpp:385
DB::executeQuery(DB::ReadBuffer&, DB::WriteBuffer&, bool, DB::Context&, std::__1::function<void (std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&)>) executeQuery.cpp:722
DB::MySQLHandler::comQuery(DB::ReadBuffer&) MySQLHandler.cpp:307
DB::MySQLHandler::run() MySQLHandler.cpp:141
```

### 3. Pipeline执行

```cpp
DB::LimitTransform::prepare(std::__1::vector<unsigned long, std::__1::allocator<unsigned long> > const&, std::__1::vector<unsigned long, std::__1::allocator<unsigned long> > const&) LimitTransform.cpp:67
DB::PipelineExecutor::prepareProcessor(unsigned long, unsigned long, std::__1::queue<DB::PipelineExecutor::ExecutionState*, std::__1::deque<DB::PipelineExecutor::ExecutionState*, std::__1::allocator<DB::PipelineExecutor::ExecutionState*> > >&, std::__1::unique_lock<std::__1::mutex>) PipelineExecutor.cpp:291
DB::PipelineExecutor::tryAddProcessorToStackIfUpdated(DB::PipelineExecutor::Edge&, std::__1::queue<DB::PipelineExecutor::ExecutionState*, std::__1::deque<DB::PipelineExecutor::ExecutionState*, std::__1::allocator<DB::PipelineExecutor::ExecutionState*> > >&, unsigned long) PipelineExecutor.cpp:264
DB::PipelineExecutor::prepareProcessor(unsigned long, unsigned long, std::__1::queue<DB::PipelineExecutor::ExecutionState*, std::__1::deque<DB::PipelineExecutor::ExecutionState*, std::__1::allocator<DB::PipelineExecutor::ExecutionState*> > >&, std::__1::unique_lock<std::__1::mutex>) PipelineExecutor.cpp:373
DB::PipelineExecutor::tryAddProcessorToStackIfUpdated(DB::PipelineExecutor::Edge&, std::__1::queue<DB::PipelineExecutor::ExecutionState*, std::__1::deque<DB::PipelineExecutor::ExecutionState*, std::__1::allocator<DB::PipelineExecutor::ExecutionState*> > >&, unsigned long) PipelineExecutor.cpp:264
DB::PipelineExecutor::prepareProcessor(unsigned long, unsigned long, std::__1::queue<DB::PipelineExecutor::ExecutionState*, std::__1::deque<DB::PipelineExecutor::ExecutionState*, std::__1::allocator<DB::PipelineExecutor::ExecutionState*> > >&, std::__1::unique_lock<std::__1::mutex>) PipelineExecutor.cpp:373
DB::PipelineExecutor::tryAddProcessorToStackIfUpdated(DB::PipelineExecutor::Edge&, std::__1::queue<DB::PipelineExecutor::ExecutionState*, std::__1::deque<DB::PipelineExecutor::ExecutionState*, std::__1::allocator<DB::PipelineExecutor::ExecutionState*> > >&, unsigned long) PipelineExecutor.cpp:264
DB::PipelineExecutor::prepareProcessor(unsigned long, unsigned long, std::__1::queue<DB::PipelineExecutor::ExecutionState*, std::__1::deque<DB::PipelineExecutor::ExecutionState*, std::__1::allocator<DB::PipelineExecutor::ExecutionState*> > >&, std::__1::unique_lock<std::__1::mutex>) PipelineExecutor.cpp:373
DB::PipelineExecutor::tryAddProcessorToStackIfUpdated(DB::PipelineExecutor::Edge&, std::__1::queue<DB::PipelineExecutor::ExecutionState*, std::__1::deque<DB::PipelineExecutor::ExecutionState*, std::__1::allocator<DB::PipelineExecutor::ExecutionState*> > >&, unsigned long) PipelineExecutor.cpp:264
DB::PipelineExecutor::prepareProcessor(unsigned long, unsigned long, std::__1::queue<DB::PipelineExecutor::ExecutionState*, std::__1::deque<DB::PipelineExecutor::ExecutionState*, std::__1::allocator<DB::PipelineExecutor::ExecutionState*> > >&, std::__1::unique_lock<std::__1::mutex>) PipelineExecutor.cpp:373
DB::PipelineExecutor::tryAddProcessorToStackIfUpdated(DB::PipelineExecutor::Edge&, std::__1::queue<DB::PipelineExecutor::ExecutionState*, std::__1::deque<DB::PipelineExecutor::ExecutionState*, std::__1::allocator<DB::PipelineExecutor::ExecutionState*> > >&, unsigned long) PipelineExecutor.cpp:264
DB::PipelineExecutor::prepareProcessor(unsigned long, unsigned long, std::__1::queue<DB::PipelineExecutor::ExecutionState*, std::__1::deque<DB::PipelineExecutor::ExecutionState*, std::__1::allocator<DB::PipelineExecutor::ExecutionState*> > >&, std::__1::unique_lock<std::__1::mutex>) PipelineExecutor.cpp:373
DB::PipelineExecutor::initializeExecution(unsigned long) PipelineExecutor.cpp:747
DB::PipelineExecutor::executeImpl(unsigned long) PipelineExecutor.cpp:764
DB::PipelineExecutor::execute(unsigned long) PipelineExecutor.cpp:479
DB::executeQuery(DB::ReadBuffer&, DB::WriteBuffer&, bool, DB::Context&, std::__1::function<void (std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&)>) executeQuery.cpp:833
DB::MySQLHandler::comQuery(DB::ReadBuffer&) MySQLHandler.cpp:307
DB::MySQLHandler::run() MySQLHandler.cpp:141
```

### 4. Output执行发送

```cpp
DB::MySQLOutputFormat::consume(DB::Chunk) MySQLOutputFormat.cpp:53
DB::IOutputFormat::work() IOutputFormat.cpp:62
DB::executeJob(DB::IProcessor *) PipelineExecutor.cpp:155
operator() PipelineExecutor.cpp:172
DB::PipelineExecutor::executeStepImpl(unsigned long, unsigned long, std::__1::atomic<bool>*) PipelineExecutor.cpp:630
DB::PipelineExecutor::executeSingleThread(unsigned long, unsigned long) PipelineExecutor.cpp:546
DB::PipelineExecutor::executeImpl(unsigned long) PipelineExecutor.cpp:812
DB::PipelineExecutor::execute(unsigned long) PipelineExecutor.cpp:479
DB::executeQuery(DB::ReadBuffer&, DB::WriteBuffer&, bool, DB::Context&, std::__1::function<void (std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&)>) executeQuery.cpp:800
DB::MySQLHandler::comQuery(DB::ReadBuffer&) MySQLHandler.cpp:311
DB::MySQLHandler::run() MySQLHandler.cpp:141
```

## **总结**

ClickHouse 的模块化比较清晰，像乐高积木一样可以组合拼装，当我们执行:

```sql
SELECT * FROM system.numbers LIMIT 5
```

首先内核解析 SQL 语句生成 AST，然后根据 AST 获取数据源 Source，pipeline.Add(Source)。
其次根据 AST 信息生成 QueryPlan，根据 QueryPlan 再生成相应的 Transform，pipeline.Add(LimitTransform)。
然后添加 Output Sink 作为数据发送对象，pipeline.Add(OutputSink)。
执行 pipeline, 各个 Transformer 开始工作。

ClickHouse 的 Transformer 调度系统叫做 Processor，也是决定性能的重要模块，详情见 [Pipeline 处理器和调度器](https://bohutang.me/2020/06/11/clickhouse-and-friends-processor/)。
ClickHouse 是一辆手动挡的豪华跑车，免费拥有，海啸们！

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

