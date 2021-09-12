---
title: 源码分析 | 使用 gcov 和 lcov 测试 PostgreSQL 代码覆盖率
date: 2016-03-30 15:34:34
categories:
- PostgreSQL
tags:
- PostgreSQL
- gcov
- lcov
- 测试
toc: true
---

<!-- more -->


# 引言

通常我们评判一个 test case 好坏的标准之一是代码的覆盖率，一个好的 test case 应该覆盖到所有的代码。

那么问题来了，我们**怎么知道这个 test case 有没有覆盖到所有的代码呢？**

以 PostgreSQL 为例，我们看看如何检测 C 语言程序的代码覆盖率。

C 代码覆盖率测试，需要用到 gcc 的配套工具`gcov`，还有一个可视化工具`lcov`。

# 1. 安装依赖

首先需要安装依赖 gcov 和 lcov 。

gcov 在 gcc 包中已经包含了，lcov 是 ltp 的一个 gcov 扩展插件，用来产生HTML报告。

```bash
sudo apt install lcov
```


# 2. 编译、安装 PG

## 2.1. 编译选项介绍

首先介绍一下 PostgreSQL 的编译选项 `--enable-coverage`：

```bash
--enable-coverage       build with coverage testing instrumentation
```

这个编译项对应gcc的两个参数：`-fprofile-arcs` 和 `-ftest-coverage`。

```bash
# enable code coverage if --enable-coverage
if test "$enable_coverage" = yes; then
  if test "$GCC" = yes; then
    CFLAGS="$CFLAGS -fprofile-arcs -ftest-coverage"
  else
    as_fn_error $? "--enable-coverage is supported only when using GCC" "$LINENO" 5
  fi
fi
```

通过`man gcc`查看这两个参数的含义：
```
-fprofile-arcs
           Add code so that program flow arcs are instrumented.  During execution the program records how many times each branch and call is executed and how many times it is taken or returns.  When
           the compiled program exits it saves this data to a file called auxname.gcda for each source file.  The data may be used for profile-directed optimizations (-fbranch-probabilities), or for
           test coverage analysis (-ftest-coverage).  Each object file's auxname is generated from the name of the output file, if explicitly specified and it is not the final executable, otherwise
           it is the basename of the source file.  In both cases any suffix is removed (e.g. foo.gcda for input file dir/foo.c, or dir/foo.gcda for output file specified as -o dir/foo.o).

--coverage
           This option is used to compile and link code instrumented for coverage analysis.  The option is a synonym for -fprofile-arcs -ftest-coverage (when compiling) and -lgcov (when linking).
           See the documentation for those options for more details.

           *   Compile the source files with -fprofile-arcs plus optimization and code generation options.  For test coverage analysis, use the additional -ftest-coverage option.  You do not need to
               profile every source file in a program.

           *   Link your object files with -lgcov or -fprofile-arcs (the latter implies the former).

           *   Run the program on a representative workload to generate the arc profile information.  This may be repeated any number of times.  You can run concurrent instances of your program, and
               provided that the file system supports locking, the data files will be correctly updated.  Also "fork" calls are detected and correctly handled (double counting will not happen).

           *   For profile-directed optimizations, compile the source files again with the same optimization and code generation options plus -fbranch-probabilities.

           *   For test coverage analysis, use gcov to produce human readable information from the .gcno and .gcda files.  Refer to the gcov documentation for further information.

           With -fprofile-arcs, for each function of your program GCC creates a program flow graph, then finds a spanning tree for the graph.  Only arcs that are not on the spanning tree have to be
           instrumented: the compiler adds code to count the number of times that these arcs are executed.  When an arc is the only exit or only entrance to a block, the instrumentation code can be
           added to the block; otherwise, a new basic block must be created to hold the instrumentation code.

-ftest-coverage
           Produce a notes file that the gcov code-coverage utility can use to show program coverage.  Each source file's note file is called auxname.gcno.  Refer to the -fprofile-arcs option above
           for a description of auxname and instructions on how to generate test coverage data.  Coverage data matches the source files more closely if you do not optimize.
```

