---
title: 源码分析 | ClickHouse和他的朋友们（1）编译、开发、测试
date: 2020-06-05 19:37:10
categories:
  - ClickHouse
tags:
  - ClickHouse和他的朋友们
  - ClickHouse
  - 源码分析
toc: true
---

<!-- more -->

**本文首发于 2020-06-05 19:37:10**

> 《ClickHouse 和他的朋友们》系列文章转载自圈内好友 [BohuTANG](https://bohutang.me/) 的博客，原文链接：
> https://bohutang.me/2020/06/05/clickhouse-and-friends-development/
> 以下为正文。

一次偶然的机会，和 ClickHouse 团队做了一次线下沟通，Alexey 提到 ClickHouse 的设计哲学:

1. The product must solve actual problem
2. And do it better than others

用工程思维解决商业问题的典范啊！

对用户来说，他们关心的不是什么天花乱坠、上天入地的高科技，只是需要一个能很好解决自己问题的方案，这在开源社区是非常难得的，靠实力“野蛮式”生长。

于是，我对这个散发着伏特加味道的利器充满了好奇，并参与到 ClickHouse 的社区中一探究竟，第一感觉是开放、友好、战斗力强(AK47 vs CK16, ClickHouse 2016 年开源)。

本文先从编译和测试入手，再到如何为社区贡献 Patch，希望对那些想参与 CK 社区的同学有所帮助。

## **如何本地编译和测试 ClickHouse？**

### **源码获取**

```
git clone --recursive https://github.com/ClickHouse/ClickHouse
```

### **编译准备**

```bash
sudo apt install build-essential
sudo apt-get install software-properties-common
sudo apt-add-repository ppa:ubuntu-toolchain-r/test
sudo apt-get update

sudo apt-get install gcc-9 g++-9 git python ninja-build
sudo snap install cmake
```

### **开始编译**

```bash
cd ClickHouse
mkdir build
cd build
export CC=gcc-9
export CXX=g++-9
cmake ..
ninja
```

### **测试方法**

ClickHouse 的测试在官方[development/tests](https://github.com/ClickHouse/ClickHouse/blob/master/docs/en/development/tests.md)文档里有详细的介绍，这里列举 3 个常用的测试模式：

#### 1. Functional Tests

功能测试，主要用于 ClickHouse 内部功能测试，方式：输入一个 sql 文件，输出一个 result，类似 MySQL 里的 mtr，[测试集合](https://github.com/ClickHouse/ClickHouse/tree/master/tests/queries)

```bash
cd tests
./clickhouse-test -c "../build/programs/clickhouse-client" 00001_select_1
```

#### 2. Integration Tests

集成测试，主要用于涉及第三方服务的测试，比如 MySQL/Postgres/MongoDB 等，以容器化方式编排调度(pytest)运行，[测试集合](https://github.com/ClickHouse/ClickHouse/tree/master/tests/integration)

由于涉及模块较多，集成测试环境的搭建有一定的难度，建议使用官方的 docker 镜像。比如要跑 test_mysql_protocol 下的集成测试集：

```bash
cd tests/integration
docker pull yandex/clickhouse-integration-tests-runner
./runner --binary /your/ClickHouse/build/programs/clickhouse  --bridge-binary /your/ClickHouse/build/programs/clickhouse-odbc-bridge --configs-dir /your/ClickHouse/programs/server/ 'test_mysql_protocol/test.py::test_java_client -ss -vv'
```

#### 3. Unit Tests

单元测试，主要用于代码模块的测试，测试集在各个模块的 tests 目录，比如: [Core/tests](https://github.com/ClickHouse/ClickHouse/tree/master/src/Core/tests)

如果大家想了解某个模块是如何工作的，强烈建议去翻翻该模块的 tests 目录，比如想了解 processor 的工作机制，跟踪调试 [Processors/tests/](https://github.com/ClickHouse/ClickHouse/blob/master/src/Processors/tests/processors_test.cpp) 即可。

## **如何给 ClickHouse 社区提 Patch？**

#### 1. fork

首先在自己的 github 上 fork 一份 ClickHouse 代码，比如 https://github.com/BohuTANG/ClickHouse

#### 2. clone 到本地

```bash
git clone --recursive https://github.com/BohuTANG/ClickHouse
git checkout -B mysql_replica(branch名字)
```

#### 3. 创建新的分支

```bash
git checkout -B mysql_replica(branch名字)
```

#### 4. 功能开发

开发者可以提交一个 Draft Pull Request 到官方，github 会显示这个 Pull Request 处于 Draft 状态，官方是无法 Merge 的

#### 5. can be testd 标签

等待 Upstream 打[can be tested]标签，一旦被标记 CI 狂魔们就强势开跑，跑一轮大概需要几十个小时。
协助开发者发现一些代码 Style、编译以及测试等错误，这样开发者就可以在自己的分支不停的迭代、修正。
![img](github-ck-ci.jpeg)

如果只是修改 typo，这个标签 Upstream 通常不会添加。

#### 6. 开发完毕

开发完成，测试 OK，把 Draft 提升为正式 Pull Request，等待 Upstraem Review。

#### 7. Merge 到 Master

如果 Upstream 通过，你的代码会被 Merge 到 Master，恭喜你成为 ClickHouse 贡献者

#### 8. 注意事项

ClickHouse Upstream 迭代非常快，一定要多关注 master 分支进度，尽量保持自己的分支代码与 master 同步。否则 Upstream Docker 更新，自己的 test 可能就过不了。

建议把[doc/development](https://github.com/ClickHouse/ClickHouse/tree/master/docs/en/development)读一遍。

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
