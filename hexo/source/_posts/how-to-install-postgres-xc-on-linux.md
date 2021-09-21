---
title: 最佳实践 | 源码编译安装配置 Postgres-XC 集群并用 pg_basebackup 配置 Datanode 热备
date: 2016-03-15 19:56:52
categories:
- Postgres-X2
tags:
- Postgres-X2
- Postgres-XC
- PostgreSQL
- Linux
toc: true
---

<!-- more -->



>**本文首发于 2016-03-15 19:56:52**

注意：本篇文章成文时 Postgres-XC 还未改名为 Postgres-X2 。

# 1. 下载源码

```bash
git clone git@github.com:postgres-x2/postgres-x2.git
```

# 2. 安装依赖

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

# 3. 编译安装

```bash
$ cd postgres-x2
$ ./configure --prefix=/home/wslu/pgsql --enable-debug #其中--prefix指定编绎完成后将要安装的路径，必须使用全路径，wslu为使用者。
$ make #执行编绎
$ make install #执行安装
```

# 4. 初始化、启动

## 4.1. 初始化 GTM

```bash
$ cd /home/wslu/pgsql

#设置PTAH变量
$ export PATH=/home/user/pgsql/bin:$PATH
#使用初始化gtm命令initgtm
$ ./bin/initgtm -Z gtm -D data/gtm/
```

## 4.2. 初始化数据库节点

初始化所有数据库节点（CO、DN）：

```bash
#使用初始化db命令initdb
$ ./bin/initdb -U wslu -A trust --locale=C -D data/co1   # -U 使用者 -D 数据目录/节点
$ ./bin/initdb -U wslu -A trust --locale=C -D data/co2
$ ./bin/initdb -U wslu -A trust --locale=C -D data/dn1
$ ./bin/initdb -U wslu -A trust --locale=C -D data/dn2
$ ./bin/initdb -U wslu -A trust --locale=C -D data/dn3
```

## 4.3. 编辑配置文件

编辑 data/co1/postgresql.conf：
```ini
# 默认值
gtm_port = 6666
# pgxc_node_name 不能重复
pgxc_node_name = co1
```

编辑 data/co2/postgresql.conf：
```ini
gtm_port = 6666
pgxc_node_name = co2
```

编辑 data/dn1/postgresql.conf：
```ini
gtm_port = 6666
pgxc_node_name = dn1
```

编辑 data/dn2/postgresql.conf：
```ini
gtm_port = 6666
pgxc_node_name = dn2
```

编辑 data/dn2/postgresql.conf：
```ini
gtm_port = 6666
pgxc_node_name = dn3
```

## 4.4. 启动服务

依次启动 gtm、datanode、coordinator：

```bash
# ./bin/gtm_ctl start -S gtm -D data/gtm -l data/gtm/gtm.log  //启动gtm（由于切换为相对路径后找不到对应的文件夹，所以创建日志会失败）
$ ./bin/gtm_ctl start -Z gtm -D data/gtm -l gtm.log  //启动gtm
# vim data/gtm/gtm.log # 使用日志查看gtm是否启动

$ ./bin/pg_ctl start -Z datanode -D data/dn1 -l data/dn1/postgresql.log  -o "-p 24071"   //启动datanode dn1， DN1_PORT=24071   根据需要自由设置
# vim data/dn1/postgresql.log # 同样使用日志查看是否启动

$ ./bin/pg_ctl start -Z datanode -D data/dn2 -l data/dn2/postgresql.log  -o "-p 24072"  //启动 dn2， DN2_PORT=24072
$ ./bin/pg_ctl start -Z datanode -D data/dn3 -l data/dn3/postgresql.log  -o "-p 24073"  //启动 dn3， DN3_PORT=24073

$ ./bin/pg_ctl start -Z coordinator -D data/co1 -l data/co1/postgresql.log  -o "-p 24076"   //启动 coordinator co1， CO1_PORT=24076
$ ./bin/pg_ctl start -Z coordinator -D data/co2 -l data/co2/postgresql.log  -o "-p 24077"   //启动 co2， CO2_PORT= 24077
```

# 5. 配置集群节点

指定动态库位置：

```bash
$ export LD_LIBRARY_PATH=/home/wslu/pgsql/lib:$LD_LIBRARY_PATH
```

配置集群节点：

```sql
# 进入co1创建节点，co1_port=24076
$ ./bin/psql -p 24076 postgres postgres

 CREATE NODE dn1 WITH (HOST = 'localhost', type = 'datanode', PORT = 24071, id = 1, content = 1); //在协调器上注册节点，各端口号与上面一致
 CREATE NODE dn2 WITH (HOST = 'localhost', type = 'datanode', PORT = 24072, id = 2, content = 2);
 CREATE NODE dn3 WITH (HOST = 'localhost', type = 'datanode', PORT = 24073, id = 3, content = 3);
 CREATE NODE co1 WITH (HOST = 'localhost', type = 'coordinator', PORT = 24076, id = 4, content = 4);
 CREATE NODE co2 WITH (HOST = 'localhost', type = 'coordinator', PORT = 24077, id = 5, content = 5);
 SELECT pgxc_pool_reload();
```

