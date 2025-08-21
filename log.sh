#!/usr/bin/env bash
# journald log limiter (Interactive, APPLY mode)
# Debian/Ubuntu (apt-based). It WILL MODIFY the system.
# Author: Lorana helper (idempotent, cron vacuum, volatile option)

set -euo pipefail

# ---------------- UI helpers ----------------
cecho() { # $1=color $2=msg
  local c="$1"; shift
  case "$c" in
    red)    printf "\033[31m%s\033[0m\n" "$*";;
    green)  printf "\033[32m%s\033[0m\n" "$*";;
    yellow) printf "\033[33m%s\033[0m\n" "$*";;
    blue)   printf "\033[34m%s\033[0m\n" "$*";;
    *)      printf "%s\n" "$*";;
  esac
}
hr() { printf -- "------------------------------------------------------------\n"; }

trap 'cecho red "发生错误，中止运行。请检查上方日志。"; exit 1' ERR

JOURNAL_CONF="/etc/systemd/journald.conf"
CLEAN_SCRIPT="/usr/local/bin/clean-journal.sh"

# ---------------- helpers ----------------
ensure_tools() {
  # journalctl 属于 systemd-journald；crontab 属于 cron/cron-extra
  sudo apt-get update -y
  sudo apt-get install -y cron
  sudo systemctl enable --now cron >/dev/null 2>&1 || true
}

remove_keys() {
  # 从 journald.conf 移除我们会写入的键，避免重复
  sudo sed -i \
    -e '/^[[:space:]]*SystemMaxUse=/d' \
    -e '/^[[:space:]]*SystemKeepFree=/d' \
    -e '/^[[:space:]]*SystemMaxFileSize=/d' \
    -e '/^[[:space:]]*SystemMaxFiles=/d' \
    -e '/^[[:space:]]*Storage=/d' \
    "$JOURNAL_CONF"
}

append_journal_block() {
  # 直接追加键值（不强制 [Journal] 段落，systemd 会解析）
  sudo tee -a "$JOURNAL_CONF" >/dev/null <<EOF
SystemMaxUse=$1
SystemKeepFree=$2
SystemMaxFileSize=$3
SystemMaxFiles=$4
$5
EOF
}

apply_journald_limits() { # args: max_use keep_free max_file_size max_files storage_line
  hr; cecho blue "写入 journald 配置并重启"; hr
  sudo touch "$JOURNAL_CONF"
  remove_keys
  append_journal_block "$1" "$2" "$3" "$4" "$5"
  sudo systemctl restart systemd-journald
}

install_clean_script() { # arg: vacuum_size like "500M" or "" to skip
  hr; cecho blue "创建/更新清理脚本与 cron 计划任务"; hr

  if [[ -n "${1:-}" ]]; then
    sudo tee "$CLEAN_SCRIPT" >/dev/null <<EOF
#!/bin/bash
# 自动清理 systemd-journald 日志
/usr/bin/journalctl --vacuum-size=$1
EOF
    sudo chmod +x "$CLEAN_SCRIPT"

    # 写入 root 的 crontab（避免重复）
    ( sudo crontab -l 2>/dev/null | grep -v "$CLEAN_SCRIPT" ; echo "0 2 * * * $CLEAN_SCRIPT" ) | sudo crontab -
    cecho green "已安装 daily vacuum 任务：每天 02:00 维持至 $1"
  else
    # 取消已存在的任务（若有）
    if sudo crontab -l 2>/dev/null | grep -q "$CLEAN_SCRIPT"; then
      sudo crontab -l 2>/dev/null | grep -v "$CLEAN_SCRIPT" | sudo crontab -
    fi
    sudo rm -f "$CLEAN_SCRIPT" || true
    cecho yellow "未配置定时清理（按预设要求跳过）。"
  fi
}

vacuum_now() { # arg: target like "500M" or "1G"
  cecho yellow "执行一次即时收缩：journalctl --vacuum-size=$1"
  sudo journalctl --vacuum-size="$1" || true
}

