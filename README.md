# Table of Contents

  * [1. hugo 主题使用说明](#1-hugo-主题使用说明)
  * [2. hexo 主题使用说明](#2-hexo-主题使用说明)
    * [2.1. 安装 hexo](#21-安装-hexo)
    * [2.2. 初始化网站目录](#22-初始化网站目录)
    * [2.3. 安装插件](#23-安装插件)
    * [2.4. 优化博客的插件](#24-优化博客的插件)
    * [2.5. 安装主题](#25-安装主题)
    * [2.6. 完善页面](#26-完善页面)
      * [2.6.1. 生成“分类”页](#261-生成分类页)
      * [2.6.2. 生成“标签”页](#262-生成标签页)
      * [2.6.3. 生成“关于”页](#263-生成关于页)
      * [2.6.4. 生成“友链”页](#264-生成友链页)
      * [2.6.5. 生成“项目”页](#265-生成项目页)
    * [2.7. 发布文章](#27-发布文章)
    * [2.8. 生成页面并预览](#28-生成页面并预览)
    * [2.9. 发布](#29-发布)
  * [个人比较喜欢的主题列表](#个人比较喜欢的主题列表)

---

## 1. hugo 主题使用说明

1. 执行`brew install hugo`安装 hugo。
2. 添加文章：在 当前路径/content/post/ 中创建目录和 md 文件，比如是 mysql-test/MySQL 测试用例详解.md。
3. 执行`hugo server -D`在终端启动服务。
4. 在浏览器输入 `http://localhost:1313/` 预览。
5. 若文章无问题，在当前路径执行`hugo`构建静态网站目录`public`。
6. 将 `public` 路径下的文件挪到 `../` 即上级目录。
7. 提交到 github。

## 2. hexo 主题使用说明

> 以安装 yelee 主题为例说明。

### 2.1. 安装 hexo

- 安装 hexo：

```bash
$ brew install hexo
```

### 2.2. 初始化网站目录

1. 初始化网站目录：

```bash
$ hexo init hexo # 将网站根目录选择hexo目录下
$ cd hexo
```

### 2.3. 安装插件

> 本小节插件都是后文`pure`主题所用到的。

**更新 npm 版本：**

```bash
$ sudo npm install -g npm
```

**安装插件：**

[hexo-wordcount](https://github.com/willin/hexo-wordcount)

```bash
$ npm install hexo-wordcount --save
```

[hexo-generator-json-content](https://github.com/alexbruno/hexo-generator-json-content)

```bash
$ npm install hexo-generator-json-content --save
```

[hexo-generator-feed](https://github.com/hexojs/hexo-generator-feed)

```bash
$ npm install hexo-generator-feed --save
```

[hexo-generator-sitemap](https://github.com/hexojs/hexo-generator-sitemap)

```bash
$ npm install hexo-generator-sitemap --save
```

> 具体用法参考链接中的 README 。

[hexo-generator-baidu-sitemap](https://github.com/coneycode/hexo-generator-baidu-sitemap)

```bash
$ npm install hexo-generator-baidu-sitemap --save
```

[hexo-renderer-marked](https://github.com/hexojs/hexo-renderer-marked) - markdown 图片插件：

```bash
$ npm install hexo-renderer-marked --save
```

安装后在`_config.yaml`中更改配置如下：

```json
post_asset_folder: true
marked:
  prependRoot: true
  postAsset: true
```

之后就可以在使用![](image.jpg)的方式愉快的插入图片了。

### 2.4. 优化博客的插件

[hexo-neat](https://github.com/rozbo/hexo-neat)

> auto minify html、js、css and make it neat

```bash
$ npm install hexo-neat --save
```

You can configure this plugin in `_config.yml`.

```bash
# hexo-neat
neat_enable: true
neat_html:
  enable: true
  exclude:
neat_css:
  enable: true
  exclude:
    - '*.min.css'
neat_js:
  enable: true
  mangle: true
  output:
  compress:
  exclude:
    - '*.min.js'
```

[hexo-baidu-url-submit](https://github.com/huiwang/hexo-baidu-url-submit)

```bash
$ npm install hexo-baidu-url-submit --save
```

[hexo-translate-title](https://github.com/cometlj/hexo-translate-title)

> translate the chinese title of Hexo blog to english words automatially

```bash
$ npm install hexo-translate-title --save
```

You can configure this plugin in `_config.yml`.

```bash
translate_title:
  translate_way: google    #google | baidu | youdao
  youdao_api_key: XXX
  youdao_keyfrom: XXX
  is_need_proxy: true     #true | false
  proxy_url: http://localhost:8123
```

[hexo-renderer-markdown-it-plus](https://github.com/CHENXCHEN/hexo-renderer-markdown-it-plus)

```bash
# Mathjax Support
$ npm un hexo-renderer-marked --save
$ npm i hexo-renderer-markdown-it-plus --save
```

You can configure this plugin in `_config.yml`.

```bash
markdown_it_plus:
  highlight: true
  html: true
  xhtmlOut: true
  breaks: true
  langPrefix:
  linkify: true
  typographer:
  quotes: “”‘’
  plugins:
    - plugin:
        name: markdown-it-katex
        enable: true
    - plugin:
        name: markdown-it-mark
        enable: false
```

Article enable mathjax:

```bash
title: Hello World
mathjax: true
```

### 2.5. 安装主题

> 以安装 [pure](https://github.com/cofess/hexo-theme-pure) 主题为例说明。

1. 下载主题：

```
cd hexo
git submodule add https://github.com/cofess/hexo-theme-pure themes/pure
```

2. 修改`_config.yml`文件的主题：

```
theme=pure
```

1. 修改`theme/pure/_config.yml`的一些配置。
2. 可按照上一小节部分来初步验证主题效果。

### 2.6. 完善页面

> `pure`主题在首页添加了 categories、tags、about 等一系列页面，但是并未关联到主题中，因此，需要在根目录中创建对应页面。

#### 2.6.1. 生成“分类”页

1. 在博客所在文件夹执行：

```bash
$ hexo new page categories
INFO  Validating config
INFO  Created: ~/work/github/blogs-of-github/DBKernel.github.io/hexo/source/categories/index.md
```

2. 根据上面的路径，找到`index.md`这个文件，修改为如下内容（参考`themes/pure/_source/categories/index.md`）：

```yaml
---
title: 分类
date: 2021-07-10 17:34:18
layout: categories
comments: false
---
```

3. 保存并关闭文件。

#### 2.6.2. 生成“标签”页

1. 在博客所在文件夹执行：

```bash
$ hexo new page tags
INFO  Validating config
INFO  Created: ~/work/github/blogs-of-github/DBKernel.github.io/hexo/source/tags/index.md
```

2. 根据上面的路径，找到 index.md 这个文件，修改为如下内容（参考`themes/pure/_source/tags/index.md`）：

```yaml
---
title: 标签
date: 2021-07-10 13:47:40
type: "tags"
layout: tags
comments: false
---
```

3. 保存并关闭文件。

#### 2.6.3. 生成“关于”页

1. 在博客所在文件夹执行：

```bash
$ hexo new page about
INFO  Validating config
INFO  Created: ~/work/github/blogs-of-github/DBKernel.github.io/hexo/source/about/index.md
```

2. 根据上面的路径，找到 index.md 这个文件，修改为如下内容（参考`themes/pure/_source/about/index.md`）：

```yaml
---
title: 关于
date: 2021-07-10 13:47:55
type: "about"
description: 个人简介
layout: about
comments: false
sidebar: custom
---
个人说明部分。
```

3. 保存并关闭文件。

#### 2.6.4. 生成“友链”页

1. 在博客所在文件夹执行：

```bash
$ hexo new page links
INFO  Validating config
INFO  Created: ~/work/github/blogs-of-github/DBKernel.github.io/hexo/source/links/index.md
```

2. 根据上面的路径，找到 index.md 这个文件，修改为如下内容（参考`themes/pure/_source/links/index.md`）：

```yaml
---
title: 友情链接
layout: links
comments: true
sidebar: none
---
个人说明部分。
```

3. 保存并关闭文件。

#### 2.6.5. 生成“项目”页

1. 在博客所在文件夹执行：

```bash
$ hexo new page repository
INFO  Validating config
INFO  Created: ~/work/github/blogs-of-github/DBKernel.github.io/hexo/source/repository/index.md
```

2. 根据上面的路径，找到 index.md 这个文件，修改为如下内容（参考`themes/pure/_source/repository/index.md`）：

```yaml
---
title: 项目
layout: repository
comments: true
sidebar: none
---
个人说明部分。
```

3. 保存并关闭文件。

### 2.7. 发布文章

1. 按如下指令创建新文章后，会生成文件`source/_posts/test.md`：

```bash
hexo new "test"
```

2. 编辑`test.md`并保存，可在 markdown 文章头添加分类、标签等标识：

```yaml
---
title: test
date: 2020-12-09 11:37:10
categories:
  - MySQL
tags:
  - MySQL
  - auto_increment
toc: true
---
```

### 2.8. 生成页面并预览

1. 生成页面：

```
hexo g
```

2. 启动本地预览：

```
hexo s
```

3.浏览器输入`http://localhost:4000`进行预览。

### 2.9. 发布

1. 将生成的页面 copy 到`../docs/`目录。
2. 推送到 github。
3. 启用 github pages，设置网站路径为`/docs`。
4. 在浏览器输入`dbkernel.github.io`访问网站。

## 个人比较喜欢的主题列表

见 [hexo/themes](hexo/themes) 和 [hugo/themes](hugo/themes) 。
