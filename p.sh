#!/usr/bin/env bash
set -euo pipefail

# ======= 配置 / Config =======
BASE="https://raw.githubusercontent.com/LoranaAurelia/Lorana-s-Debian-sh/main"
SSH_SCRIPT="ssh.sh"
SRC_SCRIPT="src.sh"
CN_SCRIPT="cn.sh"
# ============================

say(){ printf "%s\n" "$1 | $2"; }

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
  say "[信息] 正在下载并执行：$url" "[Info] Fetching & running: $url"
  # 用 bash 执行远端脚本 / execute remote with bash
  bash -c "$($FETCH "$url")"
}

menu(){
  echo "=============================="
  echo "1) SSH setup (ssh.sh) | 开启并配置 SSH"
  echo "2) APT mirror (src.sh) | 更换软件源"
  echo "3) Chinese support (cn.sh) | 中文显示支持"
  echo "=============================="
}

# 选择：支持参数/环境变量/交互
CHOICE="${1:-${CHOICE:-}}"

if [[ -z "${CHOICE}" ]]; then
  menu
  if [[ -r /dev/tty ]]; then
    printf "Pick [1-3]: | 请输入数字 [1-3]： " > /dev/tty
    IFS= read -r CHOICE < /dev/tty || true
  fi
fi

case "${CHOICE:-}" in
  1) run_remote "$SSH_SCRIPT" ;;
  2) run_remote "$SRC_SCRIPT" ;;
  3) run_remote "$CN_SCRIPT" ;;
  *) 
     say "[错误] 无效选择：${CHOICE:-<空>}（应为 1/2/3）。" "[Error] Invalid choice: ${CHOICE:-<empty>} (expected 1/2/3)."
     menu
     say "示例：curl -fsSL ${BASE%/}/p.sh | bash -s -- 1" "Example: curl -fsSL ${BASE%/}/p.sh | bash -s -- 1"
     exit 1
     ;;
esac
