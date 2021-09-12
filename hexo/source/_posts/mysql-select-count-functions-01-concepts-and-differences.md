---
title: 特性介绍 | MySQL select count(*) 、count(1)、count(列) 详解（1）：概念及区别
date: 2020-05-06 15:55:15
categories:
- MySQL
tags:
- MySQL
- Select
- Count
toc: true
---

>**本文首发于 2020-05-05 21:55:15**

### 一、前言

从接触MySQL开始断断续续的看过一些文章，对`count()`操作众说纷纭，其中分歧点主要在于`count(1)`和`count(*)`哪个效率高，有说`count(1)`比`count(*)`快的（`这种说法更普遍`），有说二者一样快的。个人理解这两种行为可能适用于的是不同的版本，我只关心较新的MySQL版本是什么行为，详见下文。

### 二、含义

首先，先说明一下常见`count()`操作及含义：

>`count(*)`：计算包括NULL值在内的行数，SQL92定义的标准统计行数的语法。
>
>`count(1)`：计算包括NULL值在内的行数，其中的1是恒真表达式。
>
>`count(列名)`：计算指定列的行数，但不包含NULL值。

### 三、具体区别

[MySQL手册](https://dev.mysql.com/doc/refman/5.7/en/group-by-functions.html#function_count)中相关描述如下：

>For transactional storage engines such as InnoDB, storing an exact row count is problematic. Multiple transactions may be occurring at the same time, each of which may affect the count.
>
>InnoDB does not keep an internal count of rows in a table because concurrent transactions might “see” different numbers of rows at the same time. Consequently, `SELECT COUNT(*)` statements only count rows visible to the current transaction.
>
>Prior to `MySQL 5.7.18`, InnoDB processes `SELECT COUNT(*)` statements by scanning the clustered index. As of `MySQL 5.7.18`, InnoDB processes `SELECT COUNT(*)` statements by traversing the smallest available secondary index unless an index or optimizer hint directs the optimizer to use a different index. If a secondary index is not present, the clustered index is scanned.
>
>Processing `SELECT COUNT(*)` statements takes some time if index records are not entirely in the buffer pool. For a faster count, create a counter table and let your application update it according to the inserts and deletes it does. However, this method may not scale well in situations where thousands of concurrent transactions are initiating updates to the same counter table. If an approximate row count is sufficient, use `SHOW TABLE STATUS`.
>
>InnoDB handles `SELECT COUNT(*)` and `SELECT COUNT(1)` operations in the same way. There is no performance difference.
>
>For `MyISAM` tables, `COUNT(*)` is optimized to return very quickly if the SELECT retrieves from one table, no other columns are retrieved, and there is no WHERE clause. For example:
>
>```sql
>mysql> SELECT COUNT(*) FROM student;
>```
>This optimization only applies to MyISAM tables, because an exact row count is stored for this storage engine and can be accessed very quickly.COUNT(1) is only subject to the same optimization if the first column is defined as NOT NULL.

**官方这段描述要点如下：**

>1. InnoDB是事务引擎，支持MVCC，并发事务可能同时“看到”不同的行数，所以，**InnoDB不保留表中的行数**，`SELECT COUNT(*)`语句只计算当前事务可见的行数。
>2. 在MySQL 5.7.18之前，InnoDB通过**扫描聚集索引**处理`SELECT COUNT(*)`语句。从MySQL 5.7.18开始，`InnoDB`通过**遍历最小的可用二级索引**来处理`SELECT COUNT(*)`语句，除非索引或优化器明确指示使用不同的索引。**如果不存在二级索引，则扫描聚集索引**。这样的设计单从 IO 的角度就节省了很多开销。
>3. **InnoDB以同样的方式处理`SELECT COUNT(*)`和`SELECT COUNT(1)`操作，没有性能差异。** 因此，建议使用符合SQL标准的`count(*)`。
>4. 对于`MyISAM`表，由于MyISAM引擎存储了精确的行数，因此，如果`SELECT COUNT(*)`语句不包含WHERE子句，则会很快返回。这个很好理解，如果带了where条件，就需要扫表了。
>5. 如果索引记录不完全在缓冲池中，则处理`SELECT(*)`语句需要一些时间。为了更快的计数，您可以创建一个计数器表，并让您的应用程序按插入和删除操作更新它。然而，这种方法在同一计数器表中启动成千上万个并发事务的情况下，可能无法很好地扩展。如果一个近似的行数足够，可以使用`SHOW TABLE STATUS`查询行数。


到这里我们明白了 `count(*)` 和 `count(1)` 本质上面其实是一样的，那么 `count(column)` 又是怎么回事呢？

>`count(column)` 也是会遍历整张表，但是不同的是它会**拿到 column 的值以后判断是否为空，然后再进行累加**，那么如果**针对主键需要解析内容**，如果是**二级索引需要再次根据主键获取内容，则要多一次 IO 操作**，所以 `count(column)` 的性能肯定不如前两者，如果按照效率比较的话：**count(*)=count(1)>count(primary key)>count(非主键column)**。

### 四、建议

基于以上描述，如果要查询innodb存储引擎的表的总行数，有如下建议：
1. 若仅仅是想获取大概的行数，建议使用`show table status`或查询`information_schema.tables`：
```sql
mysql> use db6;
Reading table information for completion of table and column names
You can turn off this feature to get a quicker startup with -A

Database changed
mysql> show tables;
+---------------+
| Tables_in_db6 |
+---------------+
| t1            |
+---------------+
1 row in set (0.01 sec)

mysql> select count(*) from t1;
+----------+
| count(*) |
+----------+
|        2 |
+----------+
1 row in set (0.00 sec)

mysql> show table status\G
*************************** 1. row ***************************
           Name: t1
         Engine: InnoDB
        Version: 10
     Row_format: Dynamic
           Rows: 2
 Avg_row_length: 8192
    Data_length: 16384
Max_data_length: 0
   Index_length: 0
      Data_free: 0
 Auto_increment: NULL
    Create_time: 2020-04-21 12:00:44
    Update_time: NULL
     Check_time: NULL
      Collation: utf8mb4_general_ci
       Checksum: NULL
 Create_options:
        Comment:
1 row in set (0.00 sec)

mysql> select * from information_schema.tables where table_name = 't1'\G
*************************** 1. row ***************************
  TABLE_CATALOG: def
   TABLE_SCHEMA: db6
     TABLE_NAME: t1
     TABLE_TYPE: BASE TABLE
         ENGINE: InnoDB
        VERSION: 10
     ROW_FORMAT: Dynamic
     TABLE_ROWS: 2
 AVG_ROW_LENGTH: 8192
    DATA_LENGTH: 16384
MAX_DATA_LENGTH: 0
   INDEX_LENGTH: 0
      DATA_FREE: 0
 AUTO_INCREMENT: NULL
    CREATE_TIME: 2020-04-21 12:00:44
    UPDATE_TIME: NULL
     CHECK_TIME: NULL
TABLE_COLLATION: utf8mb4_general_ci
       CHECKSUM: NULL
 CREATE_OPTIONS:
  TABLE_COMMENT:
1 row in set (0.00 sec)
```
2. 反之，如果必须要获取准确的总行数，建议：
>1) 创建一个计数器表，并让您的应用程序按插入和删除操作更新它。
>2) 若业务插入和删除相对较少，也可以考虑缓存到 redis。


篇幅有限，深入验证、源码分析将在下一篇文章中介绍。

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