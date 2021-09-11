---
title: 程序人生 | unix 网络编程之 getaddrinfo 函数详解及使用举例
date: 2015-01-03 21:04:36
categories:
- C语言
tags:
- C语言
- 网络编程
- APUE
toc: true
---

<!-- more -->


# 概述

IPv4 中使用 `gethostbyname()` 函数完成**主机名到地址解析**，这个函数仅仅支持 IPv4 ，且不允许调用者指定所需地址类型的任何信息，返回的结构只包含了用于存储 IPv4 地址的空间。

IPv6中引入了`getaddrinfo()`的新API，它是协议无关的，既可用于 IPv4 也可用于IPv6 。

`getaddrinfo`函数能够处理**名字到地址**以及**服务到端口**这两种转换，返回的是一个`addrinfo`的结构（列表）指针而不是一个地址清单。这些`addrinfo`结构随后可由socket函数直接使用。

`getaddrinfo`函数把协议相关性安全隐藏在这个库函数内部。应用程序只要处理由getaddrinfo函数填写的套接口地址结构。该函数在 POSIX规范中定义了。

# 函数说明

**包含头文件：**

```cpp
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
```

**函数原型：**

```cpp
int getaddrinfo( const char *hostname, const char *service, const struct addrinfo *hints, struct addrinfo **result );
```

**参数说明：**

- `hostname`: 一个主机名或者地址串(IPv4 的点分十进制串或者 IPv6 的 16 进制串)。
- `service`：服务名可以是十进制的端口号，也可以是已定义的服务名称，如 ftp、http 等。
- `hints`：可以是一个空指针，也可以是一个指向某个 addrinfo 结构体的指针，调用者在这个结构中填入关于期望返回的信息类型的暗示。
- `result`：本函数通过 result 指针参数返回一个指向 addrinfo 结构体链表的指针。

**返回值：**

0：成功；非0：出错。

# 参数设置

在`getaddrinfo`函数之前通常需要对以下6个参数进行以下设置：`nodename、servname、hints的ai_flags、ai_family、ai_socktype、ai_protocol`。

在6项参数中，对函数影响最大的是`nodename，sername`和`hints.ai_flag`，而`ai_family`只是有地址为v4地址或v6地址的区别。`ai_protocol`一般为0不作改动。

**getaddrinfo在实际使用中的几种常用参数设置：**

一般情况下，client/server编程中，server端调用`bind`（如果面向连接的还需要`listen`）；client则无需调用`bind`函数，解析地址后直接`connect`（面向连接）或直接发送数据（无连接）。因此，比较常见的情况有：
1. 通常服务器端在调用`getaddrinfo`之前，`ai_flags`设置`AI_PASSIVE`，用于`bind`；主机名`nodename`通常会设置为NULL，返回通配地址`[::]`。
2. 客户端调用`getaddrinfo`时，`ai_flags`一般不设置`AI_PASSIVE`，但是主机名`nodename`和服务名`servname`（更愿意称之为端口）则应该不为空。
3. 当然，即使不设置`AI_PASSIVE`，取出的地址也并非不可以被bind，很多程序中`ai_flags`直接设置为0，即3个标志位都不设置，这种情况下只要hostname和servname设置的没有问题就可以正确bind。

上述情况只是简单的client/server中的使用，但实际在使用getaddrinfo和查阅国外开源代码的时候，曾遇到一些将servname（即端口）设为NULL的情况（当然，此时nodename必不为NULL，否则调用getaddrinfo会报错）。

# 使用须知

1）如果本函数返回成功，那么由result参数指向的变量已被填入一个指针，它指向的是由其中的`ai_next`成员串联起来的`addrinfo`结构链表。
```cpp
struct addrinfo
{ 　　　　　　　
	int ai_flags;
	int ai_family;
	int ai_socktype;
	int ai_protocol;
	size_t ai_addrlen;
	struct sockaddr *ai_addr; /* 我认为这个成员是这个函数最大的便利。 */
	char *ai_canonname;
	struct addrinfo *ai_next;
};
```