**-fprofile-arcs**：
>`-fprofile-arcs` 用于产生 .c 文件对应的 .gcda 文件，.gcda 文件可以被用于 profile 驱动的优化，或者结合 gcov 来做代码覆盖分析。
>
>编译时尽量不要使用 -O 优化，这样代码覆盖数据 .gcda 才能尽可能和代码接近。
>
>当代码被调用时，.gcda 文件中对应的计数器会被修改，记录代码被调用的次数。

**-ftest-coverage**：
>`-ftest-coverage` 这个选项用于产生 .c 文件的 .gcno 文件。这个文件生成后不会被修改。结合 .gcda，可以分析测试代码覆盖率。


## 2.2. 编译安装

```bash
./configure --prefix=/opt/pgsql9.4.4 --with-pgport=1921 --with-perl --with-python --with-tcl --with-openssl --with-pam --with-ldap --with-libxml --with-libxslt --enable-thread-safety --enable-debug --enable-dtrace --enable-coverage

gmake world && gmake install-world
```

安装好后，我们会发现在源码目录中多了一些.gcda和.gcno的文件，每个.c文件都会对应这两个文件：

```bash
postgres@wslu-> ll
total 1.3M
-rw-r--r-- 1 postgres postgres  22K Jun 10 03:29 gistbuildbuffers.c
-rw------- 1 postgres postgres 1.6K Sep  7 14:42 gistbuildbuffers.gcda
-rw-r--r-- 1 postgres postgres  15K Sep  7 14:38 gistbuildbuffers.gcno
-rw-r--r-- 1 postgres postgres  70K Sep  7 14:38 gistbuildbuffers.o
-rw-r--r-- 1 postgres postgres  37K Jun 10 03:29 gistbuild.c
-rw------- 1 postgres postgres 2.2K Sep  7 14:42 gistbuild.gcda
-rw-r--r-- 1 postgres postgres  20K Sep  7 14:38 gistbuild.gcno
-rw-r--r-- 1 postgres postgres  92K Sep  7 14:38 gistbuild.o
-rw-r--r-- 1 postgres postgres  43K Jun 10 03:29 gist.c
-rw------- 1 postgres postgres 3.1K Sep  7 14:42 gist.gcda
-rw-r--r-- 1 postgres postgres  29K Sep  7 14:38 gist.gcno
-rw-r--r-- 1 postgres postgres  16K Jun 10 03:29 gistget.c
-rw------- 1 postgres postgres 1.3K Sep  7 14:42 gistget.gcda
-rw-r--r-- 1 postgres postgres  13K Sep  7 14:38 gistget.gcno
-rw-r--r-- 1 postgres postgres  74K Sep  7 14:38 gistget.o
-rw-r--r-- 1 postgres postgres 101K Sep  7 14:38 gist.o
-rw-r--r-- 1 postgres postgres  39K Jun 10 03:29 gistproc.c
-rw------- 1 postgres postgres 3.1K Sep  7 14:42 gistproc.gcda
-rw-r--r-- 1 postgres postgres  31K Sep  7 14:38 gistproc.gcno
-rw-r--r-- 1 postgres postgres  79K Sep  7 14:38 gistproc.o
-rw-r--r-- 1 postgres postgres 9.1K Jun 10 03:29 gistscan.c
-rw------- 1 postgres postgres  848 Sep  7 14:42 gistscan.gcda
-rw-r--r-- 1 postgres postgres 6.7K Sep  7 14:38 gistscan.gcno
-rw-r--r-- 1 postgres postgres  60K Sep  7 14:38 gistscan.o
-rw-r--r-- 1 postgres postgres  24K Jun 10 03:29 gistsplit.c
-rw------- 1 postgres postgres 1.5K Sep  7 14:42 gistsplit.gcda
-rw-r--r-- 1 postgres postgres  15K Sep  7 14:38 gistsplit.gcno
-rw-r--r-- 1 postgres postgres  68K Sep  7 14:38 gistsplit.o
-rw-r--r-- 1 postgres postgres  21K Jun 10 03:29 gistutil.c
-rw------- 1 postgres postgres 2.2K Sep  7 14:42 gistutil.gcda
-rw-r--r-- 1 postgres postgres  20K Sep  7 14:38 gistutil.gcno
-rw-r--r-- 1 postgres postgres  84K Sep  7 14:38 gistutil.o
-rw-r--r-- 1 postgres postgres 7.1K Jun 10 03:29 gistvacuum.c
-rw------- 1 postgres postgres  784 Sep  7 14:42 gistvacuum.gcda
-rw-r--r-- 1 postgres postgres 7.3K Sep  7 14:38 gistvacuum.gcno
-rw-r--r-- 1 postgres postgres  56K Sep  7 14:38 gistvacuum.o
-rw-r--r-- 1 postgres postgres  14K Jun 10 03:29 gistxlog.c
-rw------- 1 postgres postgres 1.2K Sep  7 14:42 gistxlog.gcda
-rw-r--r-- 1 postgres postgres  12K Sep  7 14:38 gistxlog.gcno
-rw-r--r-- 1 postgres postgres  50K Sep  7 14:38 gistxlog.o
-rw-r--r-- 1 postgres postgres  538 Jun 10 03:29 Makefile
-rw-r--r-- 1 postgres postgres  357 Sep  7 14:38 objfiles.txt
-rw-r--r-- 1 postgres postgres  20K Jun 10 03:29 README

postgres@wslu-> pwd
/opt/soft_bak/postgresql-9.4.4/src/backend/access/gist
```

