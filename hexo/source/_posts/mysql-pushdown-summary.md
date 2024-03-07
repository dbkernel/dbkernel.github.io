---
title: 特新介绍 | MySQL生态现有计算下推方案汇总
date: 2024-03-06 20:52:24
categories:
  - MySQL
tags:
  - MySQL
  - 计算下推
  - 优化器
toc: true
---

**作者：卢文双 资深数据库内核研发**

> **本文首发于 2024-03-06 20:52:24**
>
> https://dbkernel.com

# 前言

计算下推是数据库优化器优化查询性能的一种常见手段，早期的数据库系统提及的计算下推一般是指谓词下推，其理论源自关系代数理论。2000 年以后，随着 Oracle RAC 的盛行以及一众开源分布式数据库的崛起，存算分离的概念逐步流行，计算下推的涵盖范围由此从基本的谓词+投影下推延伸到了数据库所支持的一切可能计算的下推（JOIN、聚合、完整 query、部分 query 等）。

对于单机数据库来说，尤其是 MySQL 这种采用经典火山模型的关系型数据库，最常见的就是谓词下推、投影下推，通常在查询优化的 RBO 阶段完成（有的下推在 CBO 阶段），通过将 Filter 和 Project 算子在抽象语法树（AST）中向下移动，提前对行/列进行裁剪，减少后续计算的数据量。

当然，MySQL 中不仅仅是谓词下推、投影下推，还有条件下推、ICP 等，本文就盘点一下 MySQL 生态中有哪些计算下推。

<!-- more -->

---

# MySQL 原生方案

本小节介绍 MySQL 社区版中的计算下推方案。

## 1. 索引条件下推 ICP

### 功能介绍

ICP（Index Condition Pushdown，索引下推），是 **MySQL 5.6 版本**推出的功能，用于优化 MySQL 查询。

ICP 可以减少存储引擎查询回表的次数以及 MySQL server 层访问存储引擎的次数。

ICP 的目标是**减少整行记录读取的次数，从而减少 I/O 操作**。

**在没有使用 ICP 的情况下，索引（二级索引）扫描的过程如下：**

1.  存储引擎读取二级索引记录；
2.  根据二级索引中的主键值，定位并读取完整行记录（回表）；
3.  存储引擎把记录交给 Server 层去检测该记录是否满足 where 条件。

![非ICP图解（图片来源于网络）](no-icp-data-flow.png "非ICP图解（图片来源于网络）")

**在使用 ICP 的情况下，查询优化阶段会将部分或全部 where 条件下推，其扫描过程如下：**

1.  存储引擎读取二级索引记录（不是完整行）；
2.  **判断当前二级索引列记录是否满足下推的 where 条件**：
    1.  如果条件不满足，则跳过该行，继续处理下一行索引记录；
    2.  **如果条件满足，使用索引中的主键去定位并读取完整的行记录（回表）**；
3.  存储引擎把记录交给 Server 层，Server 层检测该记录是否满足 where 条件的其余部分。

![ICP图解（图片来源于网络）](use-icp-data-flow.png "ICP图解（图片来源于网络）")

![ICP（图片来源于网络）](use-icp-flow.jpeg "ICP（图片来源于网络）")

### **适用场景：**

- **单列/多列二级索引上的非范围扫描（比如 like）**。示例：(c3) 是单列二级索引，`with index condition`部分就是 ICP 下推的条件

![ICP-非范围扫描](icp-query-like.png "ICP-非范围扫描")

- **where 条件不满足最左匹配原则的多列二级索引扫描**。示例：(c2, c3, c4) 是多列二级索引，指定多列范围，c4>5 范围无法下推到引擎层扫描范围 `QUICK_RANGE_SELECT::ranges`

![ICP-多列二级索引](icp-multi-columns-secondary-index.png "ICP-多列二级索引")

### **使用限制 & 适用条件：**