其中，sockaddr结构体为：
```cpp
在linux环境下，结构体struct sockaddr在/usr/include/linux/socket.h中定义，具体如下：
typedef unsigned short sa_family_t;
struct sockaddr {
        sa_family_t     sa_family;    /* address family, AF_xxx       */
        char            sa_data[14];    /* 14 bytes of protocol address */
}
```

而且，`sockaddr`一般要转换为`sockaddr_in`：
```cpp
struct sockaddr_in
{
　　short int sin_family;
　　unsigned short int sin_port;
    struct in_addr sin_addr;
    unsigned char sin_zero[8];
}
```

2）可以导致返回多个addrinfo结构的情形有以下2个：
>1. 如果与hostname参数关联的地址有多个，那么适用于所请求地址簇的每个地址都返回一个对应的结构。
>2. 如果service参数指定的服务支持多个套接口类型，那么每个套接口类型都可能返回一个对应的结构，具体取决于hints结构的ai_socktype成员。

举例来说：如果指定的服务既支持TCP也支持UDP，那么调用者可以把`hints`结构中的`ai_socktype`成员设置成`SOCK_DGRAM`，使得返回的仅仅是适用于数据报套接口的信息。

3）我们必须先分配一个hints结构，把它清零后填写需要的字段，再调用getaddrinfo，然后遍历一个链表逐个尝试每个返回地址。

4）**getaddrinfo解决了把主机名和服务名转换成套接口地址结构的问题**。

5）如果getaddrinfo出错，那么返回一个非0的错误值。输出出错信息，不要用perror，而应该用`gai_strerror`，该函数原型为：
```cpp
const char *gai_strerror( int error );
```
>该函数以`getaddrinfo`返回的非0错误值的名字和含义为他的唯一参数，返回一个指向对应的出错信息串的指针。

6）**由getaddrinfo返回的所有存储空间都是动态获取的，这些存储空间必须通过调用`freeaddrinfo`返回给系统**，该函数原型为：
```cpp
void freeaddrinfo( struct addrinfo *ai );
```
>`ai`参数应指向由`getaddrinfo`返回的第一个addrinfo结构。

这个链表中的所有结构以及它们指向的任何动态存储空间都被释放掉。

# 示例

## 1. 根据主机名获取IP地址

```cpp
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>

int main(int argc, char **argv)
{
    if (argc != 2) {
        printf("Usag: ./a.out hostname|ip\n");
        exit(1);
    }
    struct addrinfo hints;
    struct addrinfo *res, *cur;
    int ret;
    struct sockaddr_in *addr;
    char ipbuf[16];
	int port;

    memset(&hints, 0, sizeof(struct addrinfo));
    hints.ai_family = AF_INET; /* Allow IPv4 */
    hints.ai_flags = AI_PASSIVE; /* For wildcard IP address */
    hints.ai_protocol = 0; /* Any protocol */
    hints.ai_socktype = SOCK_DGRAM;
	ret = getaddrinfo(argv[1], NULL,&hints,&res);
    if (ret < 0) {
		fprintf(stderr, "%s\n", gai_strerror(ret));
        exit(1);
    }

    for (cur = res; cur != NULL; cur = cur->ai_next) {
        addr = (struct sockaddr_in *)cur->ai_addr;
        printf("ip: %s\n", inet_ntop(AF_INET, &addr->sin_addr, ipbuf, 16));
		printf("port: %d\n", inet_ntop(AF_INET, &addr->sin_port, (void *)&port, 2));
		//printf("port: %d\n", ntohs(addr->sin_port));

    }
    freeaddrinfo(res);
    exit(0);
}
```

## 2. 根据主机名和端口号获取地址信息