**注意事项：**

源码文件目录的权限需要改为数据库启动用户的权限，否则无法修改 .gcda 的值，也就无法获取代码被调用的次数了。

```bash
root@wslu-> chown -R postgres:postgres /opt/soft_bak/postgresql-9.4.4
```

接下来我们看看文件的变化，以 dbsize.c 中的两个获取 pg_database_size 的 C 函数为例：

```bash
postgres@wslu-> ls -la|grep dbsize
-rw-r--r--  1 postgres postgres  19342 Jun 10 03:29 dbsize.c
-rw-------  1 postgres postgres   2664 Sep  7 15:01 dbsize.gcda
-rw-r--r--  1 postgres postgres  23272 Sep  7 14:38 dbsize.gcno
-rw-r--r--  1 postgres postgres  89624 Sep  7 14:38 dbsize.o
```

调用一次：

```bash
postgres@wslu-> psql
psql (9.4.4)
Type "help" for help.
postgres=# select pg_database_size(oid) from pg_database;
 pg_database_size
------------------
          6898180
          6889988
         24742560
          6898180
          6898180
          6898180
(6 rows)
postgres=# \q
```

再次查看：

```bash
postgres@wslu-> ls -la|grep dbsize
-rw-r--r--  1 postgres postgres  19342 Jun 10 03:29 dbsize.c
-rw-------  1 postgres postgres   2664 Sep  7 15:12 dbsize.gcda
-rw-r--r--  1 postgres postgres  23272 Sep  7 14:38 dbsize.gcno
-rw-r--r--  1 postgres postgres  89624 Sep  7 14:38 dbsize.o
```

dbsize.gcda 文件的修改时间发送了变化，说明刚才我们调用pg_database_size(oid) 时，调用了 dbsize.c 中的代码。对应的行计数器会发生变化。

# 3. 生成 HTML 报告