1.  当需要访问全表记录时，ICP 可用于  range（范围扫描）、ref（非唯一索引的"="操作）、eq_ref（唯一索引的"="操作） 和 ref_or_null（ref + 支持空值，比如：WHERE col = ... OR col IS NULL） 访问方法。
2.  ICP 可以用于 InnoDB 和 MyISAM 引擎表（包括分区表）。
3.  对于 InnoDB 表，ICP 仅支持二级索引。而对于 InnoDB 聚簇索引，由于完整的记录会被读到 InnoDB 缓冲区，在这种情况下，使用 ICP 不会减少 I/O 操作。
4.  虚拟列上创建的二级索引不支持 ICP。
5.  使用子查询的 where 条件不支持 ICP。
6.  由于引擎层无法调用位于 server 层的存储过程，因此，调用存储过程的 SQL 不支持 ICP。
7.  触发器不支持 ICP。

### **开关（默认开启）：**

```sql
SET optimizer_switch = 'index_condition_pushdown=off'; -- 关闭 ICP
SET optimizer_switch = 'index_condition_pushdown=on'; -- 启用 ICP
```

### **性能影响：**

#### 示例

准备：

```sql
// 表结构（是否显示设置id为主键，对性能没什么影响，但执行计划不同）
CREATE TABLE `icp` (
  `id` int DEFAULT NULL,
  `age` int DEFAULT NULL,
  `name` varchar(30) DEFAULT NULL,
  `memo` varchar(600) DEFAULT NULL,
  KEY `age_idx` (`age`,`name`,`memo`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4

for((i=0;i<$rows_num;i++))
do
mysql -u$user -h$host -P$port -e"insert into $db.$tb values($i, 1, 'a$i', repeat('a$i', 100))"
done

// 将其中三行数据的age从1改为2
mysql> update icp2 set age=2 where id=10 or id=20 or id=20000;
Query OK, 0 rows affected (0.00 sec)
Rows matched: 3  Changed: 0  Warnings: 0

// 表数据行数
mysql> select count(*) from icp;
+----------+
| count(*) |
+----------+
|   100000 |
+----------+
1 row in set (0.41 sec)

mysql> select count(*) from icp where age=1;
+----------+
| count(*) |
+----------+
|    99997 |
+----------+
1 row in set (6.37 sec)

```

启用 ICP：

```sql
// 启用 ICP
mysql> set optimizer_switch="index_condition_pushdown=on";
mysql> show session status like '%handler_read%';
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 3     |
| Handler_read_key      | 105   |
| Handler_read_last     | 0     |
| Handler_read_next     | 139   |
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 7     |
+-----------------------+-------+
7 rows in set (0.01 sec)
mysql> select * from icp where age = 1 and memo like '%9999%'; // 结果集19行，耗时2.41s
mysql> show session status like '%handler_read%'; // read_key + 1，read_next + 19
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 3     |
| Handler_read_key      | 106   |
| Handler_read_last     | 0     |
| Handler_read_next     | 158   |
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 7     |
+-----------------------+-------+
7 rows in set (0.01 sec)

mysql> explain analyze select * from icp where age = 1 and memo like '%9999%'\G
*************************** 1. row ***************************
EXPLAIN: -> Index lookup on icp using age_idx (age=1), with index condition: (icp.memo like '%9999%')  (cost=5432.07 rows=45945) (actual time=219.708..1973.586 rows=19 loops=1) // 只需要扫描19行

1 row in set (1.97 sec)
```

禁用 ICP：

```sql
// 禁用ICP
mysql> set optimizer_switch="index_condition_pushdown=off";
mysql> select * from icp where age = 1 and memo like '%9999%'; // 该表总数据行数1万，结果集19行，耗时12.05s
mysql> show session status like '%handler_read%'; // read_key + 1，read_next + 99997
+-----------------------+--------+
| Variable_name         | Value  |
+-----------------------+--------+
| Handler_read_first    | 3      |
| Handler_read_key      | 107    |
| Handler_read_last     | 0      |
| Handler_read_next     | 100155 |
| Handler_read_prev     | 0      |
| Handler_read_rnd      | 0      |
| Handler_read_rnd_next | 7      |
+-----------------------+--------+
7 rows in set (0.00 sec)

mysql> explain analyze select * from icp where age = 1 and memo like '%9999%'\G
*************************** 1. row ***************************
EXPLAIN: -> Filter: (icp.memo like '%9999%')  (cost=5432.07 rows=5104) (actual time=1415.435..12850.675 rows=19 loops=1)
    -> Index lookup on icp using age_idx (age=1)  (cost=5432.07 rows=45945) (actual time=0.259..11118.374 rows=99997 loops=1)
    // 需要先在引擎层执行索引扫描所有age=1的记录 99997 行并回表得到完整行，再由server层根据 memo like 条件过滤出 19 行

1 row in set (12.86 sec)
```

