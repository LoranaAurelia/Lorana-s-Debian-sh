#!/usr/bin/env bash
set -euo pipefail

SOURCE_LIST="/etc/apt/sources.list"
BACKUP_LIST="/etc/apt/sources.list.bak.$(date +%s)"

# choose sudo if not root
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

say(){ printf "%s\n" "$1 | $2"; }

# 解析可选参数（非交互）/ Optional non-interactive args
# 用法: --tencent / --aliyun / --official 或 -t/-a/-o
CHOICE_ARG="${CHOICE:-}"  # 也支持 env: CHOICE=1/2/3
while [ "${1:-}" ]; do
  case "$1" in
    --tencent|-t) CHOICE_ARG="1"; shift ;;
    --aliyun|-a)  CHOICE_ARG="2"; shift ;;
    --official|-o)CHOICE_ARG="3"; shift ;;
    *) shift ;;
  esac
done

# --- Detect OS / 识别系统 ---
detect_os() {
  if [ ! -r /etc/os-release ]; then
    say "[错误] 无法检测系统：缺少 /etc/os-release" "[Error] Cannot detect OS: /etc/os-release missing"
    exit 1
  fi
  . /etc/os-release

  ID_LC="${ID,,}"
  CODENAME="${VERSION_CODENAME:-}"
  VERSION_ID_TXT="${VERSION_ID:-}"

  case "$ID_LC" in
    debian)
      if [ -z "$CODENAME" ]; then
        case "$VERSION_ID_TXT" in
          11*) CODENAME="bullseye" ;;
          12*) CODENAME="bookworm" ;;
          13*) CODENAME="trixie" ;;
        esac
      fi
      case "$CODENAME" in
        bullseye|bookworm|trixie) DISTRO="debian" ;;
        *) say "[错误] 未支持的 Debian 版本：$PRETTY_NAME" "[Error] Unsupported Debian version: $PRETTY_NAME"; exit 1 ;;
      esac
      ;;
    ubuntu)
      if [ -z "$CODENAME" ]; then
        case "$VERSION_ID_TXT" in
          22.04*) CODENAME="jammy" ;;
          24.04*) CODENAME="noble" ;;
        esac
      fi
      case "$CODENAME" in
        jammy|noble) DISTRO="ubuntu" ;;
        *) say "[错误] 未支持的 Ubuntu 版本：$PRETTY_NAME" "[Error] Unsupported Ubuntu version: $PRETTY_NAME"; exit 1 ;;
      esac
      ;;
    *)
      say "[错误] 未支持的发行版：$PRETTY_NAME" "[Error] Unsupported distribution: $PRETTY_NAME"
      exit 1
      ;;
  esac

  say "[信息] 检测到系统：$PRETTY_NAME（代号：$CODENAME）" "[Info] Detected: $PRETTY_NAME (codename: $CODENAME)"
}

