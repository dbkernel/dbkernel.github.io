---
title: 捉虫日记 | MySQL 5.7.20 try_acquire_lock_impl 异常导致mysql crash
date: 2020-05-06 15:55:15
categories:
  - MySQL
tags:
  - MySQL
  - LF_HASH
  - 锁
toc: true
---

> **本文首发于 2021-03-07 21:13:15**

# 背景

近期线上 MySQL 5.7.20 集群不定期（多则三周，短则一两天）出现主库 mysql crash、触发主从切换问题，堆栈信息如下；

![try_acquire_lock_impl crash 堆栈](try_acquire_lock_impl.jpeg)

从堆栈信息可以明显看出，在调用 `try_acquire_lock_impl` 时触发的 crash。

# 分析

在官方 Bug 库未搜到类似问题，转而从代码库入手，搜到对应的 BUG —— [8bc828b982f678d6b57c1853bbe78080c8f84e84](https://github.com/mysql/mysql-server/commit/8bc828b982f678d6b57c1853bbe78080c8f84e84)：

```bash
BUG#26502135: MYSQLD SEGFAULTS IN

              MDL_CONTEXT::TRY_ACQUIRE_LOCK_IMPL

ANALYSIS:
=========
Server sometimes exited when multiple threads tried to
acquire and release metadata locks simultaneously (for
example, necessary to access a table). The same problem
could have occurred when new objects were registered/
deregistered in Performance Schema.

The problem was caused by a bug in LF_HASH - our lock free
hash implementation which is used by metadata locking
subsystem in 5.7 branch. In 5.5 and 5.6 we only use LF_HASH
in Performance Schema Instrumentation implementation. So
for these versions, the problem was limited to P_S.

The problem was in my_lfind() function, which searches for
the specific hash element by going through the elements
list. During this search it loads information about element
checked such as key pointer and hash value into local
variables. Then it confirms that they are not corrupted by
concurrent delete operation (which will set pointer to 0)
by checking if element is still in the list. The latter
check did not take into account that compiler (and
processor) can reorder reads in such a way that load of key
pointer will happen after it, making result of the check
invalid.

FIX:
====
This patch fixes the problem by ensuring that no such
reordering can take place. This is achieved by using
my_atomic_loadptr() which contains compiler and processor
memory barriers for the check mentioned above and other
similar places.

The default (for non-Windows systems) implementation of
my_atomic*() relies on old __sync intrisics and implements
my_atomic_loadptr() as read-modify operation. To avoid
scalability/performance penalty associated with addition of
my_atomic_loadptr()'s we change the my_atomic*() to use
newer __atomic intrisics when available. This new default
implementation doesn't have such a drawback.
```

**大体含义是：**

当多个线程分别同时获取、释放 metadata locks 时，或者在 Performance Schema 中注册/撤销新的 object 时，可能会触发该问题，导致 mysql server crash。

该问题是 LF_HASH（Lock-Free Extensible Hash Tables） 的 BUG 引起的，那么 LF_HASH 用在什么地方呢？

> 1. 在 5.5、5.6 中只用在 Performance Schema Instrumentation 模块。
> 2. 在 5.7 中也用于 metadata 加锁模块。

问题出在 my_lfind() 函数中，该函数针对 cursor->prev 的判断未考虑 CAS，该 patch 通过使用 my_atomic_loadptr() 解决了该问题：

```cpp
diff --git a/mysys/lf_hash.c b/mysys/lf_hash.c
index dc019b07bd9..3a3f665a4f1 100644
--- a/mysys/lf_hash.c
+++ b/mysys/lf_hash.c
@@ -1,4 +1,4 @@
-/* Copyright (c) 2006, 2016, Oracle and/or its affiliates. All rights reserved.
+/* Copyright (c) 2006, 2017, Oracle and/or its affiliates. All rights reserved.
    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
@@ -83,7 +83,8 @@ retry:
   do { /* PTR() isn't necessary below, head is a dummy node */
     cursor->curr= (LF_SLIST *)(*cursor->prev);
     _lf_pin(pins, 1, cursor->curr);
-  } while (*cursor->prev != (intptr)cursor->curr && LF_BACKOFF);
+  } while (my_atomic_loadptr((void**)cursor->prev) != cursor->curr &&
+                              LF_BACKOFF);
   for (;;)
   {
     if (unlikely(!cursor->curr))
@@ -97,7 +98,7 @@ retry:
     cur_hashnr= cursor->curr->hashnr;
     cur_key= cursor->curr->key;
     cur_keylen= cursor->curr->keylen;
-    if (*cursor->prev != (intptr)cursor->curr)
+    if (my_atomic_loadptr((void**)cursor->prev) != cursor->curr)
     {
       (void)LF_BACKOFF;
       goto retry;
```

# 解决

查看 change log，该问题在[5.7.22](https://dev.mysql.com/doc/relnotes/mysql/5.7/en/news-5-7-22.html)版本修复的：

> A server exit could result from simultaneous attempts by multiple threads to register and deregister metadata Performance Schema objects, or to acquire and release metadata locks. (Bug #26502135)

**升级内核版本到 5.7.29，之后巡检 1 个月，该问题未再出现，问题解决。**

**PS：**

> 篇幅有限，在后续文章中会单独分析 MDL、LF_HASH 源码，敬请关注。
