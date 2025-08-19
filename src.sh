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

# ---------- 颜色 / Colors ----------
cecho() { # $1=color $2...=msg
  local c="${1:-}"; shift || true
  case "$c" in
    red)    printf "\033[31m%s\033[0m\n" "$*";;
    green)  printf "\033[32m%s\033[0m\n" "$*";;
    yellow) printf "\033[33m%s\033[0m\n" "$*";;
    blue)   printf "\033[34m%s\033[0m\n" "$*";;
    magenta)printf "\033[35m%s\033[0m\n" "$*";;
    cyan)   printf "\033[36m%s\033[0m\n" "$*";;
    *)      printf "%s\n" "$*";;
  esac
}
hr(){ printf -- "\033[90m------------------------------------------------------------\033[0m\n"; }

say(){ cecho cyan "$1 | $2"; }
warn(){ cecho yellow "$1 | $2"; }
err(){ cecho red "$1 | $2" >&2; }

# 解析可选参数（非交互）/ Optional non-interactive args
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
    err "[错误] 无法检测系统：缺少 /etc/os-release" "[Error] Cannot detect OS: /etc/os-release missing"
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
        *) err "[错误] 未支持的 Debian 版本：$PRETTY_NAME" "[Error] Unsupported Debian version: $PRETTY_NAME"; exit 1 ;;
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
        *) err "[错误] 未支持的 Ubuntu 版本：$PRETTY_NAME" "[Error] Unsupported Ubuntu version: $PRETTY_NAME"; exit 1 ;;
      esac
      ;;
    *)
      err "[错误] 未支持的发行版：$PRETTY_NAME" "[Error] Unsupported distribution: $PRETTY_NAME"
      exit 1
      ;;
  esac

  say "[信息] 检测到系统：$PRETTY_NAME（代号：$CODENAME）" "[Info] Detected: $PRETTY_NAME (codename: $CODENAME)"
}

# --- Mirror choice / 选择镜像 ---
choose_mirror() {
  local choice="${CHOICE_ARG:-}"

  if [ -z "$choice" ]; then
    hr
    cecho green "Debian/Ubuntu APT Mirror Switcher | APT 换源助手"
    hr
    cecho yellow "1) Tencent Cloud (mirrors.cloud.tencent.com)"
    cecho yellow "2) Aliyun        (mirrors.aliyun.com)"
    cecho yellow "3) Official      (官方镜像 / official)"
    hr
    if [ -r /dev/tty ]; then
      printf "\033[36mPlease enter your choice [1-3]: \033[0m" > /dev/tty
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
      err "[错误] 无效选择，已中止。" "[Error] Invalid choice. Aborting."
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
  cecho green "[完成] 已成功切换镜像并更新索引！ | [Done] Mirror switched and index updated successfully!"
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
