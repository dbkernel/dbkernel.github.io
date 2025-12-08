#!/bin/bash

###############################################################################
# Hexo 构建脚本
#
# 功能：
#   1. 清理旧的构建输出目录
#   2. 执行 Hexo 构建生成静态文件
#   3. 将生成的 public 目录移动到指定输出目录
#   4. 复制 SEO 相关文件（Google、Bing、robots.txt、CNAME）
#
# 使用方法：
#   ./build.sh [选项]
#
# 选项：
#   -o, --output DIR     指定输出目录（默认: ../docs）
#   -c, --clean          构建前清理输出目录（默认: 启用）
#   -s, --skip-seo       跳过复制 SEO 文件
#   -h, --help           显示帮助信息
#
# 示例：
#   ./build.sh                          # 使用默认配置
#   ./build.sh -o ../output            # 指定输出目录为 ../output
#   ./build.sh --output dist --skip-seo # 输出到 dist，跳过 SEO 文件
###############################################################################

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
OUTPUT_DIR="../docs"
CLEAN_OUTPUT=true
SKIP_SEO=false
DEPENDS_DIR="../depends"

# 显示帮助信息
show_help() {
    cat << EOF
${BLUE}Hexo 构建脚本${NC}

${GREEN}使用方法：${NC}
    $0 [选项]

${GREEN}选项：${NC}
    -o, --output DIR     指定输出目录（默认: ../docs）
    -c, --clean          构建前清理输出目录（默认: 启用）
    --no-clean           不清理输出目录
    -s, --skip-seo       跳过复制 SEO 文件
    -h, --help           显示帮助信息

${GREEN}示例：${NC}
    $0                          # 使用默认配置
    $0 -o ../output            # 指定输出目录为 ../output
    $0 --output dist --skip-seo # 输出到 dist，跳过 SEO 文件
    $0 --no-clean              # 不清理输出目录

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -c|--clean)
                CLEAN_OUTPUT=true
                shift
                ;;
            --no-clean)
                CLEAN_OUTPUT=false
                shift
                ;;
            -s|--skip-seo)
                SKIP_SEO=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}错误: 未知参数 '$1'${NC}"
                echo "使用 $0 --help 查看帮助信息"
                exit 1
                ;;
        esac
    done
}

# 检查依赖
check_dependencies() {
    if ! command -v hexo &> /dev/null; then
        echo -e "${RED}错误: 未找到 hexo 命令${NC}"
        echo "请先安装 Hexo: npm install -g hexo-cli"
        exit 1
    fi
}

# 清理输出目录
clean_output() {
    if [ "$CLEAN_OUTPUT" = true ]; then
        if [ -d "$OUTPUT_DIR" ]; then
            echo -e "${YELLOW}清理输出目录: $OUTPUT_DIR${NC}"
            rm -rf "$OUTPUT_DIR"
        fi
    else
        echo -e "${YELLOW}跳过清理输出目录${NC}"
    fi
}

# 执行 Hexo 构建
build_hexo() {
    echo -e "${BLUE}开始构建 Hexo 站点...${NC}"

    if [ ! -f "package.json" ]; then
        echo -e "${RED}错误: 当前目录不是 Hexo 项目根目录${NC}"
        exit 1
    fi

    hexo generate

    if [ ! -d "public" ]; then
        echo -e "${RED}错误: Hexo 构建失败，未找到 public 目录${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Hexo 构建完成${NC}"
}

# 移动构建结果
move_output() {
    echo -e "${BLUE}移动构建结果到输出目录...${NC}"

    # 确保输出目录的父目录存在
    mkdir -p "$(dirname "$OUTPUT_DIR")"

    # 如果输出目录已存在且不是清理模式，先备份
    if [ -d "$OUTPUT_DIR" ] && [ "$CLEAN_OUTPUT" = false ]; then
        BACKUP_DIR="${OUTPUT_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}备份现有输出目录到: $BACKUP_DIR${NC}"
        mv "$OUTPUT_DIR" "$BACKUP_DIR"
    fi

    mv public "$OUTPUT_DIR"
    echo -e "${GREEN}✓ 构建结果已移动到: $OUTPUT_DIR${NC}"
}

# 复制 SEO 文件
copy_seo_files() {
    if [ "$SKIP_SEO" = true ]; then
        echo -e "${YELLOW}跳过复制 SEO 文件${NC}"
        return
    fi

    echo -e "${BLUE}复制 SEO 相关文件...${NC}"

    # 检查 depends 目录（使用绝对路径）
    local abs_depends_dir="$(cd "$(dirname "$DEPENDS_DIR")" && pwd)/$(basename "$DEPENDS_DIR")"
    if [ ! -d "$DEPENDS_DIR" ]; then
        echo -e "${YELLOW}警告: depends 目录不存在: $DEPENDS_DIR${NC}"
        echo -e "${YELLOW}当前工作目录: $(pwd)${NC}"
        return
    fi

    # 检查输出目录是否存在
    if [ ! -d "$OUTPUT_DIR" ]; then
        echo -e "${RED}错误: 输出目录不存在: $OUTPUT_DIR${NC}"
        echo -e "${RED}请先执行构建步骤${NC}"
        return
    fi

    echo -e "  源目录: ${BLUE}$DEPENDS_DIR${NC}"
    echo -e "  目标目录: ${BLUE}$OUTPUT_DIR${NC}"

    # SEO 文件列表
    SEO_FILES=(
        "google557be7742b81daa1.html"
        "robots.txt"
        "BingSiteAuth.xml"
        "CNAME"
    )

    local copied=0
    local skipped=0

    # 获取绝对路径，确保路径正确
    local current_dir="$(pwd)"
    local abs_depends="$(cd "$DEPENDS_DIR" && pwd)"
    local abs_output="$(cd "$OUTPUT_DIR" && pwd)"

    for file in "${SEO_FILES[@]}"; do
        local src="$abs_depends/$file"
        local dst="$abs_output/$file"

        if [ -f "$src" ]; then
            if cp "$src" "$dst" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $file"
                copied=$((copied + 1))
            else
                echo -e "  ${RED}✗${NC} $file (复制失败)"
                echo -e "    源: $src"
                echo -e "    目标: $dst"
                skipped=$((skipped + 1))
            fi
        else
            echo -e "  ${YELLOW}⚠${NC} $file (源文件不存在)"
            echo -e "    检查路径: $src"
            skipped=$((skipped + 1))
        fi
    done

    echo -e "${GREEN}✓ SEO 文件复制完成 (成功: $copied, 跳过: $skipped)${NC}"
}

# 显示构建摘要
show_summary() {
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}构建完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "输出目录: ${BLUE}$OUTPUT_DIR${NC}"

    if [ -d "$OUTPUT_DIR" ]; then
        local file_count=$(find "$OUTPUT_DIR" -type f | wc -l)
        local dir_size=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)
        echo -e "文件数量: ${BLUE}$file_count${NC}"
        echo -e "目录大小: ${BLUE}$dir_size${NC}"
    fi

    echo -e "${GREEN}════════════════════════════════════════${NC}"
}

# 主函数
main() {
    # 解析命令行参数
    parse_args "$@"

    # 检查依赖
    check_dependencies

    # 显示配置信息
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}Hexo 构建配置${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "输出目录: ${GREEN}$OUTPUT_DIR${NC}"
    echo -e "清理输出: ${GREEN}$CLEAN_OUTPUT${NC}"
    echo -e "跳过 SEO: ${GREEN}$SKIP_SEO${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""

    # 执行构建流程
    clean_output
    build_hexo
    move_output
    copy_seo_files
    show_summary
}

# 运行主函数
main "$@"
