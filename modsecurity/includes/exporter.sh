#!/bin/bash
# 安装 node exporter 并尽量自动注册到 Prometheus
# 依赖 shared.sh: log warn error

EXPORTER_LISTEN_PORT="${EXPORTER_LISTEN_PORT:-9100}"
PROM_FILE_SD_DIR="${PROM_FILE_SD_DIR:-/etc/prometheus/file_sd}"
PROM_FILE_SD_FILE="${PROM_FILE_SD_FILE:-shellstack-node-exporter.json}"
PROM_CONFIG_FILE="${PROM_CONFIG_FILE:-/etc/prometheus/prometheus.yml}"

_exporter_local_ip() {
  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -n "$ip" ]]; then
    echo "$ip"
    return 0
  fi
  ip="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  [[ -n "$ip" ]] && echo "$ip"
}

_exporter_install_node_exporter() {
  if command -v node_exporter >/dev/null 2>&1; then
    log "检测到 node_exporter 已安装，跳过安装"
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update >>"$LOG_FILE" 2>&1 || true
    apt-get install -y prometheus-node-exporter >>"$LOG_FILE" 2>&1 || \
      apt-get install -y node-exporter >>"$LOG_FILE" 2>&1 || \
      warn "APT 安装 node exporter 失败，请检查源或手动安装"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y node_exporter >>"$LOG_FILE" 2>&1 || warn "DNF 安装 node exporter 失败"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y node_exporter >>"$LOG_FILE" 2>&1 || warn "YUM 安装 node exporter 失败"
  else
    warn "未识别的包管理器，无法自动安装 node exporter"
  fi
}

_exporter_ensure_service_running() {
  local svc=""
  if systemctl list-unit-files 2>/dev/null | grep -q '^prometheus-node-exporter\.service'; then
    svc="prometheus-node-exporter"
  elif systemctl list-unit-files 2>/dev/null | grep -q '^node_exporter\.service'; then
    svc="node_exporter"
  fi

  if [[ -n "$svc" ]]; then
    systemctl enable --now "$svc" >>"$LOG_FILE" 2>&1 || warn "启动服务失败: $svc"
    if systemctl is-active "$svc" >/dev/null 2>&1; then
      log "node exporter 服务已运行: $svc"
      return 0
    fi
  fi

  if ss -lnt 2>/dev/null | grep -qE ":${EXPORTER_LISTEN_PORT}[[:space:]]"; then
    log "检测到 ${EXPORTER_LISTEN_PORT} 端口已监听，视为 exporter 可用"
    return 0
  fi
  warn "未检测到 exporter 服务监听 ${EXPORTER_LISTEN_PORT}，自动注册仍会继续"
}

_exporter_is_local_prometheus_server() {
  local raw="$1"
  local host="$raw"
  host="${host#http://}"
  host="${host#https://}"
  host="${host%%/*}"
  host="${host%%:*}"

  [[ "$host" == "127.0.0.1" || "$host" == "localhost" ]] && return 0
  [[ "$host" == "$(hostname -f 2>/dev/null)" || "$host" == "$(hostname 2>/dev/null)" ]] && return 0
  hostname -I 2>/dev/null | tr ' ' '\n' | grep -qx "$host"
}

_exporter_register_local_prometheus() {
  local target="$1"
  mkdir -p "$PROM_FILE_SD_DIR"
  cat > "${PROM_FILE_SD_DIR}/${PROM_FILE_SD_FILE}" <<EOF
[
  {
    "labels": {
      "job": "shellstack-node-exporter",
      "module": "modsecurity"
    },
    "targets": ["${target}"]
  }
]
EOF
  log "已写入 Prometheus file_sd: ${PROM_FILE_SD_DIR}/${PROM_FILE_SD_FILE}"

  if [[ -f "$PROM_CONFIG_FILE" ]]; then
    if ! grep -q "${PROM_FILE_SD_DIR}/\\*\\.json" "$PROM_CONFIG_FILE"; then
      cat >> "$PROM_CONFIG_FILE" <<EOF

# shellstack auto managed
scrape_configs:
  - job_name: 'shellstack-node-exporter'
    file_sd_configs:
      - files:
        - '${PROM_FILE_SD_DIR}/*.json'
EOF
      warn "已追加 scrape_configs 到 $PROM_CONFIG_FILE，请确认未与原配置冲突"
    fi
  else
    warn "未找到 Prometheus 配置文件: $PROM_CONFIG_FILE"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl reload prometheus >>"$LOG_FILE" 2>&1 || systemctl restart prometheus >>"$LOG_FILE" 2>&1 || \
      warn "Prometheus 重载失败，请手工重载"
  fi
}

_exporter_register_remote_prometheus_via_ssh() {
  local prom="$1"
  local target="$2"
  local host="$prom"
  host="${host#http://}"
  host="${host#https://}"
  host="${host%%/*}"
  host="${host%%:*}"

  if ! command -v ssh >/dev/null 2>&1; then
    warn "本机无 ssh，无法自动写入远端 Prometheus；请手工注册 target: $target"
    return 0
  fi

  local ssh_target="root@${host}"
  if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$ssh_target" "echo ok" >/dev/null 2>&1; then
    warn "无法免密 SSH 到 ${ssh_target}，请在 Prometheus 侧手工添加 target: $target"
    return 0
  fi

  ssh -o BatchMode=yes "$ssh_target" "mkdir -p '${PROM_FILE_SD_DIR}'" >>"$LOG_FILE" 2>&1 || true
  ssh -o BatchMode=yes "$ssh_target" "cat > '${PROM_FILE_SD_DIR}/${PROM_FILE_SD_FILE}' <<'EOF'
[
  {
    \"labels\": {\"job\": \"shellstack-node-exporter\", \"module\": \"modsecurity\"},
    \"targets\": [\"${target}\"]
  }
]
EOF" >>"$LOG_FILE" 2>&1 || warn "写入远端 file_sd 失败"

  ssh -o BatchMode=yes "$ssh_target" "systemctl reload prometheus || systemctl restart prometheus" >>"$LOG_FILE" 2>&1 || \
    warn "远端 Prometheus 重载失败，请手工重载"
  log "已尝试远端注册 Prometheus target: ${target} -> ${ssh_target}"
}

setup_exporter_and_register() {
  local prom_server="$1"
  log "=========================================="
  log "--with-exporter：安装 exporter 并注册到 Prometheus"
  log "=========================================="
  log "Prometheus 地址: $prom_server"

  _exporter_install_node_exporter
  _exporter_ensure_service_running

  local ip
  ip="$(_exporter_local_ip)"
  if [[ -z "$ip" ]]; then
    warn "无法识别本机 IP，使用 127.0.0.1 注册 exporter 目标"
    ip="127.0.0.1"
  fi
  local target="${ip}:${EXPORTER_LISTEN_PORT}"

  if _exporter_is_local_prometheus_server "$prom_server"; then
    _exporter_register_local_prometheus "$target"
  else
    _exporter_register_remote_prometheus_via_ssh "$prom_server" "$target"
  fi

  log "Exporter 扩展完成，目标地址: $target"
}
