---
title: 引擎特性 | MySQL-自增列详解（1）：自增列概念及使用
date: 2019-12-09 19:37:10
categories:
- MySQL
tags:
- MySQL
- auto_increment
toc: true
---

一直想写一些关于自增列的文章，今天下班比较早，Let's do this.

<!-- more -->

### 1. 概念

自增列，即 AUTO_INCREMENT，可用于为新的记录生成唯一标识。

**要求：**
1. AUTO_INCREMENT 是数据列的一种属性，只适用于整数类型数据列。
2. AUTO_INCREMENT 数据列必须具备 NOT NULL 属性。

### 2. 使用方法

#### 2.1. 创建含自增列的表
```sql
-- 不指定 AUTO_INCREMENT 的值，则从1开始
mysql> create table t1(a int auto_increment primary key,b int);
Query OK, 0 rows affected (0.01 sec)

-- 手动指定 AUTO_INCREMENT 的值
mysql> create table t2(a int auto_increment primary key,b int) AUTO_INCREMENT=100;
Query OK, 0 rows affected (0.02 sec)
```

#### 2.2. 插入数据
```sql
-- 不指定自增列
mysql> insert into t1(b) values(1),(2);
Query OK, 1 row affected (0.00 sec)

mysql> select * from t1;
+---+------+
| a | b    |
+---+------+
| 1 |    1 |
| 2 |    2 |
+---+------+
3 rows in set (0.00 sec)

-- 指定自增列
mysql> insert into t1(a,b) values(3,3);
Query OK, 1 row affected (0.00 sec)
```

#### 2.3. 如何查看表的 AUTO_INCREMENT 涨到了多少？
```sql
mysql> show create table t1;
+-------+------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Table | Create Table                                                                                                                                                     |
+-------+------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| t1    | CREATE TABLE `t1` (
  `a` int(11) NOT NULL AUTO_INCREMENT,
  `b` int(11) DEFAULT NULL,
  PRIMARY KEY (`a`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8 |
+-------+------------------------------------------------------------------------------------------------------------------------------------------------------------------+
1 row in set (0.00 sec)
```

#### 2.4. 插入数据时能否有空洞？

可以的，但要注意 `AUTO_INCREMENT 的值一定比自增列当前最大的记录值大`。

```sql
-- 创造空洞
mysql> insert into t1(a,b) values(5,5);
Query OK, 1 row affected (0.00 sec)

mysql> select * from t1;
+---+------+
| a | b    |
+---+------+
| 1 |    1 |
| 2 |    2 |
| 3 |    3 |
| 5 |    5 |
+---+------+
5 rows in set (0.00 sec)

mysql> show create table t1;
+-------+------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Table | Create Table                                                                                                                                                     |
+-------+------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| t1    | CREATE TABLE `t1` (
  `a` int(11) NOT NULL AUTO_INCREMENT,
  `b` int(11) DEFAULT NULL,
  PRIMARY KEY (`a`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8 |
+-------+------------------------------------------------------------------------------------------------------------------------------------------------------------------+
1 row in set (0.00 sec)
```

#### 2.5. 能否插入重复记录

既然自增列是唯一记录，那么肯定不能插入重复记录。

```sql
-- 尝试插入重复记录
mysql> insert into t1(a,b) values(5,5);
ERROR 1062 (23000): Duplicate entry '5' for key 'PRIMARY'
```

#### 2.6. 怎么修改 AUTO_INCREMENT 的值？

**注意**：AUTO_INCREMENT 不能小于当前自增列记录的最大值。

```sql
-- 尝试将 AUTO_INCREMENT 设为10
mysql> alter table t1 AUTO_INCREMENT=10;
Query OK, 0 rows affected (0.01 sec)
Records: 0  Duplicates: 0  Warnings: 0

mysql> show create table t1;
+-------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Table | Create Table                                                                                                                                                      |
+-------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| t1    | CREATE TABLE `t1` (
  `a` int(11) NOT NULL AUTO_INCREMENT,
  `b` int(11) DEFAULT NULL,
  PRIMARY KEY (`a`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8 |
+-------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------+
1 row in set (0.00 sec)

-- 尝试将 AUTO_INCREMENT 设为4
mysql> alter table t1 AUTO_INCREMENT=4;
Query OK, 0 rows affected (0.00 sec)
Records: 0  Duplicates: 0  Warnings: 0

-- 由于自增列最大记录值是5，那么 AUTO_INCREMENT 不能小于5，因此该值为6
mysql> show create table t1;
+-------+------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Table | Create Table                                                                                                                                                     |
+-------+------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| t1    | CREATE TABLE `t1` (
  `a` int(11) NOT NULL AUTO_INCREMENT,
  `b` int(11) DEFAULT NULL,
  PRIMARY KEY (`a`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8 |
+-------+------------------------------------------------------------------------------------------------------------------------------------------------------------------+
1 row in set (0.00 sec)
```

### 3. 问题

#### 3.1. 自增列是否有上限？

**由上文可见，自增列会一直增加，那是否有上限呢？**

上文中表 t1 的自增列是 int 类型，由下表（MySQL 5.7）可见取值范围是 -2147483648 到 2147483647（ -2<sup>31</sup> ~ 2<sup>31</sup> - 1 ）。

| Type        | Storage (Bytes) | Minimum Value Signed | Minimum Value Unsigned | Maximum Value Signed | Maximum Value Unsigned |
| ----------- | --------------- | -------------------- | ---------------------- | -------------------- | ---------------------- |
| `TINYINT`   | 1               | -128               | 0                    | 127                | 255                  |
| `SMALLINT`  | 2               | -32768             | 0                    | 32767              | 65535                |
| `MEDIUMINT` | 3               | -8388608           | 0                    | 8388607            | 16777215             |
| `INT`       | 4               | -2147483648        | 0                    | 2147483647         | 4294967295           |
| `BIGINT`    | 8               | -2<sup>63</sup>               | 0                    | 2<sup>63</sup>-1              | 2<sup>64</sup>-1                |