```cpp
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <fcntl.h>
#include <time.h>
#include <ctype.h>
#include <unistd.h>
#include <errno.h>
#include <sys/wait.h>
#include <signal.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/stat.h>
#include <netdb.h>
#include <sys/socket.h>
void main()
{
	struct addrinfo *ailist, *aip;
	struct addrinfo hint;
	struct sockaddr_in *sinp;
	char *hostname = "localhost";
	char buf[INET_ADDRSTRLEN];
	char *server = "6543"; /* 这是服务端口号 */
	const char *addr;
	int ilRc;
	hint.ai_family = AF_UNSPEC; /* hint 的限定设置 */
	hint.ai_socktype = 0; /* 这里可是设置 socket type . 比如 SOCK——DGRAM */
	hint.ai_flags = AI_PASSIVE; /* flags 的标志很多 。常用的有AI_CANONNAME; */
	hint.ai_protocol = 0; /* 设置协议 一般为0，默认 */
	hint.ai_addrlen = 0; /* 下面不可以设置，为0，或者为NULL */
	hint.ai_canonname = NULL;
	hint.ai_addr = NULL;
	hint.ai_next = NULL;
	ilRc = getaddrinfo(hostname, server, &hint, &ailist);
	if (ilRc < 0)
	{
		printf("str_error = %s\n", gai_strerror(errno));
		return;
	}

	/* 显示获取的信息 */
	for (aip = ailist; aip != NULL; aip = aip->ai_next)
	{
		sinp = (struct sockaddr_in *)aip->ai_addr;
		addr = inet_ntop(AF_INET, &sinp->sin_addr, buf, INET_ADDRSTRLEN);
		printf(" addr = %s, port = %d\n", addr?addr:"unknow ", ntohs(sinp->sin_port));
	}
}
```

## 3. 由内核分配随机端口（再也不担心端口被占了）

```cpp
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>

#define MAX_CONN_COUNT 10
 #define INVALID_SOCKET (~0)

int main(int argc, char **argv)
{
	int motionListenPort = 0;
	int motion_sock = 0;
	int	err;
	int	maxconn;
	char familyDesc[32];
	struct sockaddr_storage motion_sock_addr;
	socklen_t alen;
	struct addrinfo *addrs = NULL, *addr, hints;
	int ret;
	int tries = 0;

    memset(&hints, 0, sizeof(struct addrinfo));
    hints.ai_family = AF_INET; /* Allow IPv4 */
    hints.ai_flags = AI_PASSIVE; /* For wildcard IP address */
    hints.ai_protocol = 0; /* Any protocol */
    hints.ai_socktype = SOCK_STREAM;
	ret = getaddrinfo(NULL, "0", &hints, &addrs);
    if (ret < 0)
	{
		fprintf(stderr, "%s\n", gai_strerror(ret));
        exit(1);
    }

    for (addr = addrs; addr != NULL; addr = addr->ai_next) {
		/* Create the socket. */
		if ((motion_sock = socket(addr->ai_family, SOCK_STREAM, 0)) == INVALID_SOCKET)
		{
			fprintf(stderr, "Error:could not create socket for the motion\n");
			continue;
		}

		/* Bind it to a kernel assigned port on localhost and get the assigned port via getsockname(). */
		if (bind(motion_sock, addr->ai_addr, addr->ai_addrlen) < 0)
		{
			fprintf(stderr, "Error: could not bind socket for the motion\n");
			close(motion_sock);
			motion_sock = INVALID_SOCKET;
			continue;
		}

		alen = sizeof(motion_sock_addr);
		if (getsockname(motion_sock, (struct sockaddr *) &(motion_sock_addr), &alen) < 0)
		{
			fprintf(stderr, "could not get address of socket for the motion\n");
			close(motion_sock);
			motion_sock = INVALID_SOCKET;
			continue;
		}

		/* Resolve the motion listen port. */
		switch(motion_sock_addr.ss_family)
		{
			case AF_INET:
				{
					struct sockaddr_in *motion_addr = (struct sockaddr_in *) &motion_sock_addr;
					motionListenPort = ntohs(motion_addr->sin_port);
					strcpy(familyDesc, "IPv4");
					fprintf(stdout, "motionListenPort=%d, familyDesc = %s\n", motionListenPort, familyDesc);
					break;
				}
			case AF_INET6:
				{
					struct sockaddr_in6 *motion_addr = (struct sockaddr_in6 *) &motion_sock_addr;
					motionListenPort = ntohs(motion_addr->sin6_port);
					strcpy(familyDesc, "IPv6");
					fprintf(stdout, "motionListenPort=%d, familyDesc = %s\n", motionListenPort, familyDesc);
					break;
				}
			default:
				{
					fprintf(stderr, "Error:unrecognized address family \"%d\" for the motion\n", motion_sock_addr.ss_family);
					continue;
				}
		}

		/* 监听 */
		maxconn = MAX_CONN_COUNT;
		err = listen(motion_sock, maxconn);
		if (err < 0)
		{
			fprintf(stderr, "could not listen on socket for the motion\n");
			close(motion_sock);
			motion_sock = INVALID_SOCKET;
			continue;
		}
    }

	if (motion_sock == INVALID_SOCKET)
		goto listen_failed;

	/* XXXXXX	socket通信过程 */


	freeaddrinfo(addrs);
	close(motion_sock);
	return 0;

listen_failed:
	fprintf(stderr, "Error: failed to listen for the motion\n");
	if (addrs)
		freeaddrinfo(addrs);

	if (motion_sock != INVALID_SOCKET)
		close(motion_sock);
	motion_sock = INVALID_SOCKET;
	return -1;
}
```

