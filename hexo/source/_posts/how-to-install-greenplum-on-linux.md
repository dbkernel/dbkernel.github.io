---
title: 最佳实践 | CentOS 和 Ubuntu 下安装配置 GreenPlum 数据库集群 - 源码 & 安装包
date: 2016-01-14 19:55:08
categories:
- GreenPlum
tags:
- PostgreSQL
- GreenPlum
- Linux
toc: true
---

<!-- more -->



>**本文首发于 2016-01-14 19:55:08**

本文介绍如何在 CentOS/RedHat、Ubuntu/Debian 下通过安装包方式和源码方式安装配置 GreenPlum 集群。

# 1. 安装步骤

## 1.1. 规划

>192.168.4.93（h93）   1个主master  2个主segment、2个镜像segment
>
>192.168.4.94（h94）   1个备master  2个主segment、2个镜像segment

安装在`/home/wslu/gp/gpsql`目录下。

>**注意：** 如无特殊说明，本文后续步骤需要在 h93 和 h94 都执行。


## 1.2. 安装依赖

按如下方式在在 h93 和 h94 安装依赖。

**对于 Ubuntu/Debian：**
```bash
apt-get install -y git-core
apt-get install -y gcc g++
apt-get install -y ccache
apt-get install -y libreadline-dev
apt-get install -y bison flex
apt-get install -y zlib1g-dev
apt-get install -y openssl libssl-dev
apt-get install -y libpam-dev
apt-get install -y libcurl4-dev
apt-get install -y libbz2-dev
apt-get install -y python-dev
apt-get install -y ssh

apt-get install -y libcurl4-dev
Package libcurl4-dev is a virtual package provided by:
libcurl4-openssl-dev 7.38.0-4+deb8u2
libcurl4-nss-dev 7.38.0-4+deb8u2
libcurl4-gnutls-dev 7.38.0-4+deb8u2

apt-get install -y python-pip

pip install lockfile
pip install paramiko
pip install setuptools
pip install epydoc
pip install psi

Note: debian8 required pip install --pre psi
```

**对于 CentOS：**
```bash
yum install –y git.x86_64
yum install –y gcc.x86_64 gcc-c++.x86_64
yum install –y ccache.x86_64
yum install readline.x86_64 readline-devel.x86_64
yum install bison.x86_64 bison-devel.x86_64
yum install flex.x86_64 flex-devel.x86_64
yum install zlib.x86_64 zlib-devel.x86_64
yum install -y openssl.x86_64 openssl-devel.x86_64
yum install -y pam.x86_64 pam-devel.x86_64
yum install –y libcurl.x86_64 libcurl-devel.x86_64
yum install bzip2-libs.x86_64 bzip2.x86_64 bzip2-devel.x86_64
yum install libssh2.x86_64 libssh2-devel.x86_64
yum install python-devel.x86_64
yum install -y python-pip.noarch

# 接着执行：
pip install lockfile
pip install paramiko
pip install setuptools
pip install epydoc
pip install psi
# 或者执行：
yum install python-lockfile.noarch
yum install python-PSI.x86_64
yum install python-paramiko.noarch
yum install python-setuptools.noarch
yum install epydoc.noarch
```

## 1.3. 安装包方式安装

1. 从官网下载`greenplum-db-4.3.6.1-build-2-RHEL5-x86_64.zip`。
2. 解压：
```bash
unzip greenplum-db-4.3.6.1-build-2-RHEL5-x86_64.zip
```
3. 以普通用户安装：
```bash
$ ./greenplum-db-4.3.6.1-build-2-RHEL5-x86_64.bin
安装路径选择 /home/wslu/gp/gpsql
```

## 1.4. 源码安装
### 1.4.1. 克隆源码

```bash
$ mkdir /home/wslu/gp/greenplum
$ cd /home/wslu/gp/greenplum
$ git clone https://github.com/greenplum-db/gpdb.
```

### 1.4.2. 编译安装

