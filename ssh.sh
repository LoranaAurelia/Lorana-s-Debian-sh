#!/usr/bin/env bash
# Debian 12/13 SSH one-click setup (bilingual, colored)
set -euo pipefail

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

say(){ cecho cyan "[Info] $1 | $2"; }
warn(){ cecho yellow "[Warning] $1 | $2"; }
err(){ cecho red "[Error] $1 | $2" >&2; }

require_root(){ if [ "${EUID:-$(id -u)}" -ne 0 ]; then err "请以 root 运行。" "Run as root."; exit 1; fi; }

check_debian(){
  . /etc/os-release 2>/dev/null || { err "缺少 /etc/os-release。" "Missing /etc/os-release."; exit 1; }
  case "${VERSION_CODENAME:-}" in
    bookworm|trixie) say "检测到 ${PRETTY_NAME}。" "Detected ${PRETTY_NAME}." ;;
    *) warn "非 Debian 12/13（${PRETTY_NAME:-unknown}）。" "Not Debian 12/13 (${PRETTY_NAME:-unknown})." ;;
  esac
}

ensure_packages(){
  say "安装/检查 openssh-server 等组件..." "Installing/checking openssh-server and tools..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  apt-get install -y --no-install-recommends openssh-server curl wget >/dev/null
  say "组件就绪。" "Components ready."
}

get_port(){
  local default_port="22" from_arg="${1:-}"
  SSH_PORT=""
  [ -n "$from_arg" ] && SSH_PORT="$from_arg"
  [ -z "${SSH_PORT:-}" ] && [ -n "${PORT:-}" ] && SSH_PORT="$PORT"

  if [ -z "${SSH_PORT:-}" ]; then
    if [ -r /dev/tty ]; then
      printf "\033[36m[Prompt] 请输入 SSH 端口（默认 %s）| Enter SSH port (default %s): \033[0m" "$default_port" "$default_port" > /dev/tty
      IFS= read -r SSH_PORT < /dev/tty || true
    fi
  fi
  SSH_PORT="${SSH_PORT:-$default_port}"

  if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    warn "端口无效，改用默认 $default_port。" "Invalid port, falling back to $default_port."
    SSH_PORT="$default_port"
  fi

  if ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${SSH_PORT}\$"; then
    warn "端口 $SSH_PORT 似乎在使用，仍将尝试。" "Port $SSH_PORT seems in use; proceeding."
  fi
  say "选定 SSH 端口：$SSH_PORT" "Selected SSH port: $SSH_PORT"
}

backup(){ [ -f "$1" ] && cp -a "$1" "$1.bak-$(date +%Y%m%d%H%M%S)" && say "已备份 $1。" "Backed up $1."; }

config_sshd(){
  local cfg="/etc/ssh/sshd_config"
  backup "$cfg"; touch "$cfg"
  sed -ri 's/^\s*#?\s*PermitRootLogin\s+.*/PermitRootLogin yes/' "$cfg" || true
  grep -qE '^\s*PermitRootLogin\s+' "$cfg" || echo "PermitRootLogin yes" >> "$cfg"
  sed -ri 's/^\s*#?\s*PasswordAuthentication\s+.*/PasswordAuthentication yes/' "$cfg" || true
  grep -qE '^\s*PasswordAuthentication\s+' "$cfg" || echo "PasswordAuthentication yes" >> "$cfg"
  sed -ri '/^\s*Port\s+[0-9]+/d' "$cfg"; echo "Port ${SSH_PORT}" >> "$cfg"
  sed -ri 's/^\s*#?\s*UsePAM\s+.*/UsePAM yes/' "$cfg" || true
  grep -qE '^\s*UsePAM\s+' "$cfg" || echo "UsePAM yes" >> "$cfg"
  if sshd -t 2>/tmp/sshd_err; then
    say "sshd 配置语法检查通过。" "sshd config syntax OK."
  else
    err "sshd 配置语法错误：$(cat /tmp/sshd_err)" "sshd config syntax error: $(cat /tmp/sshd_err)"; exit 1
  fi
}

restart_ssh(){ systemctl enable ssh >/dev/null 2>&1 || true; systemctl restart ssh; say "已重启 SSH 服务。" "SSH service restarted."; }