```bash
$ mkdir html
$ cd html

$ lcov --directory /opt/soft_bak/postgresql-9.4.4 --capture --output-file ./app.info
# 如果你不需要所有的代码，修改以上目录即可，譬如只看 contrib 下面的代码覆盖率。

$ genhtml ./app.info
postgres@wslu-> ll
total 3.7M
drwxrwxr-x 12 postgres postgres 4.0K Sep  7 15:02 access
-rw-rw-r--  1 postgres postgres  141 Sep  7 15:02 amber.png
-rw-rw-r--  1 postgres postgres 3.4M Sep  7 15:02 app.info
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 bootstrap
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 catalog
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 commands
-rw-rw-r--  1 postgres postgres  141 Sep  7 15:02 emerald.png
drwxrwxr-x  2 postgres postgres  12K Sep  7 15:02 executor
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 foreign
-rw-rw-r--  1 postgres postgres 9.7K Sep  7 15:02 gcov.css
-rw-rw-r--  1 postgres postgres  167 Sep  7 15:02 glass.png
-rw-rw-r--  1 postgres postgres  57K Sep  7 15:02 index.html
-rw-rw-r--  1 postgres postgres  57K Sep  7 15:02 index-sort-f.html
-rw-rw-r--  1 postgres postgres  57K Sep  7 15:02 index-sort-l.html
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 lib
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 libpq
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 main
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 nodes
drwxrwxr-x  3 postgres postgres 4.0K Sep  7 15:02 opt
drwxrwxr-x  7 postgres postgres 4.0K Sep  7 15:02 optimizer
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 parser
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 port
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 postmaster
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 regex
drwxrwxr-x  3 postgres postgres 4.0K Sep  7 15:02 replication
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 rewrite
-rw-rw-r--  1 postgres postgres  141 Sep  7 15:02 ruby.png
drwxrwxr-x  3 postgres postgres 4.0K Sep  7 15:02 snowball
-rw-rw-r--  1 postgres postgres  141 Sep  7 15:02 snow.png
drwxrwxr-x 10 postgres postgres 4.0K Sep  7 15:02 storage
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 tcop
drwxrwxr-x  2 postgres postgres 4.0K Sep  7 15:02 tsearch
-rw-rw-r--  1 postgres postgres  117 Sep  7 15:02 updown.png
drwxrwxr-x  3 postgres postgres 4.0K Sep  7 15:02 usr
drwxrwxr-x 14 postgres postgres 4.0K Sep  7 15:02 utils
```

# 4. 查看报告

浏览器中打开 `index.html` 即可查看。

# 后记

PostgreSQL 其实已经在 Makefile 提供了生成代码覆盖 HTML 的 target 。
```bash
[root@wslu postgresql-9.4.4]# make coverage-html
```

产生的html目录如下：
```bash
[root@wslu postgresql-9.4.4]# cd coverage
[root@wslu coverage]# ll
total 224
-rw-r--r--  1 root root   141 Sep  7 19:17 amber.png
-rw-r--r--  1 root root   141 Sep  7 19:17 emerald.png
-rw-r--r--  1 root root  9893 Sep  7 19:17 gcov.css
-rw-r--r--  1 root root   167 Sep  7 19:17 glass.png
-rw-r--r--  1 root root 58737 Sep  7 19:18 index.html
-rw-r--r--  1 root root 58730 Sep  7 19:18 index-sort-f.html
-rw-r--r--  1 root root 58730 Sep  7 19:18 index-sort-l.html
-rw-r--r--  1 root root   141 Sep  7 19:17 ruby.png
-rw-r--r--  1 root root   141 Sep  7 19:17 snow.png
drwxr-xr-x 11 root root  4096 Sep  7 19:18 src
-rw-r--r--  1 root root   117 Sep  7 19:17 updown.png
drwxr-xr-x  3 root root  4096 Sep  7 19:18 usr
```

每次对代码改动后，执行完 `make check` 或其他回归测试手段后，就可以执行 `make coverage-html` 了。

# 参考链接

1. [Magus Test Archive](http://magustest.com/blog/whiteboxtesting/using-gcov-lcov/)
2. [lcov](http://ltp.sourceforge.net/coverage/lcov.php)
3. [lcov readme](http://ltp.sourceforge.net/coverage/lcov/readme.php)
4. [GitHub - linux-test-project/ltp: Linux Test Project http://linux-test-project.github.io/](https://github.com/linux-test-project/ltp)
5. [Gcov (Using the GNU Compiler Collection (GCC))](https://gcc.gnu.org/onlinedocs/gcc/Gcov.html)
6. [CodeCoverage - PostgreSQL wiki](https://wiki.postgresql.org/wiki/CodeCoverage)
7. [PostgreSQL: Documentation: devel: 33.5. Test Coverage Examination](http://www.postgresql.org/docs/devel/static/regress-coverage.html)

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