#### 结论

由以上测试情况可以看到，**在二级索引是复合索引且前面的条件过滤性较低的情况下，打开 ICP 可以有效的降低 server 层和 engine 层之间交互的次数，从而有效的降低运行时间（从 12.86s 降低到 1.97s），但是，对于多个普通单列索引构成的 where 过滤条件，无论是否启用 ICP，优化器都会将过滤性高的索引条件下推到 engine 层执行 index range scan，因此，收益不大**。

```sql
// 开启 ICP，下推 t1.a > 3，扫描 4096 行
mysql> explain analyze select * from t1 where b>1 and a>3\G
*************************** 1. row ***************************
EXPLAIN: -> Filter: (t1.b > 1)  (cost=1843.46 rows=2048) (actual time=0.389..281.599 rows=4096 loops=1)
    -> Index range scan on t1 using idx_a, with index condition: (t1.a > 3)  (cost=1843.46 rows=4096) (actual time=0.385..278.402 rows=4096 loops=1)

// 关闭 ICP，优化器判定 t1.a 过滤性更强，按 idx_a 执行 Index range scan，也是扫描 4096 行
mysql> explain analyze select * from t1 where b>1 and a>3\G
*************************** 1. row ***************************
EXPLAIN: -> Filter: ((t1.b > 1) and (t1.a > 3))  (cost=1843.46 rows=2048) (actual time=0.762..224.012 rows=4096 loops=1)
    -> Index range scan on t1 using idx_a  (cost=1843.46 rows=4096) (actual time=0.748..218.553 rows=4096 loops=1)
```

## 2. 引擎条件下推 ECP

ECP（Engine Condition Pushdown，引擎条件下推），该优化只支持 NDB 存储引擎，用于提高非索引列和常量之间直接比较的效率，在这种情况下，条件被下推到存储引擎做计算。

```sql
mysql> EXPLAIN SELECT a, b FROM t1 WHERE a < 2\G
*************************** 1. row ***************************
           id: 1
  select_type: SIMPLE
        table: t1
         type: range
possible_keys: a
          key: a
      key_len: 5
          ref: NULL
         rows: 2
        Extra: Using where with pushed condition
```

对于 NDB 集群，这种优化可以消除在 集群的数据节点 和 发出查询的 MySQL 服务器 之间通过网络发送不匹配的行的资源浪费。

## 3. 派生条件下推 DCP

### 功能介绍

DCP（Derived Condition Pushdown，派生表条件下推），从 **MySQL 8.0.22 版本**开始引入。

对于 SQL 语句：

```sql
SELECT * FROM (SELECT i, j FROM t1) AS dt WHERE i > constant
```

在很多情况下可以将外部的 WHERE 条件下推到派生表，相当于 SQL 改写为了：

```sql
SELECT * FROM (SELECT i, j FROM t1 WHERE i > constant) AS dt
```

这**减少了派⽣表返回的⾏数**，从⽽加快查询的速度。

### 适用场景

**DCP 适用于以下情况：**

1、当派生表不使用聚合函数或窗口函数时，外部 WHERE 条件可以直接下推给它，包括具有多个谓词与 AND、OR 或与二者同时连接的 WHERE 条件。比如：查询

```sql
SELECT * FROM (SELECT f1, f2 FROM t1) AS dt WHERE f1 < 3 AND f2 > 11
```

被重写为

```sql
SELECT f1, f2 FROM (SELECT f1, f2 FROM t1 WHERE f1 < 3 AND f2 > 11) AS dt
```

