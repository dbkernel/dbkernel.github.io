---
title: 源码分析 | MySQL测试框架 MTR 系列教程（三）：源码篇
date: 2023-07-05 22:03:44
categories:
  - MySQL
tags:
  - MySQL
  - 测试框架
  - MTR
toc: true
---

**作者：卢文双 资深数据库内核研发**

**序言**：

以前对 MySQL 测试框架 MTR 的使用，主要集中于 SQL 正确性验证。近期由于工作需要，深入了解了 MTR 的方方面面，发现 MTR 的能力不仅限于此，还支持单元测试、压力测试、代码覆盖率测试、内存错误检测、线程竞争与死锁等功能，因此，本着分享的精神，将其总结成一个系列。

主要内容如下：

- 入门篇：工作机制、编译安装、参数、指令示例、推荐用法、添加 case、常见问题、异常调试
- 进阶篇：高阶用法，包括单元测试、压力测试、代码覆盖率测试、内存错误检测、线程竞争与死锁
- 源码篇：分析 MTR 的源码
- 语法篇：单元测试、压力测试、mysqltest 语法、异常调试

由于个人水平有限，所述难免有错误之处，望雅正。

**本文是第三篇源码篇。**

<!-- more -->

> **本文首发于 2023-07-05 22:03:44**

---

MTR 系列基于 MySQL 8.0.29 版本，如有例外，会特别说明。

# 简介

首先回顾一下**MySQL 测试框架主要包含的组件：**

