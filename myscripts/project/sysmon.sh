#!/bin/bash
#
# sysmon.sh - A simple Linux System Monitoring Tool
#
# Reads live system stats directly from /proc and standard utilities
# (no external dependencies like psutil needed) and displays them in
# a refreshing dashboard. Optionally logs snapshots to a CSV file.
#
# Usage:
#   ./sysmon.sh                 # run with default 2s refresh
#   ./sysmon.sh -i 5            # refresh every 5 seconds
#   ./sysmon.sh -l sysmon.log   # also log each snapshot to a CSV file
#   ./sysmon.sh -i 5 -l sysmon.log
#
# Press Ctrl+C to quit.

set -euo pipefail

INTERVAL=2
LOGFILE=""

# ---------- Parse arguments ----------
while getopts ":i:l:h" opt; do
  case "$opt" in
    i) INTERVAL="$OPTARG" ;;
    l) LOGFILE="$OPTARG" ;;
    h)
      echo "Usage: $0 [-i interval_seconds] [-l logfile.csv]"
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# If logging, write CSV header once
if [[ -n "$LOGFILE" && ! -f "$LOGFILE" ]]; then
  echo "timestamp,cpu_percent,mem_used_percent,disk_root_used_percent,load_1m" > "$LOGFILE"
fi

# ---------- CPU usage (delta of /proc/stat over 1 second) ----------
get_cpu_usage() {
  # Read first sample
  read -r cpu user1 nice1 system1 idle1 iowait1 irq1 softirq1 steal1 _ < /proc/stat
  sleep 1
  # Read second sample
  read -r cpu user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 _ < /proc/stat

  prev_idle=$((idle1 + iowait1))
  idle_now=$((idle2 + iowait2))

  prev_non_idle=$((user1 + nice1 + system1 + irq1 + softirq1 + steal1))
  non_idle_now=$((user2 + nice2 + system2 + irq2 + softirq2 + steal2))

  prev_total=$((prev_idle + prev_non_idle))
  total_now=$((idle_now + non_idle_now))

  total_delta=$((total_now - prev_total))
  idle_delta=$((idle_now - prev_idle))

  if [[ "$total_delta" -eq 0 ]]; then
    echo "0.0"
  else
    awk -v td="$total_delta" -v idl="$idle_delta" 'BEGIN { printf "%.1f", (td - idl) / td * 100 }'
  fi
}

# ---------- Memory usage ----------
get_memory_stats() {
  awk '
    /^MemTotal:/     { total = $2 }
    /^MemAvailable:/ { avail = $2 }
    END {
      used = total - avail
      pct = (total > 0) ? (used / total * 100) : 0
      printf "%.1f|%.0f|%.0f", pct, used/1024, total/1024
    }
  ' /proc/meminfo
}

# ---------- Disk usage (root filesystem) ----------
get_disk_usage() {
  df -h / | awk 'NR==2 { gsub("%","",$5); print $5"|"$3"|"$2 }'
}

# ---------- Load average ----------
get_load_avg() {
  awk '{ print $1, $2, $3 }' /proc/loadavg
}

# ---------- Network throughput (bytes since boot, cumulative) ----------
get_network_stats() {
  # Sum rx/tx bytes across all interfaces except loopback
  awk -F: '
    NR > 2 && $1 !~ /lo/ {
      split($2, a, " ")
      rx += a[1]
      tx += a[9]
    }
    END { printf "%.1f|%.1f", rx/1024/1024, tx/1024/1024 }
  ' /proc/net/dev
}

# ---------- Top 5 processes by CPU ----------
get_top_processes() {
  ps -eo pid,comm,%cpu,%mem --sort=-%cpu --no-headers | head -n 5
}

# ---------- Uptime ----------
get_uptime() {
  uptime -p 2>/dev/null || awk '{printf "%.0f minutes", $1/60}' /proc/uptime
}

# ---------- Main display loop ----------
trap 'echo -e "\nExiting sysmon. Goodbye!"; exit 0' INT

while true; do
  clear
  timestamp=$(date "+%Y-%m-%d %H:%M:%S")

  cpu_pct=$(get_cpu_usage)
  IFS='|' read -r mem_pct mem_used_mb mem_total_mb <<< "$(get_memory_stats)"
  IFS='|' read -r disk_pct disk_used disk_total <<< "$(get_disk_usage)"
  read -r load1 load5 load15 <<< "$(get_load_avg)"
  IFS='|' read -r net_rx_mb net_tx_mb <<< "$(get_network_stats)"
  sys_uptime=$(get_uptime)

  echo "============================================================"
  echo "  SYSMON - Simple Linux System Monitor        $timestamp"
  echo "============================================================"
  echo " Uptime      : $sys_uptime"
  echo " Load Avg    : 1m=$load1  5m=$load5  15m=$load15"
  echo ""
  echo " CPU Usage   : ${cpu_pct}%"
  printf "   ["
  bars=$(awk -v p="$cpu_pct" 'BEGIN { printf "%d", p/2 }')
  for ((i=0; i<50; i++)); do
    if (( i < bars )); then printf "#"; else printf "."; fi
  done
  echo "]"
  echo ""
  echo " Memory      : ${mem_pct}%  (${mem_used_mb} MB / ${mem_total_mb} MB)"
  echo " Disk (/)    : ${disk_pct}%  (${disk_used} used / ${disk_total} total)"
  echo " Network     : RX ${net_rx_mb} MB  |  TX ${net_tx_mb} MB  (cumulative since boot)"
  echo ""
  echo " Top 5 Processes by CPU:"
  echo "   PID    COMMAND              %CPU   %MEM"
  get_top_processes | awk '{printf "   %-6s %-18s %-6s %-6s\n", $1, $2, $3, $4}'
  echo "============================================================"
  echo " Refreshing every ${INTERVAL}s | Press Ctrl+C to quit"

  if [[ -n "$LOGFILE" ]]; then
    echo "$timestamp,$cpu_pct,$mem_pct,$disk_pct,$load1" >> "$LOGFILE"
    echo " Logging to: $LOGFILE"
  fi

  sleep "$INTERVAL"
done