## 4. 使用ioctl获取指定网卡IP地址

```cpp
#include <arpa/inet.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

#define ETH_NAME	"eth0"

int main()

{
	int sock;
	struct sockaddr_in sin;
	struct ifreq ifr;
	sock = socket(AF_INET, SOCK_DGRAM, 0);
	if (sock == -1)
	{
		perror("socket");
		return -1;
	}

	strncpy(ifr.ifr_name, ETH_NAME, IFNAMSIZ);
	ifr.ifr_name[IFNAMSIZ - 1] = 0;
	if (ioctl(sock, SIOCGIFADDR, &ifr) < 0)
	{
		perror("ioctl");
		return -1;
	}

	memcpy(&sin, &ifr.ifr_addr, sizeof(sin));
	fprintf(stdout, "eth0: %s\n", inet_ntoa(sin.sin_addr));

	return 0;
}
```

## 5. 使用ping指令，根据hostname获取ip地址

本例未用 getaddrinfo，而是采用shell指令方法（不推荐）。

```cpp
#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <net/if.h>
#include <net/if_arp.h>
#include <arpa/inet.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <string.h>


//使用ping指令，根据hostname获取ip地址
int getIpAddrByHostname(char *hostname, char* ip_addr, size_t ip_size)
{
	char command[256];
	FILE *f;
	char *ip_pos;

	snprintf(command, 256, "ping -c1 %s | head -n 1 | sed 's/^[^(]*(\\([^)]*\\).*$/\\1/'", hostname);
	fprintf(stdout, "%s\n", command);
	if ((f = popen(command, "r")) == NULL)
	{
		fprintf(stderr, "could not open the command, \"%s\", %s\n", command, strerror(errno));
		return -1;
	}

	fgets(ip_addr, ip_size, f);
	fclose(f);

	ip_pos = ip_addr;
	for (;*ip_pos && *ip_pos!= '\n'; ip_pos++);
	*ip_pos = 0;

	return 0;
}

int main()
{
	char addr[64] = {0};
	getIpAddrByHostname("localhost", addr, INET_ADDRSTRLEN);
	fprintf(stdout, "localhost: %s\n", addr);
	return 0;
}
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



