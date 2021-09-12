---
title: 问题定位 | Peronca Xtrabackup 8.0近日踩坑总结 - xtrabackup 2.4和8.0区别
date: 2020-08-27 13:46:15
categories:
- MySQL
tags:
- MySQL
- Percona
- Xtrabackup
- RadonDB
- Xenon
- 问题定位
toc: true
---

<!-- more -->


>**本文首发于 2020-08-27 13:46:15**

### 前言

近期在给 `radondb/xenon` 适配 percona xtrabackup 8.0时，遇到了一些问题，经过多日调研、尝试终于解决，特此分享。

**版本信息：**
```
Percona-Server 8.0.19-10
Percona-Xtrabackup 8.0.13
```

版本各字段含义参考 https://www.percona.com/blog/2020/08/18/aligning-percona-xtrabackup-versions-with-percona-server-for-mysql/

### 适配过程中遇到的坑

一、MySQL 8.0 + Semi-Sync + 持续写入数据期间执行重建后，change master to && start slave 报错：
```verilog
Last_Error: Could not execute Write_rows event on table db1.t1; Duplicate entry '28646' for key 't1.PRIMARY', Error_code: 1062; handler error HA_ERR_FOUND_DUPP_KEY; the event's master log mysql-bin.000052, end_log_pos 437
```

二、MySQL 8.0 + Group Replication + 持续写入数据期间执行重建后，change master to && start group_replication 报错：
```verilog
2020-08-21T14:51:09.977606+08:00 61 [System] [MY-010597] [Repl] 'CHANGE MASTER TO FOR CHANNEL 'group_replication_applier' executed'. Previous state master_host='<NULL>', master_port= 0, master_log_file='', master_log_pos= 4, master_bind=''. New state master_host='<NULL>', master_port= 0, master_log_file='', master_log_pos= 4, master_bind=''.
2020-08-21T14:51:09.987494+08:00 61 [ERROR] [MY-013124] [Repl] Slave SQL for channel 'group_replication_applier': Slave failed to initialize relay log info structure from the repository, Error_code: MY-013124
2020-08-21T14:51:09.987542+08:00 61 [ERROR] [MY-011534] [Repl] Plugin group_replication reported: 'Error while starting the group replication applier thread'
2020-08-21T14:51:09.987651+08:00 7 [ERROR] [MY-011669] [Repl] Plugin group_replication reported: 'Unable to initialize the Group Replication applier module.'
2020-08-21T14:51:09.987831+08:00 7 [ERROR] [MY-011735] [Repl] Plugin group_replication reported: '[GCS] The member is leaving a group without being on one.'
```

要解释这个问题，首先要弄清楚xtrabackup 2.4和8.0的区别。

### xtrabackup 2.4和8.0区别

**google查到xtrabackup 8.0与2.4版本行为有所不同：**
>1. Xtrabackup 2.4 备份后生成的 `xtrabackup_binlog_info` 文件记录的 GTID 信息是准确的，但是备份恢复后 `show master status` 显示的 GTID 是不准确的。
>2. Xtrabackup 8.0 在备份只有 InnoDB 表的实例时，`xtrabackup_binlog_info` 文件记录的 GTID 信息不一定是准确的，但是备份恢复后 `show master status` 显示的 GTID 是准确的。
>3. Xtrabackup 8.0 在备份有非 InnoDB 表格的实例时，`xtrabackup_binlog_info` 文件记录的 GTID 信息是准确的，备份恢复后 `show master status` 显示的 GTID 也是准确的。

**之前研究过 xtrabackup 2.4 ，其过程大致如下：**
>1. start backup
>2. copy ibdata1 / copy .ibd file
>3. excuted FTWRL
>4. backup non-InnoDB tables and files
>5. writing xtrabackup_binlog_info
>6. executed FLUSH NO_WRITE_TO_BINLOG ENGINE LOGS
>7. executed UNLOCK TABLES
>8. copying ib_buffer_pool
>9. completed OK!

**问题1：xtrabackup 8.0 的执行过程是什么样？**

