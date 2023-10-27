---
title: 万字长文 | 业内 MySQL 线程池主流方案详解 - MariaDB/Percona/AliSQL/TXSQL/MySQL企业版
date: 2023-05-04 22:07:40
categories:
  - MySQL
tags:
  - MySQL
  - 线程池
  - MariaDB
  - Percona
toc: true
---

**作者：卢文双 资深数据库内核研发**

> **本文首发于 2023-05-04 22:07:40**

本文主要从功能层面对比 percona-server、mariadb、阿里云 AliSQL、腾讯 TXSQL、MySQL 企业版线程池方案，都基于 MySQL 8.0。

至于源码层面，腾讯、阿里云、MySQL 企业版不开源，percona 借鉴了 mariadb 早期版本的实现，但考虑到线程池代码只有 2000 行左右，相对简单，本文就不做深入阐述。

> 版本：
> MariaDB 10.9，
> Percona-Server-8.0.32-24

# 背景

社区版的 MySQL 的连接处理方法默认是为每个连接创建一个工作线程的`one-thread-per-connection`（**Per_thread**）模式。这种模式存在如下弊端：

- **由于系统的资源是有限的，随着连接数的增加，资源的竞争也增加，连接的响应时间也随之增加**，如 response time 图所示。

![response time图](response-time.png "response time图")

- **在资源未耗尽时，数据库整体吞吐随着连接数增加。一旦连接数超过了某个耗尽系统资源的临界点，由于各线程互相竞争，CPU 时间片在大量线程间频繁调度，不同线程上下文频繁切换，徒增系统开销，数据库整体吞吐反而会下降**，如下图所示。

![Per_Thread 模式下数据库整体吞吐](per-thread-throughput.png "Per_Thread 模式下数据库整体吞吐")

**Q：如何避免 在连接数暴增时，因资源竞争而导致系统吞吐下降的问题呢？**

**MariaDB & Percona 中给出了简洁的答案：** ​**线程池**。

