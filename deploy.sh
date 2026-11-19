#!/bin/bash
# -*- coding: utf-8 -*-
# 编译和部署郑码输入法
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ZHENGMA_TXT="$SCRIPT_DIR/zhengma.txt"
CUSTOM_TXT="$SCRIPT_DIR/zhengma-custom.txt"
SYSTEM_DB="/usr/share/ibus-table/tables/zhengma.db"

error_exit() {
    echo "$@" >&2
    exit 1
}

BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/zhengma-build.XXXXXXXX") || error_exit "✗ 错误：无法创建临时构建目录"
trap 'rm -r -- "$BUILD_DIR"' EXIT
MERGED_TXT="$BUILD_DIR/merged.txt"
TEMP_MERGED="$BUILD_DIR/custom.txt"
VERSIONED_TXT="$BUILD_DIR/versioned.txt"
BUILD_DB="$BUILD_DIR/zhengma.db"

BUILD_ONLY=0
OUTPUT_PATH=""
if [ "$#" -gt 0 ]; then
    [ "$#" -eq 2 ] && [ "$1" = "--build-only" ] \
        || error_exit "用法：$0 [--build-only 输出数据库路径]"
    BUILD_ONLY=1
    OUTPUT_PATH=$(realpath -m -- "$2") || error_exit "✗ 错误：无法解析输出路径"
    case "$OUTPUT_PATH" in
        "$SCRIPT_DIR"|"$SCRIPT_DIR"/*)
            error_exit "✗ 错误：生成的数据库必须保存到仓库目录之外"
            ;;
    esac
fi

echo "================================"
echo "郑码输入法编译和部署"
echo "================================"
echo

# 检查源文件
[ -f "$ZHENGMA_TXT" ] || error_exit "✗ 错误: 找不到 $ZHENGMA_TXT"

echo "1️⃣  合并码表文件..."

# 复制原始码表
cp "$ZHENGMA_TXT" "$MERGED_TXT" || error_exit "✗ 错误: 无法复制 $ZHENGMA_TXT"

# 如果存在自定义词条，转换格式后插入码表数据段
if [ -f "$CUSTOM_TXT" ]; then
    echo "   - 合并自定义词条: $CUSTOM_TXT"

    # 先检查自定义词条的格式
    echo "   - 检查词条格式..."

    CHECK_ERROR=""
    while IFS= read -r line || [ -n "$line" ]; do
        # 跳过注释和空行
        [[ "$line" =~ ^# ]] && continue
        [[ -z "$line" ]] && continue

        # 验证格式：必须有 TAB 分隔符
        if ! echo "$line" | grep -q $'\t'; then
            CHECK_ERROR="缺少 TAB: $line"
            break
        fi

        # 提取编码并检查是否为空
        code=$(echo "$line" | cut -f2-)
        if [ -z "$code" ] || [ "$code" = " " ]; then
            CHECK_ERROR="编码为空: $line"
            break
        fi
    done < "$CUSTOM_TXT"

    if [ -n "$CHECK_ERROR" ]; then
        echo
        echo "❌ 自定义词条文件格式不正确"
        echo "   $CHECK_ERROR"
        echo
        echo "预期格式: 词汇<TAB>编码"
        echo "提示：请先运行 python3 build-zhengma.py 自动生成编码"
        error_exit ""
    fi

    echo "   ✓ 词条格式检查通过"

    # 自定义词条必须放在 BEGIN_TABLE 段，不能放到 BEGIN_GOUCI 段
    END_MARKER="END_TABLE"

    [ -z "$END_MARKER" ] && error_exit "✗ 错误：无法识别码表结构，找不到结尾标记"

    echo "   - 检测到词条段结尾标记: $END_MARKER"

    # 提取原始码表中的所有词汇（用于去重检查）
    END_DEF_LINE=$(grep -n "^END_DEFINITION" "$ZHENGMA_TXT" 2>/dev/null | cut -d: -f1 | head -1)
    END_MARKER_LINE=$(grep -n "^$END_MARKER$" "$ZHENGMA_TXT" 2>/dev/null | cut -d: -f1 | head -1)

    [ -z "$END_DEF_LINE" ] && error_exit "✗ 错误：无法找到 END_DEFINITION"
    [ -z "$END_MARKER_LINE" ] && error_exit "✗ 错误：无法找到 $END_MARKER"

    echo "   - 提取原始词汇列表（可能需要几秒钟）..."

    ORIGINAL_WORDS=$(sed -n "$((END_DEF_LINE + 1)),$((END_MARKER_LINE - 1))p" "$ZHENGMA_TXT" 2>/dev/null \
        | grep -v '^#' \
        | grep -v '^[[:space:]]*$' \
        | cut -f2) || error_exit "✗ 错误：无法提取词汇列表"

    [ -z "$ORIGINAL_WORDS" ] && error_exit "✗ 错误：词汇列表为空"

    # 处理自定义词条，去重
    ADDED=0
    SKIPPED=0

    while IFS= read -r line || [ -n "$line" ]; do
        # 跳过注释和空行
        [[ "$line" =~ ^# ]] && continue
        [[ -z "$line" ]] && continue

        # 提取词汇和编码
        word=$(echo "$line" | cut -f1)
        code=$(echo "$line" | cut -f2-)

        # 检查原始码表中是否已存在（原始码表格式为：编码 TAB 词汇 TAB 频率）
        if printf '%s\n' "$ORIGINAL_WORDS" | grep -Fqx -- "$word"; then
            echo "   ⚠ 警告: '${word}' 已存在于原始码表，将被跳过"
            ((SKIPPED++))
        else
            # ibus-table-createdb 要求：编码 TAB 词汇 TAB 频率
            printf '%s\t%s\t0\n' "$code" "$word" >> "$TEMP_MERGED" || error_exit "✗ 错误：无法写入自定义词条"
            ((ADDED++))
        fi
    done < "$CUSTOM_TXT"

    # 在 END_TABLE 前插入自定义词条，保留后面的 BEGIN_GOUCI 段
    if [ -f "$TEMP_MERGED" ]; then
        awk -v additions="$TEMP_MERGED" '
            $0 == "END_TABLE" {
                while ((getline line < additions) > 0) print line
                close(additions)
            }
            { print }
        ' "$ZHENGMA_TXT" > "$MERGED_TXT" || error_exit "✗ 错误：无法插入自定义词条"
    fi

    echo "   ✓ 添加了 $ADDED 条自定义词条"
    [ $SKIPPED -gt 0 ] && echo "   ⊘ 跳过了 $SKIPPED 条（已在原始码表中）"
fi

# 验证合并文件存在且有内容
[ -f "$MERGED_TXT" ] || error_exit "✗ 错误: 合并文件不存在"
[ -s "$MERGED_TXT" ] || error_exit "✗ 错误: 合并文件为空"

echo

echo "2️⃣  编译数据库..."
# IBus Table 按 SERIAL_NUMBER 判断旧的候选缓存是否还能使用。
# 用合并后的码表计算版本号，自定义词条变动时也会使缓存失效。
CHECKSUM=$(cksum < "$MERGED_TXT") || error_exit "✗ 错误：无法计算码表版本号"
SERIAL_NUMBER=${CHECKSUM%% *}
sed "s/^SERIAL_NUMBER = [0-9][0-9]*$/SERIAL_NUMBER = $SERIAL_NUMBER/" \
    "$MERGED_TXT" > "$VERSIONED_TXT" || error_exit "✗ 错误：无法写入码表版本号"

ibus-table-createdb -s "$VERSIONED_TXT" -n "$BUILD_DB" || error_exit "✗ 错误：编译数据库失败"
[ -s "$BUILD_DB" ] || error_exit "✗ 错误：编译后找不到数据库"

echo "   ✓ 编译成功"
ls -lh "$BUILD_DB" | awk '{print "   (" $5 ")"}'

if [ "$BUILD_ONLY" -eq 1 ]; then
    install -D -m 644 -- "$BUILD_DB" "$OUTPUT_PATH" \
        || error_exit "✗ 错误：无法写入 $OUTPUT_PATH"
    echo "   ✓ 数据库已生成: $OUTPUT_PATH"
    exit 0
fi

echo

echo "3️⃣  部署到系统..."

if [ ! -w "$SYSTEM_DB" ]; then
    echo "   需要 sudo 权限来覆盖 $SYSTEM_DB"
    sudo install -m 644 -- "$BUILD_DB" "$SYSTEM_DB" || error_exit "✗ 错误: 无法使用 sudo 安装数据库"
    echo "   ✓ 已复制到 $SYSTEM_DB"
else
    install -m 644 -- "$BUILD_DB" "$SYSTEM_DB" || error_exit "✗ 错误: 无法安装数据库到 $SYSTEM_DB"
    echo "   ✓ 已复制到 $SYSTEM_DB"
fi

echo

echo "4️⃣  重启 ibus..."
ibus restart || error_exit "✗ 错误: ibus restart 失败"
sleep 2

echo "   ✓ ibus 已重启"

echo

echo "================================"
echo "✅ 完成！"
echo "================================"
echo

# 验证
echo "验证结果:"
if ibus list-engine 2>/dev/null | grep -q "table:zhengma"; then
    echo "   ✓ 郑码引擎已加载"
    ibus list-engine 2>/dev/null | grep "table:zhengma"
else
    echo "   ⚠ 警告: 未找到郑码引擎，请检查 ibus 是否正常"
fi
