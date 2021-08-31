---
title: 程序人生 | UNIX环境高级编程技巧之 df 指令实现
date: 2014-07-10 09:48:48
categories:
- 程序人生
- APUE
tags:
- APUE
- UNIX
- df
toc: true
---

<!-- more -->

## 代码

```cpp
#include <stdio.h>
#include <mntent.h>
#include <string.h>
#include <sys/vfs.h>

static const unsigned long long G = 1024*1024*1024ull;
static const unsigned long long M = 1024*1024;
static const unsigned long long K = 1024;
static char str[20];

char* kscale(unsigned long b, unsigned long bs)
{
    unsigned long long size = b * (unsigned long long)bs;
    if (size > G)
    {
        sprintf(str, "%0.2f GB", size/(G*1.0));
        return str;
    }
    else if (size > M)
    {
        sprintf(str, "%0.2f MB", size/(1.0*M));
        return str;
    }
    else if (size > K)
    {
        sprintf(str, "%0.2f K", size/(1.0*K));
        return str;
    }
    else
    {
        sprintf(str, "%0.2f B", size*1.0);
        return str;
    }
}

int main(int argc, char *argv[])
{
    FILE* mount_table;
    struct mntent *mount_entry;
    struct statfs s;
    unsigned long blocks_used;
    unsigned blocks_percent_used;
    const char *disp_units_hdr = NULL;
    mount_table = NULL;
    mount_table = setmntent("/etc/mtab", "r");

    if (!mount_table)
    {
        fprintf(stderr, "set mount entry error\n");
        return -1;
    }

    disp_units_hdr = "     Size";
    printf("Filesystem           %-15sUsed Available %s Mounted on\n",
            disp_units_hdr, "Use%");
    while (1) {
        const char *device;
        const char *mount_point;
        if (mount_table) {
            mount_entry = getmntent(mount_table);
            if (!mount_entry) {
                endmntent(mount_table);
                break;
            }
        }
        else
            continue;
        device = mount_entry->mnt_fsname;
        mount_point = mount_entry->mnt_dir;
        //fprintf(stderr, "mount info: device=%s mountpoint=%s\n", device, mount_point);
        if (statfs(mount_point, &s) != 0)
        {
            fprintf(stderr, "statfs failed!\n");
            continue;
        }
        if ((s.f_blocks > 0) || !mount_table )
        {
            blocks_used = s.f_blocks - s.f_bfree;
            blocks_percent_used = 0;
            if (blocks_used + s.f_bavail)
            {
                blocks_percent_used = (blocks_used * 100ULL
                        + (blocks_used + s.f_bavail)/2
                        ) / (blocks_used + s.f_bavail);
            }
            /* GNU coreutils 6.10 skips certain mounts, try to be compatible.  */
            if (strcmp(device, "rootfs") == 0)
                continue;
            if (printf("\n%-20s" + 1, device) > 20)
                    printf("\n%-20s", "");
            char s1[20];
            char s2[20];
            char s3[20];
            strcpy(s1, kscale(s.f_blocks, s.f_bsize));
            strcpy(s2, kscale(s.f_blocks - s.f_bfree, s.f_bsize));
            strcpy(s3, kscale(s.f_bavail, s.f_bsize));
            printf(" %9s %9s %9s %3u%% %s\n",
                    s1,
                    s2,
                    s3,
                    blocks_percent_used, mount_point);
        }
    }

    return 0;
}
```

## 编译

```bash
$ gcc -g -Wall testdf.c -o testdf
```

## 运行

- `testdf`执行效果：
```bash
$ ./testdf
Filesystem                Size      Used Available Use% Mounted on
udev                   3.87 GB    0.00 B   3.87 GB   0% /dev
tmpfs                796.17 MB  980.00 K 795.21 MB   0% /run
/dev/vda1             96.75 GB  40.54 GB  56.19 GB  42% /
tmpfs                  3.89 GB    0.00 B   3.89 GB   0% /dev/shm
tmpfs                  5.00 MB    0.00 B   5.00 MB   0% /run/lock
tmpfs                  3.89 GB    0.00 B   3.89 GB   0% /sys/fs/cgroup
/dev/vda15           104.35 MB   3.86 MB 100.50 MB   4% /boot/efi
/dev/loop1            55.50 MB  55.50 MB    0.00 B 100% /snap/core18/2074
/dev/loop2            70.62 MB  70.62 MB    0.00 B 100% /snap/lxd/16922
/dev/loop4            70.38 MB  70.38 MB    0.00 B 100% /snap/lxd/21029
/dev/loop5            32.38 MB  32.38 MB    0.00 B 100% /snap/snapd/12704
tmpfs                796.17 MB  980.00 K 795.21 MB   0% /run/snapd/ns
tmpfs                796.17 MB    0.00 B 796.17 MB   0% /run/user/1000
/dev/loop6            55.50 MB  55.50 MB    0.00 B 100% /snap/core18/2128
/dev/loop0            32.38 MB  32.38 MB    0.00 B 100% /snap/snapd/12883
```
- `原生df`执行效果：
```bash
$ df -h
Filesystem      Size  Used Avail Use% Mounted on
udev            3.9G     0  3.9G   0% /dev
tmpfs           797M  980K  796M   1% /run
/dev/vda1        97G   41G   57G  42% /
tmpfs           3.9G     0  3.9G   0% /dev/shm
tmpfs           5.0M     0  5.0M   0% /run/lock
tmpfs           3.9G     0  3.9G   0% /sys/fs/cgroup
/dev/vda15      105M  3.9M  101M   4% /boot/efi
/dev/loop1       56M   56M     0 100% /snap/core18/2074
/dev/loop2       71M   71M     0 100% /snap/lxd/16922
/dev/loop4       71M   71M     0 100% /snap/lxd/21029
/dev/loop5       33M   33M     0 100% /snap/snapd/12704
tmpfs           797M     0  797M   0% /run/user/1000
/dev/loop6       56M   56M     0 100% /snap/core18/2128
/dev/loop0       33M   33M     0 100% /snap/snapd/12883
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