线程池的原理在[percona blog](https://www.percona.com/blog/simcity-outages-traffic-control-and-thread-pool-for-mysql/ "percona blog") 中有生动的介绍，其大致可类比为早高峰期间大量汽车想通过一座大桥，如果采用`one-thread-per-connection`的方式则放任汽车自由行驶，由于桥面宽度有限，最终将导致所有汽车寸步难行。线程池的解决方案是限制同时行驶的汽车数，让桥面时刻保持最大吞吐，尽快让所有汽车抵达对岸。

数据库内核月报文章 《[MySQL · 最佳实践 · MySQL 多队列线程池优化](http://mysql.taobao.org/monthly/2019/02/09/ "MySQL · 最佳实践 · MySQL多队列线程池优化")》中举了一个高铁买票的例子，也很形象，由于售票员（类比为 CPU 的核数）有限，当有 1000 个用户（类比为数据库连接）都想买票时，如果采用 `one-thread-per-connection` 的方式，则每个人都有一个专用窗口，需要售票员跑来跑去（CPU 上下文切换，售票窗口越多，跑起来越费力）来为你服务，可以看到这是不够合理的，特别是售票员比较少而购票者很多的场景。如果采用线程池的思想，则不再是每个人都有一个专用的售票窗口（每个客户端对应一个后端线程），而是通过限定售票窗口数，让购票者排队，来减少售票员跑来跑去的成本。

回归到数据库本身，MySQL 默认的线程使用模式是会话独占模式（`one-thread-per-connection`），每个会话都会创建一个独占的线程。**当有大量的会话存在时，会导致大量的资源竞争，同时，大量的系统线程调度和缓存失效也会导致性能急剧下降**。

线程池线程池功能旨在解决以上问题，在存在大量连接的场景下，通过线程池实现**线程复用**：

- 当连接多、并发低时，通过连接复用，避免创建大量空闲线程，减少系统资源开销。
- 当连接多、并发高时，通过**限制同时运行的线程数，将其控制在合理的范围内，可避免线程调度工作过多和大量缓存失效，减少线程池间上下文切换和热锁争用**，从而对 OLTP 场景产生积极影响。

当连接数上升时，在线程池的帮助下，将数据库整体吞吐维持在一个较高水准，如图所示。

![线程池模式下数据库整体吞吐](threadpool-throughput.png "线程池模式下数据库整体吞吐")

# 适用场景

线程池采用一定数量的工作线程来处理连接请求，线程池在查询相对较短且工作负载受 CPU 限制的情况下效率最高，通常比较适应于 OLTP 工作负载的场景。如果工作负载不受 CPU 限制，那么您仍然可以通过限制线程数量来为数据库内存缓冲区节省内存。

线程池的不足在于当请求偏向于慢查询时，工作线程阻塞在高时延操作上，难以快速响应新的请求，导致系统吞吐量反而相较于传统 one-thread-per-connection 模式更低。

**线程池适用的场景**：

- 对于**大量连接的 OLTP 短查询**的场景将有最大收益。
- 对于**大量连接的只读短查询**也有明显收益。
- 有效避免大量连接高并发下数据库性能衰减。

**不太适合用线程池的场景：**

- **具有突发工作负载的场景**。在这种场景下，许多用户往往长时间处于非活跃状态，但个别时候又处于特别活跃的状态，同时，对延迟的容忍度较低，因此，线程池节流效果不太理想。不过，即使在这种情况下，也可以通过调整线程的退役频率来提高性能（使用 `thread_pool_idle_timeout` 参数）。
- **高并发、长耗时语句的场景**。在这种场景下，并发较多，且都是执行时间较长的语句，会导致工作线程堆积，一旦达到上限，完全阻止后续语句的执行，比如最常见的数据仓库场景。当然这样的场景下，不管是否使用线程池，数据库的表现都是不够理想的，**需要应用侧控制大查询的并发度**。
- **有较严重的锁冲突，如果处于锁等待的工作线程数超过总线程数，也会堆积起来，阻止无锁待的处理请求**。比如某个会话执行` FLUSH TABLES WITH READ LOCK`语句获得全局锁后暂停，那么其他执行写操作的客户端连接就会阻塞，当阻塞的数量超过线程池的上限时，整个 server 都会阻塞。当然这样的场景下，不管是否使用线程池，数据库的表现都是不够理想的，**需要应用侧进行优化**。
- **极高并发的 Prepared Statement 请求**。使用 Prepared Statement（Java 应用不算）时，会**使用 MySQL Binary Protocol，会增加很多的网络来回操作**，比如参数的绑定、结果集的返回，在极高请求压力下会给 epoll 监听进程带来一定的压力，处于事务状态中时，可能会让普通请求得不到执行机会。

为了应对这种阻塞问题，一般会允许配置 `extra_port` 或 `admin_port` 来管理连接。

> 总结一句话，线程池更适合**短连接或短查询**的场景。

# 行业方案：Percona 线程池实现

由于市面上的线程池方案大多都借鉴了 percona、mariadb 的方案，因此，首先介绍下 percona 线程池的工作机制，再说明其他方案相较于 percona 做了什么改进。

## 0. 基本原理

线程池的基本原理为：预先创建一定数量的工作线程（worker 线程）。在线程池监听线程（listener 线程）从现有连接中监听到新请求时，从工作线程中分配一个线程来提供服务。工作线程在服务结束之后不销毁线程（处于 idle 状态一段时间后会退出），而是保留在线程池中继续等待下一个请求来临。

下面我们将从线程池架构、新连接的创建与分配、listener 线程、worker 线程、timer 线程等几个方面来介绍 percona 线程池的实现。

## **1. 线程池的架构**

线程池由**多个线程组（thread group）**和**timer 线程**组成，如下图所示。

线程组的数量是线程池并发的上限，通常而言**线程组的数量**需要配置成**数据库实例的 CPU 核心数量**（可通过参数`thread_pool_size`设置），从而充分利用 CPU。线程组之间通过`线程ID % 线程组数`的方式分配连接，线程组内通过竞争方式处理连接。

线程池中还有一个服务于所有线程组的**timer 线程**，负责周期性（检查时间间隔为`threadpool_stall_limit`毫秒）检查线程组是否处于阻塞状态。当检测到阻塞的线程组时，timer 线程会通过唤醒或创建新的工作线程（`wake_or_create_thread` 函数）来让线程组恢复工作。

创建新的工作线程不是每次都能创建成功，**要根据当前的线程组中的线程数是否大于线程组中的连接数，活跃线程数是否为 0，以及上一次创建线程的时间间隔是否超过阈值（这个阈值与线程组中的线程数有关，线程组中的线程数越多，时间间隔越大**）。

![Percona线程池组成部分](percona-threadpool-components.png "Percona线程池组成部分")

线程组内部由**多个 worker 线程、0 或 1 个动态 listener 线程、高低优先级事件队列（由网络事件 event 构成）、mutex、epollfd、统计信息等组成**。如下图所示：

![Percona线程池组架构](percona-threadpool-group-architecture.png "Percona线程池组架构")

**worker 线程**：主要作用是从队列中读取并处理事件。

- 如果该线程所在组中没有 listener 线程，则该 worker 线程将成为 listener 线程，通过 epoll 的方式监听数据，并将监听到的 event 放到线程组中的队列。
- worker 线程数目动态变化，并发较大时会创建更多的 worker 线程，当从队列中取不到 event 时，work 线程将休眠，超过一定时间后结束线程。
- 一个 worker 线程只属于一个线程组。

**listener 线程**：当高低队列为空，listen 线程会自己处理，无论这次获取到多少事务。否则 listen 线程会把请求加入到队列中，**如果此时`active_thread_count=0`，唤醒一个工作线程**。

**高低优先级队列**：为了提高性能，将队列分为优先队列和普通队列。这里采用引入两个新变量`thread_pool_high_prio_tickets`和`thread_pool_high_prio_mode`。由它们控制高优先级队列策略。对**每个新连接**分配可以进入高优先级队列的 ticket。

## **2. 新连接的创建与分配**

新连接接入时，线程池按照新连接的线程 id 取模线程组个数来确定新连接归属的线程组（`thd->thread_id() % group_count`）。这样的分配逻辑非常简洁，但**由于没有充分考虑连接的负载情况，繁忙的连接可能会恰巧被分配到相同的线程组，从而导致负载不均衡的现象，这是 percona 线程池值得被优化的点**。

![Percona线程池整体架构图](percona-threadpool-architecture.png "Percona线程池整体架构图")

选定新连接归属的线程组后，**新连接申请**被作为**事件**放入**低优先级队列**中，等待线程组中 worker 线程将**高优先级事件队列**处理完后，就会处理低优先级队列中的请求。

## **3. listener 线程**

listener 线程是负责监听连接请求的线程，每个线程组都有一个**listener 线程**。

percona 线程池的 listener 采用**epoll**实现。当 epoll 监听到请求事件时，listener 会根据**请求事件的类型**来决定将其放入哪个优先级事件队列。**将事件放入高优先级队列的条件如下（见函数**`connection_is_high_prio`**），只需要满足其一即可**：

- 当前线程池的工作模式为**高优先级模式**，在此模式下只启用高优先级队列。（`mode == TP_HIGH_PRIO_MODE_STATEMENTS`）
- 当前线程池的工作模式为**高优先级事务模式**，在此模式下**每个连接的 event**最多被放入高优先级队列`threadpool_high_prio_tickets`次。超过`threadpool_high_prio_tickets`次后，该连接的请求事件只能被放入低优先级（`mode == TP_HIGH_PRIO_MODE_TRANSACTIONS`），同时，也会重置票数。
- 连接持有**表锁**
- 连接持有**mdl 锁**
- 连接持有**全局读锁**
- 连接持有**backup 锁**

```c++
inline bool connection_is_high_prio(const connection_t &c) noexcept {
  const ulong mode = c.thd->variables.threadpool_high_prio_mode;

  return (mode == TP_HIGH_PRIO_MODE_STATEMENTS) ||
         (mode == TP_HIGH_PRIO_MODE_TRANSACTIONS && c.tickets > 0 &&
          (thd_is_transaction_active(c.thd) ||
           c.thd->variables.option_bits & OPTION_TABLE_LOCK ||
           c.thd->locked_tables_mode != LTM_NONE ||
           c.thd->mdl_context.has_locks() ||
           c.thd->global_read_lock.is_acquired() ||
           c.thd->backup_tables_lock.is_acquired() ||
           c.thd->mdl_context.has_locks(MDL_key::USER_LEVEL_LOCK) ||
           c.thd->mdl_context.has_locks(MDL_key::LOCKING_SERVICE)));
}
```

被放入高优先级队列的事件可以优先被 worker 线程处理。

**只有当高优先级队列为空，并且当前线程组不繁忙的时候才处理低优先级队列中的事件**。线程组繁忙（`too_many_busy_threads`）的判断条件是**当前组内活跃工作线程数+组内处于等待状态的线程数**大于**线程组工作线程额定值**（`thread_pool_oversubscribe+1`）。这样的设计可能带来的问题是**在高优先级队列不为空或者线程组繁忙时低优先级队列中的事件迟迟得不到响应，这同样也是 percona 线程池值得被优化的一个点**。

listener 线程将事件放入高低优先级队列后，如果**线程组的活跃 worker 数量为 0**，则唤醒或创建新的 worker 线程来处理事件。

percona 的线程池中**listener 线程和 worker 线程是可以互相切换的**，详细的切换逻辑会在「worker 线程」一节介绍。

- epoll 监听到请求事件时，如果高低优先级事件队列都为空，意味着此时线程组非常空闲，大概率不存在活跃的 worker 线程。
- listener 在此情况下会将除第一个事件外的所有事件按前述规则放入高低优先级事件队列，**然后退出监听任务，亲自处理第一个事件**。
- 这样设计的好处在于当线程组非常空闲时，可以避免 listener 线程将事件放入队列，唤醒或创建 worker 线程来处理事件的开销，提高工作效率。

![Percona listener 线程流程图](percona-threadpool-listener-flow.png "Percona listener 线程流程图")

> 上图来源于腾讯数据库技术公众号

## **4. worker 线程**

worker 线程是线程池中真正干活的线程，正常情况下，每个线程组都会有一个活跃的 worker 线程。

worker 在理想状态下，可以高效运转并且快速处理完高低优先级队列中的事件。但是在实际场景中，worker 经常会遭遇 IO、锁等等待情况而难以高效完成任务，此时任凭 worker 线程等待将使得在队列中的事件迟迟得不到处理，甚至可能出现长时间没有 listener 线程监听新请求的情况。为此，每当 worker 遭遇 IO、锁等等待情况，如果此时线程组中没有 listener 线程或者高低优先级事件队列非空，并且没有过多活跃 worker，则会尝试唤醒或者创建一个 worker。

为了避免短时间内创建大量 worker，带来系统吞吐波动，线程池创建 worker 线程时有一个控制单位时间创建 worker 线程上限的逻辑，线程组内连接数越多则创建下一个线程需要等待的时间越长。

当**线程组活跃 worker 线程数量**大于等于`too_many_active_threads+1`时，认为线程组的活跃 worker 数量过多。此时需要对 worker 数量进行适当收敛，首先判断当前线程组是否有 listener 线程：

- 如果没有 listener 线程，则将当前 worker 线程转化为 listener 线程。
- 如果当前有 listener 线程，则在进入休眠前尝试通过`epoll_wait`获取一个尚未进入队列的事件，成功获取到后立刻处理该事件，否则进入休眠等待被唤醒，等待`threadpool_idle_timeout`时间后仍未被唤醒则销毁该 worker 线程。

worker 线程与 listener 线程的切换如下图所示：

![Percona worker线程与listener线程的切换](percona-threadpool-worker-switch-to-listener-flow.png "Percona worker线程与listener线程的切换")

> 上图来自于腾讯数据库技术公众号

## **5. timer 线程**

timer 线程每隔`threadpool_stall_limit`时间进行一次所有线程组的扫描（`check_stall`）。

当线程组高低优先级队列中存在事件，并且自上次检查至今没有新的事件被 worker 消费，则认为线程组处于停滞状态。

- 停滞的主要原因可能是长时间执行的非阻塞请求， 也可能发生于线程正在等待但 `wait_begin/wait_end` （尝试唤醒或创建新的 worker 线程）被上层函数忘记调用的场景。
- timer 线程会通过唤醒或创建新的 worker 线程来让停滞的线程组恢复工作。

timer 线程为了尽量减少对正常工作的线程组的影响，在`check_stall`时采用的是`try_lock`的方式，如果加不上锁则认为线程组运转良好，不再去打扰。

timer 线程除上述工作外，还负责终止空闲时间超过`wait_timeout`秒的客户端。

**下面是 Percona 的实现：**

`check_stall` 函数：

```c++
check_stall
|-- if (!thread_group->listener && !thread_group->io_event_count) {
|--   wake_or_create_thread(thread_group); // 重点函数
|-- }
|-- thread_group->io_event_count = 0; // 表示自上次 check 之后，当前线程组新获取的 event 数
|-- if (!thread_group->queue_event_count && !queues_are_empty(*thread_group)) { // 重点函数
|--   thread_group->stalled = true;
|--   wake_or_create_thread(thread_group); // 重点函数
|-- }
|-- thread_group->queue_event_count = 0;

static bool queues_are_empty(const thread_group_t &tg) noexcept {
return (tg.high_prio_queue.is_empty() && // 重点函数
(tg.queue.is_empty() || too_many_busy_threads(tg))); // 重点函数
}
```

- io_event_count：当 Listen 线程监听到事件时++
- queue_event_count ：当 work 线程从队列中获取事件时++

# 行业主流方案对比

## MySQL 企业版 vs MariaDB

MySQL 企业版是在 5.5 版本引入的线程池，以插件的方式实现的。

**相同点：**

- 都具备线程池功能，都支持 `thread_pool_size` 参数。
- 都支持专有 listener 线程（`thread_pool_dedicated_listeners` 参数）。
- 都支持高低优先级队列，且在避免低优先级队列事件饿死方面，二者采用了相同方案，即低优先级队列事件等待一段时间（`thread_pool_prio_kickup_timer` 参数）即可移入高优先级队列。
- 都使用相同的机制来探测处于停滞（stall）状态的线程，都提供了 `thread_pool_stall_limit` 参数（MariaDB 单位是 ms，MySQL 企业版单位是 10ms）。

**不同点：** Windows 平台实现方式不同。

- MariaDB 使用 Windows 自带的线程池，而 MySQL 企业版的实现用到了 `WSAPoll()` 函数（为了便于移植 Unix 程序而提供），因此，MySQL 企业版的实现将不能使用命名管道和共享内存。
- MariaDB 为每个操作系统都使用最高效的 IO 多路复用机制。
  - **Windows**：原生线程池
  - **Linux**： `epoll`
  - **Solaris** (`event ports`)
  - **FreeBSD** and **OSX** (`kevent`)
- 而 MySQL 企业版只在 Linux 上才使用优化过的 IO 多路复用机制 `epoll`，其他平台则用 `poll` 。

## MariaDB vs Percona

[Percona 的实现](https://www.percona.com/doc/percona-server/5.7/performance/threadpool.html "Percona 的实现")移植自 MariaDB，并在此基础上添加了一些功能。特别是 Percona 在 5.5-5.7 版本添加了优先级调度。而 [MariaDB 10.2](https://mariadb.com/kb/en/what-is-mariadb-102/ "MariaDB 10.2") 也支持了优先级调度，和 Percona 的工作方式类似，只是细节有所不同。

- MariaDB 10.2 版本的参数 `thread_pool_priority=auto,high,low` 对应于 Percona 的 `thread_pool_high_prio_mode=transactions,statements,none`
- MariaDB 10.2 版本中只有**处于事务中**的连接才是高优先级，而 Percona 中符合高优先级的情况包括：**1）处于事务中；2）持有表锁；3）持有 MDL 锁；4）持有全局读锁；5）持有 backup 锁**。
- 关于**避免低优先级队列语句饿死**的问题：
  - Percona 有一个 `thread_pool_high_prio_tickets` 参数，用于**指定每个连接在高优先级队列中的 tickets 数量**，而 MariaDB 没有相应参数。
  - MariaDB 有一个 `thread_pool_prio_kickup_timer` 参数，可**让低优先队列中的语句在等待指定时间后移入高优先级队列**，而 Percona 没有相应参数。
- MariaDB 有参数`thread_pool_dedicated_listener` 、`thread_pool_exact_stats`，而 Percona 没有。
  - `thread_pool_dedicated_listener` ：可用于**指定专有 listener 线程**，其只负责`epoll_wait`等待网络事件，不会变为 worker 线程。默认为 OFF，表示不固定 listener。
  - `thread_pool_exact_stats` ：是否使用高精度时间戳。
- MariaDB （比如 10.9 版本）在 `information_schema` 中新增了四张表（`THREAD_POOL_GROUPS`、`THREAD_POOL_QUEUES`、`THREAD_POOL_STATS`、`THREAD_POOL_WAITS`），便于监控线程池状态。

## AliSQL vs Percona

AliSQL 线程池也一定程度借鉴了 Percona 的机制，但也有自己的特色：

- **AliSQL 线程池给予管理类的 SQL 语句更高的优先级，保证这些语句优先执行。这样在系统负载很高时，新建连接、管理、监控等操作也能够稳定执行**。
- **AliSQL 线程池给予复杂查询 SQL 语句相对较低的优先级，并且有最大并发数的限制**。这样可以**避免过多的复杂 SQL 语句将系统资源耗尽，导致整个数据库服务不可用**。
- AliSQL 支持**动态开关线程池**。
- 从官网手册及内核月报公开资料，无法获知 AliSQL 是否支持线程组专职 listener 。

AliSQL 虽然也使用了队列，但没有直接采用 percona 或 mariadb 的高低优先级调度策略，结合[官方手册](https://help.aliyun.com/document_detail/130306.html "官方手册")和数据库内核月报 2019 年 2 月份的文章 《[MySQL 多队列线程优化](http://mysql.taobao.org/monthly/2019/02/09/?spm=wolai.workspace.0.0.3857b476u3d92G "MySQL 多队列线程优化")》，推测是使用了两层队列：

- **第一层队列为网络请求队列**，可以区分为**请求队列**（不在事务状态中的请求）和**高优先级队列**（已经在事务状态中的请求，收到请求后会马上执行，不进入第二队列）。
- **第二层队列为工作任务队列**，可以区分为**查询队列、更新队列和事务队列**。

第一层请求队列的请求经过快速的处理和分析进入第二层队列。如果是管理操作，则直接执行（假定所有管理操作都是小操作）。

对第二层队列，可以分别设置一个允许的并发度（可以接近 CPU 的个数），以实现总线程数的控制。只要线程数大于四类操作的设计并发度之和，则不同类型的操作不会互相干涉（在这里是假定同一操作超过各自并发度而进行排队是合理的）。任何一个队列超过一定的时间，如果没有完成任何语句，处于阻塞模式，则可以考虑放行，在 MySQL 线程池中有`thread_pool_stall_limit`变量来控制这个间隔，以防止任何一个队列挂起。

可以从配置参数的变化来了解优化后的线程池工作机制：

- `thread_pool_enabled` ：线程池开关。
- `thread_pool_idle_timeout` ：线程最大空闲时间，超过则退出。
- `thread_pool_max_threads` ：线程池最大工作线程数。
- `thread_pool_oversubscribe`：每个 Thread Group 的目标线程数。
- `thread_pool_normal_weights`（相较 percona 新加）：**查询、更新操作的目标线程比例（假定这两类操作的比重相同）**，即`并发度 = thread_pool_oversubscribe * 目标比例/100`。
- `thread_pool_trans_weights`（相较 percona 新加）：**事务操作的目标线程比例**，即`并发度 = thread_pool_oversubscribe * 目标比例/100`。
- `thread_pool_stall_limit`：阻塞模式检查频率（同时检查 5 个队列的状态）
- `thread_pool_size`：线程组的个数（在优化锁并发后，线程组的个数不是很关键，可以用来根据物理机器的资源配置情况来软性调节处理能力）

另外，AliSQL 新增了 6 个状态变量：`thread_pool_active_threads`，`thread_pool_big_threads`，`thread_pool_dml_threads`，`thread_pool_qry_threads`，`thread_pool_trx_threads`，`thread_pool_wait_threads` 。还有 2 个状态变量与 percona 线程池含义相同，只是名字不同。

## TXSQL vs Percona

腾讯云 TXSQL 线程池核心方案与 Percona 完全一样，额外支持的功能如下：

### **1. 支持线程池动态切换**

线程池采用一定数量的工作线程来处理用户连接请求，通常比较适应于 OLTP 工作负载的场景。但线程池并不是万能的，线程池的不足在于当用户请求偏向于慢查询时，工作线程阻塞在高时延操作上，难以快速响应新的用户请求，导致系统吞吐量反而相较于 one-thread-per-connection（简称为 Per_thread）模式更低。

Per_thread 模式与 Thread_pool 模式各有优劣，系统需要根据用户的业务类型灵活切换两种模式。在业务高峰时段切换模式，重启服务器，会严重影响用户业务。为了解决此问题，TXSQL 提出了**线程池动态切换**的优化，即在不重启数据库服务的情况下，动态开启或关闭线程池。

通过参数 `thread_handling_switch_mode` 控制，可选值及含义如下：

| 可选值   | 含义                                                |
| -------- | --------------------------------------------------- |
| disabled | 禁止模式动态迁移                                    |
| stable   | 只有新连接迁移                                      |
| fast     | 新连接 + 新请求都迁移，默认模式                     |
| sharp    | kill 当前活跃连接，迫使用户重连，达到快速切换的效果 |

在了解了 TXSQL 动态线程池的使用方法后，我们再来了解一下其具体的实现。

mysql 的`thread_handling`参数代表了连接管理方法。

**在原生 mysql 中，thread_handling 是只读参数，不允许在线修改**。

`thread_handling` 参数对应的底层实现对象是`Connection_handler_manager`，后者是 mysql 提供连接管理服务的单例类，可对外提供多种连接管理服务：

- `Per_thread` : 参数值是 one-thread-per-connection
- `No_threads` : 参数值是 no-threads
- `Thread_pool` : 新加
- `Plugin_connection_handler` : 参数值是 loaded-dynamically

在 mysql 启动时`Connection_handler_manager`只需要按照`thread_handling`初始化一种连接管理方法即可。

为了支持动态线程池，允许用户连接从 Per_thread 和 Thread_pool 模式中来回切换，我们需要允许多种连接管理方法同时存在。因此，**在 mysql 初始化阶段，TXSQL 初始化了所有连接管理方法**。

在支持`thread_handling`在**Per_thread 和 Thread_pool 模式**中来回切换后，我们需要考虑的问题主要有以下几个：

#### **1.1. 活跃用户连接的 thread_handling 切换**

Per_thread 模式下，每个用户连接对应一个`handle_connection`线程，`handle_connection`线程既负责用户网络请求的监听，又负责请求的处理。

Thread_pool 模式下，每个 thread_group 都用`epoll`来管理其中所有用户连接的网络事件，监听到的事件放入事件队列中，交予 worker 处理。

**不论是哪种模式，在处理请求的过程中（do_command）切换都不是一个好选择，而在完成一次 command 之后，尚未接到下一次请求之前是一个较合适的切换点。**

- 为实现用户连接从 Per_thread 到 Thread_pool 的切换，需要在请求处理完（`do_command`）之后判断`thread_handling`是否发生了变化。
  如需切换则立刻按照 2.2 中介绍的逻辑，通过`thread_id % group_size`选定目标 thread_group，**将当前用户连接迁移至 Thread_pool 的目标 thread_group 中**，后续该用户连接的所有网络事件统一交予 thread_group 的 epoll 监听。在完成连接迁移之后，handle_connection 线程即可完成退出或者缓存至下一次 Per_thread 模式处理新连接时复用（此为**原生 mysql 支持的逻辑**，目的是避免 Per_thread 模式下频繁地创建和销毁 handle_connection 线程）。
  - handle_connection 函数被 `Per_thread_connection_handler::add_connection` 函数调用。
- 为实现用户连接从 Thread_pool 到 Per_thread 的切换，需要在请求处理完（`threadpool_process_request`）后，**将用户线程网络句柄重新挂载到 epoll**（`start_io`）之前判断 thread_handling 是否发生了变化。**如需切换则先将网络句柄从 epoll 中移除以及将连接的信息从对应 thread_group 中清除**。由于 Per_thread 模式下每个连接对应一个 handle_connection 线程，**还需为当前用户连接创建一个 handle_connection 线程**，后续当前用户连接的网络监听和请求处理都交予该 handle_connection 线程处理。

#### **1.2. 新连接的处理**

由于 thread_handling 可能随时动态变化，为了使得新连接能被新 thread_handling 处理，需要在新连接处理接口`Connection_handler_manager::process_new_connection`中，**读取最新的 thread_handling，利用其相应的连接管理方法添加新连接**。

- 对于 Per_thread 模式，需要为新连接创建`handle_connection`线程；
- 对于 Thread_pool 模式，则需要为新连接选定 thread_group 和将其网络句柄绑定到 thread_group 的`epoll`中。

#### **1.3. thread_handling 切换的快速生效**

从前文的讨论中可以看到，**处于连接状态的用户线程需要等到一个请求处理结束才会等到合适的切换点**。

如果该用户连接迟迟不发送网络请求，则连接会阻塞在 do_command 下的`get_command`的网络等待中，无法及时切换到 Thread_pool。如何快速完成此类线程的切换呢？

> 一种比较激进的方法就是**迫使此类连接重连**，在重连后作为新连接自然地切换到 Thread_pool 中，其下一个网络请求也将被 Thread_pool 应答。

**线程池动态切换对性能的影响**：

- `pool-of-threads` 切换为 `one-thread-per-connection` 过程本身**不会带来 query 堆积，以及性能影响**。
- `one-thread-per-connection` 切换为 `pool-of-threads` 过程，**由于之前线程池处于休眠状态，在 QPS 极高并且有持续高压的情况下，可能存在一定的请求累积**。解决方案如下：
  - 方案 1：适当增大 `thread_pool_oversubscribe`，并适当调小 `thread_pool_stall_limit`，快速激活线程池。待消化完堆积 SQL 再视情况还原上述修改。
  - 方案 2：出现 SQL 累积时，短暂暂停或降低业务流量几秒钟，等待 `pool-of-threads` 完成激活，再恢复持续高压业务流量。

### 2. 线程池负载均衡优化

如前文所述，新连接**按照线程 id 取模线程组个数**来确定新连接归属的线程组（`thd->thread_id() % group_count`）。这样的分配方式未能将各线程组的实际负载考虑在内，因此**可能将繁忙的连接分配到相同的线程组，使得线程池出现负载不均衡的现象**。为了避免负载不均衡的发生，TXSQL 提出了线程池负载均衡优化。

#### **2.1. 负载的度量**

在提出负载均衡的算法之前，我们首先需要找到一种度量线程组负载状态的方法，通常我们称之为"信息策略“。下面我们分别讨论几种可能的信息策略。

**1） queue_length**

`queue_length`**代表线程组中低优先级队列和高优先级队列的长度**。此信息策略的最大优势在于简单，直接用**在工作队列中尚未处理的 event 的数量**描述当前线程组的工作负载情况。此信息策略的不足是 无法将每个网络事件 event 的处理效率纳入考量。由于每个 event 的处理效率并不相同，简单地以工作队列长度作为度量标准会带来一些误判。

**2） average_wait_usecs_in_queue**

`average_wait_usecs_in_queue`**表示最近 n 个 event 在队列中的平均等待时间**。此信息策略的优势在于能够直观地反映线程组处理 event 的响应速度。某线程组`average_wait_usecs_in_queue`明显高于其他线程组说明其工作队列中的 event 无法及时被处理，需要其他线程组对其提供帮助。

**3） group_efficiency**

`group_efficiency`表示一定的时间周期内，**线程组处理完的 event 总数占（工作队列存量 event 数+新增 event 数）的比例**。此信息策略的优势在于能够直观反映出线程组一定时间周期内的工作效率，不足在于对于运转良好的线程组也可能存在误判：当时间周期选择不合适时，运转良好的线程组可能存在时而 group_efficiency 小于 1，时而大于 1 的情况。 &#x20;
上述三种信息策略只是举例说明，还有更多信息策略可以被采用，就不再一一罗列。

#### 2 **.2. 负载均衡的实现介绍**

在明确了度量线程组负载的方法之后，我们接下来讨论如何均衡负载。我们需要考虑的问题主要如下：

**1） 负载均衡算法的触发条件**

负载均衡操作会**将用户连接从一个线程组迁移至另一个线程组**，在非必要情况下触发用户连接的迁移反而会导致用户连接的性能抖动。**为尽可能避免负载均衡算法错误触发，我们需要为触发负载均衡算法设定一个负载阈值 M，以及负载比例 N。只有线程组的负载阈值大于 M，并且其与参与均衡负载的线程组的负载比例大于 N 时，才需要启动负载均衡算法平衡负载**。

**2） 负载均衡的参数对象**

Q：当线程组触发了负载均衡算法后，该由哪些线程组参与平衡高负载线程组的负载呢？

很容易想到的一个方案是**我们维护全局的线程组负载动态序列，让负载最轻的线程组负责分担负载**。但是遗憾的是为了维护全局线程组负载动态序列，线程组每处理完一次任务都可能需要更新自身的状态，并在全局锁的保护下更新其在全局负载序列中的位置，如此一来对性能的影响势必较大，因此**全局线程组负载动态序列的方案并不理想**。

为了避免均衡负载对线程池整体性能的影响，需改全局负载比较为局部负载比较。一种可能的方法为**当当前线程组的负载高于阈值 M 时，只比较其与左右相邻的 X 个（通常 1-2 个）线程组的负载差异，当当前线程组的负载与相邻线程组的比例也高于 N 倍时，从当前线程组向低负载线程组迁移用户连接**。需要注意的是当当前线程组的负载与相邻线程组的比例不足 N 倍时，说明要么当前线程组还不够繁忙、要么其相邻线程组也较为忙碌，此时为了避免线程池整体表现恶化，不适合强行均衡负载。

**3） 均衡负载的方法**

讨论完负载均衡的触发条件及参与对象之后，接下来我们需要讨论高负载线程组向低负载线程组**迁移负载的方法**。总体而言，包括两种方法：**新连接的优化分配、旧连接的合理转移**。

在掌握了线程组的量化负载之后，**较容易实现的均衡负载方法是在新连接分配线程组时特意避开高负载线程组**，这样一来已经处于高负载状态的线程组便不会因新连接的加入进一步恶化。但仅仅如此还不够，如果高负载线程组的响应已经很迟钝，我们还需要主动将其中的旧连接迁移至合适的低负载线程组，具体迁移时机在 3.1 中已有述及，为在请求处理完（`threadpool_process_request`）后，将用户线程网络句柄重新挂载到`epoll`（start_io）之前，此处便不再展开讨论。

### 3. 线程池断连优化

#### 3.1. percona 线程池问题

如前文所述，线程池采用 epoll 来处理网络事件。当 epoll 监听到网络事件时，listener 会将网络事件放入事件队列或自己处理，此时相应用户连接不会被 epoll 监听。**percona 线程池需要等到请求处理结束之后才会使用 epoll 重新监听用户连接的新网络事件**。percona 线程池这样的设计通常不会带来问题，因为用户连接在请求未被处理时，也不会有发送新请求的需求。但特殊情况下，**如果用户连接在重新被 epoll 监听前自行退出了，此时用户连接发出的断连信号无法被 epoll 捕捉，因此在 mysql 服务器端无法及时退出该用户连接**。这样带来的影响主要有两点：

1.  **用户连接客户端虽已退出，但 mysql 服务器端却仍在运行该连接**，继续消耗 CPU、内存资源，甚至可能继续持有锁，只有等到连接超时才能退出；
2.  由于**用户连接在 mysql 服务器端未及时退出，连接数也并未清理**，如果用户业务连接数较多，可能导致用户新连接数触达最大连接数上限，用户无法连接数据库，严重影响业务。

为解决上述问题，TXSQL 提出了线程池断连优化。

#### **3.2. 断连优化的实现介绍**

断连优化的重点在于**及时监听用户连接的断连事件并及时处理**。为此需要作出的优化如下：

1.  **在 epoll 接到用户连接的正常网络事件后，立刻监听该用户连接的断连事件**；
2.  **所有用户连接退出从同步改为异步**，所有退出的连接先放入`quit_connection_queue`，后统一处理；
3.  **一旦 epoll 接到断连事件后立刻将用户连接 thd->killed 设置为`THD::KILL_CONNECTION 状态，并将连接放入 quit_connection_queue 中异步退出**；
4.  **listener 每隔固定时间（例如 100ms）处理一次 quit_connection_queue，让其中的用户连接退出**。

### **4. 新增用于监控的状态变量**

- 新增指令 `show threadpool status` ，可展示 25 个线程池状态变量。
- 在 `show full processlist` 中新增如下状态变量：
  - `Moved_to_per_thread` 表示该连接迁移到 Per_thread 的次数。
  - `Moved_to_thread_pool` 表示该连接迁移到 Thread_pool 的次数。

# 性能结果

由于腾讯 TXSQL、Percona 官方手册都没有性能数据，因此仅列出其他几种方案的性能结果。

## MariaDB 5.5 - 无优先级队列

> 本小节内容来源于[官网手册](https://mariadb.com/kb/en/threadpool-benchmarks/ "官网手册")。

MariaDB 官网是基于 5.5 版本线程池测试的，也就是不支持高低优先级队列的版本。

采用 Sysbench 0.4，以**pitbull (Linux, 24 cores)** 的情况来说明在不同场景下的 QPS 情况。

### OLTP_RO

| 并发数     | 16   | 32   | 64   | 128  | 256  | 512  | 1024 | 2048 | 4096 |
| ---------- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| per_thread | 6754 | 7905 | 8152 | 7948 | 7924 | 7587 | 5313 | 3827 | 208  |
| threadpool | 6566 | 7725 | 8108 | 8079 | 7976 | 7793 | 7429 | 6523 | 4456 |

![MariaDB OLTP_RO](mariadb-threadpool-oltp-ro.png "MariaDB OLTP_RO")

### OLTP_RW

| 并发数     | 16   | 32   | 64   | 128  | 256  | 512  | 1024 | 2048 | 4096 |
| ---------- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| per_thread | 4561 | 5316 | 5332 | 3512 | 2874 | 2476 | 1380 | 265  | 53   |
| threadpool | 4504 | 5382 | 5694 | 5567 | 5302 | 4514 | 2548 | 1186 | 484  |

![MariaDB OLTP_RW](mariadb-threadpool-oltp-rw.png "MariaDB OLTP_RW")

### POINT_SELECT

| 并发数     | 16     | 32     | 64     | 128    | 256    | 512    | 1024   | 2048   | 4096   |
| ---------- | ------ | ------ | ------ | ------ | ------ | ------ | ------ | ------ | ------ |
| per_thread | 148673 | 161547 | 169747 | 172083 | 69036  | 42041  | 21775  | 4368   | 282    |
| threadpool | 143222 | 167069 | 167270 | 165977 | 164983 | 158410 | 148690 | 147107 | 143934 |

![MariaDB POINT_SELECT](mariadb-threadpool-point-select.png "MariaDB POINT_SELECT")

### UPDATE_NOKEY

| 并发数     | 16    | 32    | 64    | 128   | 256   | 512   | 1024  | 2048  | 4096  |
| ---------- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- |
| per_thread | 65213 | 71680 | 19418 | 13008 | 11155 | 8742  | 5645  | 635   | 332   |
| threadpool | 64902 | 70236 | 70037 | 68926 | 69930 | 69929 | 67099 | 62376 | 17766 |

![MariaDB UPDATE_NOKEY](mariadb-threadpool-update-nokey.png "MariaDB UPDATE_NOKEY")

## AliSQL

如下是开启线程池和不开启线程池的性能对比。从测试结果可以看出线程池在高并发的情况下有着明显的性能优势。

### update_non_index

![AliSQL update_non_index](alisql-threadpool-update-non-index.png "AliSQL update_non_index")

### write_only

![AliSQL write_only](alisql-threadpool-write-only.png "AliSQL write_only")

### read_write

![AliSQL read_write](alisql-threadpool-read-write.png "AliSQL read_write")

### point_select

![AliSQL point_select](alisql-threadpool-point-select.png "AliSQL point_select")

# 总结

## 功能区别

|                              | **MySQL 企业版**                                             | **MariaDB**                                                  | **Percona**                                          | 腾讯 TXSQL                                           | 阿里云 AliSQL              |
| ---------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ | ---------------------------------------------------- | ---------------------------------------------------- | -------------------------- |
| **功能实现方式**             | 插件                                                         | 非插件                                                       | 非插件                                               | 非插件                                               | **推测是非插件**           |
| **版本**                     | 5.5 版本引入                                                 | 5.5 版本引入，10.2 版本完善                                  | 5.5-5.7/8.0                                          | 5.7/8.0                                              | 5.6/5.7/8.0                |
| **是否开源**                 | 否                                                           | 是                                                           | 是                                                   | 否                                                   | 否                         |
| **动态开关线程池**           | 插件式，不支持                                               | 不支持                                                       | 不支持                                               | 支持                                                 | 支持                       |
| **优先级处理策略**           | 设定高低优先级，且低优先级事件等待一段时间可升为高优先级队列 | 设定高低优先级，且低优先级事件等待一段时间可升为高优先级队列 | 设定高低优先级，且限制每个连接在高优先级队列中的票数 | 设定高低优先级，且限制每个连接在高优先级队列中的票数 | 控制事务、非事务语句的比例 |
| **各线程组之间负载均衡优化** | 不支持                                                       | 不支持                                                       | 不支持                                               | 支持                                                 | -                          |
| **线程池断连优化**           | -                                                            | 不支持                                                       | 不支持                                               | 支持                                                 | -                          |
| **监控**                     | -                                                            | 2 个状态变量                                                 | 2 个状态变量                                         | 27 个状态变量                                        | 8 个状态变量               |
| **借鉴方案**                 | -                                                            | -                                                            | MariaDB                                              | Percona                                              | MariaDB 5.5                |
| **跨平台**                   | Windows/Unix                                                 | Windows/Unix/MacOS                                           | Windows/Unix                                         | -                                                    | -                          |

Q：**如果线程池阻塞了，怎么处理？**

> MySQL 8.0.14 以前的版本使用 `extra_port` 功能（percona & mariadb），8.0.14 及之后版本官方支持了 `admin_port` 功能。

## 参数区别

由于业内线程池方案基本都会参考 MariaDB 或 Percona，因此，以 Percona 和 MariaDB 的参数为准，基于 MySQL 8.0，总结其他方案是否有相同或类似参数。

> 注意：MySQL 企业版核心方案与 MariaDB 类似，且关于差异点，官方描述较少，因此，不做对比。

|                                                                                                                                              | MariaDB                                                                | Percona | 腾讯 TXSQL                                                | 阿里云 AliSQL                                    |
| -------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ------- | --------------------------------------------------------- | ------------------------------------------------ |
| `thread_handling`&#xA;线程池开关                                                                                                             | 有                                                                     | 有      | 有类似参数 `thread_handling_switch_mode` （支持动态开关） | 有类似参数 `thread_pool_enabled`（支持动态开关） |
| `thread_pool_idle_timeout`&#xA;线程最大空闲时间，超过则退出。                                                                                | 有                                                                     | 有      | 有                                                        | 有                                               |
| `thread_pool_high_prio_mode` 高优先级队列调度策略，支持 `transactions`,`statements`,`none` 三种策略                                          | 有类似参数 `thread_pool_priority`，支持 `high`, `low`, `auto` 三种策略 | 有      | 有                                                        | 无                                               |
| `thread_pool_high_prio_tickets` 控制每个连接在高优先级中的票数，仅在调度模式是**事务模式**时生效                                             | 无                                                                     | 有      | 有                                                        | 无                                               |
| `thread_pool_max_threads` 线程池最大工作线程数                                                                                               | 有                                                                     | 有      | 有                                                        | 有                                               |
| `thread_pool_oversubscribe` 每个线程组中的最大工作线程数                                                                                     | 有                                                                     | 有      | 有                                                        | 有                                               |
| `thread_pool_size` 线程组数，一般推荐设为 CPU 核心数                                                                                         | 有                                                                     | 有      | 有                                                        | 有                                               |
| `thread_pool_stall_limit` timer 线程判断线程组是否停滞（定期调用 check_stall ）的时间间隔                                                    | 有                                                                     | 有      | 有                                                        | 有                                               |
| `thread_pool_prio_kickup_timer` 低优先队列中的语句在等待该值指定的时间后，则移入高优先级队列                                                 | 有                                                                     | 无      | 无                                                        | 无                                               |
| `thread_pool_dedicated_listener` 是否启用专用 listener 线程。若关闭，则 listener 有可能变为 worker。                                         | 有                                                                     | 无      | 无                                                        | 无                                               |
| `thread_pool_exact_stats` 是否使用高精度时间戳                                                                                               | 有                                                                     | 无      | 无                                                        | 无                                               |
| `thread_pool_normal_weights`：查询、更新操作的目标线程比例（假定这两类操作的比重相同），即`并发度= thread_pool_oversubscribe * 目标比例/100` | 无                                                                     | 无      | 无                                                        | 有                                               |
| `thread_pool_trans_weights`：事务操作的目标线程比例，即`并发度= thread_pool_oversubscribe * 目标比例/100`                                    | 无                                                                     | 无      | 无                                                        | 有                                               |

**可见**：

1.  阿里云 AliSQL 线程池资料较少，虽然有些参数不具备，但并不说明未实现对应机制，比如专用 listener 线程。

## 监控区别

### **Percona、MariaDB：**

只有两个状态变量：

- &#x20;`Threadpool_threads`&#x20;
- `Threadpool_idle_threads`

### **阿里云 AliSQL**：

新增了一些状态变量：

| 状态名                     | 状态说明                                                                                         |
| -------------------------- | ------------------------------------------------------------------------------------------------ |
| thread_pool_active_threads | 线程池中的活跃线程数                                                                             |
| thread_pool_big_threads    | 线程池中正在执行复杂查询的线程数。复杂查询包括有子查询、聚合函数、group by、limit 等的查询语句。 |
| thread_pool_dml_threads    | 线程池中的在执行 DML 的线程数                                                                    |
| thread_pool_idle_threads   | 线程池中的空闲线程数                                                                             |
| thread_pool_qry_threads    | 线程池中正在执行简单查询的线程数                                                                 |
| thread_pool_total_threads  | 线程池中的总线程数                                                                               |
| thread_pool_trx_threads    | 线程池中正在执行事务的线程数                                                                     |
| thread_pool_wait_threads   | 线程池中正在等待磁盘 IO、事务提交的线程数                                                        |

### **腾讯云 TXSQL**：

新增 `show threadpool status` 指令，展示的相关状态如下：

| 状态名                            | 状态说明                                                                                                     |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| groupid                           | 线程组 id                                                                                                    |
| connection_count                  | 线程组用户连接数                                                                                             |
| thread_count                      | 线程组内工作线程数                                                                                           |
| havelistener                      | 线程组当前是否存在 listener                                                                                  |
| active_thread_count               | 线程组内活跃 worker 数量                                                                                     |
| waiting_thread_count              | 线程组内等待中的 worker 数量（调用 wait_begin 的 worker）                                                    |
| waiting_threads_size              | 线程组中无网络事件需要处理，进入休眠期等待被唤醒的 worker 数量（等待 thread_pool_idle_timeout 秒后自动销毁） |
| queue_size                        | 线程组普通优先级队列长度                                                                                     |
| high_prio_queue_size              | 线程组高优先级队列长度                                                                                       |
| get_high_prio_queue_num           | 线程组内事件从高优先级队列被取走的总次数                                                                     |
| get_normal_queue_num              | 线程组内事件从普通优先级队列被取走的总次数                                                                   |
| create_thread_num                 | 线程组内创建的 worker 线程总数                                                                               |
| wake_thread_num                   | 线程组内从 waiting_threads 队列中唤醒的 worker 总数                                                          |
| oversubscribed_num                | 线程组内 worker 发现当前线程组处于 oversubscribed 状态，并且准备进入休眠的次数                               |
| mysql_cond_timedwait_num          | 线程组内 worker 进入 waiting_threads 队列的总次数                                                            |
| check_stall_nolistener            | 线程组被 timer 线程 check_stall 检查中发现没有 listener 的总次数                                             |
| check_stall_stall                 | 线程组被 timer 线程 check_stall 检查中被判定为 stall 状态的总次数                                            |
| max_req_latency_us                | 线程组中用户连接在队列等待的最长时间（单位毫秒）                                                             |
| conns_timeout_killed              | 线程组中用户连接因客户端无新消息时间超过阈值（net_wait_timeout）被 killed 的总次数                           |
| connections_moved_in              | 从其他线程组中迁入该线程组的连接总数                                                                         |
| connections_moved_out             | 从该线程组迁出到其他线程组的连接总数                                                                         |
| connections_moved_from_per_thread | 从 one-thread-per-connection 模式中迁入该线程组的连接总数                                                    |
| connections_moved_to_per_thread   | 从该线程组中迁出到 one-thread-per-connection 模式的连接总数                                                  |
| events_consumed                   | 线程组处理过的 events 总数                                                                                   |
| average_wait_usecs_in_queue       | 线程组内所有 events 在队列中的平均等待时间                                                                   |

在 `show full processlist` 中新增如下状态：

- `Moved_to_per_thread` 表示该连接迁移到 Per_thread 的次数。
- `Moved_to_thread_pool` 表示该连接迁移到 Thread_pool 的次数.

# 参考链接

1.  腾讯 TXSQL：
    1.  [原创｜线程池详解 (qq.com)](https://mp.weixin.qq.com/s/BXEYVfYCsZ5fD2IG6fNVrA "原创｜线程池详解 (qq.com)")
    2.  [云数据库 MySQL 动态线程池-自研内核 TXSQL-文档中心-腾讯云 (tencent.com)](https://cloud.tencent.com/document/product/236/48851 "云数据库 MySQL 动态线程池-自研内核 TXSQL-文档中心-腾讯云 (tencent.com)")
2.  Percona：
    1.  [Thread pool - Percona Server for MySQL](https://docs.percona.com/percona-server/8.0/performance/threadpool.html "Thread pool - Percona Server for MySQL")
    2.  [SimCity outages, traffic control and Thread Pool for MySQL (percona.com)](https://www.percona.com/blog/simcity-outages-traffic-control-and-thread-pool-for-mysql/ "SimCity outages, traffic control and Thread Pool for MySQL (percona.com)")
    3.  [关于 MySQL 线程池，这也许是目前最全面的实用帖 - MySQL - dbaplus 社群](https://dbaplus.cn/news-11-1989-1.html "关于MySQL线程池，这也许是目前最全面的实用帖 - MySQL - dbaplus社群")
3.  MariaDB：
    1.  [Thread Pool in MariaDB - MariaDB Knowledge Base](https://mariadb.com/kb/en/thread-pool-in-mariadb/ "Thread Pool in MariaDB - MariaDB Knowledge Base")
4.  阿里云 AliSQL：
    1.  [MySQL · 特性分析 · 线程池 (taobao.org)](http://mysql.taobao.org/monthly/2016/02/09/ "MySQL · 特性分析 · 线程池 (taobao.org)")
    2.  [MySQL · 最佳实践 · MySQL 多队列线程池优化 (taobao.org)](http://mysql.taobao.org/monthly/2019/02/09/ "MySQL · 最佳实践 · MySQL多队列线程池优化 (taobao.org)")
5.  MySQL 企业版：
    1.  [MySQL :: MySQL 8.0 Reference Manual :: 5.6.3 MySQL Enterprise Thread Pool](https://dev.mysql.com/doc/refman/8.0/en/thread-pool.html "MySQL :: MySQL 8.0 Reference Manual :: 5.6.3 MySQL Enterprise Thread Pool")

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