open_firewall(){
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi "Status: active"; then
    say "ufw 开放端口 ${SSH_PORT}/tcp。" "ufw allow ${SSH_PORT}/tcp."; ufw allow "${SSH_PORT}/tcp" || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    say "firewalld 开放端口 ${SSH_PORT}/tcp。" "firewalld open ${SSH_PORT}/tcp."
    firewall-cmd --permanent --add-port="${SSH_PORT}/tcp" || true
    firewall-cmd --add-port="${SSH_PORT}/tcp" || true
    firewall-cmd --reload || true
  fi
  say "如用 nftables/iptables 请确认已放行该端口。" "If using nftables/iptables, ensure the port is allowed."
}

detect_ips(){
  PUBLIC_IP=""
  if command -v curl >/dev/null 2>&1; then
    PUBLIC_IP="$(curl -fsS -4 https://ipinfo.io/ip || true)"
    [ -z "$PUBLIC_IP" ] && PUBLIC_IP="$(curl -fsS -6 https://ipinfo.io/ip || true)"
  elif command -v wget >/dev/null 2>&1; then
    PUBLIC_IP="$(wget -qO- -4 https://ipinfo.io/ip || true)"
    [ -z "$PUBLIC_IP" ] && PUBLIC_IP="$(wget -qO- -6 https://ipinfo.io/ip || true)"
  fi

  PRIV_V4="$(ip -o -4 addr show scope global up 2>/dev/null | awk '!/ lo /{print $4}' | cut -d/ -f1 | xargs || true)"
  PRIV_V6="$(ip -o -6 addr show scope global up 2>/dev/null | awk '!/ lo /{print $4}' | cut -d/ -f1 | xargs || true)"
  if [ -z "$PRIV_V4$PRIV_V6" ]; then
    PRIV_V4="$(hostname -I 2>/dev/null | xargs || true)"
  fi
}

print_connection_info(){
  detect_ips
  hr
  cecho green "Connection Info / 连接信息"
  cecho blue "Port: ${SSH_PORT}"
  cecho blue "Private IPv4 / 内网 IPv4: ${PRIV_V4:-N/A}"
  cecho blue "Private IPv6 / 内网 IPv6: ${PRIV_V6:-N/A}"
  cecho blue "Public IP / 公网: ${PUBLIC_IP:-N/A}"
  cecho blue "Account / 账号: root"
  echo
  cecho magenta "Built-in ssh (Linux/macOS/Windows) / 内置 ssh 命令："
  if [ -n "${PUBLIC_IP:-}" ]; then
    cecho cyan "ssh root@${PUBLIC_IP} -p ${SSH_PORT}"
  else
    if [ -n "${PRIV_V4:-}" ]; then
      for ip in $PRIV_V4; do cecho cyan "ssh root@${ip} -p ${SSH_PORT}"; done
    fi
    if [ -n "${PRIV_V6:-}" ]; then
      for ip in $PRIV_V6; do cecho cyan "ssh root@[${ip}] -p ${SSH_PORT}"; done
    fi
    [ -z "${PRIV_V4}${PRIV_V6}" ] && cecho cyan "ssh root@<IP-or-domain> -p ${SSH_PORT}"
  fi
  echo
  cecho magenta "scp example / scp 示例:"
  if [ -n "${PUBLIC_IP:-}" ]; then
    cecho cyan "scp -P ${SSH_PORT} ./localfile root@${PUBLIC_IP}:/root/"
  else
    cecho cyan "scp -P ${SSH_PORT} ./localfile root@<IP-or-domain>:/root/"
  fi
  cecho yellow "Security: root+password enabled, use a strong password."
  cecho yellow "安全：已启用 root+密码，请使用强密码。"
  hr
}

main(){
  require_root
  say "开始配置 SSH（root 登录 + 密码验证 + 端口设置）。" "Starting SSH config (root login + password auth + port)."
  check_debian
  ensure_packages

  PORT_ARG=""; ACCEPT_DEFAULT="0"
  while [ "${1:-}" ]; do
    case "$1" in
      --port|-p) PORT_ARG="${2:-}"; shift 2 ;;
      -y) ACCEPT_DEFAULT="1"; shift ;;
      *) shift ;;
    esac
  done
  [ "$ACCEPT_DEFAULT" = "1" ] && PORT_ARG="22"

  get_port "$PORT_ARG"
  config_sshd
  open_firewall
  restart_ssh

  print_connection_info

  say "完成。如无法连接，请检查防火墙/云安全组。" "Done. If connection fails, check firewall/cloud SG."
}
main "$@"