至此，集群配置完成。

# 6. 常见操作

## 6.1. 停止集群

```bash
$ ./bin/pg_ctl stop -D data/co1 -m immediate
$ ./bin/pg_ctl stop -D data/co2 -m immediate
$ ./bin/pg_ctl stop -D data/dn1 -m immediate
$ ./bin/pg_ctl stop -D data/dn2 -m immediate
$ ./bin/pg_ctl stop -D data/dn3 -m immediate
$ ./bin/gtm_ctl stop -Z gtm -D data/gtm
$ rm -f data/gtm/register.node
```

## 6.2. 启动集群

```bash
$ ./bin/gtm_ctl start -Z gtm -D data/gtm -p ./bin -l data/gtm/gtm.log
$ ./bin/pg_ctl start -l data/dn1/postgresql.log -Z datanode -D data/dn1 -o "-p 24071"
$ ./bin/pg_ctl start -l data/dn2/postgresql.log -Z datanode -D data/dn2 -o "-p 24072"
$ ./bin/pg_ctl start -l data/dn3/postgresql.log -Z datanode -D data/dn3 -o "-p 24073"
$ ./bin/pg_ctl start -l data/co1/postgresql.log -Z coordinator -D data/co1 -o "-p 24076"
$ ./bin/pg_ctl start -l data/co2/postgresql.log -Z coordinator -D data/co2 -o "-p 24077"
```

## 6.3. 清理数据

如需清除数据，请先停止服务器集群，然后清除数据存储目录:

```bash
$ ./bin/pg_ctl stop -D data/co1 -m immediate
$ ./bin/pg_ctl stop -D data/co2 -m immediate
$ ./bin/pg_ctl stop -D data/dn1 -m immediate
$ ./bin/pg_ctl stop -D data/dn2 -m immediate
$ ./bin/pg_ctl stop -D data/dn3 -m immediate
$ ./bin/gtm_ctl stop -Z gtm -D data/gtm
$ rm -f data/gtm/register.node
$ rm -rf data
```

# 7. 配置 Datanode 热备

## 7.1. 修改所有 CO 和 DN 的 pg_hba.conf

将下面两行的注释去掉：

```bash
$ vi data/co1/pg_hba.conf
host    replication     wslu        127.0.0.1/32            trust
host    replication     wslu        ::1/128                 trust

$ vi data/co2/pg_hba.conf
host    replication     wslu        127.0.0.1/32            trust
host    replication     wslu        ::1/128                 trust

$ vi data/dn1/pg_hba.conf
host    replication     wslu        127.0.0.1/32            trust
host    replication     wslu        ::1/128                 trust

$ vi data/dn2/pg_hba.conf
host    replication     wslu        127.0.0.1/32            trust
host    replication     wslu        ::1/128                 trust

$ vi data/dn3/pg_hba.conf
host    replication     wslu        127.0.0.1/32            trust
host    replication     wslu        ::1/128                 trust
```

此处为了测试方便，将校验方式设为 trust；实际生产中要改为 md5，即根据账户密码验证。

## 7.2. 修改所有 CO 和 DN 的 postgresql.conf

添加以下内容：

```bash
$ vi data/co1/postgresql.conf
listen_addresses = '*'
log_line_prefix = '%t:%r:%u@%d:[%p]: '
#logging_collector = on
port = 24076
wal_level = archive

$ vi data/co2/postgresql.conf
listen_addresses = '*'
log_line_prefix = '%t:%r:%u@%d:[%p]: '
#logging_collector = on
port = 24077
wal_level = archive

$ vi data/dn1/postgresql.conf
hot_standby = on
#logging_collector = on
listen_addresses = '*'
log_line_prefix = '%t:%r:%u@%d:[%p]: '
wal_keep_segments = 10
wal_level = hot_standby
max_wal_senders = 5
include_if_exists = 'synchronous_standby_names.conf'
port = 24071

$ vi data/dn2/postgresql.conf
hot_standby = on
#logging_collector = on
listen_addresses = '*'
log_line_prefix = '%t:%r:%u@%d:[%p]: '
wal_keep_segments = 10
wal_level = hot_standby
max_wal_senders = 5
include_if_exists = 'synchronous_standby_names.conf'
port = 24072

$ vi data/dn3/postgresql.conf
hot_standby = on
#logging_collector = on
listen_addresses = '*'
log_line_prefix = '%t:%r:%u@%d:[%p]: '
wal_keep_segments = 10
wal_level = hot_standby
max_wal_senders = 5
include_if_exists = 'synchronous_standby_names.conf'
port = 24073
```

## 7.3. 创建备 DN

在数据库集群开启的前提下执行下列指令，以创建备 Datanode 目录：

