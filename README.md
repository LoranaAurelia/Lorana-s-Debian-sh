好的 ✅ 我帮你写一个 `README.md`，把这四个脚本的用途、依赖包、以及通过 **门户脚本 p.sh** 的远程执行方法写清楚。

---

# 🛠 一键运维脚本集

本仓库包含四个 Bash 脚本，适用于 **Debian 12/13 (以及部分 Ubuntu)** 的快速初始化和常见环境修复：

* `p.sh`：门户脚本（入口统一，远程执行其他脚本）
* `ssh.sh`：一键开启并配置 SSH（支持 root 登录、端口自定义、防火墙放行等）
* `src.sh`：APT 源更换助手（支持腾讯云、阿里云、官方）
* `cn.sh`：中文显示修复器（locale、ncurses、screen/tmux/git 等）

---

## 📦 依赖

所有脚本均需 **root 权限**（必须 `sudo` 执行）。
脚本会自动检测/安装必要的软件包：

* `bash`
* `curl` 或 `wget` （二选一即可）
* `sudo`（如非 root 用户调用）

---

## 🚀 远程执行（推荐方式）

门户脚本统一入口：

```bash
# 使用 curl
sudo bash -c "$(curl -fsSL https://sdsh.cn.xuetao.host/p.sh)" -- <编号>

# 使用 wget
sudo bash -c "$(wget -qO- https://sdsh.cn.xuetao.host/p.sh)" -- <编号>
```

其中 `<编号>` 可选：

* `1` = SSH 安装与配置（ssh.sh）
* `2` = 更换 APT 源（src.sh）
* `3` = 中文显示修复（cn.sh）

例如：

```bash
# 一键安装并配置 SSH
sudo bash -c "$(curl -fsSL https://sdsh.cn.xuetao.host/p.sh)" -- 1

# 更换软件源
sudo bash -c "$(curl -fsSL https://sdsh.cn.xuetao.host/p.sh)" -- 2

# 修复中文显示
sudo bash -c "$(curl -fsSL https://sdsh.cn.xuetao.host/p.sh)" -- 3
```

---

## 📜 脚本说明

### 1. ssh.sh

* 安装 `openssh-server`
* 开启 root 登录、密码认证
* 配置端口（默认 22，可交互修改或用参数 `--port`）
* 自动检测公网/私网 IP 并打印连接信息
* 自动放行防火墙（支持 `ufw` / `firewalld`）

---

### 2. src.sh

* 自动识别系统版本（Debian 11/12/13，Ubuntu 22.04/24.04）
* 交互选择镜像源（腾讯云 / 阿里云 / 官方）
* 自动备份 `/etc/apt/sources.list` 并写入新源
* 自动执行 `apt update`

---

### 3. cn.sh

* 安装 `locales`、`ncurses-term` 等必要组件
* 自动生成并设置 `zh_CN.UTF-8`
* 修复 `screen` / `tmux` / `less` / `git` / `readline` 的中文兼容
* 修改 `sshd_config`，允许 `LANG/LC_*` 环境传递
* 输出验证与提示

---

### 4. p.sh

* 门户脚本，统一入口
* 负责下载并执行远程脚本
* 自动检测 `curl` 或 `wget`

---

## 🔒 注意事项

* 所有操作需 **root 权限**（如非 root 请加 `sudo`）。
* 建议在 **新装系统/测试环境** 先验证，再在生产环境使用。
* SSH 脚本会开启 **root + 密码** 登录，请务必修改为强密码，或后续改用密钥登录。

---
