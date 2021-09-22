---
title: 程序人生 | UNIX环境高级编程技巧之 du 指令实现
date: 2014-07-10 10:00:41
categories:
- C语言
tags:
- APUE
- C语言
- UNIX
- du
toc: true
---

<!-- more -->

>**本文首发于 2014-07-10 10:00:41**

## 代码

```cpp
#include <stdio.h>
#include <stdlib.h>
#include <glob.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#define PATHSIZE 1024

static int path_noloop(const char *path)
{
    char *pos;

    pos = strrchr(path,'/');//定位最右边的'/'的位置

    if(strcmp(pos+1,".") == 0 || (strcmp(pos+1,"..") == 0))
        return 0;
    return 1;

}

static int64_t mydu(const char *path)
{
    int i;
    glob_t globres;
    int64_t sum;
    static struct stat statres;
    static char nextpath[PATHSIZE];

    if(lstat(path, &statres) < 0)
    {
        perror("lstat()");
        return 0;//exit(1);
    }

    if(!S_ISDIR(statres.st_mode))
        return statres.st_blocks;

    strncpy(nextpath, path,PATHSIZE);
    strncat(nextpath, "/*" , PATHSIZE);
    glob(nextpath,GLOB_NOSORT, NULL, &globres);

    strncpy(nextpath, path,PATHSIZE);
    strncat(nextpath, "/.*" , PATHSIZE);
    glob(nextpath,GLOB_NOSORT|GLOB_APPEND, NULL, &globres);

    sum = statres.st_blocks;

    for(i = 0 ;i < globres.gl_pathc ; i++)
    {
        if(path_noloop(globres.gl_pathv[i]))
            sum += mydu(globres.gl_pathv[i]);
    }

    return sum;
}

int main(int argc,char **argv)
{
    if(argc < 2)
    {
        fprintf(stderr,"Usage...\n");
        exit(1);
    }
    printf("%lld 512B blocks\n", (long long int)mydu(argv[1]));
    return 0;
}
```

## 编译

```bash
$ gcc -g -Wall testdu.c -o testdu
```

## 运行

- `testdf`执行效果：
```bash
$ ./testdu /usr/bin
1766184 512B blocks
```
- `原生df`执行效果：
```bash
$ du -sh /usr/bin
859M	/usr/bin
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
