#!/bin/bash
set -x
if [ "$1" == "" ];then
  echo "Usage: $0 websource-hugo-path"
  exit 1
fi

if [ ! -d $1 ];then
  echo "Error: the dir $1 not exist"
  exit 1
fi

rm -rf ./docs
cd $1
hugo
mv public ../docs
cd ..
set +x