```bash
$ pg_basebackup -D data/dn1s -Fp -Xs -v -P -h localhost -p 24071 -U wslu
$ pg_basebackup -D data/dn2s -Fp -Xs -v -P -h localhost -p 24072 -U wslu
$ pg_basebackup -D data/dn3s -Fp -Xs -v -P -h localhost -p 24073 -U wslu
```

## 7.4. 在所有备 DN 新建 recovery.conf

```bash
$ vi dn1s/recovery.conf
standby_mode = 'on'
primary_conninfo = 'user=wslu host=localhost port=24071 sslmode=disable sslcompression=1'

$ vi dn2s/recovery.conf
standby_mode = 'on'
primary_conninfo = 'user=wslu host=localhost port=24072 sslmode=disable sslcompression=1'

$ vi dn3s/recovery.conf
standby_mode = 'on'
primary_conninfo = 'user=wslu host=localhost port=24073 sslmode=disable sslcompression=1'
```

## 7.5. 在所有主 DN 新建 synchronous_standby_names.conf

```bash
vi data/dn1/synchronous_standby_names.conf
synchronous_standby_names='*'
```

## 7.6. 在所有 CO 添加备 DN 节点

这里以 co1 为例，co2 也要执行同样操作（ 对于支持热备的其他 pg 商用数据库，类型不是 datanode 而是 standby）：

```sql
$ ./bin/psql -p 24076 postgres postgres    //进入co1创建节点，co1_port=24076
 CREATE NODE dn1s WITH (HOST = 'localhost', type = 'datanode', PORT = 34071, id = 6, content = 1); //在协调器上注册节点，各端口号与上面一致
 CREATE NODE dn2s WITH (HOST = 'localhost', type = 'datanode', PORT = 34072, id = 7, content = 2);
 CREATE NODE dn3s WITH (HOST = 'localhost', type = 'datanode', PORT = 34073, id = 8, content = 3);
```

## 7.7. 启动所有备 DN 服务

```bash
./bin/pg_ctl start -D data/dn1s -l data/dn1s/postgresql.log  -o "-p 34071"
./bin/pg_ctl start -D data/dn2s -l data/dn2s/postgresql.log  -o "-p 34072"
./bin/pg_ctl start -D data/dn3s -l data/dn3s/postgresql.log  -o "-p 34073"
```

相应的，停止所有备 DN 节点服务的指令为：
```bash
./bin/pg_ctl stop -D data/dn1s -m immediate
./bin/pg_ctl stop -D data/dn2s -m immediate
./bin/pg_ctl stop -D data/dn3s -m immediate
```

# 8. Q&A
## 8.1. 如何提升备 DN 为主 DN

我并未实现成功，但参照其他 PostgreSQL 的分布式数据库，步骤如下：

1. 杀掉主 DN 进程，在备 DN 的目录下创建一个触发文件（例如：promote）文件。
2. 通过 `kill -SIGUSR1 备DN进程号` 指令给备 DN 的 postmaster 进程发送一个 SIGUSR1 信号。
3. 在主 CO 执行类似 `alter node dn1s with(promote);` 的指令。
4. 退出 psql，再重新连入 psql。
5. 此时，备 DN 就作为主 DN 运行了，可执行 DDL、DML 等所有操作。


## 8.2. 当备 DN 挂掉时，如何关闭主备 DN 之间的数据同步

也就是关闭 walsender 和 walreciever。

这就涉及到源码级别了，一般做两步：

1. 将主 DN 状态改为 `OutSync`（别的数据库的做法）。
2. 在代码中将 `SyncRepStandbyNames` 设为 `""`。


## 补充

本教程关于配置备 DN 的描述只能对各个 DN 的数据做备份，并未成功实现某个 DN 挂掉了自动切换到备 DN。

另外，我并未在 Postgres-XC（现在 github 改名为了 Postgres-X2）源码的回归测试中看到如何在 pgxc_nodes 系统表创建备 DN 节点。

不过，GreenPlum（以 PostgreSQL 为基础开发的分布式数据库）有此功能，可做参考。

----

欢迎关注我的微信公众号【MySQL数据库技术】。

<img src="https://dbkernel-1306518848.cos.ap-beijing.myqcloud.com/wechat/my-wechat-official-account.png" width="400" height="400" alt="MySQL数据库技术" align="center"/>


| 标题                 | 网址                                                  |
| -------------------- | ----------------------------------------------------- |
| GitHub               | https://dbkernel.github.io                            |
| 知乎                 | https://www.zhihu.com/people/dbkernel/posts           |
| 思否（SegmentFault） | https://segmentfault.com/u/dbkernel                   |
| 掘金                 | https://juejin.im/user/5e9d3ed251882538083fed1f/posts |
| 开源中国（oschina）  | https://my.oschina.net/dbkernel                       |
| 博客园（cnblogs）    | https://www.cnblogs.com/dbkernel                      |