2、当派生表具有 GROUP BY 且未使用窗口函数时，如果外部 WHERE 条件引用了一个或多个不属于 GROUP BY 的列，那么该 WHERE 条件可以作为 HAVING 条件下推到派生表中。比如：查询

```sql
SELECT * FROM (SELECT i, j, SUM(k) AS sum FROM t1 GROUP BY i, j) AS dt WHERE sum > 100
```

被重写为

```sql
SELECT * FROM (SELECT i, j, SUM(k) AS sum FROM t1 GROUP BY i, j HAVING sum > 100) AS dt
```

3、当派生表使用一个 GROUP BY 且外部 WHERE 条件中的列就是 GROUP BY 的列时，引用这些列的 WHERE 条件可以直接下推到派生表中。比如：查询

```sql
SELECT * FROM (SELECT i,j, SUM(k) AS sum FROM t1 GROUP BY i,j) AS dt WHERE i > 10
```

被重写为

```sql
SELECT * FROM (SELECT i,j, SUM(k) AS sum FROM t1 WHERE i > 10 GROUP BY i,j) AS dt
```

4、如果外部 WHERE 条件中同时包含了第 2 种与第 3 种的情况，即同时具有”引用属于 GROUP BY 的列的谓词“ 和 ”引用不属于 GROUP BY 的列的谓词“，则第一种谓词作为 WHERE 条件下推，第二种谓词下推后作为 HAVING 条件。比如：查询

```sql
SELECT * FROM (SELECT i, j, SUM(k) AS sum FROM t1 GROUP BY i,j) AS dt WHERE i > 10 AND sum > 100
```

被重写为类似如下形式的 SQL

```sql
SELECT * FROM (
    SELECT i, j, SUM(k) AS sum FROM t1
        WHERE i > 10 // 第一种
        GROUP BY i, j
        HAVING sum > 100 // 第二种
    ) AS dt;
```

### 使用限制

**DCP 也存在如下使用限制：**

1.  如果派生表包含 UNION，不能使用 DCP 。该限制在   MySQL 8.0.29 基本被取消了，但以下两种情况除外：
    1.  如果 UNION 的任何派生表是  recursive common table expression ，则不能将条件下推到 UNION 查询。
    2.  不能将”包含不确定表达式的条件“下推到派生表中。
2.  派生表不能使用 limit 子句。
3.  包含子查询的条件不能被下推。
4.  如果派生表是外部 join 的 inner table，不能使用 DCP。
5.  如果派生表是一个  common table expression 并且被多次引用，则不能将条件下推到该派生表。
6.  如果条件的形式是  `derived_column > ?` ，可以下推使用参数的条件。但是，If a derived column in an outer WHERE condition is an expression having a ? in the underlying derived table, this condition cannot be pushed down.

**开关（默认开启）：**

```sql
set optimizer_switch="derived_condition_pushdown=on";
set optimizer_switch="derived_condition_pushdown=off";
```

源码分析可参考：

- MySQL · 性能优化 · 条件下推到物化表：<http://mysql.taobao.org/monthly/2016/07/08/>

## 4. 谓词下推

**何为谓词？**

P : X→ {true, false} called a predicate on X .

