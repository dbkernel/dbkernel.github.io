---
title: 程序人生 | Makefile 常用模板 - 静态链接库/动态链接库/可执行文件
date: 2014-07-10 11:51:10
categories:
  - 编译调试
tags:
  - Makefile
toc: true
---

<!-- more -->

> **本文首发于 2014-07-10 11:51:10**

## 前言

本文把 makefile  分成了三份：生成可执行文件的 makefile，生成静态链接库的 makefile，生成动态链接库的 makefile。

这些 makefile 都很简单，一般都是一看就会用，用法也很容易，只需要把它们拷贝到你的代码的同一目录下，然后就可以用  make  来生成目标文件了。

下面是三个 makefile 的源代码：

## 生成可执行文件的 makefile

```makefile
######################################
#
######################################
#source file
#源文件，自动找所有.c和.cpp文件，并将目标定义为同名.o文件
SOURCE  := $(wildcard *.c) $(wildcard *.cpp)
OBJS    := $(patsubst %.c,%.o,$(patsubst %.cpp,%.o,$(SOURCE)))

#target you can change test to what you want
#目标文件名，输入任意你想要的执行文件名
TARGET  := test

#compile and lib parameter
#编译参数
CC      := gcc
LIBS    :=
LDFLAGS :=
DEFINES :=
INCLUDE := -I.
CFLAGS  := -g -Wall -O3 $(DEFINES) $(INCLUDE)
CXXFLAGS:= $(CFLAGS) -DHAVE_CONFIG_H


#i think you should do anything here
#下面的基本上不需要做任何改动了
.PHONY : everything objs clean veryclean rebuild

everything : $(TARGET)

all : $(TARGET)

objs : $(OBJS)

rebuild: veryclean everything

clean :
    rm -fr *.so
    rm -fr *.o

veryclean : clean
    rm -fr $(TARGET)

$(TARGET) : $(OBJS)
    $(CC) $(CXXFLAGS) -o $@ $(OBJS) $(LDFLAGS) $(LIBS)
```

## 生成静态链接库的 makefile

```makefile
######################################
#
#
######################################

#target you can change test to what you want
#共享库文件名，lib*.a
TARGET  := libtest.a

#compile and lib parameter
#编译参数
CC      := gcc
AR      = ar
RANLIB  = ranlib
LIBS    :=
LDFLAGS :=
DEFINES :=
INCLUDE := -I.
CFLAGS  := -g -Wall -O3 $(DEFINES) $(INCLUDE)
CXXFLAGS:= $(CFLAGS) -DHAVE_CONFIG_H

#i think you should do anything here
#下面的基本上不需要做任何改动了

#source file
#源文件，自动找所有.c和.cpp文件，并将目标定义为同名.o文件
SOURCE  := $(wildcard *.c) $(wildcard *.cpp)
OBJS    := $(patsubst %.c,%.o,$(patsubst %.cpp,%.o,$(SOURCE)))

.PHONY : everything objs clean veryclean rebuild

everything : $(TARGET)

all : $(TARGET)

objs : $(OBJS)

rebuild: veryclean everything

clean :
    rm -fr *.o

veryclean : clean
    rm -fr $(TARGET)

$(TARGET) : $(OBJS)
    $(AR) cru $(TARGET) $(OBJS)
    $(RANLIB) $(TARGET)
```

## 生成动态链接库的 makefile

```makefile
######################################
#
#
######################################

#target you can change test to what you want
#共享库文件名，lib*.so
TARGET  := libtest.so

#compile and lib parameter
#编译参数
CC      := gcc
LIBS    :=
LDFLAGS :=
DEFINES :=
INCLUDE := -I.
CFLAGS  := -g -Wall -O3 $(DEFINES) $(INCLUDE)
CXXFLAGS:= $(CFLAGS) -DHAVE_CONFIG_H
SHARE   := -fPIC -shared -o

#i think you should do anything here
#下面的基本上不需要做任何改动了

#source file
#源文件，自动找所有.c和.cpp文件，并将目标定义为同名.o文件
SOURCE  := $(wildcard *.c) $(wildcard *.cpp)
OBJS    := $(patsubst %.c,%.o,$(patsubst %.cpp,%.o,$(SOURCE)))

.PHONY : everything objs clean veryclean rebuild

everything : $(TARGET)

all : $(TARGET)

objs : $(OBJS)

rebuild: veryclean everything

clean :
    rm -fr *.o

veryclean : clean
    rm -fr $(TARGET)

$(TARGET) : $(OBJS)
    $(CC) $(CXXFLAGS) $(SHARE) $@ $(OBJS) $(LDFLAGS) $(LIBS)
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
