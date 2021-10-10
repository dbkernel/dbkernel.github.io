---
title: 源码分析 | ClickHouse和他的朋友们（８）纯手工打造的SQL解析器
date: 2020-07-26 21:55:10
categories:
- ClickHouse
tags:
- ClickHouse和他的朋友们
- ClickHouse
- Parser
- 源码分析
toc: true
---

<!-- more -->

**本文首发于 2020-07-26 21:55:10**

>《ClickHouse和他的朋友们》系列文章转载自圈内好友 [BohuTANG](https://bohutang.me/) 的博客，原文链接：
>https://bohutang.me/2020/07/25/clickhouse-and-friends-parser/
>以下为正文。

现实生活中的物品一旦被标记为“纯手工打造”，给人的第一感觉就是“上乘之品”，一个字“贵”，比如北京老布鞋。

但是在计算机世界里，如果有人告诉你 ClickHouse 的 SQL 解析器是纯手工打造的，是不是很惊讶！

这个问题引起了不少网友的关注，所以本篇聊聊 ClickHouse 的纯手工解析器，看看它们的底层工作机制及优缺点。

枯燥先从一个 SQL 开始：

```sql
EXPLAIN SELECT a,b FROM t1
```

## token

首先对 SQL 里的字符逐个做判断，然后根据其关联性做 token 分割：

![parser.png](parser.png)


比如连续的 WordChar，那它就是 BareWord，解析函数在 [Lexer::nextTokenImpl()](https://github.com/ClickHouse/ClickHouse/blob/558f9c76306ffc4e6add8fd34c2071b64e914103/src/Parsers/Lexer.cpp#L61)，解析调用栈：

```cpp
DB::Lexer::nextTokenImpl() Lexer.cpp:63
DB::Lexer::nextToken() Lexer.cpp:52
DB::Tokens::operator[](unsigned long) TokenIterator.h:36
DB::TokenIterator::get() TokenIterator.h:62
DB::TokenIterator::operator->() TokenIterator.h:64
DB::tryParseQuery(DB::IParser&, char const*&, char const*, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> >&, bool, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, bool, unsigned long, unsigned long) parseQuery.cpp:224
DB::parseQueryAndMovePosition(DB::IParser&, char const*&, char const*, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, bool, unsigned long, unsigned long) parseQuery.cpp:314
DB::parseQuery(DB::IParser&, char const*, char const*, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, unsigned long, unsigned long) parseQuery.cpp:332
DB::executeQueryImpl(const char *, const char *, DB::Context &, bool, DB::QueryProcessingStage::Enum, bool, DB::ReadBuffer *) executeQuery.cpp:272
DB::executeQuery(DB::ReadBuffer&, DB::WriteBuffer&, bool, DB::Context&, std::__1::function<void (std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&)>) executeQuery.cpp:731
DB::MySQLHandler::comQuery(DB::ReadBuffer&) MySQLHandler.cpp:313
DB::MySQLHandler::run() MySQLHandler.cpp:150
```

## ast

token 是最基础的元组，他们之间没有任何关联，只是一堆生冷的词组与符号，所以我们还需对其进行**语法解析**，让这些 token 之间建立一定的关系，达到一个可描述的活力。

ClickHouse 在解每一个 token 的时候，会根据当前的 token 进行状态空间进行预判（parse 返回 true 则进入子状态空间继续），然后决定状态跳转，比如：

```sql
EXPLAIN  -- TokenType::BareWord
```

逻辑首先会进入Parsers/ParserQuery.cpp 的 [ParserQuery::parseImpl](https://github.com/ClickHouse/ClickHouse/blob/558f9c76306ffc4e6add8fd34c2071b64e914103/src/Parsers/ParserQuery.cpp#L26) 方法：

```cpp
bool res = query_with_output_p.parse(pos, node, expected)
    || insert_p.parse(pos, node, expected)
    || use_p.parse(pos, node, expected)
    || set_role_p.parse(pos, node, expected)
    || set_p.parse(pos, node, expected)
    || system_p.parse(pos, node, expected)
    || create_user_p.parse(pos, node, expected)
    || create_role_p.parse(pos, node, expected)
    || create_quota_p.parse(pos, node, expected)
    || create_row_policy_p.parse(pos, node, expected)
    || create_settings_profile_p.parse(pos, node, expected)
    || drop_access_entity_p.parse(pos, node, expected)
    || grant_p.parse(pos, node, expected);
```

这里会对所有 query 类型进行 parse 方法的调用，直到有分支返回 true。

我们来看**第一层** query_with_output_p.parse [Parsers/ParserQueryWithOutput.cpp](https://github.com/ClickHouse/ClickHouse/blob/558f9c76306ffc4e6add8fd34c2071b64e914103/src/Parsers/ParserQueryWithOutput.cpp#L31)：

```cpp
bool parsed =
       explain_p.parse(pos, query, expected)
    || select_p.parse(pos, query, expected)
    || show_create_access_entity_p.parse(pos, query, expected)
    || show_tables_p.parse(pos, query, expected)
    || table_p.parse(pos, query, expected)
    || describe_table_p.parse(pos, query, expected)
    || show_processlist_p.parse(pos, query, expected)
    || create_p.parse(pos, query, expected)
    || alter_p.parse(pos, query, expected)
    || rename_p.parse(pos, query, expected)
    || drop_p.parse(pos, query, expected)
    || check_p.parse(pos, query, expected)
    || kill_query_p.parse(pos, query, expected)
    || optimize_p.parse(pos, query, expected)
    || watch_p.parse(pos, query, expected)
    || show_access_p.parse(pos, query, expected)
    || show_access_entities_p.parse(pos, query, expected)
    || show_grants_p.parse(pos, query, expected)
    || show_privileges_p.parse(pos, query, expected
```

跳进**第二层** explain_p.parse [ParserExplainQuery::parseImpl](https://github.com/ClickHouse/ClickHouse/blob/558f9c76306ffc4e6add8fd34c2071b64e914103/src/Parsers/ParserExplainQuery.cpp#L10)状态空间：

```cpp
bool ParserExplainQuery::parseImpl(Pos & pos, ASTPtr & node, Expected & expected)
{
    ASTExplainQuery::ExplainKind kind;
    bool old_syntax = false;

    ParserKeyword s_ast("AST");
    ParserKeyword s_analyze("ANALYZE");
    ParserKeyword s_explain("EXPLAIN");
    ParserKeyword s_syntax("SYNTAX");
    ParserKeyword s_pipeline("PIPELINE");
    ParserKeyword s_plan("PLAN");

    ... ...
    else if (s_explain.ignore(pos, expected))
    {
       ... ...
    }

    ... ...

    ParserSelectWithUnionQuery select_p;
    ASTPtr query;
    if (!select_p.parse(pos, query, expected))
        return false;
    ... ...
```

s_explain.ignore 方法会进行一个 keyword 解析，解析出 ast node:

```sql
EXPLAIN -- keyword
```

跃进**第三层** select_p.parse [ParserSelectWithUnionQuery::parseImpl](https://github.com/ClickHouse/ClickHouse/blob/558f9c76306ffc4e6add8fd34c2071b64e914103/src/Parsers/ParserSelectWithUnionQuery.cpp#L26)状态空间：

```cpp
bool ParserSelectWithUnionQuery::parseImpl(Pos & pos, ASTPtr & node, Expected & expected)
{
    ASTPtr list_node;

    ParserList parser(std::make_unique<ParserUnionQueryElement>(), std::make_unique<ParserKeyword>("UNION ALL"), false);
    if (!parser.parse(pos, list_node, expected))
        return false;
...
```

parser.parse 里又调用**第四层** [ParserSelectQuery::parseImpl](https://github.com/ClickHouse/ClickHouse/blob/558f9c76306ffc4e6add8fd34c2071b64e914103/src/Parsers/ParserSelectQuery.cpp#L24) 状态空间：

```cpp
bool ParserSelectQuery::parseImpl(Pos & pos, ASTPtr & node, Expected & expected)
{
    auto select_query = std::make_shared<ASTSelectQuery>();
    node = select_query;

    ParserKeyword s_select("SELECT");
    ParserKeyword s_distinct("DISTINCT");
    ParserKeyword s_from("FROM");
    ParserKeyword s_prewhere("PREWHERE");
    ParserKeyword s_where("WHERE");
    ParserKeyword s_group_by("GROUP BY");
    ParserKeyword s_with("WITH");
    ParserKeyword s_totals("TOTALS");
    ParserKeyword s_having("HAVING");
    ParserKeyword s_order_by("ORDER BY");
    ParserKeyword s_limit("LIMIT");
    ParserKeyword s_settings("SETTINGS");
    ParserKeyword s_by("BY");
    ParserKeyword s_rollup("ROLLUP");
    ParserKeyword s_cube("CUBE");
    ParserKeyword s_top("TOP");
    ParserKeyword s_with_ties("WITH TIES");
    ParserKeyword s_offset("OFFSET");

    ParserNotEmptyExpressionList exp_list(false);
    ParserNotEmptyExpressionList exp_list_for_with_clause(false);
    ParserNotEmptyExpressionList exp_list_for_select_clause(true);
    ...

            if (!exp_list_for_select_clause.parse(pos, select_expression_list, expected))
            return false;
```

**第五层** exp_list_for_select_clause.parse [ParserExpressionList::parseImpl](https://github.com/ClickHouse/ClickHouse/blob/558f9c76306ffc4e6add8fd34c2071b64e914103/src/Parsers/ExpressionListParsers.cpp#L520)状态空间继续：

```cpp
bool ParserExpressionList::parseImpl(Pos & pos, ASTPtr & node, Expected & expected)
{
    return ParserList(
        std::make_unique<ParserExpressionWithOptionalAlias>(allow_alias_without_as_keyword),
        std::make_unique<ParserToken>(TokenType::Comma))
        .parse(pos, node, expected);
}
```

… … 写不下去个鸟！

可以发现，ast parser 的时候，预先构造好状态空间，比如 select 的状态空间:

1. expression list
2. from tables
3. where
4. group by
5. with …
6. order by
7. limit

在一个状态空间內，还可以根据 parse 返回的 bool 判断是否继续进入子状态空间，一直递归解析出整个 ast。

## 总结

手工 parser 的好处是代码清晰简洁，每个细节可防可控，以及友好的错误处理，改动起来不会一发动全身。

缺点是手工成本太高，需要大量的测试来保证其正确性，还需要一些fuzz来保证可靠性。

好在ClickHouse 已经实现的比较全面，即使有新的需求，在现有基础上修修补补即可。

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

