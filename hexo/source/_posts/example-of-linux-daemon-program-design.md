---
title: 程序人生 | Linux Daemon 程序设计示例
date: 2014-08-08 17:55:32
categories:
- Linux
tags:
- C语言
- Linux
- shell
- daemon
toc: true
---

<!-- more -->

>**本文首发于 2014-08-08 17:55:32**

# 概念

daemon 程序，又称为守护进程，通常在系统后台长时间运行，由于没有控制终端而无法与前台交互。daemon程序一般作为系统服务使用，Linux系统中运行着很多这样的守护进程，如 iptables，nfs，ypbind，dhcpd 等。

# daemon 程序设计步骤

1. 程序运行后调用fork，并让父进程退出。子进程获得一个新的进程ID，但继承了父进程的进程组ID。
2. 调用setsid创建一个新的session，使自己成为新session和新进程组的leader，并使进程没有控制终端(tty)。
3. 设置文件创建mask为0，避免创建文件时权限的影响。
4. 关闭不需要的打开文件描述符。因为 daemon 程序在后台执行，不需要于终端交互，通常就关闭STDIN、STDOUT和STDERR。其它根据实际情况处理。
5. daemon 无法输出信息，可以使用SYSLOG或自己的日志系统进行日志处理。（可选）
6. 编写管理 daemon 的SHELL脚本，使用service对 daemon 进行管理和监控。（可选）

# 示例

## daemon 程序源码

```cpp
//这里使用自己的日志系统，当然也可以使用SYSLOG。
#define LOGBUFSZ 256     /*log buffer size*/
#define LOGFILE  "/var/log/wsiod.log"  /*log filename*/
int wsio_logit(char * func, char *msg, ...)
{
        va_list args;
        char prtbuf[LOGBUFSZ];
        int save_errno;
        struct tm *tm;
        time_t current_time;
        int fd_log;

        save_errno = errno;
        va_start (args, msg);
        (void) time (¤t_time);            /* Get current time */
        tm = localtime (¤t_time);
        sprintf (prtbuf, "%02d/%02d %02d:%02d:%02d %s ", tm->tm_mon+1,
                    tm->tm_mday, tm->tm_hour, tm->tm_min, tm->tm_sec, func);
        vsprintf (prtbuf+strlen(prtbuf), msg, args);
        va_end (args);
        fd_log = open (LOGFILE, O_WRONLY | O_CREAT | O_APPEND, 0664);
        write (fd_log, prtbuf, strlen(prtbuf));
        close (fd_log);
        errno = save_errno;
        return 0;
}

int init_daemon(void)
{
  pid_t pid;
  int i;

  /* parent exits , child continues */
  if((pid = fork()) < 0)
    return -1;
  else if(pid != 0)
    exit(0);

  setsid(); /* become session leader */

  for(i=0;i<= 2;++i) /* close STDOUT, STDIN, STDERR, */
    close(i);

  umask(0); /* clear file mode creation mask */
  return 0;
}

void sig_term(int signo)
{
  if(signo == SIGTERM)  /* catched signal sent by kill(1) command */
  {
     wsio_logit("", "wsiod stopped/n");
     exit(0);
　}
}

/* main program of daemon */
int main(void)
{
if(init_daemon() == -1){
printf("can't fork self/n");
exit(0);
  }
  wsio_logit("", "wsiod started/n");
  signal(SIGTERM, sig_term); /* arrange to catch the signal */

  while (1) {
    // Do what you want here
    … …
  }
  exit(0);
}
```

## daemon 程序管理脚本

daemon 程序可以使用 service 工具进行管理，包括启动、停止、查看状态等，但前题是需要编写一个如下的简单SHELL脚本，比如 `/etc/init.d/wsiod` ：
```bash
#!/bin/sh
#
# wsiod         This shell script takes care of starting and stopping wsiod.
#
# chkconfig: 35 65 35
# description: wsiod is web servce I/O server, which is used to access files on remote hosts.

# Source function library.
. /etc/rc.d/init.d/functions

# Source networking configuration.
. /etc/sysconfig/network

# Check that networking is up.
[ ${NETWORKING} = "no" ] && exit 0

RETVAL=0
prog="wsiod"
WSIOARGS="-h $HOSTNAME -p 80 -t STANDALONE -k -c -d"
start() {
        # Start daemons.
        echo -n $"Starting $prog: "
        daemon /usr/local/bin/wsiod ${WSIOARGS}
        RETVAL=$?
        echo
        [ $RETVAL -eq 0 ] && touch /var/lock/subsys/wsiod
        return $RETVAL
}
stop() {
        # Stop daemons.
        echo -n $"Shutting down $prog: "
        killproc wsiod
        RETVAL=$?
        echo
        [ $RETVAL -eq 0 ] && rm -f /var/lock/subsys/wsiod
        return $RETVAL
}

# See how we were called.
case "$1" in
  start)
        start
        ;;
  stop)
        stop
        ;;
  restart|reload)
        stop
        start
        RETVAL=$?
        ;;
  status)
        status wsiod
        RETVAL=$?
        ;;
  *)
        echo $"Usage: $0 {start|stop|restart|status}"
        exit 1
esac

exit $RETVAL
```

## daemon 程序指令

由上述脚本可知，该 daemon 程序支持的指令有 start|stop|restart|reload|status ，以启动 daemon 程序为例，指令为：
```bash
/etc/init.d/wsiod start
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