验证如下：

```sql
mysql> show create table t1;
+-------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Table | Create Table                                                                                                                                                              |
+-------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| t1    | CREATE TABLE `t1` (
  `a` int(11) NOT NULL AUTO_INCREMENT,
  `b` int(11) DEFAULT NULL,
  PRIMARY KEY (`a`)
) ENGINE=InnoDB AUTO_INCREMENT=2147483644 DEFAULT CHARSET=utf8 |
+-------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
1 row in set (0.01 sec)

mysql> insert into t1(b) values(0),(0),(0);
Query OK, 1 row affected (0.00 sec)

mysql> insert into t1(b) values(0);
ERROR 1062 (23000): Duplicate entry '2147483647' for key 'PRIMARY'
mysql> show create table t1;
+-------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Table | Create Table                                                                                                                                                              |
+-------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| t1    | CREATE TABLE `t1` (
  `a` int(11) NOT NULL AUTO_INCREMENT,
  `b` int(11) DEFAULT NULL,
  PRIMARY KEY (`a`)
) ENGINE=InnoDB AUTO_INCREMENT=2147483647 DEFAULT CHARSET=utf8 |
+-------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
1 row in set (0.00 sec)
```

这里需要补充说明下 `int(11)` 中的数字的含义：
>MySQL中整数数据类型后面的(N)指定**显示宽度**。
>显示宽度不影响查询出来的结果。
>显示宽度限制了小数点的位置(只要实际数字不超过显示宽度，这种情况下，数字显示为原样)。
>显示宽度也是一个有用的工具，可以让开发人员知道应该将值填充到哪个长度。

#### 3.2. 如何避免自增列超过最大值？

可以采用`无符号的 BIGINT 类型`（也可根据业务产生自增列的速度采用合适的类型），能极大提升自增列的范围。

```sql
mysql> create table t2(a bigint unsigned primary key auto_increment,b int);
Query OK, 0 rows affected (0.00 sec)

mysql> alter table t2 auto_increment=18446744073709551613;
Query OK, 0 rows affected (0.00 sec)
Records: 0  Duplicates: 0  Warnings: 0

mysql> show create table t2;
+-------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Table | Create Table                                                                                                                                                                                    |
+-------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| t2    | CREATE TABLE `t2` (
  `a` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `b` int(11) DEFAULT NULL,
  PRIMARY KEY (`a`)
) ENGINE=InnoDB AUTO_INCREMENT=18446744073709551613 DEFAULT CHARSET=utf8 |
+-------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
1 row in set (0.01 sec)

mysql> insert into t2(b) values(0);
Query OK, 1 row affected (0.00 sec)

mysql> insert into t2(b) values(0);
ERROR 1467 (HY000): Failed to read auto-increment value from storage engine
mysql>
mysql> select * from t2;
+----------------------+------+
| a                    | b    |
+----------------------+------+
| 18446744073709551613 |    0 |
+----------------------+------+
1 row in set (0.00 sec)
```
**`UNSIGNED BIGINT` 类型的范围究竟有多大呢？**

> 假如每秒自增100万次，想要消耗完需要 `18446744073709551613/1000000/3600/24/365`=584942年。

**有的朋友会问如果自增列不是采用BIGINT类型，那么达到最大值后该表就无法写入，此时该怎么办呢？**
> 一般达到最大值后再次插入数据会报错`ERROR 1467 (HY000): Failed to read auto-increment value from storage engine`，可以通过alter table 将自增列的类型设为数值范围更大的类型（比如BIGINT）。


### 4. 总结

1. AUTO_INCREMENT 列必定唯一，且仅用于整型类型。
2. AUTO_INCREMENT 列会持续增长，不会因 delete 自增列最大的记录而变小。
3. 当 AUTO_INCREMENT 列达到当前类型的最大值后将无法插入数据，会报错`ERROR 1467 (HY000): Failed to read auto-increment value from storage engine`，此时将自增列改为 BIGINT 类型可解决问题。
4. 为了避免自增列达到最大值，可将其设为BIGINT类型。
4. 使用 alter table 修改 AUTO_INCREMENT 列时，其值会取`自增列当前最大记录值+1`与`将要设置的值`的最大值。
5. 在MySQL 5.7 中，将列设置成 AUTO_INCREMENT 之后，必须将其设置成主键/或者是主键的一部分，否则会报错`ERROR 1075 (42000): Incorrect table definition; there can be only one auto column and it must be defined as a key`。

----

欢迎关注我的微信公众号【MySQL数据库技术】。

<img src="https://dbkernel-1306518848.cos.ap-beijing.myqcloud.com/wechat/my-wechat-official-account.png" width="400" height="400" alt="MySQL数据库技术" align="left"/>

| 标题                 | 网址                                                  |
| -------------------- | ----------------------------------------------------- |
| GitHub                 | https://dbkernel.github.io           |
| 知乎                 | https://www.zhihu.com/people/dbkernel/posts           |
| 思否（SegmentFault） | https://segmentfault.com/u/dbkernel                   |
| 掘金                 | https://juejin.im/user/5e9d3ed251882538083fed1f/posts |
| InfoQ                | https://www.infoq.cn/u/dbkernel/publish               |
| 开源中国（oschina）  | https://my.oschina.net/dbkernel                       |
| 博客园（cnblogs）    | https://www.cnblogs.com/dbkernel                      |