# --- Mirror choice / 选择镜像 ---
choose_mirror() {
  local choice="${CHOICE_ARG:-}"

  if [ -z "$choice" ]; then
    echo "=============================="
    echo "Debian/Ubuntu APT Mirror Switcher | APT 换源助手"
    echo "=============================="
    echo "1) Tencent Cloud (mirrors.cloud.tencent.com)"
    echo "2) Aliyun        (mirrors.aliyun.com)"
    echo "3) Official      (官方镜像 / official)"
    echo "=============================="
    if [ -r /dev/tty ]; then
      # 关键：从 /dev/tty 读取，管道执行也能交互
      printf "Please enter your choice [1-3]: " > /dev/tty
      IFS= read -r choice < /dev/tty || true
    fi
  fi

  case "$choice" in
    1)
      if [ "$DISTRO" = "debian" ]; then
        MIRROR="http://mirrors.cloud.tencent.com/debian"
        SECURITY="http://mirrors.cloud.tencent.com/debian-security"
      else
        MIRROR="http://mirrors.cloud.tencent.com/ubuntu"
        SECURITY="http://mirrors.cloud.tencent.com/ubuntu"
      fi
      NAME="Tencent Cloud | 腾讯云"
      ;;
    2)
      if [ "$DISTRO" = "debian" ]; then
        MIRROR="http://mirrors.aliyun.com/debian"
        SECURITY="http://mirrors.aliyun.com/debian-security"
      else
        MIRROR="http://mirrors.aliyun.com/ubuntu"
        SECURITY="http://mirrors.aliyun.com/ubuntu"
      fi
      NAME="Aliyun | 阿里云"
      ;;
    3|"")
      # 允许直接回车默认官方源 / Empty = default to official
      if [ "$DISTRO" = "debian" ]; then
        MIRROR="http://deb.debian.org/debian"
        SECURITY="http://security.debian.org/debian-security"
      else
        MIRROR="http://archive.ubuntu.com/ubuntu"
        SECURITY="http://security.ubuntu.com/ubuntu"
      fi
      NAME="Official | 官方"
      ;;
    *)
      say "[错误] 无效选择，已中止。" "[Error] Invalid choice. Aborting."
      exit 1
      ;;
  esac

  say "[信息] 已选择镜像：$NAME" "[Info] Selected mirror: $NAME"
}

backup_sources() {
  say "[信息] 备份当前 sources.list 到：$BACKUP_LIST" "[Info] Backing up current sources.list to: $BACKUP_LIST"
  $SUDO cp -f "$SOURCE_LIST" "$BACKUP_LIST" 2>/dev/null || true
}

write_debian_sources() {
  case "$CODENAME" in
    bullseye) SEC_SUITE="bullseye-security" ;;
    bookworm) SEC_SUITE="bookworm-security" ;;
    trixie)   SEC_SUITE="trixie-security" ;;
  esac

  say "[信息] 写入 Debian 源到 $SOURCE_LIST" "[Info] Writing Debian sources to $SOURCE_LIST"
  $SUDO tee "$SOURCE_LIST" > /dev/null <<EOF
deb $MIRROR $CODENAME main contrib non-free non-free-firmware
deb-src $MIRROR $CODENAME main contrib non-free non-free-firmware

deb $SECURITY $SEC_SUITE main contrib non-free non-free-firmware
deb-src $SECURITY $SEC_SUITE main contrib non-free non-free-firmware

deb $MIRROR ${CODENAME}-updates main contrib non-free non-free-firmware
deb-src $MIRROR ${CODENAME}-updates main contrib non-free non-free-firmware

deb $MIRROR ${CODENAME}-backports main contrib non-free non-free-firmware
deb-src $MIRROR ${CODENAME}-backports main contrib non-free non-free-firmware
EOF
}

write_ubuntu_sources() {
  say "[信息] 写入 Ubuntu 源到 $SOURCE_LIST" "[Info] Writing Ubuntu sources to $SOURCE_LIST"
  $SUDO tee "$SOURCE_LIST" > /dev/null <<EOF
deb $MIRROR $CODENAME main restricted universe multiverse
deb-src $MIRROR $CODENAME main restricted universe multiverse

deb $MIRROR ${CODENAME}-updates main restricted universe multiverse
deb-src $MIRROR ${CODENAME}-updates main restricted universe multiverse

deb $SECURITY ${CODENAME}-security main restricted universe multiverse
deb-src $SECURITY ${CODENAME}-security main restricted universe multiverse

deb $MIRROR ${CODENAME}-backports main restricted universe multiverse
deb-src $MIRROR ${CODENAME}-backports main restricted universe multiverse
EOF
}

apt_update() {
  say "[信息] 正在更新索引，请稍候…" "[Info] Updating package index..."
  $SUDO apt update
  say "[完成] 已成功切换镜像并更新索引！" "[Done] Mirror switched and index updated successfully!"
}

main() {
  detect_os
  choose_mirror
  backup_sources
  if [ "$DISTRO" = "debian" ]; then
    write_debian_sources
  else
    write_ubuntu_sources
  fi
  apt_update
}

main "$@"
