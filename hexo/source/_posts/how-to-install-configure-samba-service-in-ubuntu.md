---
title: 系统运维 | Ubuntu 下安装配置samba 服务的详细过程
date: 2014-08-05 10:14:48
categories:
  - Linux
tags:
  - Linux
  - 系统运维
toc: true
---

<!-- more -->

> **本文首发于 2014-08-05 10:14:48**

# 1. Samba 作用

Samba 的主要任务就是实现 Linux 系统和 Windows 系统之间的资源共享。我们现在是要在 Linux 下配置 Samba，让 Windows 的用户可以访问你的 PC。

当然，也可用于 VMWare 虚拟机与宿主机之间的资源共享。

# 2. 安装

我是在 ubuntu 上实现的，所以我只需在配置好 ubuntu 的更新源之后，在终端中使用一下两句命令，就可以安装 Samba 的软件包

```bash
sudo apt-get install smaba
sudo apt-get install smbfs
```

# 3. Samba 服务的构成

Samba 的核心是两个守护进程`smbd`和`nmbd` 。它们的配置信息都保存在`/etc/samba/smb.conf`里面。

其中`smbd`处理 Samba 软件与 Linux 协商，`nmbd`使其他主机能浏览 Linux 服务器。

# 4. Samba 配置文件

配置文件为`/etc/samba/smb.conf`，如果担心改了之后有问题，可以先备份一下：

```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb_conf_backup
```

**一个完整的 Samba 配置文件包含两部分：**

- Samba Global Settings 全局参数设置
  > 该部分由`[global]段`来完成配置，主要是设置整体的规则。其中参数`workgroup`比较特殊，用于提供`NT域名或者工作组名`，需要根据实际情况修改：

```bash
workgroup=mygroup
```

- Share Definitions 共享定义
  > 有很多段，都用`[]标志`开始的，需要根据实际情况修改。

**语法说明：**

- 每个部分有消息头和参数构成，消息头用`[]`表示，如`[global]`就是一个消息头。
- 参数的结构形式是`parameter=value`。
- 注释用 `#` 表示，这个和 shell 脚本有点像。
- 有一些配置前面有 `;` ，这个表示这一行的配置可以更改，如需修改，则要去掉`;`，配置才可能生效。

# 5. 示例

## 5.1. 设置共享目录

假定共享目录为`/home/share/samba`：

```bash
sudo mkdir -p /home/share/samba
sudo chmod 777 /home/share/samba
```

## 5.2. 修改配置文件

修改 global 段：

```ini
[global]
    workgroup = WORKGROUP
    display charset = UTF-8
    unix charset = UTF-8
    dos charset = cp936
```

添加 Share 段：

```ini
[Share]
    comment = Shared Folder with username and password
    path = /home/share/samba
    public = yes
    writable = no
    valid users = user
    create mask = 0300
    directory mask = 0300
    force user = nobody
    force group = nogroup
    available = yes
    browseable = yes
```

搜索到 security 配置项，修改为：

```ini
security = user
username map = /etc/samba/smbusers
```

保存并关闭配置文件。

## 5.3. 添加 Samba 用户

```bash
sudo useradd user #增加了一个叫做user的用户
sudo smbpasswd user #修改user的对samba服务的密码，系统会提示输入密码
```

## 5.4. 重启服务

```bash
sudo /etc/init.d/samba restart
```

## 5.5. 使用

- 在 windows 系统下使用

  - 方法一：在 IE 地址栏中输入：`\\你的IP`，然后回车，可能要求你输入用户名和密码（第 5.3 小节设定的）。
  - 方法二：在`网上邻居`中新建`邻居`，在路径中输入: `\\你的IP\Share`，然后点击下一步完成（可能会要求输入用户名和密码）。

- 在 Linux 下访问：在终端中挂载文件系统

```bash
sudo mount -t smbfs -o username=user,password=123456 //218.*.*.*/Share /mnt
```

> 其中，`-t参数`指示了文件系统的类型，`username`是用户名，`password`是密码，`218.*.*.*`是你的 IP，`Share`是在配置文件中已经指明的段名，`/mnt`是要挂载到的文件夹。

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
