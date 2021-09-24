---
title: 特性介绍 | PostgreSQL 的依赖约束详解 - 系统表 pg_depend & pg_constraint
date: 2015-11-04 15:28:08
categories:
- PostgreSQL
tags:
- PostgreSQL
- pg_depend
- pg_constraint
toc: true
---

<!-- more -->

>**本文首发于 2015-11-04 15:28:08**

# 前言

本文成文较早，依赖的是 PostgreSQL 9.3 版本，后续内核版本可能不兼容，但核心原理是相通的，可做参考。

# 表结构

## pg_depend

pg_depend 是 postgres 的一张系统表，用来记录数据库对象之间的依赖关系，除了常见的主外键，还有其他一些内部依赖关系，可以通过这个系统表呈现出来。

```sql
postgres=# \d+ pg_depend
                       Table "pg_catalog.pg_depend"
   Column    |  Type   | Modifiers | Storage | Stats target | Description
-------------+---------+-----------+---------+--------------+-------------
 classid     | oid     | not null  | plain   |              | 系统OID
 objid       | oid     | not null  | plain   |              | 对象OID
 objsubid    | integer | not null  | plain   |              |
 refclassid  | oid     | not null  | plain   |              | 引用系统OID
 refobjid    | oid     | not null  | plain   |              | 引用对象ID
 refobjsubid | integer | not null  | plain   |              |
 deptype     | "char"  | not null  | plain   |              | pg_depend类型
Indexes:
    "pg_depend_depender_index" btree (classid, objid, objsubid)
    "pg_depend_reference_index" btree (refclassid, refobjid, refobjsubid)
Has OIDs: no
```
>OID 是 Object Identifier 的缩写，是对象 ID 的意思，因为是无符号的4字节类型，表示范围不够大，所以一般不用做主键使用，仅用在系统内部，比如系统表等应用。可以与一些整型数字进行转换。与之相关的系统参数是 `default_with_oids` ，默认是 off 。

`pg_depend.deptype` 字段自 9.1 版本之后多了一个 extension 的类型，目前类型有：

>- `DEPENDENCY_NORMAL (n)` ：普通的依赖对象，如表与schema的关系。
>- `DEPENDENCY_AUTO (a)` ：自动的依赖对象，如主键约束。
>- `DEPENDENCY_INTERNAL (i)` ：内部的依赖对象，通常是对象本身。
>- `DEPENDENCY_EXTENSION (e)` ：9.1新增的的扩展依赖。
>- `DEPENDENCY_PIN (p)` ：系统内置的依赖。


## pg_constraint

```sql
postgres=# \d pg_constraint
     Table "pg_catalog.pg_constraint"
    Column     |     Type     | Modifiers
---------------+--------------+-----------
 conname       | name         | not null        -- 约束名
 connamespace  | oid          | not null        -- 约束所在命名空间的OID
 contype       | "char"       | not null        -- 约束类型
 condeferrable | boolean      | not null        -- 约束是否可以推迟
 condeferred   | boolean      | not null        -- 缺省情况下，约束是否可以推迟
 convalidated  | boolean      | not null        -- 约束是否经过验证
 conrelid      | oid          | not null        -- 约束所在的表的OID
 contypid      | oid          | not null        -- 约束所在的域的OID
 conindid      | oid          | not null        -- 如果是唯一、主键、外键或排除约束，则为支持这个约束的索引；否则为0
 confrelid     | oid          | not null        -- 如果是外键，则为参考的表；否则为 0
 confupdtype   | "char"       | not null        -- 外键更新操作代码
 confdeltype   | "char"       | not null        -- 外键删除操作代码
 confmatchtype | "char"       | not null        -- 外键匹配类型
 conislocal    | boolean      | not null
 coninhcount   | integer      | not null        -- 约束直接继承祖先的数量
 connoinherit  | boolean      | not null
 conkey        | smallint[]   |         -- 如果是表约束（包含外键，但是不包含约束触发器），则是约束字段的列表
 confkey       | smallint[]   |         -- 如果是一个外键，是参考的字段的列表
 conpfeqop     | oid[]        |         -- 如果是一个外键，是PK = FK比较的相等操作符的列表
 conppeqop     | oid[]        |        -- 如果是一个外键，是PK = PK比较的相等操作符的列表
 conffeqop     | oid[]        |         -- 如果是一个外键，是FK = FK比较的相等操作符的列表
 conexclop     | oid[]        |         -- 如果是一个排除约束，是每个字段排除操作符的列表
 conbin        | pg_node_tree |         -- 如果是一个检查约束，那就是其表达式的内部形式
 consrc        | text         |         -- 如果是检查约束，则是表达式的人类可读形式
Indexes:
    "pg_constraint_oid_index" UNIQUE, btree (oid)
    "pg_constraint_conname_nsp_index" btree (conname, connamespace)
    "pg_constraint_conrelid_index" btree (conrelid)
    "pg_constraint_contypid_index" btree (contypid)
```