make_persistent_if_needed() {
  # Storage=auto 默认：如果 /var/log/journal 存在则持久化
  # 对于非 volatile 预设，确保目录存在以启用持久化限额
  sudo mkdir -p /var/log/journal
  sudo systemd-tmpfiles --create --prefix /var/log/journal >/dev/null 2>&1 || true
}

set_volatile_storage() {
  # Storage=volatile：仅内存日志（重启丢失，不写盘）
  # 同时清掉磁盘持久化痕迹并收缩
  sudo sed -i '/^[[:space:]]*Storage=/d' "$JOURNAL_CONF"
  echo "Storage=volatile" | sudo tee -a "$JOURNAL_CONF" >/dev/null
  sudo systemctl restart systemd-journald

  # 尽量释放磁盘占用
  sudo journalctl --vacuum-time=1s || true
  sudo rm -rf /var/log/journal 2>/dev/null || true
}

summary() {
  hr; cecho green "完成。当前 journald 磁盘占用："; hr
  journalctl --disk-usage || true
  hr
  cecho blue "当前配置片段（grep）："
  grep -E '^(SystemMaxUse|SystemKeepFree|SystemMaxFileSize|SystemMaxFiles|Storage)=' "$JOURNAL_CONF" || true
  hr
}

# ---------------- banners ----------------
intro() {
  hr
  cecho green "journald 日志上限一键配置器"
  echo "适用：Debian / Ubuntu（apt 系）"
  echo "目标：限制 /var/log（journald）占用，自动/按需清理"
  hr
}

presets_help() {
  echo
  echo "选择预设"
  cecho yellow "【预设说明】"
  echo
  cecho green  "1) 最小化（推荐大多数用户）"
  echo "   - SystemMaxUse=500M  KeepFree=50M  MaxFileSize=100M  MaxFiles=5"
  echo "   - 每天 02:00 vacuum 到 500M"
  echo
  cecho blue   "2) 小体量服务"
  echo "   - SystemMaxUse=1G    KeepFree=100M MaxFileSize=200M  MaxFiles=8"
  echo "   - 每天 02:00 vacuum 到 1G"
  echo
  cecho blue   "3) 中体量服务"
  echo "   - SystemMaxUse=2G    KeepFree=200M MaxFileSize=300M  MaxFiles=10"
  echo "   - 每天 02:00 vacuum 到 2G"
  echo
  cecho red    "4) 纯内存日志（极限精简。注意：此选项每次重启后系统日志都将被清空！）"
  echo "   - Storage=volatile（只存内存，重启后清空，不写盘）"
  echo "   - 不创建定时任务；立刻清空磁盘持久化"
  hr
}

# ---------------- main ----------------
main() {
  intro
  ensure_tools

  # 一次性打印预设说明
  presets_help
  echo
  read -rp "请选择预设编号 [1/2/3/4]: " pre
  echo

  case "${pre:-}" in
    1)
      hr; cecho green "应用：最小化（500M）"; hr
      make_persistent_if_needed
      apply_journald_limits "500M" "50M" "100M" "5" ""
      install_clean_script "500M"
      vacuum_now "500M"
      ;;
    2)
      hr; cecho green "应用：小体量（1G）"; hr
      make_persistent_if_needed
      apply_journald_limits "1G" "100M" "200M" "8" ""
      install_clean_script "1G"
      vacuum_now "1G"
      ;;
    3)
      hr; cecho green "应用：中体量（2G）"; hr
      make_persistent_if_needed
      apply_journald_limits "2G" "200M" "300M" "10" ""
      install_clean_script "2G"
      vacuum_now "2G"
      ;;
    4)
      hr; cecho green "应用：纯内存日志（volatile）"; hr
      set_volatile_storage
      install_clean_script ""   # 不设定时清理
      ;;
    *)
      cecho red "无效选择：${pre:-<空>}（应为 1/2/3/4）。"
      exit 1;;
  esac

  summary
  cecho yellow "提示：如需临时查看磁盘占用，可执行：journalctl --disk-usage"
}

main "$@"