A predicate is a function that returns bool (or something that can be implicitly converted to bool）

**谓词是返回 bool 型（或可隐式转换为 bool 型）的函数**。

一般来说，where 中的条件单元都是谓词：

- \=, >, <, >=, <=, BETWEEN, LIKE, IS \[NOT] NULL
- <>, IN, OR, NOT IN, NOT LIKE

谓词下推是指将查询语句中的过滤表达式尽可能下推到距离数据源最近的地方做计算，以尽早完成数据的过滤，进而显著地减少数据传输或计算的开销。

- 下推前：select count(1) from t1 A join t3 B on A.a = B.a where **A.b > 100 and B.b > 100**;
- 下推后：select count(1) from (select \* from t1 where **a>100**) A join (select \*  from t3 where **b<100**) B on A.a = B.a;

**MySQL/PG 优化器会自动做谓词下推的优化**，比如：

```sql
mysql> explain analyze select count(1) from t1 A join t3 B on A.a = B.c where A.b > 100 and B.b > 100\G
*************************** 1. row ***************************
EXPLAIN: -> Aggregate: count(1)  (cost=366.05 rows=331) (actual time=23.188..23.189 rows=1 loops=1)
    -> Nested loop inner join  (cost=332.95 rows=331) (actual time=1.421..22.925 rows=302 loops=1)
        -> Filter: ((b.b > 100) and (b.c is not null))  (cost=101.25 rows=662) (actual time=1.172..6.911 rows=662 loops=1)
            -> Table scan on B  (cost=101.25 rows=1000) (actual time=0.535..6.242 rows=1000 loops=1)
        -> Filter: (a.b > 100)  (cost=0.25 rows=0) (actual time=0.023..0.024 rows=0 loops=662)
            -> Single-row index lookup on A using PRIMARY (a=b.c)  (cost=0.25 rows=1) (actual time=0.022..0.023 rows=1 loops=662)
```

## 5. Secondary Engine - HTAP

问：该特性是什么版本引入的？

> 从手册中对`SECONDARY_LOAD`的说明以及代码提交记录时间点，是在**8.0.13**引入的 Secondary Engine。之后，release log 中直到 8.0.19 版本才有相关 bug 修复记录。

**引入 Secondary Engine，用于支持多引擎（建表语句中的 Engine 为 Primary Engine）**，使用示例如下：

```sql
INSTALL PLUGIN mock SONAME "ha_mock.so";

CREATE TABLE `se` (
  `id` int DEFAULT NULL,
  `age` int DEFAULT NULL,
  `name` varchar(30) DEFAULT NULL,
  `memo` varchar(600) DEFAULT NULL,
  KEY `age_idx` (`age`,`name`,`memo`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 SECONDARY_ENGINE=MOCK;

// 系统变量
SET @use_secondary_engine= "ON";
SET @use_secondary_engine= "OFF";
SET @use_secondary_engine= "FORCED";

// 加载和卸载数据
ALTER TABLE SE SECONDARY_LOAD;
ALTER TABLE SE SECONDARY_UNLOAD;
```

在支持 InnoDB 的同时，还可以把数据存放在其他的存储引擎上。 全量的数据都存储在 Primary Engine 上，某些指定表数据在 Secondary Engine 上也存放了一份，然后在访问这些数据的时候，会根据系统参数和 cost 选择存储引擎，提高查询效率。

MySQL 官方集成了 RAPID 来为 MySQL 提供实时的数据分析服务，即[HeatWave](https://dev.mysql.com/doc/heatwave/en/ "HeatWave")，同时支持 InnoDB 和 RAPID 执行引擎（未开源），也就是 HTAP。

![HeatWave架构图](heatwave-architecture.png "HeatWave架构图")

不过，开源 MySQL 引入 Secondary Engine 机制，有助于集成其他存储引擎或者数据库，开源生态中[StoneDB](https://www.stoneatom.com/StonedbDocs?id=167 "StoneDB")就是基于该特性来实现的 HTAP。

# 第三方方案

本小节只介绍 RDS 范畴的计算下推，对于 PolarDB、Aurora 这种存算分离架构不做讲述。

## 1. limit/offset、sum 下推

腾讯云 TXSQL（腾讯自研 MySQL 分支）支持了 limit/offset、sum 下推。

### **功能介绍**

该功能**将单表查询的 LIMIT/OFFSET 或 SUM 操作下推到 InnoDB**，有效降低查询时延。

- LIMIT/OFFSET 下推到二级索引时，该功能将避免“回表”操作，有效降低扫描代价。
- SUM 操作下推到 InnoDB 时，在 InnoDB 层进行计算返回“最终”结果，节省 Server 层和 InnoDB 引擎层多次迭代“每行”记录的代价。

### 适用场景

该功能主要针对单表查询下存在 LIMIT/OFFSET 或 SUM 的场景，如  `Select * from tbl Limit 10、Select * from tbl Limit 10,2`、`Select sum(c1) from tbl`  等语句。

#### **无法优化的场景**：

- 查询语句存在 distinct、group by、having。
- 存在嵌套子查询。
- 使用了 FULLTEXT 索引。
- 存在 order by 并且优化器不能利用 index 实现 order by。
- 使用多范围的 MRR。
- 存在 SQL_CALC_FOUND_ROWS。

#### **个人理解**：

下推的前提是不能影响结果集的正确性，因此：

- 只能支持单表查询
- where 条件：
  - 若无 where 条件，也可支持单表的全表扫描（Table Scan）
  - 若有 where 条件，则必须满足只对一条索引做范围扫描即可覆盖全部 where 条件才可下推，反之，则不能下推
- 不支持全文索引这种特殊的索引
- 若存在无法被优化器消除的 distinct、group by、having、order by，则不能下推
- 由于 MRR 机制、SQL_CALC_FOUND_ROWS 语法的特殊性，下推的收益不大

### **性能数据**

sysbench 导入一百万行数据后：

- 执行  `select * from sbtest1 limit 1000000,1;`  的时间从 6.3 秒下降到 2.8 秒。
  - **对于高并发、二级索引扫描且需回表主键列的情况，收益会更大，可能有 8 倍以上的提升**。
- 执行  `select sum(k) from sbtest1; `的时间从 5.4 秒下降到 1.5 秒。

### 机制（个人理解）

无论是 limit/offset 下推，还是 sum 下推，都借鉴了 ICP 的机制，思路大同小异。这里以 offset 为例，说下我的理解：

1.  在 Server 层做查询优化时，为了避免下推后导致结果集有误，需先判断是否满足下推条件（单表查询、InnoDB 引擎、非「无法优化的场景」），若满足，则将 offset 条件下推到引擎层，同时屏蔽掉 Server 层的 offset 逻辑。
2.  若下推了 offset 算子，比如 offset 100，则需要在引擎层跳过 100 行，后续逻辑与下推前相同。

**个人对 offset 下推的理解**：

![offset下推图解](offset-architecture.png "offset下推图解")

### 延伸

**问：其他聚合函数是否可以下推优化？**

从官方手册（ [https://dev.mysql.com/doc/refman/8.0/en/aggregate-functions.html](https://dev.mysql.com/doc/refman/8.0/en/aggregate-functions.html "https://dev.mysql.com/doc/refman/8.0/en/aggregate-functions.html")）支持的聚合函数来看：

- 至少`AVG()`也是可以很容易支持的。
- 对于`COUNT()`函数，由于 MySQL 8.0 支持了并行扫描，暂时来看优化的意义不大。
- 对于`MIN()`、`MAX()`函数，优化器会使用索引来优化，基本只扫描一行即可，无下推必要。
- 其他聚合函数不太常用，下推优化意义不大。

# 总结

正文说的很清晰了，就不强行总结了（\^\_^）

# 参考

- MySQL ICP： [https://dev.mysql.com/doc/refman/8.0/en/index-condition-pushdown-optimization.html](https://dev.mysql.com/doc/refman/8.0/en/index-condition-pushdown-optimization.html "https://dev.mysql.com/doc/refman/8.0/en/index-condition-pushdown-optimization.html")
- MySQL ECP：[https://dev.mysql.com/doc/refman/8.0/en/engine-condition-pushdown-optimization.html](https://dev.mysql.com/doc/refman/8.0/en/engine-condition-pushdown-optimization.html "https://dev.mysql.com/doc/refman/8.0/en/engine-condition-pushdown-optimization.html")
- MySQL DCP：[https://dev.mysql.com/doc/refman/8.0/en/derived-condition-pushdown-optimization.html](https://dev.mysql.com/doc/refman/8.0/en/derived-condition-pushdown-optimization.html "https://dev.mysql.com/doc/refman/8.0/en/derived-condition-pushdown-optimization.html")
- Secondary Engine：[http://mysql.taobao.org/monthly/2020/11/04/](http://mysql.taobao.org/monthly/2020/11/04/ "http://mysql.taobao.org/monthly/2020/11/04/")
- 腾讯自研内核 TXSQL 计算下推功能：[https://cloud.tencent.com/document/product/236/63445](https://cloud.tencent.com/document/product/236/63445 "https://cloud.tencent.com/document/product/236/63445")

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