# 查询依赖关系的 SQL

如下 SQL 可以列出系统和用户对象的各种依赖关系：

```sql
SELECT classid::regclass AS "depender object class",
    CASE classid
        WHEN 'pg_class'::regclass THEN objid::regclass::text
        WHEN 'pg_type'::regclass THEN objid::regtype::text
        WHEN 'pg_proc'::regclass THEN objid::regprocedure::text
        ELSE objid::text
    END AS "depender object identity",
    objsubid,
    refclassid::regclass AS "referenced object class",
    CASE refclassid
        WHEN 'pg_class'::regclass THEN refobjid::regclass::text
        WHEN 'pg_type'::regclass THEN refobjid::regtype::text
        WHEN 'pg_proc'::regclass THEN refobjid::regprocedure::text
        ELSE refobjid::text
    END AS "referenced object identity",
    refobjsubid,
    CASE deptype
        WHEN 'p' THEN 'pinned'
        WHEN 'i' THEN 'internal'
        WHEN 'a' THEN 'automatic'
        WHEN 'n' THEN 'normal'
    END AS "dependency type"
FROM pg_catalog.pg_depend WHERE (objid >= 16384 OR refobjid >= 16384);
```
>我通常喜欢在 where 后面加个条件 `and deptype <>'i'` ，以排除 internal 依赖。


# 示例

**创建一张表：**
```sql
postgres=# create table tbl_parent(id int);
CREATE TABLE
```

**执行查询依赖关系的 SQL：**
```sql
postgres=# 执行上面的SQL;
 depender object class | depender object identity | objsubid | referenced object class | referenced object identity | refobjsubid | dependency type
-----------------------+--------------------------+----------+-------------------------+------------- pg_class              | tbl_parent               |        0 | pg_namespace            | 2200                       |           0 | normal
(1 row)
```
>看起来只是建了个表，没有约束，实际上该表是建立在 schema 下面的，因此只依赖于 schema 。

添加主键约束：
```sql
postgres=# alter table tbl_parent add primary key(id);
ALTER TABLE
 depender object class | depender object identity | objsubid | referenced object class | referenced object identity | refobjsubid | dependency type
-----------------------+--------------------------+----------+-------------------------+------- pg_class              | tbl_parent               |        0 | pg_namespace            | 2200                       |           0 | normal
 pg_constraint         | 16469                    |        0 | pg_class                | tbl_parent                 |           1 | automatic
(2 rows)
```
>约束类型变为了`automatic`，表明这个主键约束是依赖于表上的，是自动模式，详细信息可以在系统表 `pg_constrant` 里面查询。

正常情况下用户删除有依赖关系的对象时，会提示需要先删除依赖的对象。但是如果通过系统表删除有依赖关系的对象时，若操作有误，就会导致异常。例如：下面的操作就会导致报错`cache lookup failed for constraint`：
```sql
postgres=# select oid,conname,connamespace,contype from pg_constraint where conname like 'tbl_parent%';
  oid  |     conname     | connamespace | contype
-------+-----------------+--------------+---------
 16469 | tbl_parent_pkey |         2200 | p
(1 row)

postgres=# delete from pg_constraint where conname like 'tbl_parent%';
DELETE 1
postgres=# select oid,conname,connamespace,contype from pg_constraint where conname like 'tbl_parent%';
 oid | conname | connamespace | contype
-----+---------+--------------+---------
(0 rows)

postgres=# drop table tbl_parent;
ERROR:  cache lookup failed for constraint 16469   --16496是约束的OID
postgres=#
```

之所以出现该报错，是因为手动把约束对象删除了，但在 pg_depend 里却仍然存在依赖关系，因此，删除该表时，由于找不到最里层的依赖对象而报错。

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

