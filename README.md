# ibus-table-zhengma （个人定制版）

## 来源

本仓库基于 [hevz/ibus-table-zhengma](https://github.com/hevz/ibus-table-zhengma) 创建。

**上游信息**：
- 作者：Hevz <r@hev.cc>
- 许可证：GPL-3
- 序列号：20181006
- 源文件版本日期：2018-10-06

**复制日期**：2026-11-19

## 本仓库的目的

维护个人的郑码输入法自定义词库，包括：
- 原始的 `zhengma.txt` 码表
- 自定义词条列表 (`zhengma-custom.txt`)
- 自动化脚本（造词、编译、部署）

本仓库提供的是基于 **ibus-table** 的郑码码表，适合已经使用 IBus 的 Linux 桌面环境。安装步骤会因发行版和桌面环境而异；下文以 Ubuntu/Debian 系统的常见目录为例。

## 文件结构

```
.
├── zhengma.txt              ← 原始码表（来自 hevz）
├── zhengma.svg              ← 图标
├── zhengma-custom.txt       ← 自定义词条（词 TAB 编码）
├── build-zhengma.py         ← 造词脚本：自动计算编码
├── deploy.sh                ← 部署脚本：编译 + 安装
├── README.md                ← 本文件
└── zhengma.db               ← 当前部署脚本生成的数据库
```

## 使用方法

### 1. 添加新词

编辑 `zhengma-custom.txt`，每行格式：

```
词汇 TAB 编码
```

例如：
```
大模型	gfea
深度学习	deea
```

编码可以：
- **手动指定**（如果你知道的话）
- **或者留空** → 由脚本自动计算

### 2. 自动生成编码

```bash
python3 build-zhengma.py
```

脚本会：
1. 读取 `zhengma-custom.txt` 中编码为空的词
2. 根据构词规则 (`RULES = ce2:...; ce3:...; ca4:...`) 自动计算编码
3. 写回 `zhengma-custom.txt`
4. 输出日志

### 3. 编译 + 部署

在已安装 ibus-table 的 Linux 系统上运行：

```bash
bash deploy.sh
```

脚本会合并码表、生成 `zhengma.db`，安装到 `/usr/share/ibus-table/tables/` 并重启 IBus。需要 `ibus-table-createdb` 命令；如果系统提示找不到命令，请先安装发行版提供的 ibus-table 软件包。脚本可能会通过 `sudo` 请求权限。

## 安装方案

Gitee 上的[原安装说明](https://gitee.com/dunszou/ibus-table-zhengma)以 Ubuntu 20.04 为例，采用把数据库和图标复制到 ibus-table 系统目录、重新登录后在输入源设置中启用的方式。该说明也明确建议优先考虑 ibus-rime；这里记录的 ibus-table 安装流程是给需要使用本仓库这份码表的用户。Rime 与 ibus-table 使用不同格式的输入方案，不能直接拿本仓库的 `.db` 文件安装到 Rime。

### 方案一：从本仓库编译安装

1. 安装 IBus 和 ibus-table。Ubuntu/Debian 可执行：

   ```bash
   sudo apt update
   sudo apt install ibus ibus-table
   ```

2. 在本仓库目录运行 `bash deploy.sh`。脚本将合并 `zhengma.txt` 与 `zhengma-custom.txt`，编译出 `zhengma.db`，并安装到 `/usr/share/ibus-table/tables/`。
3. 安装输入法图标：

   ```bash
   sudo install -D -m 644 zhengma.svg /usr/share/ibus-table/icons/zhengma.svg
   ```

4. 刷新 IBus，然后在桌面环境的“设置 → 区域与语言 → 输入源”中添加中文郑码输入源：

   ```bash
   ibus restart
   ```

   若列表未更新，先注销并重新登录，再检查输入源列表。

### 方案二：手动安装已有数据库

如果不需要合并自定义词条或重新编译，可以使用仓库中的 `zhengma.db`：

```bash
sudo install -D -m 644 zhengma.db /usr/share/ibus-table/tables/zhengma.db
sudo install -D -m 644 zhengma.svg /usr/share/ibus-table/icons/zhengma.svg
ibus restart
```

之后在桌面环境的“设置 → 区域与语言 → 输入源”中添加中文郑码输入源；如果没有出现，注销并重新登录后再查看。不同发行版可能使用不同的安装目录或输入源界面，请以其 ibus-table 软件包布局为准。

### 卸载

删除本输入法安装的数据库和图标，然后重启 IBus：

```bash
sudo rm -f /usr/share/ibus-table/tables/zhengma.db
sudo rm -f /usr/share/ibus-table/icons/zhengma.svg
ibus restart
```

同时可在“输入源”设置中移除郑码。若原来已有同名数据库或图标，请先备份；上述命令会删除对应路径上的文件。

### 4. 恢复到原始码表

如果想恢复到原始 hevz 版本的码表（不含任何自定义词条），只需清空自定义词条文件再部署：

```bash
# 清空自定义词条
> zhengma-custom.txt

# 重新部署（此时仅包含原始码表）
bash deploy.sh
```

部署后生成的 `zhengma.db` 将仅包含原始码表（除 `AUTO_COMMIT = FALSE` 这个参数外，与 hevz 源码定义一致）。

## ☁️ 云端迁移

- **2026-11-19**：初始化，复制 hevz 版本

## 本仓库的改动

相对于上游 hevz 的 zhengma.txt，本仓库进行了以下修改：

### 1. 关闭"无重码自动上屏"

**改动**：`AUTO_COMMIT = FALSE`（第 64 行）

**原因**：郑码码表最大码长为 4，当输入 4 码且唯一匹配时会自动上屏，这对某些用户的输入习惯不适。

**上游状态**：`AUTO_COMMIT = TRUE`（默认启用）

**如何恢复**：若要启用自动上屏，编辑 `zhengma.txt` 改为 `AUTO_COMMIT = TRUE`，然后运行 `bash deploy.sh` 重新编译。

## 许可证

遵循 GPL-3（继承自 hevz 的原始项目，zhengma.txt 第 61 行声明 `LICENSE = GPL-3`）

## 贡献与致谢

- **上游作者**：Hevz <r@hev.cc>
- **郑码设计者**：郑易里教授、郑珑工程师
