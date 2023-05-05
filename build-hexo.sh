#!/bin/bash
set -x
#if [ "$1" == "" ];then
#  echo "Usage: $0 websource-hexo-path"
#  exit 1
#fi
#
#if [ ! -d $1 ];then
#  echo "Error: the dir $1 not exist"
#  exit 1
#fi

rm -rf ./docs
#cd $1
cd hexo
hexo g
mv public ../docs
cd ..
set +x

###### 搜索引擎 SEO
# github.io 无法使用百度，目前只配置了 google、bing
# 除了下述的文件验证方式，在主题 _config.yml 中配置 google-site-verification ，还会采用HTML标签方式
cp google557be7742b81daa1.html docs/
cp robots.txt docs/
# 非常简单，很好用
cp BingSiteAuth.xml docs
# domain
cp CNAME docs
