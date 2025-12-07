#!/bin/bash

# Hugo 主题管理脚本
# 支持选择主题、测试、编译、发布到 GitHub Pages
#
# 使用方法:
#   ./manage-theme.sh [主题名] [操作]
#   或
#   ./manage-theme.sh  # 交互式选择

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
THEMES_DIR="themes"
CONTENT_DIR="content"
CONFIGS_DIR="configs"
BUILD_DIR="site"
DOCS_DIR="../docs"
GITHUB_BASE_URL="https://dbkernel.github.io/"
LOCAL_BASE_URL="http://localhost:1313"
LOCAL_PORT=1313

# 可用主题列表
AVAILABLE_THEMES=("blowfish" "DoIt" "FeelIt" "FixIt" "LoveIt")

# 显示帮助信息
show_help() {
    echo -e "${BLUE}Hugo 主题管理脚本${NC}"
    echo ""
    echo "使用方法:"
    echo "  $0 [主题名] [操作]"
    echo "  $0                    # 交互式选择"
    echo ""
    echo "可用主题:"
    for theme in "${AVAILABLE_THEMES[@]}"; do
        if [ -d "$THEMES_DIR/$theme" ]; then
            echo "  - $theme"
        fi
    done
    echo ""
    echo "可用操作:"
    echo "  test      - 启动测试服务器 (默认)"
    echo "  build     - 编译站点"
    echo "  deploy    - 编译并部署到 docs/ 目录"
    echo "  clean     - 清理临时文件"
    echo ""
    echo "示例:"
    echo "  $0 FixIt test      # 使用 FixIt 主题启动测试服务器"
    echo "  $0 blowfish deploy # 使用 blowfish 主题编译并部署"
}

# 检查主题是否存在
check_theme() {
    local theme=$1

    if [ ! -d "$THEMES_DIR/$theme" ]; then
        echo -e "${RED}错误: 主题 '$theme' 不存在于 $THEMES_DIR/ 目录中${NC}"
        echo "可用主题:"
        for t in "${AVAILABLE_THEMES[@]}"; do
            if [ -d "$THEMES_DIR/$t" ]; then
                echo "  - $t"
            fi
        done
        exit 1
    fi
}

# 交互式选择主题
select_theme() {
    echo -e "${BLUE}请选择要使用的主题:${NC}"
    echo ""

    local i=1
    local theme_list=()
    for theme in "${AVAILABLE_THEMES[@]}"; do
        if [ -d "$THEMES_DIR/$theme" ]; then
            echo "  $i) $theme"
            theme_list+=("$theme")
            i=$((i+1))
        fi
    done

    echo ""
    read -p "请输入选项编号 (1-$((i-1))): " choice

    if [ -z "$choice" ] || [ "$choice" -lt 1 ] || [ "$choice" -gt $((i-1)) ]; then
        echo -e "${RED}无效的选择${NC}"
        exit 1
    fi

    SELECTED_THEME="${theme_list[$((choice-1))]}"
}

# 交互式选择操作
select_action() {
    echo ""
    echo -e "${BLUE}请选择要执行的操作:${NC}"
    echo ""
    echo "  1) test    - 启动测试服务器"
    echo "  2) build   - 编译站点（不部署）"
    echo "  3) deploy  - 编译并部署到 docs/ 目录"
    echo "  4) clean   - 清理临时文件"
    echo ""
    read -p "请输入选项编号 (1-4，默认1): " choice

    case "${choice:-1}" in
        1) SELECTED_ACTION="test" ;;
        2) SELECTED_ACTION="build" ;;
        3) SELECTED_ACTION="deploy" ;;
        4) SELECTED_ACTION="clean" ;;
        *) SELECTED_ACTION="test" ;;
    esac
}

