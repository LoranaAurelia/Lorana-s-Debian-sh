#!/usr/bin/env bash
# zram + swap one-key installer (Interactive, APPLY mode)
# Debian/Ubuntu (apt-based). It WILL MODIFY the system.
# Author: Lorana helper (force-load module, idempotent, fallback with zramctl)

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

# ---------------- utils ----------------
ceil_div() { # ceil(a/b)
  local a="$1" b="$2"
  echo $(( (a + b - 1) / b ))
}

detect_mem_gib() {
  local mem_kib
  mem_kib=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)   # KiB
  local gib
  gib=$(ceil_div "$mem_kib" 1048576)                      # 1 GiB = 1048576 KiB
  echo "$gib"
}

round_up_int() { awk -v x="$1" 'BEGIN{printf "%d", (x == int(x) ? x : int(x)+1)}'; }

disk_free_gb_root() {
  # 可用空间（GiB，向下取整）
  df -BG / | awk 'NR==2{gsub("G","",$4); print int($4)}'
}

replace_or_append_fstab_line() {
  local line="$1"
  sudo sed -i '\|/swapfile|d' /etc/fstab
  echo "$line" | sudo tee -a /etc/fstab >/dev/null
}

bytes_from_gib_percent() { # args: mem_gb percent -> bytes
  awk -v m="$1" -v p="$2" 'BEGIN{
    # bytes = GiB * 1024^3 * percent/100
    printf "%.0f", m*1024*1024*1024*(p/100.0)
  }'
}

# ---------------- calculators ----------------
calc_sizes_simple() { # args: mem_gb preset -> stdout: "zram_percent swap_gb"
  local MEM="$1" PRE="$2"
  local zram_percent swap_gb
  case "$PRE" in
    1) # 轻度：ZRAM=50%，SWAP=内存/2
       zram_percent=50
       swap_gb=$(round_up_int "$(awk -v m="$MEM" 'BEGIN{print m*0.5}')")
       ;;
    2) # 中度：ZRAM=65%，SWAP=内存
       zram_percent=65
       swap_gb="$MEM"
       ;;
    3) # 重度：ZRAM=80%，SWAP=内存×2（上限 16G，避免把小盘写爆）
       zram_percent=80
       swap_gb=$(round_up_int "$(awk -v m="$MEM" 'BEGIN{print m*2.0}')")
       [[ "$swap_gb" -gt 16 ]] && swap_gb=16
       ;;
    *) cecho red "无效预设编号：$PRE"; exit 1;;
  esac
  echo "$zram_percent" "$swap_gb"
}

# ---------------- banners ----------------
intro() {
  hr
  cecho green "ZRAM + SWAP 一键配置器"
  echo "适用：Debian / Ubuntu（apt 系）"
  echo "策略：高优先级 ZRAM（压缩内存） + 低优先级 SWAP（兜底）"
  hr
}

presets_help() {
  hr
  cecho yellow "【简单模式（按 2C2G 场景参考；每增加 2G 内存，可大致提升 ~70% 负载预期。"
  cecho yellow "  若物理内存 ≥8G，通常直接使用“轻度”配置即可，ZRAM 已完全足够，Swap 保底也可避免 OOM。）】"
  echo

  cecho green  "1) 轻度（ZRAM=50%，SWAP=内存的一半）"
  echo "   适合场景："
  echo "   - 系统整体负载较轻，运行服务数量不多，主机物理内存基本够用；"
  echo "   - 主要作用是“保底”，防止突发性的内存占用导致 OOM 崩溃。"
  echo "   举例（Sealdice 部署）：单个中大型体量或三个内/小型体量的 Sealdice + 内置客户端/Lagrange；"
  echo "   或中型体量的 Sealdice + Napcat。"
  echo

  cecho blue   "2) 中度（ZRAM=65%，SWAP=内存）"
  echo "   适合场景："
  echo "   - 服务数量较多，内存峰值可能触及 OOM；"
  echo "   - 在性能与容错之间保持一定平衡。"
  echo "   举例（Sealdice 部署）：单个大型体量或三个中型体量的 Sealdice + 内置客户端/Lagrange；"
  echo "   或中型体量的 Sealdice + Napcat。"
  echo

  cecho yellow "3) 重度（ZRAM=80%，SWAP=内存×2，含上限保护）"
  echo "   适合场景："
  echo "   - 系统运行的服务非常多，几乎所有物理内存都会被吃光；"
  echo "   - 需要尽可能避免 OOM，在极限负载下为系统“兜底”。"
  echo "   举例（Sealdice 部署）：两个大型体量或五个中型体量的 Sealdice + 内置客户端/Lagrange；"
  echo "   或中型体量的 Sealdice + Napcat，同时还额外运行一个 Sealdice + 内置客户端/Lagrange。"
  echo

  cecho red    "⚠️ 重要警告："
  echo "   - ZRAM 与 SWAP 不是救世主！ZRAM 以 CPU 换内存，SWAP 完全依赖磁盘 I/O。内存极小却塞大量服务只会“能跑”，性能瓶颈巨大。"
  echo "   - 国内大多数云厂商磁盘 I/O 一般，指望 SWAP 顶内存会严重拖累性能。"
  echo "     ZRAM 救不了 Napcat ，因为它的瓶颈在硬盘，再大的 ZRAM/SWAP 也无济于事。"
  hr
}

