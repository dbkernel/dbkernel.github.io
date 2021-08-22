---
title: 源码分析 | ClickHouse和他的朋友们（3）MySQL Protocol和Write调用栈
date: 2020-06-08 19:57:10
categories:
- ClickHouse
tags:
- ClickHouse和他的朋友们
- ClickHouse
- 源码分析
toc: true
---

<!-- more -->

>《ClickHouse和他的朋友们》系列文章转载自圈内好友 [BohuTANG](https://bohutang.me/) 的博客，原文链接：
>https://bohutang.me/2020/06/08/clickhouse-and-friends-mysql-protocol-write-stack/
>以下为正文。

上篇的[MySQL Protocol和Read调用](https://dbkernel.github.io/2020/06/07/clickhouse-and-friends-02-mysql-protocol-read-stack/)里介绍了 ClickHouse 一条查询语句的调用栈，本文继续介绍写的调用栈，开整。

## **Write请求**

1. 建表:

   ```sql
   mysql> CREATE TABLE test(a UInt8, b UInt8, c UInt8) ENGINE=MergeTree() PARTITION BY (a, b) ORDER BY c;
   Query OK, 0 rows affected (0.03 sec)
   ```

2. 写入数据：

   ```sql
   INSERT INTO test VALUES(1,1,1), (2,2,2);
   ```

## **调用栈分析**

### 1. 获取存储引擎 OutputStream

```cpp
DB::StorageMergeTree::write(std::__1::shared_ptr<DB::IAST> const&, DB::Context const&) StorageMergeTree.cpp:174
DB::PushingToViewsBlockOutputStream::PushingToViewsBlockOutputStream(std::__1::shared_ptr<DB::IStorage> const&, DB::Context const&, std::__1::shared_ptr<DB::IAST> const&, bool) PushingToViewsBlockOutputStream.cpp:110
DB::InterpreterInsertQuery::execute() InterpreterInsertQuery.cpp:229
DB::executeQueryImpl(const char *, const char *, DB::Context &, bool, DB::QueryProcessingStage::Enum, bool, DB::ReadBuffer *) executeQuery.cpp:364
DB::executeQuery(DB::ReadBuffer&, DB::WriteBuffer&, bool, DB::Context&, std::__1::function<void (std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&)>) executeQuery.cpp:696
DB::MySQLHandler::comQuery(DB::ReadBuffer&) MySQLHandler.cpp:311
DB::MySQLHandler::run() MySQLHandler.cpp:141
```

### 2. 从 SQL 组装 InputStream

`(1,1,1), (2,2,2)` 如何组装成 inputstream 结构呢？

```cpp
DB::InputStreamFromASTInsertQuery::InputStreamFromASTInsertQuery(std::__1::shared_ptr<DB::IAST> const&, DB::ReadBuffer*,
DB::InterpreterInsertQuery::execute() InterpreterInsertQuery.cpp:300
DB::executeQueryImpl(char const*, char const*, DB::Context&, bool, DB::QueryProcessingStage::Enum, bool, DB::ReadBuffer*) executeQuery.cpp:386
DB::MySQLHandler::comQuery(DB::ReadBuffer&) MySQLHandler.cpp:313
DB::MySQLHandler::run() MySQLHandler.cpp:150
```

然后

```cpp
res.in = std::make_shared<InputStreamFromASTInsertQuery>(query_ptr, nullptr, query_sample_block, context, nullptr);
res.in = std::make_shared<NullAndDoCopyBlockInputStream>(res.in, out_streams.at(0));
```

通过 NullAndDoCopyBlockInputStream的 copyData 方法构造出 Block：

```cpp
DB::ValuesBlockInputFormat::readRow(std::__1::vector<COW<DB::IColumn>::mutable_ptr<DB::IColumn>, std::__1::allocator<COW<DB::IColumn>::mutable_ptr<DB::IColumn> > >&, unsigned long) ValuesBlockInputFormat.cpp:93
DB::ValuesBlockInputFormat::generate() ValuesBlockInputFormat.cpp:55
DB::ISource::work() ISource.cpp:48
DB::InputStreamFromInputFormat::readImpl() InputStreamFromInputFormat.h:48
DB::IBlockInputStream::read() IBlockInputStream.cpp:57
DB::InputStreamFromASTInsertQuery::readImpl() InputStreamFromASTInsertQuery.h:31
DB::IBlockInputStream::read() IBlockInputStream.cpp:57
void DB::copyDataImpl<DB::copyData(DB::IBlockInputStream&, DB::IBlockOutputStream&, std::__1::atomic<bool>*)::$_0&, void (&)(DB::Block const&)>(DB::IBlockInputStream&, DB::IBlockOutputStream&, DB::copyData(DB::IBlockInputStream&, DB::IBlockOutputStream&, std::__1::atomic<bool>*)::$_0&, void (&)(DB::Block const&)) copyData.cpp:26
DB::copyData(DB::IBlockInputStream&, DB::IBlockOutputStream&, std::__1::atomic<bool>*) copyData.cpp:62
DB::NullAndDoCopyBlockInputStream::readImpl() NullAndDoCopyBlockInputStream.h:47
DB::IBlockInputStream::read() IBlockInputStream.cpp:57
void DB::copyDataImpl<std::__1::function<bool ()> const&, std::__1::function<void (DB::Block const&)> const&>(DB::IBlockInputStream&, DB::IBlockOutputStream&, std::__1::function<bool ()> const&, std::__1::function<void (DB::Block const&)> const&) copyData.cpp:26
DB::copyData(DB::IBlockInputStream&, DB::IBlockOutputStream&, std::__1::function<bool ()> const&, std::__1::function<void (DB::Block const&)> const&) copyData.cpp:73
DB::executeQuery(DB::ReadBuffer&, DB::WriteBuffer&, bool, DB::Context&, std::__1::function<void (std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&)>) executeQuery.cpp:785
DB::MySQLHandler::comQuery(DB::ReadBuffer&) MySQLHandler.cpp:313
DB::MySQLHandler::run() MySQLHandler.cpp:150
```

### 3. 组装 OutputStream

```cpp
DB::InterpreterInsertQuery::execute() InterpreterInsertQuery.cpp:107
DB::executeQueryImpl(const char *, const char *, DB::Context &, bool, DB::QueryProcessingStage::Enum, bool, DB::ReadBuffer *) executeQuery.cpp:364
DB::executeQuery(DB::ReadBuffer&, DB::WriteBuffer&, bool, DB::Context&, std::__1::function<void (std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&)>) executeQuery.cpp:696
DB::MySQLHandler::comQuery(DB::ReadBuffer&) MySQLHandler.cpp:311
DB::MySQLHandler::run() MySQLHandler.cpp:141
```

组装顺序:

1. NullAndDoCopyBlockInputStream
2. CountingBlockOutputStream
3. AddingDefaultBlockOutputStream
4. SquashingBlockOutputStream
5. PushingToViewsBlockOutputStream
6. MergeTreeBlockOutputStream

### 4. 写入OutputStream

```cpp
DB::MergeTreeBlockOutputStream::write(DB::Block const&) MergeTreeBlockOutputStream.cpp:17
DB::PushingToViewsBlockOutputStream::write(DB::Block const&) PushingToViewsBlockOutputStream.cpp:145
DB::SquashingBlockOutputStream::finalize() SquashingBlockOutputStream.cpp:30
DB::SquashingBlockOutputStream::writeSuffix() SquashingBlockOutputStream.cpp:50
DB::AddingDefaultBlockOutputStream::writeSuffix() AddingDefaultBlockOutputStream.cpp:25
DB::CountingBlockOutputStream::writeSuffix() CountingBlockOutputStream.h:37
DB::copyDataImpl<DB::copyData(DB::IBlockInputStream&, DB::IBlockOutputStream&, std::__1::atomic<bool>*)::<lambda()>&, void (&)(const DB::Block&)>(DB::IBlockInputStream &, DB::IBlockOutputStream &, <lambda()> &, void (&)(const DB::Block &)) copyData.cpp:52
DB::copyData(DB::IBlockInputStream&, DB::IBlockOutputStream&, std::__1::atomic<bool>*) copyData.cpp:138
DB::NullAndDoCopyBlockInputStream::readImpl() NullAndDoCopyBlockInputStream.h:57
DB::IBlockInputStream::read() IBlockInputStream.cpp:60
void DB::copyDataImpl<std::__1::function<bool ()> const&, std::__1::function<void (DB::Block const&)> const&>(DB::IBlockInputStream&, DB::IBlockOutputStream&, std::__1::function<bool ()> const&, std::__1::function<void (DB::Block const&)> const&) copyData.cpp:29
DB::copyData(DB::IBlockInputStream&, DB::IBlockOutputStream&, std::__1::function<bool ()> const&, std::__1::function<void (DB::Block const&)> const&) copyData.cpp:154
DB::executeQuery(DB::ReadBuffer&, DB::WriteBuffer&, bool, DB::Context&, std::__1::function<void (std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&)>) executeQuery.cpp:748
DB::MySQLHandler::comQuery(DB::ReadBuffer&) MySQLHandler.cpp:311
DB::MySQLHandler::run() MySQLHandler.cpp:141
```

通过 copyData 方法，让数据在 OutputStream 间层层透传，一直到 MergeTreeBlockOutputStream。

### 5. 返回 Client

```cpp
DB::MySQLOutputFormat::finalize() MySQLOutputFormat.cpp:62
DB::IOutputFormat::doWriteSuffix() IOutputFormat.h:78
DB::OutputStreamToOutputFormat::writeSuffix() OutputStreamToOutputFormat.cpp:18
DB::MaterializingBlockOutputStream::writeSuffix() MaterializingBlockOutputStream.h:22
void DB::copyDataImpl<std::__1::function<bool ()> const&, std::__1::function<void (DB::Block const&)> const&>(DB::IBlockInputStream&, DB::IBlockOutputStream&, std::__1::function<bool ()> const&, std::__1::function<void (DB::Block const&)> const&) copyData.cpp:52
DB::copyData(DB::IBlockInputStream&, DB::IBlockOutputStream&, std::__1::function<bool ()> const&, std::__1::function<void (DB::Block const&)> const&) copyData.cpp:154
DB::executeQuery(DB::ReadBuffer&, DB::WriteBuffer&, bool, DB::Context&, std::__1::function<void (std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&)>) executeQuery.cpp:748
DB::MySQLHandler::comQuery(DB::ReadBuffer&) MySQLHandler.cpp:311
DB::MySQLHandler::run() MySQLHandler.cpp:141
```

## **总结**

```sql
INSERT INTO test VALUES(1,1,1), (2,2,2);
```

首先内核解析 SQL 语句生成 AST，根据 AST 获取 Interpreter：InterpreterInsertQuery。
其次 Interpreter 依次添加相应的 OutputStream。
然后从 InputStream 读取数据，写入到 OutputStream，stream 会层层渗透，一直写到底层的存储引擎。
最后写入到 Socket Output，返回结果。

ClickHouse 的 OutputStream 编排还是比较复杂，缺少类似 Pipeline 的调度和编排，但是由于模式比较固化，目前看还算清晰。

----

欢迎关注我的微信公众号【MySQL数据库技术】。

<img src="https://dbkernel-1306518848.cos.ap-beijing.myqcloud.com/wechat/my-wechat-official-account.png" width="400" height="400" alt="MySQL数据库技术" align="left"/>

| 标题                 | 网址                                                  |
| -------------------- | ----------------------------------------------------- |
| GitHub                 | https://dbkernel.github.io           |
| 知乎                 | https://www.zhihu.com/people/dbkernel/posts           |
| 思否（SegmentFault） | https://segmentfault.com/u/dbkernel                   |
| 掘金                 | https://juejin.im/user/5e9d3ed251882538083fed1f/posts |
| 开源中国（oschina）  | https://my.oschina.net/dbkernel                       |
| 博客园（cnblogs）    | https://www.cnblogs.com/dbkernel                      |