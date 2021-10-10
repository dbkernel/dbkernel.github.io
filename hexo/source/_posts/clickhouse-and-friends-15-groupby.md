---
title: 源码分析 | ClickHouse和他的朋友们（15）Group By 为什么这么快
date: 2021-01-26 21:31:12
categories:
- ClickHouse
tags:
- ClickHouse和他的朋友们
- ClickHouse
- group by
- 源码分析
toc: true
---

<!-- more -->


**本文首发于 2021-01-26 21:31:12**

>《ClickHouse和他的朋友们》系列文章转载自圈内好友 [BohuTANG](https://bohutang.me/) 的博客，原文链接：
>https://bohutang.me/2021/01/21/clickhouse-and-friends-groupby/
>以下为正文。

在揭秘 ClickHouse Group By 之前，先聊聊数据库的性能对比测试问题。

在虎哥看来，一个“讲武德”的性能对比测试应该提供什么信息呢？

首先要尊重客观事实，在什么场景下，x 比 y 快？
其次是为什么 x 会比 y 快？

如果以上两条都做到了，还有一点也比较重要： x 的优势可以支撑多久？ 是架构等带来的长期优势，还是一袋烟的优化所得，是否能持续跟上自己的灵魂。

如果只是贴几个妖艳的数字，算不上是 benchmark，而是 benchmarket。

好了，回到 Group By 正题。

相信很多同学已经体验到 ClickHouse Group By 的出色性能，本篇就来分析下快的原因。

首先安慰一下，ClickHouse 的 Group By 并没有使用高大上的黑科技，只是摸索了一条相对较优的方案。

## 一条 SQL

```sql
SELECT sum(number) FROM numbers(10) GROUP BY number % 3
```

我们就以这条简单的 SQL 作为线索，看看 ClickHouse 怎么实现 Group By 聚合。

## 1. 生成 AST

```sql
EXPLAIN AST
SELECT sum(number)
FROM numbers(10)
GROUP BY number % 3

┌─explain─────────────────────────────────────┐
│ SelectWithUnionQuery (children 1)           │
│  ExpressionList (children 1)                │
│   SelectQuery (children 3)                  │
│    ExpressionList (children 1)              │
│     Function sum (children 1)               │  // sum 聚合
│      ExpressionList (children 1)            │
│       Identifier number                     │
│    TablesInSelectQuery (children 1)         │
│     TablesInSelectQueryElement (children 1) │
│      TableExpression (children 1)           │
│       Function numbers (children 1)         │
│        ExpressionList (children 1)          │
│         Literal UInt64_10                   │
│    ExpressionList (children 1)              │
│     Function modulo (children 1)            │  // number % 3 函数
│      ExpressionList (children 2)            │
│       Identifier number                     │
│       Literal UInt64_3                      │
└─────────────────────────────────────────────┘
```

## 2. 生成 Query Plan

```sql
EXPLAIN
SELECT sum(number)
FROM numbers(10)
GROUP BY number % 3

┌─explain───────────────────────────────────────────────────────────────────────┐
│ Expression ((Projection + Before ORDER BY))                                   │
│   Aggregating                                                                 │ // sum 聚合
│     Expression (Before GROUP BY)                                              │ // number % 3
│       SettingQuotaAndLimits (Set limits and quota after reading from storage) │
│         ReadFromStorage (SystemNumbers)                                       │
└───────────────────────────────────────────────────────────────────────────────┘
```

代码主要在 [InterpreterSelectQuery::executeImpl@Interpreters/InterpreterSelectQuery.cpp](https://github.com/ClickHouse/ClickHouse/blob/27ddf78ba572b893cb5351541f566d1080d8a9c6/src/Interpreters/InterpreterSelectQuery.cpp#L1063)

## 3. 生成 Pipeline

```sql
EXPLAIN PIPELINE
SELECT sum(number)
FROM numbers(10)
GROUP BY number % 3

┌─explain───────────────────────┐
│ (Expression)                  │
│ ExpressionTransform           │
│   (Aggregating)               │
│   AggregatingTransform        │  // sum 计算
│     (Expression)              │
│     ExpressionTransform       │  // number % 3 计算
│       (SettingQuotaAndLimits) │
│         (ReadFromStorage)     │
└───────────────────────────────┘
```

## 4. 执行 Pipeline

Pipeline 是从底部往上逐一执行。

### 4.1 ReadFromStorage

首先从 ReadFromStorage 执行，生成一个 block1， 数据如下:

```sql
┌─number─┐
│      0 │
│      1 │
│      2 │
│      3 │
│      4 │
│      5 │
│      6 │
│      7 │
│      8 │
│      9 │
└────────┘
number类型为 UInt64
```

### 4.2 ExpressionTransform

ExpressionTransform 包含了 2 个 action:

1. 名字为 number，type 为 INPUT
2. 名字为 `modulo(number, 3)`， type 为 FUNCTION

经过 ExpressionTransform 运行处理后生成一个新的 block2， 数据如下:

```sql
┌─number─┬─modulo(number, 3)─┐
│      0 │                 0 │
│      1 │                 1 │
│      2 │                 2 │
│      3 │                 0 │
│      4 │                 1 │
│      5 │                 2 │
│      6 │                 0 │
│      7 │                 1 │
│      8 │                 2 │
│      9 │                 0 │
└────────┴───────────────────┘
number 类型为 UInt64
modulo(number, 3) 类型为 UInt8
```

代码主要在 [ExpressionActions::execute@Interpreters/ExpressionActions.cpp](https://github.com/ClickHouse/ClickHouse/blob/27ddf78ba572b893cb5351541f566d1080d8a9c6/src/Interpreters/ExpressionActions.cpp#L416)

### 4.3 AggregatingTransform

AggregatingTransform 是 Group By 高性能的核心所在。
本示例中的 `modulo(number, 3)` 类型为 UInt8，在做优化上，ClickHouse 会选择使用数组代替 hashtable作为分组，区分逻辑见 [Interpreters/Aggregator.cpp](https://github.com/ClickHouse/ClickHouse/blob/27ddf78ba572b893cb5351541f566d1080d8a9c6/src/Interpreters/Aggregator.cpp#L526)

在计算 sum 的时候，首先会生成一个数组 [1024]，然后做了一个编译展开(代码 [addBatchLookupTable8@AggregateFunctions/IAggregateFunction.h](https://github.com/ClickHouse/ClickHouse/blob/27ddf78ba572b893cb5351541f566d1080d8a9c6/src/AggregateFunctions/IAggregateFunction.h#L412-L487)):

```cpp
static constexpr size_t UNROLL_COUNT = 4;
std::unique_ptr<Data[]> places{new Data[256 * UNROLL_COUNT]};
bool has_data[256 * UNROLL_COUNT]{}; /// Separate flags array to avoid heavy initialization.

size_t i = 0;

/// Aggregate data into different lookup tables.
size_t batch_size_unrolled = batch_size / UNROLL_COUNT * UNROLL_COUNT;
for (; i < batch_size_unrolled; i += UNROLL_COUNT)
{
    for (size_t j = 0; j < UNROLL_COUNT; ++j)
    {
        size_t idx = j * 256 + key[i + j];
        if (unlikely(!has_data[idx]))
        {
            new (&places[idx]) Data;
            has_data[idx] = true;
        }
        func.add(reinterpret_cast<char *>(&places[idx]), columns, i + j, nullptr);
    }
}
```

`sum(number) … GROUP BY number % 3` 计算方式：

```
array[0] = 0 + 3 + 6 + 9 = 18
array[1] = 1 + 4 + 7 = 12
array[2] = 2 + 5 + 8 = 15
```

这里只是针对 UInt8 做的一个优化分支，那么对于其他类型怎么优化处理呢？
ClickHouse 针对不同的类型分别提供了不同的 hashtable，声势比较浩大（代码见 [Aggregator.h](https://github.com/ClickHouse/ClickHouse/blob/27ddf78ba572b893cb5351541f566d1080d8a9c6/src/Interpreters/Aggregator.h#L68-L103)）：

```cpp
using AggregatedDataWithUInt8Key = FixedImplicitZeroHashMapWithCalculatedSize<UInt8, AggregateDataPtr>;
using AggregatedDataWithUInt16Key = FixedImplicitZeroHashMap<UInt16, AggregateDataPtr>;
using AggregatedDataWithUInt32Key = HashMap<UInt32, AggregateDataPtr, HashCRC32<UInt32>>;
using AggregatedDataWithUInt64Key = HashMap<UInt64, AggregateDataPtr, HashCRC32<UInt64>>;
using AggregatedDataWithShortStringKey = StringHashMap<AggregateDataPtr>;
using AggregatedDataWithStringKey = HashMapWithSavedHash<StringRef, AggregateDataPtr>;
using AggregatedDataWithKeys128 = HashMap<UInt128, AggregateDataPtr, UInt128HashCRC32>;
using AggregatedDataWithKeys256 = HashMap<DummyUInt256, AggregateDataPtr, UInt256HashCRC32>;
using AggregatedDataWithUInt32KeyTwoLevel = TwoLevelHashMap<UInt32, AggregateDataPtr, HashCRC32<UInt32>>;
using AggregatedDataWithUInt64KeyTwoLevel = TwoLevelHashMap<UInt64, AggregateDataPtr, HashCRC32<UInt64>>;
using AggregatedDataWithShortStringKeyTwoLevel = TwoLevelStringHashMap<AggregateDataPtr>;
using AggregatedDataWithStringKeyTwoLevel = TwoLevelHashMapWithSavedHash<StringRef, AggregateDataPtr>;
using AggregatedDataWithKeys128TwoLevel = TwoLevelHashMap<UInt128, AggregateDataPtr, UInt128HashCRC32>;
using AggregatedDataWithKeys256TwoLevel = TwoLevelHashMap<DummyUInt256, AggregateDataPtr, UInt256HashCRC32>;
using AggregatedDataWithUInt64KeyHash64 = HashMap<UInt64, AggregateDataPtr, DefaultHash<UInt64>>;
using AggregatedDataWithStringKeyHash64 = HashMapWithSavedHash<StringRef, AggregateDataPtr, StringRefHash64>;
using AggregatedDataWithKeys128Hash64 = HashMap<UInt128, AggregateDataPtr, UInt128Hash>;
using AggregatedDataWithKeys256Hash64 = HashMap<DummyUInt256, AggregateDataPtr, UInt256Hash>;
```

如果我们改成 `GROUP BY number*100000` 后，它会选择 AggregatedDataWithUInt64Key 的 hashtable 作为分组。

而且 ClickHouse 提供了一种 Two Level 方式，用语应对有大量分组 key 的情况，Level1 先分大组，Level2 小组可以并行计算。

针对 String 类型，根据不同的长度，hashtable 也做了很多优化，代码见 [HashTable/StringHashMap.h](https://github.com/ClickHouse/ClickHouse/blob/27ddf78ba572b893cb5351541f566d1080d8a9c6/src/Common/HashTable/StringHashMap.h#L78-L82)

## 总结

ClickHouse 会根据 Group By 的最终类型，选择一个最优的 hashtable 或数组，作为分组基础数据结构，使内存和计算尽量最优。

这个”最优解“是怎么找到的？从 test 代码可以看出，是不停的尝试、测试验证出来的，浓厚的 bottom-up 哲学范。

hashtable 测试代码：[Interpreters/tests](https://github.com/ClickHouse/ClickHouse/tree/27ddf78ba572b893cb5351541f566d1080d8a9c6/src/Interpreters/tests)

lookuptable 测试代码： [tests/average.cpp](https://github.com/ClickHouse/ClickHouse/blob/27ddf78ba572b893cb5351541f566d1080d8a9c6/src/Common/tests/average.cpp)


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