首先，查看重建期间的`general log`：
```verilog
2020-08-26T16:20:18.136376+08:00	  170 Query	SET SESSION wait_timeout=2147483
2020-08-26T16:20:18.136439+08:00	  170 Query	SET SESSION autocommit=1
2020-08-26T16:20:18.136523+08:00	  170 Query	SET NAMES utf8
2020-08-26T16:20:18.136595+08:00	  170 Query	SHOW VARIABLES
2020-08-26T16:20:18.138840+08:00	  170 Query	SELECT COUNT(*) FROM information_schema.tables WHERE engine = 'MyISAM' OR engine = 'RocksDB'
2020-08-26T16:20:18.140203+08:00	  170 Query	SHOW ENGINES
2020-08-26T16:20:18.140407+08:00	  170 Query	SHOW ENGINE INNODB STATUS
2020-08-26T16:20:18.141570+08:00	  170 Query	SELECT PLUGIN_NAME, PLUGIN_LIBRARY FROM information_schema.plugins WHERE PLUGIN_STATUS = 'ACTIVE' AND PLUGIN_TYPE = 'KEYRING'
2020-08-26T16:20:18.142140+08:00	  170 Query	SELECT  CONCAT(table_schema, '/', table_name), engine FROM information_schema.tables WHERE engine NOT IN ('MyISAM', 'InnoDB', 'CSV', 'MRG_MYISAM', 'ROCKSDB') AND table_schema NOT IN (  'performance_schema', 'information_schema',   'mysql')
2020-08-26T16:20:18.209819+08:00	  171 Query	SET SESSION wait_timeout=2147483
2020-08-26T16:20:18.209879+08:00	  171 Query	SET SESSION autocommit=1
2020-08-26T16:20:18.209950+08:00	  171 Query	SET NAMES utf8
2020-08-26T16:20:18.210015+08:00	  171 Query	SHOW VARIABLES
2020-08-26T16:20:18.214030+08:00	  170 Query	SELECT T2.PATH,        T2.NAME,        T1.SPACE_TYPE FROM   INFORMATION_SCHEMA.INNODB_TABLESPACES T1        JOIN INFORMATION_SCHEMA.INNODB_TABLESPACES_BRIEF T2 USING (SPACE) WHERE  T1.SPACE_TYPE = 'Single' && T1.ROW_FORMAT != 'Undo'UNION SELECT T2.PATH,        SUBSTRING_INDEX(SUBSTRING_INDEX(T2.PATH, '/', -1), '.', 1) NAME,        T1.SPACE_TYPE FROM   INFORMATION_SCHEMA .INNODB_TABLESPACES T1        JOIN INFORMATION_SCHEMA .INNODB_TABLESPACES_BRIEF T2 USING (SPACE) WHERE  T1.SPACE_TYPE = 'General' && T1.ROW_FORMAT != 'Undo'
2020-08-26T16:20:19.533904+08:00	  170 Query	FLUSH NO_WRITE_TO_BINLOG BINARY LOGS
2020-08-26T16:20:19.543095+08:00	  170 Query	SELECT server_uuid, local, replication, storage_engines FROM performance_schema.log_status
2020-08-26T16:20:19.543418+08:00	  170 Query	SHOW VARIABLES
2020-08-26T16:20:19.545383+08:00	  170 Query	SHOW VARIABLES
2020-08-26T16:20:19.550641+08:00	  170 Query	FLUSH NO_WRITE_TO_BINLOG ENGINE LOGS
2020-08-26T16:20:20.556885+08:00	  170 Query	SELECT UUID()
2020-08-26T16:20:20.557118+08:00	  170 Query	SELECT VERSION()
```

可见，**xtrabackup 8.0默认情况下大致过程如下：**
>1. start backup
>2. copy .ibd file
>3. backup non-InnoDB tables and files
>4. executed FLUSH NO_WRITE_TO_BINLOG BINARY LOGS
>5. selecting LSN and binary log position from p_s.log_status
>6. copy last binlog file
>7. writing /mysql/backup/backup/binlog.index
>8. writing xtrabackup_binlog_info
>9. executing FLUSH NO_WRITE_TO_BINLOG ENGINE LOGS
>10. copy ib_buffer_pool
>11. completed OK!
>
>**注意：** 当存在非InnoDB表时，xtrabackup 8.0会执行FTWRL。

从上述步骤可知，xtrabackup 8.0与2.4的步骤**主要区别**为：

当只存在InnoDB引擎的表时，不再执行FTWRL，而是通过 上述第5步（`SELECT server_uuid, local, replication, storage_engines FROM performance_schema.log_status` ）来获取LSN、binlog position、GTID 。