- [mysql-test-run.pl](https://dev.mysql.com/doc/dev/mysql-server/latest/PAGE_MYSQL_TEST_RUN_PL.html "mysql-test-run.pl") ：perl 脚本，简称 **mtr**，是 MySQL 最常用的测试工具，负责控制流程，包括启停、识别执行哪些用例、创建文件夹、收集结果等等，主要作用是验证 SQL 语句在各种场景下是否返回正确的结果。
- [mysqltest](https://dev.mysql.com/doc/dev/mysql-server/latest/PAGE_MYSQLTEST.html "mysqltest") ：C++二进制程序，负责执行测试用例，包括读文件、解析特定语法、执行用例。用例的特殊语法（比如，`--source`，`--replace_column`等）都在`command_names`和`enum_commands`两个枚举结构体中。
- [mysql_client_test](https://dev.mysql.com/doc/dev/mysql-server/latest/PAGE_MYSQL_CLIENT_TEST.html "mysql_client_test") ：C++二进制程序，用于测试 MySQL 客户端 API（[mysqltest](https://dev.mysql.com/doc/dev/mysql-server/latest/PAGE_MYSQLTEST.html "mysqltest") 无法用于测试 API）。
- [mysql-stress-test.pl](https://dev.mysql.com/doc/dev/mysql-server/latest/PAGE_MYSQL_STRESS_TEST_PL.html "mysql-stress-test.pl") ：perl 脚本，用于 MySQL Server 的压力测试。
- 支持 gcov/gprof 代码覆盖率测试工具。

除此之外，还提供了单元测试工具，以便为存储引擎和插件创建单独的单元测试程序。

**各个组件的位置如下：**

| 源码位置                           | 安装目录位置                      |
| ---------------------------------- | --------------------------------- |
| `mysql-test/mysql-test-run.pl`     | `mysql-test/mysql-test-run.pl`    |
| `client/mysqltest.cc`              | `bin/mysqltest`                   |
| `testclients/mysql_client_test.cc` | `bin/mysql_client_test`           |
| `mysql-test/mysql-stress-test.pl`  | `mysql-test/mysql-stress-test.pl` |

# 源码分析

## **基本原理**

简要回顾一下 MTR 的基本原理：

SQL 正确性：对比（diff）期望输出和实际输出，若完全一致，则测试通过；反之，测试失败。

高级用法：以下工具都需要在编译时启用对应的选项。

- valgrind：mtr 根据传参拼接 valgrind 指令的方式来测试。
- ASAN：包含编译器插桩模块，还有一个运行时的库用来替换 malloc 函数。插桩模块主要用在栈内存上，而运行时库主要用在堆内存上。
- MSAN：核心是编译插桩，同时还有一个运行时库，用来在启动时，将低地址内存设置为不可读，然后映射为影子内存。
- UBSAN：在编译时对可疑操作进行插桩，以捕获程序运行时的未定义行为。同时，还有一个额外的运行时库。
- gcov/gprof：mtr 根据传参拼接相关指令来测试。
- 单元测试：通过 mtr 调用 mysqltest，再调用 `xx-t` 等生成的二进制文件。

更多内容请参考本系列「（一）入门篇」及「（二）进阶篇」。

## 整体流程图

![线程池流程图](threadpool-architecture.png "线程池流程图")

## mysql-test-run.pl

### 时序图

**MTR 框架时序图如下所示：**

![MTR时序图（来源于腾讯数据库技术公众号）](threadpool-sequence-chart.png "MTR时序图（来源于腾讯数据库技术公众号）")

### 框架流程

如上图所示，`mysql-test-run.pl`框架运行流程如下：

1、**初始化（Initialization）**。

- 确定用例执行范围（`collect_test_cases`），包括运行哪些 suite，skip 哪些用例，在本阶段根据`disabled.def`文件、`--skip-xxx`命令（比如`skip-rpl`）等确定执行用例。将所有用例组织到一个大的内存结构中（`my @tests_list`、`my @tests`），包括用例启动参数，用例。
- 同时，初始化数据库（`initialize_servers()->mysql_install_db()`）。后面运行用例启动数据库时，不需要每次初始化，只需从这里的目录中拷贝启动。

2、**运行用例（run test）**。

主线程根据参数`--parallel`（默认是 1）启动一个或者多个用例执行线程（`run_worker()`），各线程有自己独立的 client port，data dir 等。

启动的`run_worker`与主线程之间是 server-client 模式，主线程是 server，`run_worker()`是 client。

- 主线程与`run_worker`是一问一答模式，主线程向`run_worker`发送运行用例的文件路径、配置文件参数等各种参数信息，`run_worker`向主线程返回运行结果，直到所有在 collection 中的用例都运行完毕，主线程 close 各`run_worker`，进行收尾工作。
- 主线程先读取各`run_worker`返回值，对上一个用例进行收尾工作。之后，读取 collection 中的用例，通过本地 socket 发送到`run_worker`线程，`run_worker`线程接收到主线程命令，运行本次用例执行函数`run_testcase()`，而 `run_testcase()`主要负责 3 件事：**启动 mysqld、启动并监控 mysqltest，处理执行结果**。
  - 启动 mysqld： 根据参数启动一个或者多个 mysqld（`start_servers()`），在`start_servers`大多数情况下会拷贝主线程初始化后的目录到`run_worker`的目录，作为新实例的启动目录，用 shell 命令启动数据库。
  - 启动并监控 mysqltest：用例在`mysqltest`中执行（会逐行扫描 `*.test` 文件中的 SQL 或指令并于 MySQL 中执行），`run_worker`线程会监控`mysqltest`的运行状态，监测其是否运行超时或者运行结束。
  - 处理执行结果：`mysqltest`执行结束会留下执行日志，框架根据执行日志判断执行是否通过，如果没通过是否需要重试等

### 代码

本小节所涉及代码都来自于`mysql-test-run.pl`文件，但由于该文件内容过多，此处只截取关键流程代码。

#### 引用模块

```perl
require "lib/mtr_gcov.pl";
require "lib/mtr_gprof.pl";
require "lib/mtr_io.pl";
require "lib/mtr_lock_order.pl";
require "lib/mtr_misc.pl";
require "lib/mtr_process.pl";

```

#### 主流程

```perl
# BEGIN 是 Perl 语言的标记，用于程序体“运行前”执行的代码逻辑，会在所有代码（包括main函数）执行前执行
BEGIN {
  # Check that mysql-test-run.pl is started from mysql-test/
  unless (-f "mysql-test-run.pl") {
    print "**** ERROR **** ",
      "You must start mysql-test-run from the mysql-test/ directory\n";
    exit(1);
  }

  # Check that lib exist
  unless (-d "lib/") {
    print "**** ERROR **** ", "Could not find the lib/ directory \n";
    exit(1);
  }
}

# END 是 Perl 语言的标记，用于程序体“运行后”执行的代码逻辑，会在所有代码执行后执行
END {
    my $current_id = $$;
    if ($parent_pid && $current_id == $parent_pid) {
        remove_redundant_thread_id_file_locations();
  clean_unique_id_dir();
    }
    if (defined $opt_tmpdir_pid and $opt_tmpdir_pid == $$) {
    if (!$opt_start_exit) {
      # Remove the tempdir this process has created
      mtr_verbose("Removing tmpdir $opt_tmpdir");
      rmtree($opt_tmpdir);
    } else {
      mtr_warning(
          "tmpdir $opt_tmpdir should be removed after the server has finished");
    }
  }
}

select(STDERR);
$| = 1;    # Automatically flush STDERR - output should be in sync with STDOUT
select(STDOUT);
$| = 1;    # Automatically flush STDOUT

main();

```

#### main 函数

```perl
sub main {
  # Default, verbosity on
  report_option('verbose', 0);

  # This is needed for test log evaluation in "gen-build-status-page"
  # in all cases where the calling tool does not log the commands directly
  # before it executes them, like "make test-force-pl" in RPM builds.
  mtr_report("Logging: $0 ", join(" ", @ARGV));

  command_line_setup(); # 分析命令行参数

  # Create a directory to store build thread id files
  create_unique_id_dir();

  $build_thread_id_file = "$build_thread_id_dir/" . $$ . "_unique_ids.log";
  open(FH, ">>", $build_thread_id_file) or
    die "Can't open file $build_thread_id_file: $!";
  print FH "# Unique id file paths\n";
  close(FH);

  # --help will not reach here, so now it's safe to assume we have binaries
  My::SafeProcess::find_bin($bindir, $path_client_bindir);

  $secondary_engine_support =
    ($secondary_engine_support and find_secondary_engine($bindir)) ? 1 : 0;

  if ($secondary_engine_support) {
    check_secondary_engine_features(using_extern());
    # Append secondary engine test suite to list of default suites if found.
    add_secondary_engine_suite();
  }

  if ($opt_gcov) { # 是否启用了 -gcov 参数
    gcov_prepare($basedir); # 删除之前生成的临时文件，比如 *.gcov、*.da、*.gcda
  }

  if ($opt_lock_order) { # 是否启用了 --lock-order=bool 参数
    lock_order_prepare($bindir); # 创建 lock_order 目录
  }

  ######################################
  # 根据参数，收集需要测试的 suites
  ######################################

  # Collect test cases from a file and put them into '@opt_cases'.
  if ($opt_do_test_list) { # 对应选项 --do-test-list=FILE ，各个测试 case 按行分割，如需注释则添加 # 号
    collect_test_cases_from_list(\@opt_cases, $opt_do_test_list, \$opt_ctest);
  }

  my $suite_set;
  if ($opt_suites) { # 是否通过 --suites 参数指定了要运行的 suites 集合
    # Collect suite set if passed through the MTR command line
    if ($opt_suites =~ /^default$/i) {
      $suite_set = 0;
    } elsif ($opt_suites =~ /^non[-]default$/i) {
      $suite_set = 1;
    } elsif ($opt_suites =~ /^all$/i) {
      $suite_set = 2;
    }
  } else {
    # Use all suites(suite set 2) in case the suite set isn't explicitly
    # specified and :-
    # a) A PREFIX or REGEX is specified using the --do-suite option
    # b) Test cases are passed on the command line
    # c) The --do-test or --do-test-list options are used
    #
    # If none of the above are used, use the default suite set (i.e.,
    # suite set 0)
    $suite_set = ($opt_do_suite or
                    @opt_cases  or
                    $::do_test  or
                    $opt_do_test_list
    ) ? 2 : 0;
  }

  # Ignore the suite set parameter in case a list of suites is explicitly
  # given
  if (defined $suite_set) {
    mtr_print(
         "Using '" . ("default", "non-default", "all")[$suite_set] . "' suites")
      if @opt_cases;

    if ($suite_set == 0) {
      # Run default set of suites
      $opt_suites = $DEFAULT_SUITES;
    } else {
      # Include the main suite by default when suite set is 'all'
      # since it does not have a directory structure like:
      # mysql-test/<suite_name>/[<t>,<r>,<include>]
      $opt_suites = ($suite_set == 2) ? "main" : "";

      # Scan all sub-directories for available test suites.
      # The variable $opt_suites is updated by get_all_suites()
      find(\&get_all_suites, "$glob_mysql_test_dir");
      find({ wanted => \&get_all_suites, follow => 1 }, "$basedir/internal")
        if (-d "$basedir/internal");

      if ($suite_set == 1) {
        # Run only with non-default suites
        for my $suite (split(",", $DEFAULT_SUITES)) {
          for ("$suite", "i_$suite") {
            remove_suite_from_list($_);
          }
        }
      }

      # Remove cluster test suites if ndb cluster is not enabled
      if (not $ndbcluster_enabled) {
        for my $suite (split(",", $opt_suites)) {
          next if not $suite =~ /ndb/;
          remove_suite_from_list($suite);
        }
      }

      # Remove secondary engine test suites if not supported
      if (defined $::secondary_engine and not $secondary_engine_support) {
        for my $suite (split(",", $opt_suites)) {
          next if not $suite =~ /$::secondary_engine/;
          remove_suite_from_list($suite);
        }
      }
    }
  }

  my $mtr_suites = $opt_suites;
  # Skip suites which don't match the --do-suite filter
  if ($opt_do_suite) {
    my $opt_do_suite_reg = init_pattern($opt_do_suite, "--do-suite");
    for my $suite (split(",", $opt_suites)) {
      if ($opt_do_suite_reg and not $suite =~ /$opt_do_suite_reg/) {
        remove_suite_from_list($suite);
      }
    }

    # Removing ',' at the end of $opt_suites if exists
    $opt_suites =~ s/,$//;
  }

  if ($opt_skip_sys_schema) {
    remove_suite_from_list("sysschema");
  }

  if ($opt_suites) {
    # Remove extended suite if the original suite is already in
    # the suite list
    for my $suite (split(",", $opt_suites)) {
      if ($suite =~ /^i_(.*)/) {
        my $orig_suite = $1;
        if ($opt_suites =~ /,$orig_suite,/ or
            $opt_suites =~ /^$orig_suite,/ or
            $opt_suites =~ /^$orig_suite$/ or
            $opt_suites =~ /,$orig_suite$/) {
          remove_suite_from_list($suite);
        }
      }
    }

    # Finally, filter out duplicate suite names if present,
    # i.e., using `--suite=ab,ab mytest` should not end up
    # running ab.mytest twice.
    my %unique_suites = map { $_ => 1 } split(",", $opt_suites);
    $opt_suites = join(",", sort keys %unique_suites);

    if (@opt_cases) {
      mtr_verbose("Using suite(s): $opt_suites");
    } else {
      mtr_report("Using suite(s): $opt_suites");
    }
  } else {
    if ($opt_do_suite) {
      mtr_error("The PREFIX/REGEX '$opt_do_suite' doesn't match any of " .
                "'$mtr_suites' suite(s)");
    }
  }

  ##############################################
  # 决定并发数量：
  # 1. 如果设置了 --parallel 参数，则根据参数来决定；
  # 2. 反之，根据 CPU 核心数来决定；
  ##############################################

  # Environment variable to hold number of CPUs
  my $sys_info = My::SysInfo->new();
  $ENV{NUMBER_OF_CPUS} = $sys_info->num_cpus();

  if ($opt_parallel eq "auto") {
    # Try to find a suitable value for number of workers
    $opt_parallel = $ENV{NUMBER_OF_CPUS};
    if (defined $ENV{MTR_MAX_PARALLEL}) {
      my $max_par = $ENV{MTR_MAX_PARALLEL};
      $opt_parallel = $max_par if ($opt_parallel > $max_par);
    }
    $opt_parallel = 1 if ($opt_parallel < 1);
  }


  init_timers(); # 字面意义，初始化 timer

  ##############################################
  # 之前收集了 test suites，现在收集 test cases
  ##############################################

  mtr_report("Collecting tests");
  my $tests = collect_test_cases($opt_reorder, $opt_suites,
                                 \@opt_cases,  $opt_skip_test_list);
  mark_time_used('collect');
  # A copy of the tests list, that will not be modified even after the tests
  # are executed.
  my @tests_list = @{$tests};

  check_secondary_engine_option($tests) if $secondary_engine_support;

  if ($opt_report_features) {
    # Put "report features" as the first test to run. No result file,
    # prints the output on console.
    my $tinfo = My::Test->new(master_opt    => [],
                              name          => 'report_features',
                              path          => 'include/report-features.test',
                              shortname     => 'report_features',
                              slave_opt     => [],
                              template_path => "include/default_my.cnf",);
    unshift(@$tests, $tinfo);
  }

  my $num_tests = @$tests;
  if ($num_tests == 0) {
    mtr_report("No tests found, terminating");
    exit(0);
  }

  ##############################################
  # 初始化测试所需的 servers
  # 1. kill 掉之前运行 mtr 残留的进程
  # 2. 通过 mysqld --initialize [options] 创建测试所用 database
  ##############################################

  initialize_servers();

  ##############################################
  # 以并行方式运行单元测试
  ##############################################

  # Run unit tests in parallel with the same number of workers as
  # specified to MTR.
  $ctest_parallel = $opt_parallel;

  # Limit parallel workers to the number of regular tests to avoid
  # idle workers.
  $opt_parallel = $num_tests if $opt_parallel > $num_tests;
  $ENV{MTR_PARALLEL} = $opt_parallel;
  mtr_report("Using parallel: $opt_parallel");

  my $is_option_mysqlx_port_set = $opt_mysqlx_baseport ne "auto";
  if ($opt_parallel > 1) {
    if ($opt_start_exit || $opt_stress || $is_option_mysqlx_port_set) {
      mtr_warning("Parallel cannot be used neither with --start-and-exit nor",
                  "--stress nor --mysqlx_port.\nSetting parallel value to 1.");
      $opt_parallel = 1;
    }
  }

  $num_tests_for_report = $num_tests;

  # Shutdown report is one extra test created to report
  # any failures or crashes during shutdown.
  $num_tests_for_report = $num_tests_for_report + 1;

  # When either --valgrind or --sanitize option is enabled, a dummy
  # test is created.
  if ($opt_valgrind_mysqld or $opt_sanitize) {
    $num_tests_for_report = $num_tests_for_report + 1;
  }

  # Please note, that disk_usage() will print a space to separate its
  # information from the preceding string, if the disk usage report is
  # enabled. Otherwise an empty string is returned.
  my $disk_usage = disk_usage();
  if ($disk_usage) {
    mtr_report(sprintf("Disk usage of vardir in MB:%s", $disk_usage));
  }

  # Create server socket on any free port
  my $server = new IO::Socket::INET(Listen    => $opt_parallel,
                                    LocalAddr => 'localhost',
                                    Proto     => 'tcp',);
  mtr_error("Could not create testcase server port: $!") unless $server;
  my $server_port = $server->sockport();

  if ($opt_resfile) {
    resfile_init("$opt_vardir/mtr-results.txt");
    print_global_resfile();
  }

  if ($secondary_engine_support) {
    secondary_engine_offload_count_report_init();
    # Create virtual environment
    create_virtual_env($bindir);
  }

  if ($opt_summary_report) {
    mtr_summary_file_init($opt_summary_report);
  }
  if ($opt_xml_report) {
    mtr_xml_init($opt_xml_report);
  }

  # Read definitions from include/plugin.defs
  read_plugin_defs("include/plugin.defs", 0);

 # Also read from plugin.defs files in internal and internal/cloud if they exist
  my @plugin_defs = ("$basedir/internal/mysql-test/include/plugin.defs",
                     "$basedir/internal/cloud/mysql-test/include/plugin.defs");

  for my $plugin_def (@plugin_defs) {
    read_plugin_defs($plugin_def) if -e $plugin_def;
  }

  # Simplify reference to semisync plugins
  $ENV{'SEMISYNC_PLUGIN_OPT'} = $ENV{'SEMISYNC_SOURCE_PLUGIN_OPT'};

  if (IS_WINDOWS) {
    $ENV{'PLUGIN_SUFFIX'} = "dll";
  } else {
    $ENV{'PLUGIN_SUFFIX'} = "so";
  }

  if ($group_replication) {
    $ports_per_thread = $ports_per_thread + 10;
  }

  if ($secondary_engine_support) {
    # Reserve 10 extra ports per worker process
    $ports_per_thread = $ports_per_thread + 10;
  }

  create_manifest_file();

  # Create child processes
  my %children;

  $parent_pid = $$;
  for my $child_num (1 .. $opt_parallel) {
    my $child_pid = My::SafeProcess::Base::_safe_fork();
    if ($child_pid == 0) {
      $server = undef;    # Close the server port in child
      $tests  = {};       # Don't need the tests list in child

      # Use subdir of var and tmp unless only one worker
      if ($opt_parallel > 1) {
        set_vardir("$opt_vardir/$child_num");
        $opt_tmpdir = "$opt_tmpdir/$child_num";
      }

      init_timers();
      run_worker($server_port, $child_num); ###### 核心函数
      exit(1);
    }

    $children{$child_pid} = 1;
  }

  mtr_print_header($opt_parallel > 1);

  mark_time_used('init');

  # 这里的 server 指的是 mtr 的主控制循环，而不是 mysql server 。
  # 该函数的主要作用是定期（每秒）唤醒一次，检查来自 worker 的新消息并处理，
  # 当 test cases 执行完或超时时，该函数会退出。
  my $completed = run_test_server($server, $tests, $opt_parallel);

  exit(0) if $opt_start_exit;

  ##############################################
  # 为退出测试做收尾工作
  ##############################################

  # Send Ctrl-C to any children still running
  kill("INT", keys(%children));

  if (!IS_WINDOWS) {
    # Wait for children to exit
    foreach my $pid (keys %children) {
      my $ret_pid = waitpid($pid, 0);
      if ($ret_pid != $pid) {
        mtr_report("Unknown process $ret_pid exited");
      } else {
        delete $children{$ret_pid};
      }
    }
  }

  # Remove config files for components
  read_plugin_defs("include/plugin.defs", 1);
  for my $plugin_def (@plugin_defs) {
    read_plugin_defs($plugin_def, 1) if -e $plugin_def;
  }

  remove_manifest_file();

  if (not $completed) {
    mtr_error("Test suite aborted");
  }

  if (@$completed != $num_tests) {
    # Not all tests completed, failure
    mtr_report();
    mtr_report("Only ", int(@$completed), " of $num_tests completed.");
    foreach (@tests_list) {
      $_->{key} = "$_" unless defined $_->{key};
    }
    my %is_completed_map = map { $_->{key} => 1 } @$completed;
    my @not_completed;
    foreach (@tests_list) {
      if (!exists $is_completed_map{$_->{key}}) {
        push (@not_completed, $_->{name});
      }
    }
    if (int(@not_completed) <= 100) {
      mtr_error("Not all tests completed:", join(" ", @not_completed));
    } else {
      mtr_error("Not all tests completed:", join(" ", @not_completed[0...49]), "... and", int(@not_completed)-50, "more");
    }
  }

  mark_time_used('init');

  push @$completed, run_ctest() if $opt_ctest;

  # Create minimalistic "test" for the reporting failures at shutdown
  my $tinfo = My::Test->new(name      => 'shutdown_report',
                            shortname => 'shutdown_report',);

  # Set dummy worker id to align report with normal tests
  $tinfo->{worker} = 0 if $opt_parallel > 1;
  if ($shutdown_report) {
    $tinfo->{result}   = 'MTR_RES_FAILED';
    $tinfo->{comment}  = "Mysqld reported failures at shutdown, see above";
    $tinfo->{failures} = 1;
  } else {
    $tinfo->{result} = 'MTR_RES_PASSED';
  }
  mtr_report_test($tinfo);
  report_option('prev_report_length', 0);
  push @$completed, $tinfo;

  if ($opt_valgrind_mysqld or $opt_sanitize) {
    # Create minimalistic "test" for the reporting
    my $tinfo = My::Test->new(
      name      => $opt_valgrind_mysqld ? 'valgrind_report' : 'sanitize_report',
      shortname => $opt_valgrind_mysqld ? 'valgrind_report' : 'sanitize_report',
    );

    # Set dummy worker id to align report with normal tests
    $tinfo->{worker} = 0 if $opt_parallel > 1;
    if ($valgrind_reports) {
      $tinfo->{result} = 'MTR_RES_FAILED';
      if ($opt_valgrind_mysqld) {
        $tinfo->{comment} = "Valgrind reported failures at shutdown, see above";
      } else {
        $tinfo->{comment} =
          "Sanitizer reported failures at shutdown, see above";
      }
      $tinfo->{failures} = 1;
    } else {
      $tinfo->{result} = 'MTR_RES_PASSED';
    }
    mtr_report_test($tinfo);
    report_option('prev_report_length', 0);
    push @$completed, $tinfo;
  }

  if ($opt_quiet) {
    my $last_test = $completed->[-1];
    mtr_report() if !$last_test->is_failed();
  }

  mtr_print_line();

  if ($opt_gcov) {
    gcov_collect($bindir, $opt_gcov_exe, $opt_gcov_msg, $opt_gcov_err);
  }

  if ($ctest_report) {
    print "$ctest_report\n";
    mtr_print_line();
  }

  # Cleanup the build thread id files
  remove_redundant_thread_id_file_locations();
  clean_unique_id_dir();

  # Cleanup the secondary engine environment
  if ($secondary_engine_support) {
    clean_virtual_env();
  }

  print_total_times($opt_parallel) if $opt_report_times;

  mtr_report_stats("Completed", $completed);

  remove_vardir_subs() if $opt_clean_vardir;

  exit(0);
}
```

#### run_worker 函数

```perl
# This is the main loop for the worker thread (which, as mentioned, is
# actually a separate process except on Windows).
#
# Its main loop reads messages from the main thread, which are either
# 'TESTCASE' with details on a test to run (also read with
# My::Test::read_test()) or 'BYE' which will make the worker clean up
# and send a 'SPENT' message. If running with valgrind, it also looks
# for valgrind reports and sends 'VALGREP' if any were found.
sub run_worker ($) {
  my ($server_port, $thread_num) = @_;

  $SIG{INT} = sub { exit(1); };

  # Connect to server
  my $server = new IO::Socket::INET(PeerAddr => 'localhost',
                                    PeerPort => $server_port,
                                    Proto    => 'tcp');
  mtr_error("Could not connect to server at port $server_port: $!")
    unless $server;

  # Set worker name
  report_option('name', "worker[$thread_num]");

  # Set different ports per thread
  set_build_thread_ports($thread_num);

  # Turn off verbosity in workers, unless explicitly specified
  report_option('verbose', undef) if ($opt_verbose == 0);

  environment_setup();

  # Read hello from server which it will send when shared
  # resources have been setup
  my $hello = <$server>;

  setup_vardir(); # 创建 var 目录（默认，若指定 --vardir，则以参数为准），用于存放测试过程中产生的文件。
  check_running_as_root(); # 检查是否以 root 运行，若是，则无需检查文件权限了。

  if (using_extern()) {
    create_config_file_for_extern(%opts_extern);
  }

  # Ask server for first test
  print $server "START\n";

  mark_time_used('init');

  while (my $line = <$server>) {
    chomp($line);
    if ($line eq 'TESTCASE') {
      my $test = My::Test::read_test($server);

      # Clear comment and logfile, to avoid reusing them from previous test
      delete($test->{'comment'});
      delete($test->{'logfile'});

      # A sanity check. Should this happen often we need to look at it.
      if (defined $test->{reserved} && $test->{reserved} != $thread_num) {
        my $tres = $test->{reserved};
        my $name = $test->{name};
        mtr_warning("Test $name reserved for w$tres picked up by w$thread_num");
      }
      $test->{worker} = $thread_num if $opt_parallel > 1;

      run_testcase($test); # 运行测试用例（test case），返回 0 表示执行成功，非 0 表示失败。
      |-- do_before_run_mysqltest($tinfo);
      |-- start_mysqltest($tinfo);
      |-- while 循环定期判断 mysqltest 的执行状态并做后续处理

      # Stop the secondary engine servers if started.
      stop_secondary_engine_servers() if $test->{'secondary-engine'};

      $ENV{'SECONDARY_ENGINE_TEST'} = 0;

      # Send it back, now with results set
      $test->write_test($server, 'TESTRESULT');
      mark_time_used('restart');
    } elsif ($line eq 'BYE') { # 收到 BYE 指令
      mtr_report("Server said BYE");
      my $ret = stop_all_servers($opt_shutdown_timeout); # 关闭所有 server
      if (defined $ret and $ret != 0) {
        shutdown_exit_reports();
        $shutdown_report = 1;
      }
      print $server "SRV_CRASH\n" if $shutdown_report;
      mark_time_used('restart');

      my $valgrind_reports = 0;
      if ($opt_valgrind_mysqld or $opt_sanitize) {
        $valgrind_reports = valgrind_exit_reports() if not $shutdown_report;
        print $server "VALGREP\n" if $valgrind_reports;
      }

      if ($opt_gprof) { # 如果指定了 -gprof ，则使用 gprof 解析 gcov 生成的结果文件 gmon.out
        gprof_collect(find_mysqld($basedir), keys %gprof_dirs);
      }

      mark_time_used('admin');
      print_times_used($server, $thread_num);
      exit($valgrind_reports);
    } else {
      mtr_error("Could not understand server, '$line'");
    }
  }

  stop_all_servers();
  exit(1);
}
```

## mysql-stress-test.pl

该文件会被 `mysql-test-run.pl`调用，但压力测试的命令或 SQL 需要自行编写。

### 指令用法

```bash
perl mysql-stress-test.pl
--stress-suite-basedir=/opt/qa/mysql-test-extra-5.0/mysql-test
--stress-basedir=/opt/qa/test
--server-logs-dir=/opt/qa/logs
--test-count=20
--stress-tests-file=innodb-tests.txt
--stress-init-file=innodb-init.txt
--threads=5
--suite=funcs_1
--mysqltest=/opt/mysql/mysql-5.0/client/mysqltest
--server-user=root
--server-database=test
--cleanup

```

### 代码流程

该文件代码比较简单，主要步骤为：

1. 解析参数，检查文件、路径的合法性；
2. PREPARATION STAGE ：准备测试所需文件；
3. INITIALIZATION STAGE ：读取`--stress-init-file`指定的文件来初始化 stress database ；
4. STRESS TEST RUNNING STAGE ：根据参数`--threads`指定的数量创建线程（若不指定，默认是 1）。每个线程都执行`test_loop`函数来运行压力测试。
   1. 调用 `test_init` 函数初始化 session 变量。
   2. 调用`test_execute` 函数来执行测试（测试结果`.result`的文件名是随机生成的）。

## mysqltest.cc

### 工作原理

执行框架主要集中在`mysqltest.cc`中，`mysqltest`读取用例文件（`*.test`），根据预定义的命令（比如`--source`，`--replace_column`, `shutdown_server`等）执行相应的操作。

根据`mysql-test-run.pl` 文件中的`run_worker` 函数传入的运行参数（`args`）获得用例文件路径等信息，然后读取文件逐行执行语句，语句分为两种：

- **一种是可以直接执行的 SQL 语句**
- **一种是控制语句**，控制语句用来控制 mysqlclient 的特殊行为，比如`shutdown mysqld`等，这些命令预定义在`command_names`中。

详见 《[04 - MySQL 测试框架 MTR 系列教程 4 - 语法篇](https://www.wolai.com/gUcRYZJpPu5jivm7oau9Ur "04 - MySQL 测试框架 MTR 系列教程4 - 语法篇")》

### 调用栈

通过 `main()` 函数可以清晰的看到 `mysqltest.cc` 的整体流程，主要分为几步：

1. 初始化或准备工作；
2. while 循环读取 command 并处理，每个 command 的处理函数又可能是一个循环解析字符串并执行的过程；
3. 分析执行结果。

```c++
main
|-- init_signal_handling
|-- parse_args(argc, argv);
|-- mysql_server_init
|-- // 打开或创建 result log
|-- mysql_init(&con->mysql)
|-- safe_connect(&con->mysql, con->name, opt_host, opt_user, opt_pass, opt_db,
               opt_port, unix_sock) // Connect to a server doing several retries if needed
|-- ssl_client_check_post_connect_ssl_setup(
          &con->mysql, [](const char *err) { die("%s", err); })
|-- mysql_query_wrapper(
        &con->mysql, "SET optimizer_switch='hypergraph_optimizer=on';")
|-- // 其他准备工作
    ...
|-- while (!read_command(&command) && !abort_flag) {
     // 解析 command type
     ...

     if (ok_to_do) {
     // 根据 command->type 做对应处理
     switch (command->type) {
        case Q_CONNECT:
          do_connect(command); // 创建新连接
          break;
        case Q_CONNECTION:
          select_connection(command);
          break;
        case Q_DISCONNECT:
        case Q_DIRTY_CLOSE:
          do_close_connection(command);
          break;
        case Q_ENABLE_QUERY_LOG:
          set_property(command, P_QUERY, false); // 通过设置某个属性值为 0或1，达到关闭/启用的目的
          break;
        case Q_DISABLE_QUERY_LOG:
          set_property(command, P_QUERY, true);
          break;
        case Q_ENABLE_ABORT_ON_ERROR:
          set_property(command, P_ABORT, true);
          break;
        case Q_DISABLE_ABORT_ON_ERROR:
          set_property(command, P_ABORT, false);
          break;
        case Q_ENABLE_RESULT_LOG:
          set_property(command, P_RESULT, false);
          break;
        case Q_DISABLE_RESULT_LOG:
          set_property(command, P_RESULT, true);
          break;
        case Q_ENABLE_CONNECT_LOG:
          set_property(command, P_CONNECT, false);
          break;
        case Q_DISABLE_CONNECT_LOG:
          set_property(command, P_CONNECT, true);
          break;
        case Q_ENABLE_WARNINGS:
          do_enable_warnings(command);
          break;
        case Q_DISABLE_WARNINGS:
          do_disable_warnings(command);
          break;
        case Q_ENABLE_INFO:
          set_property(command, P_INFO, false);
          break;
        case Q_DISABLE_INFO:
          set_property(command, P_INFO, true);
          break;
        case Q_ENABLE_SESSION_TRACK_INFO:
          set_property(command, P_SESSION_TRACK, true);
          break;
        case Q_DISABLE_SESSION_TRACK_INFO:
          set_property(command, P_SESSION_TRACK, false);
          break;
        case Q_ENABLE_METADATA:
          set_property(command, P_META, true);
          break;
        case Q_DISABLE_METADATA:
          set_property(command, P_META, false);
          break;
        case Q_SOURCE:
          do_source(command);
          break;
        case Q_SLEEP:
          do_sleep(command);
          break;
        case Q_WAIT_FOR_SLAVE_TO_STOP:
          do_wait_for_slave_to_stop(command);
          break;
        case Q_INC:
          do_modify_var(command, DO_INC);
          break;
        case Q_DEC:
          do_modify_var(command, DO_DEC);
          break;
        case Q_ECHO:
          do_echo(command);
          command_executed++;
          break;
        case Q_REMOVE_FILE:
          do_remove_file(command);
          break;
        case Q_REMOVE_FILES_WILDCARD:
          do_remove_files_wildcard(command);
          break;
        case Q_COPY_FILES_WILDCARD:
          do_copy_files_wildcard(command);
          break;
        case Q_MKDIR:
          do_mkdir(command);
          break;
        case Q_RMDIR:
          do_rmdir(command, false);
          break;
        case Q_FORCE_RMDIR:
          do_rmdir(command, true);
          break;
        case Q_FORCE_CPDIR:
          do_force_cpdir(command);
          break;
        case Q_LIST_FILES:
          do_list_files(command);
          break;
        case Q_LIST_FILES_WRITE_FILE:
          do_list_files_write_file_command(command, false);
          break;
        case Q_LIST_FILES_APPEND_FILE:
          do_list_files_write_file_command(command, true);
          break;
        case Q_FILE_EXIST:
          do_file_exist(command);
          break;
        case Q_WRITE_FILE:
          do_write_file(command);
          break;
        case Q_APPEND_FILE:
          do_append_file(command);
          break;
        case Q_DIFF_FILES:
          do_diff_files(command);
          break;
        case Q_SEND_QUIT:
          do_send_quit(command);
          break;
        case Q_CHANGE_USER:
          do_change_user(command);
          break;
        case Q_CAT_FILE:
          do_cat_file(command);
          break;
        case Q_COPY_FILE:
          do_copy_file(command);
          break;
        case Q_MOVE_FILE:
          do_move_file(command);
          break;
        case Q_CHMOD_FILE:
          do_chmod_file(command);
          break;
        case Q_PERL:
          do_perl(command);
          break;
        case Q_RESULT_FORMAT_VERSION:
          do_result_format_version(command);
          break;
        case Q_DELIMITER:
          do_delimiter(command);
          break;
        case Q_DISPLAY_VERTICAL_RESULTS:
          display_result_vertically = true;
          break;
        case Q_DISPLAY_HORIZONTAL_RESULTS:
          display_result_vertically = false;
          break;
        case Q_SORTED_RESULT:
          /*
            Turn on sorting of result set, will be reset after next
            command
          */
          display_result_sorted = true;
          start_sort_column = 0;
          break;
        case Q_PARTIALLY_SORTED_RESULT:
          /*
            Turn on sorting of result set, will be reset after next
            command
          */
          display_result_sorted = true;
          start_sort_column = atoi(command->first_argument);
          command->last_argument = command->end;
          break;
        case Q_LOWERCASE:
          /*
            Turn on lowercasing of result, will be reset after next
            command
          */
          display_result_lower = true;
          break;
        case Q_SKIP_IF_HYPERGRAPH:
          /*
            Skip the next query if running with --hypergraph; will be reset
            after next command.
           */
          skip_if_hypergraph = true;
          break;
        case Q_LET:
          do_let(command);
          break;
        case Q_EXPR:
          do_expr(command);
          break;
        case Q_EVAL:
        case Q_QUERY_VERTICAL:
        case Q_QUERY_HORIZONTAL:
          if (command->query == command->query_buf) {
            /* Skip the first part of command, i.e query_xxx */
            command->query = command->first_argument;
            command->first_word_len = 0;
          }
          [[fallthrough]];
        case Q_QUERY:
        case Q_REAP: {
          bool old_display_result_vertically = display_result_vertically;
          /* Default is full query, both reap and send  */
          int flags = QUERY_REAP_FLAG | QUERY_SEND_FLAG;

          if (q_send_flag) {
            // Last command was an empty 'send' or 'send_eval'
            flags = QUERY_SEND_FLAG;
            if (q_send_flag == 2)
              // Last command was an empty 'send_eval' command. Set the command
              // type to Q_SEND_EVAL so that the variable gets replaced with its
              // value before executing.
              command->type = Q_SEND_EVAL;
            q_send_flag = 0;
          } else if (command->type == Q_REAP) {
            flags = QUERY_REAP_FLAG;
          }

          /* Check for special property for this query */
          display_result_vertically |= (command->type == Q_QUERY_VERTICAL);

          /*
            We run EXPLAIN _before_ the query. If query is UPDATE/DELETE is
            matters: a DELETE may delete rows, and then EXPLAIN DELETE will
            usually terminate quickly with "no matching rows". To make it more
            interesting, EXPLAIN is now first.
          */
          if (explain_protocol_enabled)
            run_explain(cur_con, command, flags, false);
          if (json_explain_protocol_enabled)
            run_explain(cur_con, command, flags, true);

          if (*output_file) {
            strmake(command->output_file, output_file, sizeof(output_file) - 1);
            *output_file = 0;
          }
          run_query(cur_con, command, flags); // 执行查询
          display_opt_trace(cur_con, command, flags);
          command_executed++;
          command->last_argument = command->end;

          /* Restore settings */
          display_result_vertically = old_display_result_vertically;

          break;
        }
        case Q_SEND:
        case Q_SEND_EVAL:
          if (!*command->first_argument) {
            // This is a 'send' or 'send_eval' command without arguments, it
            // indicates that _next_ query should be send only.
            if (command->type == Q_SEND)
              q_send_flag = 1;
            else if (command->type == Q_SEND_EVAL)
              q_send_flag = 2;
            break;
          }

          /* Remove "send" if this is first iteration */
          if (command->query == command->query_buf)
            command->query = command->first_argument;

          /*
            run_query() can execute a query partially, depending on the flags.
            QUERY_SEND_FLAG flag without QUERY_REAP_FLAG tells it to just send
            the query and read the result some time later when reap instruction
            is given on this connection.
          */
          run_query(cur_con, command, QUERY_SEND_FLAG); // 执行查询
          command_executed++;
          command->last_argument = command->end;
          break;
        case Q_ERROR:
          do_error(command);
          break;
        case Q_REPLACE:
          do_get_replace(command);
          break;
        case Q_REPLACE_REGEX:
          do_get_replace_regex(command);
          break;
        case Q_REPLACE_COLUMN:
          do_get_replace_column(command);
          break;
        case Q_REPLACE_NUMERIC_ROUND:
          do_get_replace_numeric_round(command);
          break;
        case Q_SAVE_MASTER_POS:
          do_save_master_pos();
          break;
        case Q_SYNC_WITH_MASTER:
          do_sync_with_master(command);
          break;
        case Q_SYNC_SLAVE_WITH_MASTER: {
          do_save_master_pos();
          if (*command->first_argument)
            select_connection(command);
          else
            select_connection_name("slave");
          do_sync_with_master2(command, 0);
          break;
        }
        case Q_COMMENT: {
          command->last_argument = command->end;

          /* Don't output comments in v1 */
          if (opt_result_format_version == 1) break;

          /* Don't output comments if query logging is off */
          if (disable_query_log) break;

          /* Write comment's with two starting #'s to result file */
          const char *p = command->query;
          if (p && *p == '#' && *(p + 1) == '#') {
            dynstr_append_mem(&ds_res, command->query, command->query_len);
            dynstr_append(&ds_res, "\n");
          }
          break;
        }
        case Q_EMPTY_LINE:
          /* Don't output newline in v1 */
          if (opt_result_format_version == 1) break;

          /* Don't output newline if query logging is off */
          if (disable_query_log) break;

          dynstr_append(&ds_res, "\n");
          break;
        case Q_PING:
          handle_command_error(command, mysql_ping(&cur_con->mysql)); // 执行 ping 指令
          break;
        case Q_RESET_CONNECTION:
          do_reset_connection();
          global_attrs->clear();
          break;
        case Q_QUERY_ATTRIBUTES:
          do_query_attributes(command);
          break;
        case Q_SEND_SHUTDOWN:
          if (opt_offload_count_file) {
            // Save the value of secondary engine execution status
            // before shutting down the server.
            if (secondary_engine->offload_count(&cur_con->mysql, "after"))
              cleanup_and_exit(1);
          }

          handle_command_error(
              command, mysql_query_wrapper(&cur_con->mysql, "shutdown"));
          break;
        case Q_SHUTDOWN_SERVER:
          do_shutdown_server(command);
          break;
        case Q_EXEC:
        case Q_EXECW:
          do_exec(command, false);
          command_executed++;
          break;
        case Q_EXEC_BACKGROUND:
          do_exec(command, true); // 执行 shell 命令
          command_executed++;
          break;
        case Q_START_TIMER:
          /* Overwrite possible earlier start of timer */
          timer_start = timer_now();
          break;
        case Q_END_TIMER:
          /* End timer before ending mysqltest */
          timer_output();
          break;
        case Q_CHARACTER_SET:
          do_set_charset(command);
          break;
        case Q_DISABLE_PS_PROTOCOL:
          set_property(command, P_PS, false);
          /* Close any open statements */
          close_statements();
          break;
        case Q_ENABLE_PS_PROTOCOL:
          set_property(command, P_PS, ps_protocol);
          break;
        case Q_DISABLE_RECONNECT:
          set_reconnect(&cur_con->mysql, 0);
          break;
        case Q_ENABLE_RECONNECT:
          set_reconnect(&cur_con->mysql, 1);
          enable_async_client = false;
          /* Close any open statements - no reconnect, need new prepare */
          close_statements();
          break;
        case Q_ENABLE_ASYNC_CLIENT:
          set_property(command, P_ASYNC, true);
          break;
        case Q_DISABLE_ASYNC_CLIENT:
          set_property(command, P_ASYNC, false);
          break;
        case Q_DISABLE_TESTCASE:
          if (testcase_disabled == 0)
            do_disable_testcase(command);
          else
            die("Test case is already disabled.");
          break;
        case Q_ENABLE_TESTCASE:
          // Ensure we don't get testcase_disabled < 0 as this would
          // accidentally disable code we don't want to have disabled.
          if (testcase_disabled == 1)
            testcase_disabled = false;
          else
            die("Test case is already enabled.");
          break;
        case Q_DIE:
          /* Abort test with error code and error message */
          die("%s", command->first_argument);
          break;
        case Q_EXIT:
          /* Stop processing any more commands */
          abort_flag = true;
          break;
        case Q_SKIP: {
          DYNAMIC_STRING ds_skip_msg;
          init_dynamic_string(&ds_skip_msg, nullptr, command->query_len);

          // Evaluate the skip message
          do_eval(&ds_skip_msg, command->first_argument, command->end, false);

          char skip_msg[FN_REFLEN];
          strmake(skip_msg, ds_skip_msg.str, FN_REFLEN - 1);
          dynstr_free(&ds_skip_msg);

          if (!no_skip) {
            // --no-skip option is disabled, skip the test case
            abort_not_supported_test("%s", skip_msg);
          } else {
            const char *path = cur_file->file_name;
            const char *fn = get_filename_from_path(path);

            // Check if the file is in excluded list
            if (excluded_string && strstr(excluded_string, fn)) {
              // File is present in excluded list, skip the test case
              abort_not_supported_test("%s", skip_msg);
            } else {
              // File is not present in excluded list, ignore the skip
              // and continue running the test case
              command->last_argument = command->end;
              skip_ignored = true;  // Mark as noskip pass or fail.
            }
          }
        } break;
        case Q_OUTPUT: {
          static DYNAMIC_STRING ds_to_file;
          const struct command_arg output_file_args[] = {
              {"to_file", ARG_STRING, true, &ds_to_file, "Output filename"}};
          check_command_args(command, command->first_argument, output_file_args,
                             1, ' ');
          strmake(output_file, ds_to_file.str, FN_REFLEN);
          dynstr_free(&ds_to_file);
          break;
        }

        default:
          processed = 0;
          break;
      }
    }

    if (!processed) {
      current_line_inc = 0;
      switch (command->type) {
        case Q_WHILE: // 处理 while 代码块
          do_block(cmd_while, command); // 该函数内是一个循环
          break;
        case Q_IF: // 处理 if 代码块
          do_block(cmd_if, command);
          break;
        case Q_ASSERT:
          do_block(cmd_assert, command);
          break;
        case Q_END_BLOCK:
          do_done(command);
          break;
        default:
          current_line_inc = 1;
          break;
      }
    } else
      check_eol_junk(command->last_argument);

    if (command_executed != last_command_executed || command->used_replace) {
      /*
        As soon as any command has been executed,
        the replace structures should be cleared
      */
      free_all_replace();

      /* Also reset "sorted_result", "lowercase" and "skip_if_hypergraph"*/
      display_result_sorted = false;
      display_result_lower = false;
      skip_if_hypergraph = false;
    }
    last_command_executed = command_executed;

    parser.current_line += current_line_inc;
    if (opt_mark_progress) mark_progress(&progress_file, parser.current_line);

    // Write result from command to log file immediately.
    flush_ds_res();
  } // while-end


|-- // ================= 检查结果 =================

 /*
    The whole test has been executed _sucessfully_.
    Time to compare result or save it to record file.
    The entire output from test is in the log file
  */
  if (log_file.bytes_written()) {
    if (result_file_name) {
      /* A result file has been specified */

      if (record) {
        /* Recording */

        /* save a copy of the log to result file */
        if (my_copy(log_file.file_name(), result_file_name, MYF(0)) != 0)
          die("Failed to copy '%s' to '%s', errno: %d", log_file.file_name(),
              result_file_name, errno);

      } else {
        /* Check that the output from test is equal to result file */
        check_result();
      }
    }
  } else {
    /* Empty output is an error *unless* we also have an empty result file */
    if (!result_file_name || record ||
        compare_files(log_file.file_name(), result_file_name)) {
      die("The test didn't produce any output");
    } else {
      empty_result = true; /* Meaning empty was expected */
    }
  }

  if (!command_executed && result_file_name && !empty_result)
    die("No queries executed but non-empty result file found!");

  verbose_msg("Test has succeeded!");
  timer_output();
  /* Yes, if we got this far the test has suceeded! Sakila smiles */
  cleanup_and_exit(0);
  return 0; /* Keep compiler happy too */
}
```

# 参考

[MySQL: The MySQL Test Framework](https://dev.mysql.com/doc/dev/mysql-server/latest/PAGE_MYSQL_TEST_RUN.html "MySQL: The MySQL Test Framework")

[浅析 mysql-test 框架 - 腾讯云开发者社区-腾讯云 (tencent.com)](https://cloud.tencent.com/developer/article/1564376 "浅析mysql-test框架 - 腾讯云开发者社区-腾讯云 (tencent.com)")

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
