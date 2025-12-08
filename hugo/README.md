# Hugo 主题管理脚本

## 设计思想

脚本采用**基于 exampleSite 的构建方式**：

1. **从 exampleSite（来自于themes/{主题}/exampleSite） 复制完整配置**：每个主题的 `themes/{theme}/exampleSite/` 目录包含完整的示例配置和内容
2. **自动更新关键配置**：脚本自动更新 `baseURL`（开发/生产环境）和 `themesDir`（主题路径）
3. **合并用户内容**：将 `content/` 目录中的用户内容合并到站点，覆盖 exampleSite 的同名文件
4. **临时构建目录**：所有构建操作在 `site/` 临时目录中进行，不影响源文件

**优势**：
- 配置修改直观：直接编辑 `themes/{theme}/exampleSite/` 中的配置文件即可
- 无需维护单独的配置目录：所有配置都在主题的 exampleSite 中
- 支持多主题切换：同一套内容可以快速切换不同主题

## 使用方法

### 交互式使用

```bash
cd hugo
./manage-theme.sh
```

脚本会引导选择主题和操作。

### 命令行使用

```bash
# 启动测试服务器（默认操作）
./manage-theme.sh DoIt
./manage-theme.sh DoIt test

# 编译站点（不部署）
./manage-theme.sh DoIt build

# 编译并部署到 docs/ 目录
./manage-theme.sh DoIt deploy

# 清理临时文件
./manage-theme.sh DoIt clean
```

## 可用主题

- `blowfish`
- `DoIt`
- `FixIt`
- `LoveIt`

**注意**：`FeelIt` 主题暂不支持，原因如下：
- 使用了较多已废弃的 Hugo API，存在兼容性问题
- 与 `LoveIt` 主题风格相似（`FeelIt` 基于 `LoveIt` 开发）
- 如需类似风格，建议使用 `LoveIt` 主题

## 可用操作

- **test** - 启动本地测试服务器（http://localhost:1313）
- **build** - 编译站点到 `site/public/` 目录
- **deploy** - 编译并部署到 `../docs/` 目录（GitHub Pages）
- **clean** - 清理 `site/` 临时目录

## 目录结构

```
hugo/
├── manage-theme.sh          # 主脚本
├── themes/                  # 主题目录
│   └── {theme}/
│       └── exampleSite/     # 主题示例站点（包含完整配置）
├── content/                 # 用户内容目录
│   ├── zh/                 # 中文内容
│   └── en/                 # 英文内容
├── site/                    # 临时构建目录（自动创建）
└── ../docs/                 # 部署目录（GitHub Pages）
```

## 配置修改

如需修改主题配置，直接编辑对应主题的 `exampleSite/` 目录中的配置文件：

```bash
# 例如修改 DoIt 主题的配置
vim themes/DoIt/exampleSite/config/_default/params.toml
```

修改后重新运行脚本即可生效。

## 示例

### 测试主题

```bash
./manage-theme.sh DoIt test
# 访问 http://localhost:1313 预览
```

### 部署到 GitHub Pages

```bash
./manage-theme.sh DoIt deploy
git add docs/
git commit -m "Deploy DoIt theme"
git push
```

### 切换主题

```bash
# 测试 blowfish 主题
./manage-theme.sh blowfish test

# 部署 FixIt 主题
./manage-theme.sh FixIt deploy
```

## TODO

- [ ] FixIt 主题中无 exampleSites 之类的目录，因此，暂未适配。
  - [ ] 从官方说明来看，只要将 `themes/FixIt/*` 覆盖到当前 site 目录，并修改 theme 即可。
  - [ ] 直接进入 `themes/FixIt` 目录，执行 `hugo server -D` 测试，发现只有菜单栏，完全没有预期效果；而其他主题定义的配置基本都在 `themes/{主题}/exampleSite` 中；基于此，暂无解决方法。
- [ ] 目前示例配置都是从 `themes/{主题}/exampleSite` 中拷贝的，暂未用到 `example-sites/` 目录，后续若存在定制化配置时，需要将脚本拷贝示例配置的路径改为 example-sites/{主题}/ 目录。
- [ ] `themes/seal` 是基于开源项目修改而来的。