手册中对于表 [log_status](https://dev.mysql.com/doc/refman/8.0/en/performance-schema-log-status-table.html) 的描述如下：
>The [`log_status`](https://dev.mysql.com/doc/refman/8.0/en/performance-schema-log-status-table.html) table provides information that enables an online backup tool to copy the required log files without locking those resources for the duration of the copy process.
>
>When the [`log_status`](https://dev.mysql.com/doc/refman/8.0/en/performance-schema-log-status-table.html) table is queried, the server blocks logging and related administrative changes for just long enough to populate the table, then releases the resources. The [`log_status`](https://dev.mysql.com/doc/refman/8.0/en/performance-schema-log-status-table.html) table informs the online backup which point it should copy up to in the source's binary log and `gtid_executed` record, and the relay log for each replication channel. It also provides relevant information for individual storage engines, such as the last log sequence number (LSN) and the LSN of the last checkpoint taken for the `InnoDB` storage engine.

从上述手册描述可知，`performance_schema.log_status`是MySQL 8.0提供给在线备份工具获取复制信息的表格，查询该表时，mysql server将阻止日志的记录和相关的更改来获取足够的时间以填充该表，然后释放资源。

log_status 表通知在线备份工具当前主库的 binlog 的位点和 gtid_executed 的值以及每个复制通道的 relay log。另外，它还提供了各个存储引擎的相关信息，比如，提供了 InnoDB 引擎使用的最后一个日志序列号（LSN）和最后一个检查点的 LSN。

`performance_schema.log_status`表定义为：
```sql
-- Semi-Sync
mysql> select * from performance_schema.log_status\G
*************************** 1. row ***************************
    SERVER_UUID: 6b437e80-e5d5-11ea-88e3-52549922fdbb
          LOCAL: {"gtid_executed": "6b437e80-e5d5-11ea-88e3-52549922fdbb:1-201094", "binary_log_file": "mysql-bin.000079", "binary_log_position": 195}
    REPLICATION: {"channels": []}
STORAGE_ENGINES: {"InnoDB": {"LSN": 23711425885, "LSN_checkpoint": 23711425885}}
1 row in set (0.00 sec)

-- Group Replication
mysql> select * from performance_schema.log_status\G
*************************** 1. row ***************************
    SERVER_UUID: 7bd32480-e5d5-11ea-8f8a-525499cfbb7d
          LOCAL: {"gtid_executed": "aaaaaaaa-aaaa-aaaa-aaaa-53ab6ea1210a:1-11", "binary_log_file": "mysql-bin.000003", "binary_log_position": 1274}
    REPLICATION: {"channels": [{"channel_name": "group_replication_applier", "relay_log_file": "mysql-relay-bin-group_replication_applier.000004", "relay_log_position": 311, "relay_master_log_file": "", "exec_master_log_position": 0}, {"channel_name": "group_replication_recovery", "relay_log_file": "mysql-relay-bin-group_replication_recovery.000003", "relay_log_position": 151, "relay_master_log_file": "", "exec_master_log_position": 0}]}
STORAGE_ENGINES: {"InnoDB": {"LSN": 20257208, "LSN_checkpoint": 20257208}}
1 row in set (0.00 sec)
```

**问题2：`performance_schema.log_status`提供的信息是否准确呢？**

当写入压力大时，该表中的binlog position与GTID信息不一致。
```sql
mysql> select * from performance_schema.log_status\G  show master status;
*************************** 1. row ***************************
    SERVER_UUID: 6b437e80-e5d5-11ea-88e3-52549922fdbb
          LOCAL: {"gtid_executed": "6b437e80-e5d5-11ea-88e3-52549922fdbb:1-448709", "binary_log_file": "mysql-bin.000087", "binary_log_position": 341265185}
    REPLICATION: {"channels": []}
STORAGE_ENGINES: {"InnoDB": {"LSN": 33797305275, "LSN_checkpoint": 33433316246}}
1 row in set (0.11 sec)

+------------------+-----------+--------------+------------------+-----------------------------------------------+
| File             | Position  | Binlog_Do_DB | Binlog_Ignore_DB | Executed_Gtid_Set                             |
+------------------+-----------+--------------+------------------+-----------------------------------------------+
| mysql-bin.000087 | 343317905 |              |                  | 6b437e80-e5d5-11ea-88e3-52549922fdbb:1-448709 |
+------------------+-----------+--------------+------------------+-----------------------------------------------+
1 row in set (0.01 sec)
```

**问题3：既然log_status中的binlog position不准确，为什么备份恢复后GTID并没有缺失，数据也没问题？**

原因是xtrabackup 8.0在第4步`FLUSH NO_WRITE_TO_BINLOG BINARY LOGS`之后，在第6步`copy last binlog file`，这样备份恢复出的新实例在启动后不仅会读取 `gtid_executed` 表，还会读取拷贝的那个binlog文件来更新GTID。

```verilog
$ mysqlbinlog -vv /data/mysql/mysql-bin.000096
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=1*/;
/*!50003 SET @OLD_COMPLETION_TYPE=@@COMPLETION_TYPE,COMPLETION_TYPE=0*/;
DELIMITER /*!*/;
# at 4
#200827 11:26:47 server id 575010000  end_log_pos 124 CRC32 0xb026e372 	Start: binlog v 4, server v 8.0.19-10 created 200827 11:26:47
# Warning: this binlog is either in use or was not closed properly.
BINLOG '
9ydHXw/Q9EUieAAAAHwAAAABAAQAOC4wLjE5LTEwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAEwANAAgAAAAABAAEAAAAYAAEGggAAAAICAgCAAAACgoKKioAEjQA
CgFy4yaw
'/*!*/;
# at 124
#200827 11:26:47 server id 575010000  end_log_pos 195 CRC32 0xad060415 	Previous-GTIDs
# 6b437e80-e5d5-11ea-88e3-52549922fdbb:1-465503
SET @@SESSION.GTID_NEXT= 'AUTOMATIC' /* added by mysqlbinlog */ /*!*/;
DELIMITER ;
# End of log file
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/;
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=0*/;
```

### 问题定位

#### 坑一：MySQL 8.0 + Semi-Sync 重建问题

xenon原有的重建逻辑是适配于MySQL 5.6、5.7的（重建过程中xenon进程存活），一直无问题：
>1. 禁用raft，将xenon状态设为LEARNER ；
>2. 如mysql进程存在，则stop mysql；
>3. 清空MySQL数据目录；
>4. 执行`xtrabackup --backup`以`xbstream`方式获取对端数据；
>5. 执行`xtrabackup --prepare`应用redo log；
>6. 启动mysql；
>7. 执行`stop slave; reset slave all`；
>8. 执行`reset master`，以`xtrabackup_binlog_info`文件中的GTID为准设置`gtid_purged`；
>9. 启用raft，将xenon状态设为FOLLOWER或IDLE；
>10. 等待xenon自动`change master to`到主节点。
>11. 执行`start slave`。

**问题1：为什么在 MySQL 8.0 + Semi-Sync 组合下会出现 Duplicate entry ？**

跟踪重建过程中的general log，发现在第6和第7步中间，也就是设置`gtid_purged`之前凭空多出了 `change master to` 和 `start slave` 操作：
```verilog
2020-08-24T21:55:22.817859+08:00            8 Query     SET GLOBAL rpl_semi_sync_master_enabled=OFF
2020-08-24T21:55:22.818025+08:00            8 Query     SET GLOBAL read_only = 1
2020-08-24T21:55:22.818143+08:00            8 Query     SET GLOBAL super_read_only = 1
2020-08-24T21:55:22.818323+08:00            8 Query     START SLAVE
2020-08-24T21:55:22.824449+08:00            8 Query     STOP SLAVE
2020-08-24T21:55:22.824610+08:00            8 Query     CHANGE MASTER TO MASTER_HOST = '192.168.0.3', MASTER_USER = 'qc_repl', MASTER_PASSWORD = <secret>, MASTER_PORT = 3306, MASTER_AUTO_POSITION = 1
2020-08-24T21:55:22.833710+08:00            8 Query     START SLAVE
2020-08-24T21:55:22.935973+08:00           10 Query     BEGIN
2020-08-24T21:55:22.936084+08:00           10 Query     COMMIT /* implicit, from Xid_log_event */
......
2020-08-24T21:55:24.701711+08:00           10 Query     BEGIN
2020-08-24T21:55:24.701901+08:00           10 Query     COMMIT /* implicit, from Xid_log_event */
2020-08-24T21:55:24.816571+08:00            8 Query     SET GLOBAL rpl_semi_sync_master_enabled=OFF
2020-08-24T21:55:24.816886+08:00            8 Query     SET GLOBAL read_only = 1
2020-08-24T21:55:24.817177+08:00            8 Query     SET GLOBAL super_read_only = 1
2020-08-24T21:55:24.817281+08:00            8 Query     START SLAVE
2020-08-24T21:55:25.039581+08:00           10 Query     BEGIN
2020-08-24T21:55:25.039749+08:00           10 Query     COMMIT /* implicit, from Xid_log_event */
......
2020-08-24T21:55:25.152919+08:00           10 Query     BEGIN
2020-08-24T21:55:25.153082+08:00           10 Query     COMMIT /* implicit, from Xid_log_event */
2020-08-24T21:55:25.389776+08:00            8 Query     STOP SLAVE
2020-08-24T21:55:25.392581+08:00            8 Query     RESET SLAVE ALL
2020-08-24T21:55:25.407434+08:00            8 Query     RESET MASTER
2020-08-24T21:55:25.417292+08:00            8 Query     SET GLOBAL gtid_purged='6b437e80-e5d5-11ea-88e3-52549922fdbb:1-102610
'
2020-08-24T21:55:25.419835+08:00            8 Query     START SLAVE
2020-08-24T21:55:25.427071+08:00            8 Query     SET GLOBAL read_only = 1
2020-08-24T21:55:25.427178+08:00            8 Query     SET GLOBAL super_read_only = 1
2020-08-24T21:55:25.427271+08:00            8 Query     SET GLOBAL sync_binlog=1000
2020-08-24T21:55:25.427339+08:00            8 Query     SET GLOBAL innodb_flush_log_at_trx_commit=1
2020-08-24T21:55:25.427423+08:00            8 Query     SHOW SLAVE STATUS
2020-08-24T21:55:25.427600+08:00            8 Query     SHOW MASTER STATUS
2020-08-24T21:55:26.817622+08:00            8 Query     SET GLOBAL rpl_semi_sync_master_enabled=OFF
2020-08-24T21:55:26.817794+08:00            8 Query     SET GLOBAL read_only = 1
2020-08-24T21:55:26.817897+08:00            8 Query     SET GLOBAL super_read_only = 1
2020-08-24T21:55:26.817988+08:00            8 Query     START SLAVE
2020-08-24T21:55:26.818381+08:00            8 Query     SHOW SLAVE STATUS
2020-08-24T21:55:26.818570+08:00            8 Query     SHOW MASTER STATUS
2020-08-24T21:55:26.818715+08:00            8 Query     STOP SLAVE
2020-08-24T21:55:26.818823+08:00            8 Query     CHANGE MASTER TO MASTER_HOST = '192.168.0.3', MASTER_USER = 'qc_repl', MASTER_PASSWORD = <secret>, MASTER_PORT = 3306, MASTER_AUTO_POSITION = 1
2020-08-24T21:55:26.832164+08:00            8 Query     START SLAVE
```

这就是说在设置gtid_purged之前已经启用复制获取了一部分数据，那么 xtrabackup_binlog_info 中的内容就不再准确，之后设置的GTID与实际数据就不一致，实际的数据比设置的GTID要多，引起主键冲突。

**问题2：为什么之前MySQL 5.6、5.7从没遇到过这个问题呢？**

测试了很多次，发现在 MySQL 5.6 & 5.7 在`set gtid_purged` 前执行 `change master to & start slave` 后会报复制错误 `Slave failed to initialize relay log info structure from the repository` ，而在`reset slave all; reset master、set gtid_purged`后再执行 `change master to & start slave` 就可以正常复制，数据无误。

**问题3：xenon中哪块逻辑引起的额外的 change master to 和 start slave ？**

问题根源在重建期间 xenon 会设为 LEARNER 角色，而该角色在探测到MySQL Alive后，会 change master 到主节点。正常来说，要等raft状态设为 FOLLOWER 后由 FOLLOWER 的监听线程 change master 到主节点。（代码见 [pr104](https://github.com/radondb/xenon/pull/104) 、[pr102](https://github.com/radondb/xenon/pull/102)  ）


#### 坑二：MySQL 8.0 + Group-Replication 重建后无法启动MGR

根据报错信息`Slave failed to initialize relay log info structure from the repository`看，应该是xtrabackup重建后的数据目录保留了slave复制信息导致的，尝试在启动组复制前执行`reset slave或reset slave all`即可解决。

### 总结

>1. Xtrabackup 2.4 备份后生成的 `xtrabackup_binlog_info` 文件记录的 GTID 信息是准确的，但是备份恢复后 `show master status` 显示的 GTID 是不准确的。
>2. Xtrabackup 8.0 在备份只有 InnoDB 表的实例时，`xtrabackup_binlog_info` 文件记录的 GTID 信息不一定是准确的，但是备份恢复后 `show master status` 显示的 GTID 是准确的。
>3. Xtrabackup 8.0 在备份有非 InnoDB 表格的实例时，`xtrabackup_binlog_info` 文件记录的 GTID 信息是准确的，备份恢复后 `show master status` 显示的 GTID 也是准确的。
>4. 使用 Xtrabackup 8.0 重建集群节点后，无需执行 `reset master & set gtid_purged` 操作。
>5. 使用 Xtrabackup 8.0 重建 Group-Replication 集群节点后，启动组复制前需要先执行`reset slave或reset slave all`清除slave信息，否则 `start group_replication` 会失败。


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


