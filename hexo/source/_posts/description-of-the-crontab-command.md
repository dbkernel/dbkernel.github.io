---
title: 实用工具 | Linux 定时任务 crontab 命令详解
date: 2016-11-23 10:24:45
categories:
- Linux
tags:
- Linux
- crontab
toc: true
---

<!-- more -->

>**本文首发于 2016-11-23 10:24:45**

## 概述

Linux 下的任务调度分为两类：**系统任务调度**和**用户任务调度**。Linux 系统任务是由 `cron (crond)` 这个系统服务来控制的，这个系统服务是默认启动的。用户自己设置的计划任务则使用 `crontab` 命令。


## cron 配置文件

在 Ubuntu/Debian 中，配置文件路径为 `/etc/crontab`（CentOS也类似），其内容为：
```bash
# /etc/crontab: system-wide crontab
# Unlike any other crontab you don't have to run the `crontab'
# command to install the new version when you edit this file
# and files in /etc/cron.d. These files also have username fields,
# that none of the other crontabs do.

SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Example of job definition:
# .---------------- minute (0 - 59)
# |  .------------- hour (0 - 23)
# |  |  .---------- day of month (1 - 31)
# |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
# |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
# |  |  |  |  |
# *  *  *  *  * user-name command to be executed
17 *	* * *	root    cd / && run-parts --report /etc/cron.hourly
25 6	* * *	root	test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.daily )
47 6	* * 7	root	test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.weekly )
52 6	1 * *	root	test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.monthly )
#
```

- `SHELL` 环境变量用于指定系统要使用的shell，此处为`/bin/sh`。
- `PATH` 环境变量指定了系统执行命令的路径。
- 也可以添加`MAILTO`变量，如果指定，则表示 crond 的任务执行信息将通过电子邮件发送给指定的用户。
- 其他部分在后文详细讲述。

用户定期要执行的工作，比如用户数据备份、定时邮件提醒等，都可以使用 crontab 工具来定制自己的计划任务。所有`非root用户`定义的 crontab 文件都被保存在 `/var/spool/cron` 目录中，其文件名与用户名一致。
```bash
ls /var/spool/cron/crontabs/admin
```

除此之外，还有两个文件`/etc/cron.deny`和`/etc/cron.allow`，前者中可列出不允许哪些用户使用 crontab 命令，后者中可列出允许哪些用户使用 crontab 命令。

## crontab 文件含义

用户所建立的crontab文件中，每一行都代表一项任务，每行的每个字段代表一项设置，它的格式共分为六个字段，前五段是时间设定段，第六段是要执行的命令段，格式如下：
```bash
minute hour day month week command
```

各字段含义如下：
- minute：表示分钟，可以是从0到59之间的任何整数。
- hour：表示小时，可以是从0到23之间的任何整数。
- day：表示日期，可以是从1到31之间的任何整数。
- month：表示月份，可以是从1到12之间的任何整数。
- week：表示星期几，可以是从0到7之间的任何整数，这里的0或7代表星期日。
- command：要执行的命令，可以是系统命令，也可以是自己编写的脚本文件。

在以上各个字段中，还可以使用以下特殊字符：
- `星号(*)`：代表所有可能的值，例如 month 字段如果是星号，则表示在满足其它字段的制约条件后每月都执行该命令操作。
- `逗号(,)`：可以用逗号隔开的值指定一个列表范围，例如：`1,2,5,7,8,9` 。
- `中杠(-)`：可以用整数之间的中杠表示一个整数范围，例如：`2-6` 表示`2,3,4,5,6` 。
- `正斜线(/)`：可以用正斜线指定时间的间隔频率，例如：`0-23/2`表示每两小时执行一次。同时正斜线可以和星号一起使用，例如：`*/10`，如果用在minute字段，表示**每十分钟执行一次**。


## crontab命令详解

**命令格式：**
```bash
usage:	crontab [-u user] file
	crontab [ -u user ] [ -i ] { -e | -l | -r }
		(default operation is replace, per 1003.2)
	-e	(edit user's crontab)
	-l	(list user's crontab)
	-r	(delete user's crontab)
	-i	(prompt before deleting user's crontab)
```

- -u user：用于设定某个用户的crontab服务。
- file: file 为命令文件名，表示将 file 作为 crontab 的任务列表文件并载入 crontab ；如果在命令行中没有指定这个文件，crontab 命令将接受标准输入（键盘）上键入的命令，并将它们载入crontab 。
- -e：编辑某个用户的 crontab 文件内容，如不指定用户则表示当前用户。
- -l：显示某个用户的 crontab 文件内容，如不指定用户则表示当前用户。
- -r：从 /var/spool/cron 目录中删除某个用户的crontab文件，如不指定用户，则默认删除当前用户 crontab 文件。
- -i：在删除用户的 crontab 文件时给确认提示。

## crontab 注意事项

1. crontab有2种编辑方式：**直接编辑/etc/crontab文件**与**crontab –e**，其中`/etc/crontab`里的计划任务是**系统的计划任务**，而**用户的计划任务**需要通过`crontab –e`来编辑。
2. 每次编辑完某个用户的 cron 设置后，cron 自动在 /var/spool/cron 下生成一个与此用户同名的文件，此用户的 cron 信息都记录在这个文件中，`这个文件是不可以直接编辑的，只可以用 crontab -e 来编辑`。
3. crontab 中的 command 尽量使用绝对路径，否则会经常因为路径错误导致任务无法执行。
4. 新创建的 cron job 不会马上执行，至少要等2分钟才能执行，可重启 cron 来立即执行。
5. `%` 在crontab文件中表示`换行`，因此假如脚本或命令含有`%`，需要使用`\%`来进行转义。
6. `crontab -e`的默认编辑器是 nano ，如需使用 vim，可在`/etc/profile`或`~/.bashrc`中添加 `export EDITOR=vi` 来解决。


## crontab 配置示例

- 每分钟执行1次 command（因cron默认每1分钟扫描一次，因此全为`*`即可）：
```bash
* * * * * command
```

- 每小时的第3和第15分钟执行 command ：
```bash
3,15 * * * * command
```

- 每天上午8-11点的第3和15分钟执行 command ：
```bash
3,15 8-11 * * * command
```

- 每隔2天的上午8-11点的第3和15分钟执行 command ：
```bash
3,15 8-11 */2 * * command
```

- 每个星期一的上午8点到11点的第3和第15分钟执行 command ：
```bash
3,15 8-11 * * 1 command
```

- 每晚的21:30分重启 smb ：
```bash
30 21 * * * /etc/init.d/smb restart
```

- 每月1、10、22日的 4:45 重启 smb ：
```bash
45 4 1,10,22 * * /etc/init.d/smb restart
```

- 每周六、周日的 1:10 重启 smb ：
```bash
10 1 * * 6,0 /etc/init.d/smb restart
```

- 每天 18:00 至 23:00 之间每隔30分钟重启 smb ：
```bash
0,30 18-23 * * * /etc/init.d/smb restart
```

- 每隔1小时重启 smb ：
```bash
* */1 * * * /etc/init.d/smb restart
```

- 晚上23点到早上7点之间，每隔1小时重启 smb ：
```bash
* 23-7/1 * * * /etc/init.d/smb restart
```

- 每月的4号与每周一到周三的11点重启 smb ：
```bash
0 11 4 * mon-wed /etc/init.d/smb restart
```

- 每小时执行`/etc/cron.hourly`目录内的脚本：
```bash
0 1 * * * root run-parts /etc/cron.hourly
```

----

欢迎关注我的微信公众号【数据库内核】：分享主流开源数据库和存储引擎相关技术。

<img src="https://dbkernel-1306518848.cos.ap-beijing.myqcloud.com/wechat/my-wechat-official-account.png" width="400" height="400" alt="欢迎关注公众号数据库内核" align="center"/>

| 标题                 | 网址                                                  |
| -------------------- | ----------------------------------------------------- |
| GitHub               | https://dbkernel.github.io                            |
| 知乎                 | https://www.zhihu.com/people/dbkernel/posts           |
| 思否（SegmentFault） | https://segmentfault.com/u/dbkernel                   |
| 掘金                 | https://juejin.im/user/5e9d3ed251882538083fed1f/posts |
| 开源中国（oschina）  | https://my.oschina.net/dbkernel                       |
| 博客园（cnblogs）    | https://www.cnblogs.com/dbkernel                      |

