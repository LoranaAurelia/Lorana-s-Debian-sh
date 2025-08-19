
# 🛠 雪桃的Debian快速初配置脚本

本仓库包含四个 Bash 脚本，适用于 **Debian 12/13 (以及部分 Ubuntu)** 的快速初始化和常见环境修复：

* `p.sh`：门户脚本（入口统一，远程执行其他脚本）
* `ssh.sh`：一键开启并配置 SSH（支持 root 登录、端口自定义、防火墙放行等）
* `src.sh`：APT 源更换助手（支持腾讯云、阿里云、官方）
* `cn.sh`：中文显示修复器（locale、ncurses、screen/tmux/git 等）

---

## 📦 依赖

所有脚本均需 **root 权限** 执行（sudo不行）。

* `bash`
* `curl` 或 `wget` （二选一即可）

---

## 🚀 远程执行（推荐方式）

先装依赖：
```
apt install bash curl wget sudo
```
然后执行门户脚本入口：
```
sudo bash -c "$(curl -fsSL https://sdsh.cn.xuetao.host/p.sh)"
```
或者你也可以使用wget：
```
sudo bash -c "$(wget -qO- https://sdsh.cn.xuetao.host/p.sh)"
```
上面的是中国访问优化的地址，如果你想直接在Github拉取：

```
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/LoranaAurelia/Lorana-s-Debian-sh/main/p.sh)"
```
```
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/LoranaAurelia/Lorana-s-Debian-sh/main/p.sh)"
```
