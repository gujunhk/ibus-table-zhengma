#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
自动生成郑码自定义词条的编码

根据郑码构词规则，自动从汉字的笔画码计算多字词的编码。

使用方法：
  python3 build-zhengma.py

输入：
  - zhengma.txt: 原始码表（包含 BEGIN_GOUCI/END_GOUCI 段的笔画码）
  - zhengma-custom.txt: 自定义词条列表（词汇，编码可选）

输出：
  - zhengma-custom.txt: 更新后的词条（自动填充编码）
"""

import re
import sys
from pathlib import Path


def parse_gouci(zhengma_txt_path):
    """从 zhengma.txt 的 BEGIN_GOUCI 段提取所有汉字的笔画码"""
    gouci = {}
    in_gouci = False

    try:
        with open(zhengma_txt_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.rstrip('\n')

                if line == 'BEGIN_GOUCI':
                    in_gouci = True
                    continue
                if line == 'END_GOUCI':
                    in_gouci = False
                    break

                if in_gouci and line and not line.startswith('#'):
                    parts = line.split('\t')
                    if len(parts) == 2:
                        char, code = parts
                        gouci[char] = code
    except FileNotFoundError:
        print(f"错误: 找不到文件 {zhengma_txt_path}", file=sys.stderr)
        sys.exit(1)

    return gouci


def parse_rules(zhengma_txt_path):
    """从 zhengma.txt 解析 RULES 行"""
    rules = {}

    with open(zhengma_txt_path, 'r', encoding='utf-8') as f:
        for line in f:
            if line.startswith('RULES = '):
                rules_str = line[8:].strip()
                # 格式：ce2:p11+p12+p21+p22;ce3:p11+p21+p22+p31;ca4:p11+p21+p31+p41
                for rule_part in rules_str.split(';'):
                    key, positions = rule_part.split(':')
                    pos_list = positions.split('+')
                    rules[key] = pos_list
                break

    return rules


def get_code_position(char_code, position_spec):
    """
    从字的编码中提取指定位置的字符

    位置格式如 "p11"、"p12" 等，其中：
    - 第一个数字是第几个字（1-4）
    - 第二个数字是该字编码中的第几个字符（1-4）
    """
    # 位置格式：p<字号><字符号>
    match = re.match(r'p(\d)(\d)', position_spec)
    if not match:
        return None

    char_idx = int(match.group(1)) - 1  # 转换为 0-based
    char_pos = int(match.group(2)) - 1  # 转换为 0-based

    return (char_idx, char_pos)


def calculate_code(phrase, gouci, rules):
    """
    根据构词规则计算多字词的编码

    Args:
        phrase: 汉字词组
        gouci: 汉字 -> 笔画码的映射
        rules: 构词规则 {'ce2': [...], 'ce3': [...], ...}

    Returns:
        编码字符串，或 None 如果无法计算
    """
    phrase_len = len(phrase)

    # 确定规则 key
    if phrase_len == 2:
        rule_key = 'ce2'
    elif phrase_len == 3:
        rule_key = 'ce3'
    elif phrase_len == 4:
        rule_key = 'ca4'
    else:
        return None  # 不支持的字数

    if rule_key not in rules:
        return None

    # 获取各个字的笔画码
    char_codes = []
    for char in phrase:
        if char not in gouci:
            return None  # 字找不到笔画码
        char_codes.append(gouci[char])

    # 按规则提取
    result = []
    for pos_spec in rules[rule_key]:
        char_idx, char_pos = get_code_position(pos_spec, pos_spec)

        if char_idx >= len(char_codes):
            return None

        code = char_codes[char_idx]
        if char_pos >= len(code):
            return None  # 该字的笔画码不够长

        result.append(code[char_pos])

    return ''.join(result)


def process_custom_words(custom_txt_path, zhengma_txt_path):
    """处理自定义词条，自动填充编码"""

    print(f"正在读取码表: {zhengma_txt_path}")
    gouci = parse_gouci(zhengma_txt_path)
    print(f"  ✓ 加载了 {len(gouci)} 个汉字的笔画码")

    rules = parse_rules(zhengma_txt_path)
    print(f"  ✓ 加载了 {len(rules)} 条构词规则: {', '.join(rules.keys())}")

    if not Path(custom_txt_path).exists():
        print(f"自定义词条文件不存在，创建空文件: {custom_txt_path}")
        Path(custom_txt_path).touch()
        return

    print(f"\n正在处理自定义词条: {custom_txt_path}")

    with open(custom_txt_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    updated = []
    generated_count = 0
    skipped_count = 0

    for line_no, line in enumerate(lines, 1):
        line = line.rstrip('\n')

        # 跳过注释和空行
        if not line or line.startswith('#'):
            updated.append(line)
            continue

        parts = line.split('\t')
        phrase = parts[0]
        code = parts[1].strip() if len(parts) > 1 else ''

        # 如果编码为空（无论是否有 TAB），尝试自动生成
        if not code:
            generated_code = calculate_code(phrase, gouci, rules)

            if generated_code:
                updated.append(f"{phrase}\t{generated_code}")
                print(f"  ✓ 行 {line_no}: {phrase:10} → {generated_code}")
                generated_count += 1
            else:
                # 生成失败，保持原样
                updated.append(line)
                print(f"  ✗ 行 {line_no}: {phrase:10} → 无法生成编码")
                skipped_count += 1
        else:
            # 编码已有，保持原样
            updated.append(line)

    # 写回文件
    with open(custom_txt_path, 'w', encoding='utf-8') as f:
        for line in updated:
            f.write(line + '\n')

    print(f"\n完成！")
    print(f"  自动生成: {generated_count} 条")
    print(f"  无法生成: {skipped_count} 条")
    print(f"  已写入: {custom_txt_path}")


if __name__ == '__main__':
    # 获取脚本所在目录
    script_dir = Path(__file__).parent

    zhengma_txt = script_dir / 'zhengma.txt'
    custom_txt = script_dir / 'zhengma-custom.txt'

    if not zhengma_txt.exists():
        print(f"错误: 找不到 {zhengma_txt}", file=sys.stderr)
        sys.exit(1)

    process_custom_words(str(custom_txt), str(zhengma_txt))