# 更新配置文件中的 baseURL 和 themesDir
update_config() {
    local theme=$1
    local base_url=$2
    # 注意：此函数在 init_site 中被调用时，当前目录已经是 BUILD_DIR

    # 查找配置文件（可能在根目录或 config/_default/ 目录中）
    local config_files=()

    # 检查根目录的配置文件（支持 config.toml, hugo.toml 等）
    for name in config hugo; do
        for ext in toml yaml yml json; do
            if [ -f "$name.$ext" ]; then
                config_files+=("$name.$ext")
            fi
        done
    done

    # 检查 config/_default/ 目录中的配置文件
    if [ -d "config/_default" ]; then
        for name in config hugo; do
            for ext in toml yaml yml json; do
                if [ -f "config/_default/$name.$ext" ]; then
                    config_files+=("config/_default/$name.$ext")
                fi
            done
        done
    fi

    if [ ${#config_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}警告: 未找到配置文件，跳过更新${NC}"
        return
    fi

    # 更新每个找到的配置文件
    for config_file in "${config_files[@]}"; do
        # 更新 baseURL（根据文件格式）
        if [[ "$config_file" == *.toml ]]; then
            # TOML 格式
            if grep -q "^baseURL" "$config_file"; then
                sed -i "s|^baseURL = .*|baseURL = \"$base_url\"|" "$config_file"
            else
                # 如果不存在，添加到文件开头
                sed -i "1i baseURL = \"$base_url\"" "$config_file"
            fi

            # 更新 theme（如果存在且值为 "./"）
            if grep -q "^theme = \"./\"" "$config_file"; then
                sed -i "s|^theme = \"./\"|theme = \"$theme\"|" "$config_file"
            elif grep -q "^theme = " "$config_file"; then
                sed -i "s|^theme = .*|theme = \"$theme\"|" "$config_file"
            fi

            # 更新 themesDir（如果存在）
            if grep -q "^themesDir" "$config_file"; then
                sed -i "s|^themesDir = .*|themesDir = \"../themes\"|" "$config_file"
            fi
        elif [[ "$config_file" == *.yaml ]] || [[ "$config_file" == *.yml ]]; then
            # YAML 格式
            if grep -q "^baseURL:" "$config_file"; then
                sed -i "s|^baseURL: .*|baseURL: \"$base_url\"|" "$config_file"
            else
                sed -i "1i baseURL: \"$base_url\"" "$config_file"
            fi

            # 更新 theme（如果存在）
            if grep -q "^theme:" "$config_file"; then
                sed -i "s|^theme: .*|theme: \"$theme\"|" "$config_file"
            fi

            if grep -q "^themesDir:" "$config_file"; then
                sed -i "s|^themesDir: .*|themesDir: \"../themes\"|" "$config_file"
            fi
        fi

        echo -e "${GREEN}✓${NC} 配置文件已更新: $config_file"
    done
}

# 复制 exampleSite 内容
copy_example_site() {
    local theme=$1
    local example_site_dir="../$THEMES_DIR/$theme/exampleSite"

    # 检查 exampleSite 目录是否存在
    if [ ! -d "$example_site_dir" ]; then
        echo -e "${YELLOW}警告: exampleSite 目录不存在: $example_site_dir${NC}"
        echo -e "${YELLOW}提示: 将使用空配置初始化站点，实际效果可能与主题预期效果不一致${NC}"
        echo -e "${YELLOW}建议: 请检查主题目录结构，或参考主题文档进行手动配置${NC}"
        echo ""
        # 不退出，继续执行，让 Hugo 使用默认配置
        return 0
    fi

    # 检查目录是否为空（排除 .git 等隐藏文件）
    local file_count=$(find "$example_site_dir" -mindepth 1 -maxdepth 1 ! -name '.*' ! -name 'themes' | wc -l)
    if [ "$file_count" -eq 0 ]; then
        echo -e "${YELLOW}警告: exampleSite 目录为空: $example_site_dir${NC}"
        echo -e "${YELLOW}提示: 将使用空配置初始化站点，实际效果可能与主题预期效果不一致${NC}"
        echo -e "${YELLOW}建议: 请检查主题目录结构，或参考主题文档进行手动配置${NC}"
        echo ""
        # 不退出，继续执行
        return 0
    fi

    echo "  复制 exampleSite 内容..."

    # 复制所有内容（排除 themes 目录，因为我们会单独处理）
    # 使用 rsync 或 cp，排除 themes 目录
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --exclude='themes' "$example_site_dir/" ./
    else
        # 如果没有 rsync，使用 cp
        find "$example_site_dir" -mindepth 1 -maxdepth 1 ! -name 'themes' ! -name '.*' -exec cp -r {} . \;
    fi

    echo -e "${GREEN}✓${NC} exampleSite 内容已复制"
}

# 初始化站点
init_site() {
    local theme=$1

    echo -e "${BLUE}初始化站点...${NC}"

    # 清理旧的构建目录
    if [ -d "$BUILD_DIR" ]; then
        echo "  清理旧的构建目录..."
        rm -rf "$BUILD_DIR"
    fi

    # 创建构建目录
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    # 从 exampleSite 复制所有内容
    copy_example_site "$theme"

    # 如果 exampleSite 不存在或为空，需要创建基本的配置文件
    if [ ! -f "hugo.toml" ] && [ ! -f "config.toml" ] && [ ! -f "hugo.yaml" ] && [ ! -f "config.yaml" ] && [ ! -f "hugo.json" ] && [ ! -f "config.json" ]; then
        echo -e "${YELLOW}警告: 未找到配置文件，创建基本配置...${NC}"
        cat > hugo.toml <<EOF
baseURL = "$LOCAL_BASE_URL"
languageCode = "zh-cn"
title = "DB Kernel - $theme"
theme = "$theme"
themesDir = "../themes"

defaultContentLanguage = "zh"
hasCJKLanguage = true

[languages]
[languages.zh]
  languageName = "中文"
  weight = 1
[languages.en]
  languageName = "English"
  weight = 2
EOF
        echo -e "${GREEN}✓${NC} 已创建基本配置文件: hugo.toml"
    fi

    # 更新配置文件中的 baseURL 和 themesDir
    update_config "$theme" "$LOCAL_BASE_URL"

    # 创建主题目录的符号链接
    echo "  设置主题..."
    if [ -d "../$THEMES_DIR/$theme" ]; then
        # 创建 themes 目录（如果不存在）
        mkdir -p themes

        # 使用绝对路径创建符号链接，更可靠
        local abs_themes_dir="$(cd "../$THEMES_DIR" && pwd)"
        local abs_build_dir="$(pwd)"
        ln -sf "$abs_themes_dir/$theme" "$abs_build_dir/themes/$theme"
        echo -e "${GREEN}✓${NC} 主题链接已创建: themes/$theme"
    else
        echo -e "${RED}错误: 主题目录不存在${NC}"
        exit 1
    fi

    # 覆盖用户自定义的内容（如果存在）
    echo "  合并用户内容..."
    if [ -d "../$CONTENT_DIR" ]; then
        # 合并用户的内容到 content 目录
        # 使用 rsync 或 cp 来合并
        if command -v rsync >/dev/null 2>&1; then
            rsync -a "../$CONTENT_DIR/" content/
        else
            cp -r "../$CONTENT_DIR"/* content/ 2>/dev/null || true
        fi
        echo -e "${GREEN}✓${NC} 用户内容已合并"
    else
        echo -e "${YELLOW}提示: 用户内容目录不存在，使用 exampleSite 的默认内容${NC}"
    fi

    # 保持在 BUILD_DIR 目录，不返回
    echo -e "${GREEN}✓${NC} 站点初始化完成"
}

# 测试服务器
test_server() {
    local theme=$1

    echo ""
    echo -e "${BLUE}启动测试服务器...${NC}"
    echo ""

    init_site "$theme"
    # init_site 已经 cd 到 BUILD_DIR，当前目录已经是 BUILD_DIR

    echo -e "${GREEN}服务器信息:${NC}"
    echo "  主题: $theme"
    echo "  地址: $LOCAL_BASE_URL"
    echo "  端口: $LOCAL_PORT"
    echo ""
    echo -e "${YELLOW}按 Ctrl+C 停止服务器${NC}"
    echo ""

    # 启动服务器
    hugo server -D --port "$LOCAL_PORT" --bind 0.0.0.0
}

# 编译站点
build_site() {
    local theme=$1
    local base_url=$2

    echo ""
    echo -e "${BLUE}编译站点...${NC}"
    echo ""

    init_site "$theme"
    # init_site 已经 cd 到 BUILD_DIR

    # 更新 baseURL 为生产环境
    if [ "$base_url" != "$LOCAL_BASE_URL" ]; then
        echo "  更新 baseURL 为生产环境: $base_url"
        update_config "$theme" "$base_url"
    fi

    # 编译
    echo "  开始编译..."
    hugo --minify

    if [ $? -eq 0 ] && [ -d "public" ]; then
        echo ""
        echo -e "${GREEN}✓${NC} 编译成功！"
        echo "  输出目录: $BUILD_DIR/public"
        echo "  文件数: $(find public -type f | wc -l)"
        echo "  大小: $(du -sh public | cut -f1)"
    else
        echo -e "${RED}✗${NC} 编译失败"
        cd ..  # 返回原目录
        exit 1
    fi

    cd ..  # 返回原目录
}

# 部署到 docs 目录
deploy_site() {
    local theme=$1

    echo ""
    echo -e "${BLUE}部署站点到 docs/ 目录...${NC}"
    echo ""

    # 先编译
    build_site "$theme" "$GITHUB_BASE_URL"

    cd "$BUILD_DIR"

    # 备份旧的 docs 目录
    if [ -d "../../$DOCS_DIR" ]; then
        BACKUP_DIR="../../${DOCS_DIR}-backup-$(date +%Y%m%d-%H%M%S)"
        echo "  备份旧的 docs/ 到 $(basename $BACKUP_DIR)"
        mv "../../$DOCS_DIR" "$BACKUP_DIR"
    fi

    # 复制构建结果
    echo "  复制 public/ 到 ../../$DOCS_DIR/"
    cp -r public "../../$DOCS_DIR"

    # 创建 .nojekyll 文件（GitHub Pages 需要）
    touch "../../$DOCS_DIR/.nojekyll"

    echo ""
    echo -e "${GREEN}✓${NC} 部署完成！"
    echo "  输出目录: ../../$DOCS_DIR"
    echo "  文件数: $(find "../../$DOCS_DIR" -type f | wc -l)"
    echo "  大小: $(du -sh "../../$DOCS_DIR" | cut -f1)"
    echo ""
    echo -e "${GREEN}访问地址: $GITHUB_BASE_URL${NC}"

    cd ..
}

# 清理临时文件
clean_build() {
    echo ""
    echo -e "${BLUE}清理临时文件...${NC}"

    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
        echo -e "${GREEN}✓${NC} 已清理构建目录: $BUILD_DIR"
    else
        echo "  没有需要清理的文件"
    fi

    echo -e "${GREEN}✓${NC} 清理完成"
}

# 主函数
main() {
    # 检查是否在正确的目录
    if [ ! -d "$THEMES_DIR" ]; then
        echo -e "${RED}错误: 请在 hugo/ 目录下运行此脚本${NC}"
        exit 1
    fi

    # 解析参数
    if [ $# -eq 0 ]; then
        # 交互式模式
        select_theme
        select_action
    elif [ $# -eq 1 ]; then
        # 只有主题名，默认测试
        SELECTED_THEME=$1
        SELECTED_ACTION="test"
    elif [ $# -eq 2 ]; then
        # 主题名和操作
        SELECTED_THEME=$1
        SELECTED_ACTION=$2
    else
        show_help
        exit 1
    fi

    # 检查主题
    check_theme "$SELECTED_THEME"

    # 执行操作
    case "$SELECTED_ACTION" in
        test)
            test_server "$SELECTED_THEME"
            ;;
        build)
            build_site "$SELECTED_THEME" "$GITHUB_BASE_URL"
            ;;
        deploy)
            deploy_site "$SELECTED_THEME"
            ;;
        clean)
            clean_build
            ;;
        *)
            echo -e "${RED}未知操作: $SELECTED_ACTION${NC}"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"