advanced_help() {
  cecho yellow "【进阶模式】手动填写 ZRAM 百分比与 SWAP 大小（GiB）"
  echo "- 建议：ZRAM 50%~80%；SWAP 0.5×~2× 内存（取决于 I/O）"
  echo "- 优先级固定：ZRAM=100，SWAP=10；Swappiness=180（优先用 ZRAM）"
}

# ---------------- apply actions ----------------
apply_packages() {
  hr; cecho blue "安装依赖：zram-tools"; hr
  sudo apt-get update -y
  sudo apt-get install -y zram-tools bc util-linux
}

stop_and_clean_zram() {
  sudo systemctl stop zramswap 2>/dev/null || true
  # 卸载所有 zram swap
  awk 'NR>1 && $1 ~ /\/dev\/zram/ {print $1}' /proc/swaps 2>/dev/null | while read -r dev; do
    sudo swapoff "$dev" 2>/dev/null || true
  done
  # reset 设备
  for d in /dev/zram*; do
    [[ -e "$d" ]] || continue
    [[ -e /sys/block/${d##*/}/reset ]] && echo 1 | sudo tee /sys/block/${d##*/}/reset >/dev/null || true
  done
}

ensure_module_loaded() {
  # 持久化加载 + 立即加载
  echo zram | sudo tee /etc/modules-load.d/zram.conf >/dev/null
  sudo modprobe zram || true
}

apply_zram_conf() { # args: zram_percent mem_gb
  local ZP="$1" MEM="$2"
  hr; cecho blue "写入 /etc/default/zramswap 并启动"; hr
  sudo tee /etc/default/zramswap >/dev/null <<EOF
ALGO=zstd
PERCENT=${ZP}
PRIORITY=100
EOF

  ensure_module_loaded
  sudo systemctl daemon-reload || true
  sudo systemctl enable zramswap >/dev/null 2>&1 || true
  sudo systemctl restart zramswap || true

  # 验证是否已有 zram swap；否则手动兜底创建
  if ! awk 'NR>1 {print $1}' /proc/swaps | grep -q '^/dev/zram'; then
    cecho yellow "zramswap 未挂载 zram，使用 zramctl 兜底创建..."
    local bytes
    bytes=$(bytes_from_gib_percent "$MEM" "$ZP")

    # 清理可能存在的旧设备
    for d in /dev/zram*; do
      [[ -e "$d" ]] || continue
      sudo swapoff "$d" 2>/dev/null || true
      [[ -e /sys/block/${d##*/}/reset ]] && echo 1 | sudo tee /sys/block/${d##*/}/reset >/dev/null || true
    done

    # 创建并启用
    local DEV
    DEV=$(zramctl -f -s "${bytes}" -a zstd)
    [[ -z "$DEV" ]] && { cecho red "zramctl 创建设备失败"; exit 1; }
    sudo mkswap "$DEV" >/dev/null
    sudo swapon "$DEV" -p 100
  fi

  # 最终确认
  if ! awk 'NR>1 {print $1}' /proc/swaps | grep -q '^/dev/zram'; then
    cecho red "仍未检测到 zram 处于启用状态，请检查：journalctl -u zramswap、lsmod | grep zram"; exit 1
  fi
}

apply_sysctl() {
  hr; cecho blue "设置 vm.swappiness=180"; hr
  echo 'vm.swappiness=180' | sudo tee /etc/sysctl.d/99-swap.conf >/dev/null
  sudo sysctl -p /etc/sysctl.d/99-swap.conf >/dev/null
}

apply_swapfile() { # args: swap_gb
  local SZ="$1"
  hr; cecho blue "创建/更新 SWAP 文件：/swapfile (${SZ}G)"; hr

  # 磁盘空间检查
  local free_gb
  free_gb=$(disk_free_gb_root)
  if [[ "$free_gb" -lt "$((SZ + 1))" ]]; then
    cecho red "可用磁盘空间不足（当前 ${free_gb}G，可用需 ≥ $((SZ+1))G），中止。"
    exit 1
  fi

  # 关掉所有 swap（会把 /dev/zram* 也一起关掉）
  sudo swapoff -a || true

  # 删除旧 /swapfile 并重建
  sudo rm -f /swapfile || true
  sudo fallocate -l "${SZ}G" /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile >/dev/null
  sudo swapon /swapfile -p 10

  # 写入 fstab（可幂等）
  replace_or_append_fstab_line "/swapfile none swap sw,pri=10 0 0"

  # --- 关键补救：重新启用 ZRAM ---
  # 优先尝试通过服务恢复（由 apply_zram_conf 写好的 /etc/default/zramswap 生效）
  if systemctl is-enabled --quiet zramswap 2>/dev/null; then
    sudo systemctl restart zramswap || true
  fi

  # 兜底：若服务没把 zram 挂上，则手动把 /dev/zram* 再挂回（优先级 100）
  if ! awk 'NR>1 {print $1}' /proc/swaps | grep -q '^/dev/zram'; then
    for d in /dev/zram*; do
      [[ -e "$d" ]] || continue
      # 如果设备未初始化，先 mkswap；随后挂载并设高优先级
      sudo mkswap "$d" >/dev/null 2>&1 || true
      sudo swapon "$d" -p 100 2>/dev/null || true
    done
  fi
}

show_summary() {
  hr; cecho green "完成。当前 SWAP 设备："; hr
  swapon --show || true
  hr
  cecho blue "zramswap 服务状态（简要）："
  systemctl status zramswap --no-pager -l 2>/dev/null | sed -n '1,8p' || true
  hr
  cecho yellow "说明："
  echo "- ZRAM：算法 zstd，优先级 100；SWAP：/swapfile，优先级 10。"
  echo "- 该脚本可重复执行：会先清理旧 ZRAM/Swap 再重新配置。"
}

# ---------------- main ----------------
main() {
  intro

  local mem_gb zram_percent swap_gb
  mem_gb=$(detect_mem_gib)
  cecho green "检测到物理内存（向上取整）：${mem_gb}G"

  echo
  cecho blue "请选择模式："
  echo "  1) 简单模式（按部署体量选预设）"
  echo "  2) 进阶模式（自定义 ZRAM% 与 SWAP 大小）"
  read -rp "输入你的选择 [1/2]: " mode
  echo

  case "$mode" in
    1)
      presets_help
      read -rp "选择预设编号 [1/2/3]: " pre
      read -r zram_percent swap_gb <<<"$(calc_sizes_simple "$mem_gb" "$pre")"
      if [[ "$pre" == "3" ]]; then
        cecho red "注意：重度预设对磁盘 I/O 要求较高，低 I/O VPS 可能出现明显延迟。"
      fi
      ;;
    2)
      advanced_help
      read -rp "请输入 ZRAM 百分比（20~90，建议 50~80）: " zram_percent
      if ! [[ "$zram_percent" =~ ^[0-9]+$ ]] || [[ "$zram_percent" -lt 20 || "$zram_percent" -gt 90 ]]; then
        cecho red "ZRAM 百分比需为 20~90 的整数。"; exit 1
      fi
      read -rp "请输入 SWAP 文件大小（GiB，>=1 的整数）: " swap_gb
      if ! [[ "$swap_gb" =~ ^[0-9]+$ ]] || [[ "$swap_gb" -lt 1 ]]; then
        cecho red "SWAP 大小需为 >=1 的整数 GiB。"; exit 1
      fi
      ;;
    *)
      cecho red "无效选择。"; exit 1;;
  esac

  hr
  cecho green "将应用以下配置："
  echo " - 物理内存：${mem_gb}G"
  echo " - ZRAM：zstd，比例=${zram_percent}%（预估大小 ≈ $(awk -v m="$mem_gb" -v zp="$zram_percent" 'BEGIN{printf "%.1f", m*zp/100.0}')G）"
  echo " - SWAP：/swapfile = ${swap_gb}G"
  echo " - 优先级：ZRAM=100，SWAP=10；vm.swappiness=180"
  hr

  read -rp "确认执行？[y/N]: " yes
  [[ "${yes:-N}" =~ ^[Yy]$ ]] || { cecho yellow "已取消。"; exit 0; }

  apply_packages
  stop_and_clean_zram
  apply_zram_conf "$zram_percent" "$mem_gb"
  apply_swapfile "$swap_gb"
  apply_sysctl
  show_summary
}

main "$@"