```bash
$ cd /home/wslu/gp/greenplum
$ CFLAGS+="-O2" ./configure--prefix=/home/wslu/gp/gpsql --enable-debug --enable-depend --enable-cassert
$ make
$ make install
```

安装时如果遇到某些 python 包（lockfile、 paramiko、PSI等）找不到，可以参考 [HAWQ](https://github.com/apache/incubator-hawq) 项目，将 `<hawq_src>/tools/bin/pythonSrc/` 下所有的压缩包拷贝到`/home/wslu/gp/greenplum/gpMgmt/bin/pythonSrc/ext/` 中，然后再 `make install` 即可。

至此集群源码编译完成。

## 1.5. 设置参数
### 1.5.1. 设置操作系统参数

1. 关闭防火墙。
2. 加速SSH连接：
```bash
sudo sed -i 's/^GSS/#&/g' /etc/ssh/sshd_config # 用来加速SSH连接的
service sshd restart
```

3. 设置内核和内存方面的参数：
```bash
# 设置内核参数, 并在启动时生效
sysctl -p - >>/etc/sysctl.conf <<EOF
# configurations
kernel.sysrq=1
kernel.core_pattern=core
kernel.core_uses_pid=1
kernel.msgmnb=65536
kernel.msgmax=65536
kernel.msgmni=2048
kernel.sem=25600 3200000 10000 14200
net.ipv4.tcp_syncookies=1
net.ipv4.ip_forward=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.tcp_tw_recycle=1
net.ipv4.tcp_max_syn_backlog=4096
net.ipv4.conf.all.arp_filter=1
net.ipv4.ip_local_port_range=1025 65535
net.core.netdev_max_backlog=10000
net.core.rmem_max=2097152
net.core.wmem_max=2097152
vm.overcommit_memory=1
EOF
```
4. 可以参考官方推荐设置共享内存相关参数：
```ini
# vi /etc/sysctl.conf
kernel.shmmax = 500000000
kernel.shmmni = 4096
kernel.shmall = 4000000000
kernel.sem = 250 512000 100 2048
kernel.sysrq = 1
kernel.core_uses_pid = 1
kernel.msgmnb = 65536
kernel.msgmax = 65536
kernel.msgmni = 2048
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.conf.all.arp_filter = 1
net.ipv4.ip_local_port_range = 1025 65535
net.core.netdev_max_backlog = 10000
net.core.rmem_max = 2097152
net.core.wmem_max = 2097152
vm.overcommit_memory = 2
```

5. 设置文件读写相关参数：
```bash
# 设置limits
cat >>/etc/security/limits.d/greenplum.conf <<EOF
# GreenPlum configurations
* soft nofile 65536
* hard nofile 65536
* soft nproc 131072
* hard nproc 131072
EOF
```

### 1.5.2. 设置数据库相关参数

GUC参数设置示例（需要根据机器配置调整）：

```ini
work_mem=1GB
shared_buffers=2GB
max_connections=500
max_pool_size=2000
enable_mergejoin=off
enable_nestloop=off
max_prepared_transactions=50
autovacuum=off
interconnect_setup_timeout=1200
```

## 1.6. demo 集群

>**提示：** 如果不想用demo集群，可以直接跳过本小节。

安装完成后，可以使用如下指令创建 demo 集群（在本机创建包含3个segment，3个segment-mirror，1个master的集群）：
```bash
$ cd /home/wslu/gp/gpsql
$ source greenplum_path.sh
$ gpssh-exkeys –h localhost
$ cd gpAux/gpdemo
$ make cluster
$ source gpdemo-env.sh
```

## 1.7. 设置环境变量

```bash
$ source gpsql/greenplum_path.sh
$ export MASTER_DATA_DIRECTORY=/home/wslu/gp/gpsql/data/master/gpseg-1
```

## 1.8. 交换 SSH 密钥

```bash
gpssh-exkeys –h h93
gpssh-exkeys –h h94
```

## 1.9. 初始化集群

1. 在 h93 和 h94 执行下述指令，以创建数据目录：
```bash
$ mkdir gpsql/data/primary gpsql/data/mirror gpsql/data/master –p
```

2. 在 h93 创建配置文件 `configs/gpinitsystem_config`，内容如下：
```bash
ARRAY_NAME="EMC Greenplum DW"
SEG_PREFIX=gpseg
PORT_BASE=40000
declare -a DATA_DIRECTORY=(/home/wslu/gp/gpsql/data/primary /home/wslu/gp/gpsql/data/primary)
MASTER_HOSTNAME=h93
MASTER_DIRECTORY=/home/wslu/gp/gpsql/data/master
MASTER_PORT=5432
TRUSTED_SHELL=ssh
CHECK_POINT_SEGMENTS=8
ENCODING=UNICODE
MIRROR_PORT_BASE=50000
REPLICATION_PORT_BASE=41000
MIRROR_REPLICATION_PORT_BASE=51000
declare -a MIRROR_DATA_DIRECTORY=(/home/wslu/gp/gpsql/data/mirror /home/wslu/gp/gpsql/data/mirror)
```
>**注意**：configs目录是我自己创建的、便于保存自定义配置文件的目录。该步骤的目的是创建一个初始化时要用的配置文件，并没有路径的要求。

3. 在 h93 创建配置文件 `configs/hostfile_gpinitsystem`，内容如下：
```bash
h93
h94
```
>**注意**：configs 目录是我自己创建的、便于保存自定义配置文件的目录。该步骤的目的是创建一个初始化时要用的配置文件，并没有路径的要求。

4. 在 h93 执行下述指令初始化集群：
```verilog
[wslu@h93 gpsql]$ gpinitsystem -c configs/gpinitsystem_config -h configs/hostfile_gpinitsystem –a
20160114:14:30:03:005980 gpinitsystem:h93:wslu-[INFO]:-Checking configuration parameters, please wait...
20160114:14:30:03:005980 gpinitsystem:h93:wslu-[INFO]:-Reading Greenplum configuration file configs/gpinitsystem_config
20160114:14:30:03:005980 gpinitsystem:h93:wslu-[INFO]:-Locale has not been set in configs/gpinitsystem_config, will set to default value
20160114:14:30:03:005980 gpinitsystem:h93:wslu-[INFO]:-Locale set to en_US.utf8
20160114:14:30:03:005980 gpinitsystem:h93:wslu-[INFO]:-No DATABASE_NAME set, will exit following template1 updates
20160114:14:30:03:005980 gpinitsystem:h93:wslu-[INFO]:-MASTER_MAX_CONNECT not set, will set to default value 250
20160114:14:30:03:005980 gpinitsystem:h93:wslu-[INFO]:-Checking configuration parameters, Completed
20160114:14:30:04:005980 gpinitsystem:h93:wslu-[INFO]:-Commencing multi-home checks, please wait...
..
20160114:14:30:05:005980 gpinitsystem:h93:wslu-[INFO]:-Configuring build for standard array
20160114:14:30:05:005980 gpinitsystem:h93:wslu-[INFO]:-Commencing multi-home checks, Completed
20160114:14:30:05:005980 gpinitsystem:h93:wslu-[INFO]:-Building primary segment instance array, please wait...
....
20160114:14:30:08:005980 gpinitsystem:h93:wslu-[INFO]:-Building group mirror array type , please wait...
....
20160114:14:30:12:005980 gpinitsystem:h93:wslu-[INFO]:-Checking Master host
20160114:14:30:12:005980 gpinitsystem:h93:wslu-[INFO]:-Checking new segment hosts, please wait...
........
20160114:14:30:28:005980 gpinitsystem:h93:wslu-[INFO]:-Checking new segment hosts, Completed
20160114:14:30:28:005980 gpinitsystem:h93:wslu-[INFO]:-Greenplum Database Creation Parameters
20160114:14:30:28:005980 gpinitsystem:h93:wslu-[INFO]:---------------------------------------
20160114:14:30:28:005980 gpinitsystem:h93:wslu-[INFO]:-Master Configuration
20160114:14:30:28:005980 gpinitsystem:h93:wslu-[INFO]:---------------------------------------
20160114:14:30:28:005980 gpinitsystem:h93:wslu-[INFO]:-Master instance name       = EMC Greenplum DW
20160114:14:30:28:005980 gpinitsystem:h93:wslu-[INFO]:-Master hostname            = h93
20160114:14:30:28:005980 gpinitsystem:h93:wslu-[INFO]:-Master port                = 5432
20160114:14:30:28:005980 gpinitsystem:h93:wslu-[INFO]:-Master instance dir        = /home/wslu/gp/gpsql/data/master/gpseg-1
20160114:14:30:28:005980 gpinitsystem:h93:wslu-[INFO]:-Master LOCALE              = en_US.utf8
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Greenplum segment prefix   = gpseg
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Master Database            =
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Master connections         = 250
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Master buffers             = 128000kB
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Segment connections        = 750
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Segment buffers            = 128000kB
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Checkpoint segments        = 8
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Encoding                   = UNICODE
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Postgres param file        = Off
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Initdb to be used          = /home/wslu/gp/gpsql/bin/initdb
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-GP_LIBRARY_PATH is         = /home/wslu/gp/gpsql/lib
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Ulimit check               = Passed
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Array host connect type    = Single hostname per node
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Master IP address [1]      = ::1
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Master IP address [2]      = 192.168.4.93
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Master IP address [3]      = fe80::225:90ff:fe3b:86c2
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Standby Master             = Not Configured
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Primary segment #          = 2
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Total Database segments    = 4
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Trusted shell              = ssh
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Number segment hosts       = 2
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Mirror port base           = 50000
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Replicaton port base       = 41000
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Mirror replicaton port base= 51000
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Mirror segment #           = 2
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Mirroring config           = ON
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Mirroring type             = Group
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:----------------------------------------
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Greenplum Primary Segment Configuration
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:----------------------------------------
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-h93      /home/wslu/gp/gpsql/data/primary/gpseg0        40000          2          0       41000
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-h93      /home/wslu/gp/gpsql/data/primary/gpseg1        40001          3          1       41001
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-h94      /home/wslu/gp/gpsql/data/primary/gpseg2        40000          4          2       41000
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-h94      /home/wslu/gp/gpsql/data/primary/gpseg3        40001          5          3       41001
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:---------------------------------------
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-Greenplum Mirror Segment Configuration
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:---------------------------------------
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-h94      /home/wslu/gp/gpsql/data/mirror/gpseg0          50000          6          0       51000
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-h94      /home/wslu/gp/gpsql/data/mirror/gpseg1          50001          7          1       51001
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-h93      /home/wslu/gp/gpsql/data/mirror/gpseg2          50000          8          2       51000
20160114:14:30:29:005980 gpinitsystem:h93:wslu-[INFO]:-h93      /home/wslu/gp/gpsql/data/mirror/gpseg3          50001          9          3       51001
Continue with Greenplum creation Yy/Nn>
y
20160114:14:30:32:005980 gpinitsystem:h93:wslu-[INFO]:-Building the Master instance database, please wait...
20160114:14:31:08:005980 gpinitsystem:h93:wslu-[INFO]:-Starting the Master in admin mode
20160114:14:32:01:005980 gpinitsystem:h93:wslu-[INFO]:-Commencing parallel build of primary segment instances
20160114:14:32:01:005980 gpinitsystem:h93:wslu-[INFO]:-Spawning parallel processes    batch [1], please wait...
....
20160114:14:32:02:005980 gpinitsystem:h93:wslu-[INFO]:-Waiting for parallel processes batch [1], please wait...
...........................................................
20160114:14:33:01:005980 gpinitsystem:h93:wslu-[INFO]:------------------------------------------------
20160114:14:33:01:005980 gpinitsystem:h93:wslu-[INFO]:-Parallel process exit status
20160114:14:33:01:005980 gpinitsystem:h93:wslu-[INFO]:------------------------------------------------
20160114:14:33:01:005980 gpinitsystem:h93:wslu-[INFO]:-Total processes marked as completed           = 4
20160114:14:33:01:005980 gpinitsystem:h93:wslu-[INFO]:-Total processes marked as killed              = 0
20160114:14:33:01:005980 gpinitsystem:h93:wslu-[INFO]:-Total processes marked as failed              = 0
20160114:14:33:01:005980 gpinitsystem:h93:wslu-[INFO]:------------------------------------------------
20160114:14:33:01:005980 gpinitsystem:h93:wslu-[INFO]:-Commencing parallel build of mirror segment instances
20160114:14:33:01:005980 gpinitsystem:h93:wslu-[INFO]:-Spawning parallel processes    batch [1], please wait...
....
20160114:14:33:01:005980 gpinitsystem:h93:wslu-[INFO]:-Waiting for parallel processes batch [1], please wait...
.........................................
20160114:14:33:43:005980 gpinitsystem:h93:wslu-[INFO]:------------------------------------------------
20160114:14:33:43:005980 gpinitsystem:h93:wslu-[INFO]:-Parallel process exit status
20160114:14:33:43:005980 gpinitsystem:h93:wslu-[INFO]:------------------------------------------------
20160114:14:33:43:005980 gpinitsystem:h93:wslu-[INFO]:-Total processes marked as completed           = 4
20160114:14:33:43:005980 gpinitsystem:h93:wslu-[INFO]:-Total processes marked as killed              = 0
20160114:14:33:43:005980 gpinitsystem:h93:wslu-[INFO]:-Total processes marked as failed              = 0
20160114:14:33:43:005980 gpinitsystem:h93:wslu-[INFO]:------------------------------------------------
20160114:14:33:43:005980 gpinitsystem:h93:wslu-[INFO]:-Deleting distributed backout files
20160114:14:33:43:005980 gpinitsystem:h93:wslu-[INFO]:-Removing back out file
20160114:14:33:43:005980 gpinitsystem:h93:wslu-[INFO]:-No errors generated from parallel processes
20160114:14:33:43:005980 gpinitsystem:h93:wslu-[INFO]:-Restarting the Greenplum instance in production mode
20160114:14:33:43:001932 gpstop:h93:wslu-[INFO]:-Starting gpstop with args: -a -i -m -d /home/wslu/gp/gpsql/data/master/gpseg-1
20160114:14:33:43:001932 gpstop:h93:wslu-[INFO]:-Gathering information and validating the environment...
20160114:14:33:43:001932 gpstop:h93:wslu-[INFO]:-Obtaining Greenplum Master catalog information
20160114:14:33:43:001932 gpstop:h93:wslu-[INFO]:-Obtaining Segment details from master...
20160114:14:33:43:001932 gpstop:h93:wslu-[INFO]:-Greenplum Version: 'postgres (Greenplum Database) 4.3.99.00 build dev'
20160114:14:33:43:001932 gpstop:h93:wslu-[INFO]:-There are 0 connections to the database
20160114:14:33:43:001932 gpstop:h93:wslu-[INFO]:-Commencing Master instance shutdown with mode='immediate'
20160114:14:33:43:001932 gpstop:h93:wslu-[INFO]:-Master host=h93
20160114:14:33:43:001932 gpstop:h93:wslu-[INFO]:-Commencing Master instance shutdown with mode=immediate
20160114:14:33:43:001932 gpstop:h93:wslu-[INFO]:-Master segment instance directory=/home/wslu/gp/gpsql/data/master/gpseg-1
20160114:14:33:44:001932 gpstop:h93:wslu-[INFO]:-Attempting forceful termination of any leftover master process
20160114:14:33:44:001932 gpstop:h93:wslu-[INFO]:-Terminating processes for segment /home/wslu/gp/gpsql/data/master/gpseg-1
20160114:14:33:45:002019 gpstart:h93:wslu-[INFO]:-Starting gpstart with args: -a -d /home/wslu/gp/gpsql/data/master/gpseg-1
20160114:14:33:45:002019 gpstart:h93:wslu-[INFO]:-Gathering information and validating the environment...
20160114:14:33:45:002019 gpstart:h93:wslu-[INFO]:-Greenplum Binary Version: 'postgres (Greenplum Database) 4.3.99.00 build dev'
20160114:14:33:45:002019 gpstart:h93:wslu-[INFO]:-Greenplum Catalog Version: '300701081'
20160114:14:33:45:002019 gpstart:h93:wslu-[INFO]:-Starting Master instance in admin mode
20160114:14:33:46:002019 gpstart:h93:wslu-[INFO]:-Obtaining Greenplum Master catalog information
20160114:14:33:46:002019 gpstart:h93:wslu-[INFO]:-Obtaining Segment details from master...
20160114:14:33:46:002019 gpstart:h93:wslu-[INFO]:-Setting new master era
20160114:14:33:46:002019 gpstart:h93:wslu-[INFO]:-Master Started...
20160114:14:33:46:002019 gpstart:h93:wslu-[INFO]:-Shutting down master
20160114:14:33:47:002019 gpstart:h93:wslu-[INFO]:-Commencing parallel primary and mirror segment instance startup, please wait...
........
20160114:14:33:55:002019 gpstart:h93:wslu-[INFO]:-Process results...
20160114:14:33:55:002019 gpstart:h93:wslu-[INFO]:-----------------------------------------------------
20160114:14:33:55:002019 gpstart:h93:wslu-[INFO]:-   Successful segment starts                                            = 8
20160114:14:33:55:002019 gpstart:h93:wslu-[INFO]:-   Failed segment starts                                                = 0
20160114:14:33:55:002019 gpstart:h93:wslu-[INFO]:-   Skipped segment starts (segments are marked down in configuration)   = 0
20160114:14:33:55:002019 gpstart:h93:wslu-[INFO]:-----------------------------------------------------
20160114:14:33:55:002019 gpstart:h93:wslu-[INFO]:-
20160114:14:33:55:002019 gpstart:h93:wslu-[INFO]:-Successfully started 8 of 8 segment instances
20160114:14:33:55:002019 gpstart:h93:wslu-[INFO]:-----------------------------------------------------
20160114:14:33:55:002019 gpstart:h93:wslu-[INFO]:-Starting Master instance h93 directory /home/wslu/gp/gpsql/data/master/gpseg-1
20160114:14:33:56:002019 gpstart:h93:wslu-[INFO]:-Command pg_ctl reports Master h93 instance active
20160114:14:33:56:002019 gpstart:h93:wslu-[INFO]:-No standby master configured.  skipping...
20160114:14:33:56:002019 gpstart:h93:wslu-[INFO]:-Database successfully started
20160114:14:33:59:005980 gpinitsystem:h93:wslu-[INFO]:-Completed restart of Greenplum instance in production mode
20160114:14:33:59:005980 gpinitsystem:h93:wslu-[INFO]:-Loading gp_toolkit...
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-Scanning utility log file for any warning messages
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-Log file scan check passed
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-Greenplum Database instance successfully created
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-------------------------------------------------------
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-To complete the environment configuration, please
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-update wslu .bashrc file with the following
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-1. Ensure that the greenplum_path.sh file is sourced
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-2. Add "export MASTER_DATA_DIRECTORY=/home/wslu/gp/gpsql/data/master/gpseg-1"
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-   to access the Greenplum scripts for this instance:
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-   or, use -d /home/wslu/gp/gpsql/data/master/gpseg-1 option for the Greenplum scripts
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-   Example gpstate -d /home/wslu/gp/gpsql/data/master/gpseg-1
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-Script log file = /home/wslu/gpAdminLogs/gpinitsystem_20160114.log
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-To remove instance, run gpdeletesystem utility
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-To initialize a Standby Master Segment for this Greenplum instance
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-Review options for gpinitstandby
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-------------------------------------------------------
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-The Master /home/wslu/gp/gpsql/data/master/gpseg-1/pg_hba.conf post gpinitsystem
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-has been configured to allow all hosts within this new
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-array to intercommunicate. Any hosts external to this
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-new array must be explicitly added to this file
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-Refer to the Greenplum Admin support guide which is
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-located in the /home/wslu/gp/gpsql/docs directory
20160114:14:34:02:005980 gpinitsystem:h93:wslu-[INFO]:-------------------------------------------------------
```

5. 查看目录结构：
```bash
[wslu@h93 gpsql]$ ls data
master  mirror  primary
[wslu@h93 gpsql]$ ls data/master/
gpseg-1
[wslu@h93 gpsql]$ ls data/mirror/
gpseg2  gpseg3
[wslu@h93 gpsql]$ ls data/primary/
gpseg0  gpseg1
[wslu@h93 gpsql]$

[wslu@h94 gpsql]$ ls data/
master  mirror  primary
[wslu@h94 gpsql]$ ls data/master/
[wslu@h94 gpsql]$ ls data/primary/
gpseg2  gpseg3
[wslu@h94 gpsql]$ ls data/mirror/
gpseg0  gpseg1
[wslu@h94 gpsql]$
```

6. 在 h94 初始化备 master（主备 master 必须在不同主机，如果要配置单机多节点，则不能配置备 master。这是因为目前主备 master 必须在相同目录，所以必然不同主机。如果端口不是5432，那么需要指定PGPORT）：
```verilog
[wslu@h93 gpsql]$ PGPORT=5432 PGDATABASE=postgres gpinitstandby -s h94
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:-Validating environment and parameters for standby initialization...
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:-Checking for filespace directory /home/wslu/gp/gpsql/data/master/gpseg-1 on h94
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:------------------------------------------------------
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:-Greenplum standby master initialization parameters
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:------------------------------------------------------
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:-Greenplum master hostname               = h93
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:-Greenplum master data directory         = /home/wslu/gp/gpsql/data/master/gpseg-1
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:-Greenplum master port                   = 5432
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:-Greenplum standby master hostname       = h94
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:-Greenplum standby master port           = 5432
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:-Greenplum standby master data directory = /home/wslu/gp/gpsql/data/master/gpseg-1
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:-Greenplum update system catalog         = On
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:------------------------------------------------------
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:- Filespace locations
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:------------------------------------------------------
20160114:14:40:47:003933 gpinitstandby:h93:wslu-[INFO]:-pg_system -> /home/wslu/gp/gpsql/data/master/gpseg-1
Do you want to continue with standby master initialization? Yy|Nn (default=N):
> y
20160114:14:40:53:003933 gpinitstandby:h93:wslu-[INFO]:-Syncing Greenplum Database extensions to standby
20160114:14:40:53:003933 gpinitstandby:h93:wslu-[INFO]:-The packages on h94 are consistent.
20160114:14:40:53:003933 gpinitstandby:h93:wslu-[INFO]:-Adding standby master to catalog...
20160114:14:40:53:003933 gpinitstandby:h93:wslu-[INFO]:-Database catalog updated successfully.
20160114:14:40:54:003933 gpinitstandby:h93:wslu-[INFO]:-Updating pg_hba.conf file...
20160114:14:41:00:003933 gpinitstandby:h93:wslu-[INFO]:-pg_hba.conf files updated successfully.
20160114:14:41:09:003933 gpinitstandby:h93:wslu-[INFO]:-Updating filespace flat files...
20160114:14:41:09:003933 gpinitstandby:h93:wslu-[INFO]:-Filespace flat file updated successfully.
20160114:14:41:10:003933 gpinitstandby:h93:wslu-[INFO]:-Starting standby master
20160114:14:41:10:003933 gpinitstandby:h93:wslu-[INFO]:-Checking if standby master is running on host: h94  in directory: /home/wslu/gp/gpsql/data/master/gpseg-1
20160114:14:41:11:003933 gpinitstandby:h93:wslu-[INFO]:-Cleaning up pg_hba.conf backup files...
20160114:14:41:17:003933 gpinitstandby:h93:wslu-[INFO]:-Backup files of pg_hba.conf cleaned up successfully.
20160114:14:41:17:003933 gpinitstandby:h93:wslu-[INFO]:-Successfully created standby master on h94
```

7. 此时，h94的data/master目录就不为空了：
```bash
$ [wslu@h94 gpsql]$ ls data/master/
gpseg-1
```

## 1.10. 测试

```sql
[wslu@h93 gpsql]$ psql -p 5432 postgres
psql (8.3devel)
Type "help" for help.

postgres=#
postgres=#
postgres=# \db
        List of tablespaces
    Name    | Owner | Filespae Name
------------+-------+---------------
 pg_default | wslu  | pg_system
 pg_global  | wslu  | pg_system
(2 rows)
```

至此，集群完成了初始化。

## 1.11. 补充：如何将所有节点部署在一台主机？

如果要将所有节点配置在一台主机，比如：在 h93 配置2个主 segment、2个镜像 segment、1个 master，只需要把`hostfile_config`中的 h94 删掉，然后在 h93 删除 `data/primary，data/mirror，data/master` 目录下的内容，重新初始化即可。

# 2. GreenPlum 常用指令

**说明：** 每次使用集群的任何指令前，必须执行：

```bash
$ source greenplum-path.sh
$ exportMASTER_DATA_DIRECTORY=/home/wslu/gp/gpsql/data/master/gpseg-1
```

下文不再赘述。

## 2.1. 启动集群

手动启动集群：

```bash
$ gpstart –a
```

## 2.2. 停止集群

```bash
$ gpstop –a
```

## 2.3. 重启集群

```bash
$ gpstop –a –r
```

## 2.4. 查看集群状态

```bash
$ gpstate –m | -e
```

## 2.5. reload 配置文件

在不停止集群情况下，若配置文件发生变更，reload配置文件：
```bash
$ gpstop –u
```

## 2.6. 维护模式下启动 master

仅仅启动 master 来执行维护管理任务，不会影响 segment 中的数据。例如，在维护模式下你可以仅连接 master 实例的数据库并且编辑系统表设置。

1. 以维护模式启动 master：
```bash
$ gpstart –m
```

2. 维护模式下连接 master 来维护系统表。例如：
```bash
$ PGOPTIONS='-c gp_session_role=utility' psql template1
```

3. 完成管理任务后，使 master 关闭工具模式。然后，重启进入正常模式：
```bash
$ gpstop -m
```

## 2.7. 访问数据库

可以使用 psql 连接集群：

```sql
 [wslu@h93 gpsql]$ psql -p 5432 postgres
psql (8.3devel)
Type "help" for help.

postgres=#
```

## 2.8. GUC 参数配置

**使用 gpconfig 设置 guc 参数：**

```bash
$ gpconfig -c gp_vmem_protect_limit -v4096MB
```

gpconfig 可以设置 master 和所有 segment 的 guc 参数，也可以使用 `--masteronly` 参数只设置 master 的参数。设置完 guc 参数后需要根据 guc 参数类型决定重启集群或 reload 配置文件。

**显示guc参数：**

```bash
$ psql –c ‘showstatement_mem;’ 或 gpconfig –show statement_mem
$ psql –c ‘show all;’ 或 gpconfig –l
```

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




