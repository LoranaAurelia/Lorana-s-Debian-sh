#!/usr/bin/env bash
set -euo pipefail

# ======= 配置 / Config =======
BASE="https://raw.githubusercontent.com/LoranaAurelia/Lorana-s-Debian-sh/main"
SSH_SCRIPT="ssh.sh"
SRC_SCRIPT="src.sh"
CN_SCRIPT="cn.sh"
SWAP_SCRIPT="swap.sh"
# ============================

# ---------- 颜色 / Colors ----------
# 用法：cecho green "文本"
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

say(){ # 彩色双语提示
  local zh="$1" en="$2"
  cecho cyan "$zh"
  cecho cyan "$en"
}

need_fetcher(){
  if command -v curl >/dev/null 2>&1; then
    FETCH="curl -fsSL"
  elif command -v wget >/dev/null 2>&1; then
    FETCH="wget -qO-"
  else
    say "[错误] 需要安装 curl 或 wget。" "[Error] curl or wget required."
    exit 1
  fi
}

run_remote(){
  local path="$1"
  local url="${BASE%/}/$path"
  need_fetcher
  hr
  cecho blue "[信息] 正在下载并执行：$url"
  cecho blue "[Info ] Fetching & running: $url"
  hr
  # 用 bash 执行远端脚本 / execute remote with bash
  bash -c "$($FETCH "$url")"
}

menu(){
  hr
  cecho green "== 一键门户 / One-Key Portal =="
  hr
  cecho yellow "1) SSH setup (${SSH_SCRIPT})        | 开启并配置 SSH"
  cecho yellow "2) APT mirror (${SRC_SCRIPT})       | 更换软件源"
  cecho yellow "3) Chinese support (${CN_SCRIPT})   | 中文显示支持"
  cecho yellow "4) Swap & ZRAM (${SWAP_SCRIPT})     | 配置 Swap 与 ZRAM"
  hr
}

# 选择：支持参数/环境变量/交互
CHOICE="${1:-${CHOICE:-}}"

if [[ -z "${CHOICE}" ]]; then
  menu
  if [[ -r /dev/tty ]]; then
    printf "\033[36mPick [1-4]: | 请输入数字 [1-4]： \033[0m" > /dev/tty
    IFS= read -r CHOICE < /dev/tty || true
  fi
fi

case "${CHOICE:-}" in
  1) run_remote "$SSH_SCRIPT" ;;
  2) run_remote "$SRC_SCRIPT" ;;
  3) run_remote "$CN_SCRIPT" ;;
  4) run_remote "$SWAP_SCRIPT" ;;
  *)
     cecho red "[错误] 无效选择：${CHOICE:-<空>}（应为 1/2/3/4）。"
     cecho red "[Error] Invalid choice: ${CHOICE:-<empty>} (expected 1/2/3/4)."
     menu
     cecho magenta "示例：curl -fsSL ${BASE%/}/p.sh | bash -s -- 4    # 直接执行 Swap & ZRAM"
     cecho magenta "Example: curl -fsSL ${BASE%/}/p.sh | bash -s -- 4  # run Swap & ZRAM directly"
     exit 1
     ;;
esac
