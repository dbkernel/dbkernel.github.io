---
title: 程序人生 | UNIX 环境高级编程技巧之 getopt & getopt_long 使用示例
date: 2014-01-10 19:48:48
categories:
  - C语言
tags:
  - APUE
  - C语言
  - UNIX
  - getopt
toc: true
---

<!-- more -->

> **本文首发于 2014-01-10 19:48:48**

# 1. getopt

该函数用来解析命令行参数。

## 1.1. 函数定义

```cpp
int getopt(int argc, char * const argv[], const char *optstring);
#include <unistd.h>
```

前两个参数设为 main 函数的两个参数。

> optstring 设为由该命令要处理的各个选项组成的字符串。选项后面带有冒号'：'时，该选项是一个带参数的选项。
>
> 举例：`make -f filename -n`
> -f 是一个带参数的选项，-n 是一个没有参数的选项。
>
> 可以像下面这样调用 `函数getopt` 来解析上面的例子。

```cpp
c = getopt(argc, argv, "f:n");
```

此函数的**返回值即为当前找到的命令选项，全部选项都找到时的返回值为-1**。

通常一个命令有多个选项，为了取得所有选项，需要循环调用此函数，直到返回值为-1。
要使用此函数，还有几个全局变量必须要了解：

```cpp
extern char *optarg;
extern int optind, opterr, optopt;
 /*
optarg: 当前选项带参数时，optarg指向该参数。
optind: argv的索引。通常选项参数取得完毕时，通过此变量可以取得非选项参数（argv[optind]）
optopt: 一个选项在argv中有，但在optstring中不存在时，或者一个带参数的选项没有参数时，
        getopt()返回'?'，同时将optopt设为该选项。
opterr: 将此变量设置为0，可以抑制getopt()输出错误信息。
*/
```

## 1.2. 实例

```cpp
#include <unistd.h>
#include <string.h>
#include <stdio.h>

int main(int argc, char *argv[ ])
{
    int c;
    int flg = 0;
    char filename[256];
    char testdata[256];

    if (argc < 2)
    {
        printf("usage:%s [-f filename] [-n] testdata\n", argv[0]);
        return -1;
    }

    opterr = 0;
    while ((c = getopt(argc, argv, "f:n")) != -1)
    {
        switch (c)
        {
            case 'f':
                strncpy(filename, optarg, sizeof(filename)-1);
                break;
            case 'n':
                flg = 1;
                break;
            case '?':
            default:
                printf("usage:%s [-f filename] [-n] testdata\n", argv[0]);
                return -1;
        }
    }

    if (argv[optind] == NULL)
    {
        printf("usage:%s [-f filename] [-n] testdata\n", argv[0]);
        return -1;
    }
    else
    {
        strncpy(testdata, argv[optind], sizeof(testdata)-1);
    }

    printf("fliename:%s flg:%d testdata:%s\n", filename, flg, testdata);
    return 0;
}
```

# 2. getopt_long

这是支持长命令选项的函数，长选项以'--'开头。

## 2.1. 函数定义

```cpp
int getopt_long(int argc, char * const argv[],
                  const char *optstring,
                  const struct option *longopts, int *longindex);
#include <getopt.h>
```

前三个参数与函数 getopt 的参数是一样的。

只支持长选项时，参数 optstring 设置为 NULL 或者空字符串""。

第四个参数是一个构造体 struct option 的数组。此构造体定义在头文件 getopt.h 中。此数组的最后一个须将成员都置为 0。

```cpp
struct option {
const char *name;
int has_arg;
int *flag;
int val;
};
```

**构造体各个成员的解释如下：**

> - name : 长选项的名字。
> - has_arg : no_argument 或 0 表示此选项不带参数，required_argument 或 1 表示此选项带参数，optional_argument 或 2 表示是一个可选选项。
> - flag : 设置为 NULL 时，getopt_long()返回 val,设置为 NULL 以外时，>getopt_long()返回 0，且将\*flag 设为 val。
> - val : 返回值或者\*flag 的设定值。有些命令既支持长选项也支持短选项，可以通过设定此值为短选项实现。

第五个参数是一个输出参数，函数 getopt_long()返回时，longindex 的值是 struct option 数组的索引。

**关于返回值有以下几种情况：**

> - 识别为短选项时，返回值为该短选项。
> - 识别为长选项时，如果 flag 是 NULL 的情况下，返回 val,如果 flag 非 NULL 的情况下，返回 0。
> - 所有选项解析结束时返回-1。
> - 存在不能识别的选项或者带参数选项的参数不存在时返回'?' 。

## 2.2. 实例

```cpp
#include <stdio.h>     /* for printf */
#include <stdlib.h>    /* for exit */
#include <getopt.h>

int main(int argc, char **argv)
{
   int c;
   int digit_optind = 0;
   int flag = 0;

   while (1) {
       int this_option_optind = optind ? optind : 1;
       int option_index = 0;
       static struct option long_options[] = {
           {"add",     required_argument, 0,  0 },
           {"append",  no_argument,       0,  0 },
           {"delete",  required_argument, 0,  0 },
           {"verbose", no_argument,       0,  0 },
           {"create",  required_argument, 0, 'c'},
           {"file",    required_argument, 0, 'f'},
           {0,         0,                 0,  0 }
       };

       c = getopt_long_only(argc, argv, "abc:d:f:012", long_options, &option_index);
       if (c == -1)
           break;

       switch (c) {
       case 0:
           printf("option %s", long_options[option_index].name);
           if (optarg)
               printf(" with arg %s", optarg);
           printf("\n");
           break;

       case '0':
       case '1':
       case '2':
           if (digit_optind != 0 && digit_optind != this_option_optind)
             printf("digits occur in two different argv-elements.\n");

           digit_optind = this_option_optind;
           printf("option %c\n", c);
           break;
       case 'a':
           printf("option a\n");
           break;
       case 'b':
           printf("option b\n");
           break;
       case 'c':
           printf("option c with value '%s'\n", optarg);
           break;
       case 'd':
           printf("option d with value '%s'\n", optarg);
           break;
        case 'f':
            printf("option f with value '%s'\n", optarg);
            break;
       case '?':
           break;
       default:
           printf("?? getopt returned character code 0%o ??\n", c);
       }
   }

   if (optind < argc) {
       printf("non-option ARGV-elements: ");
       while (optind < argc)
           printf("%s ", argv[optind++]);
       printf("\n");
   }

   exit(EXIT_SUCCESS);
}
```

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
