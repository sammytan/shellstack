#!/bin/bash
# 安装 node exporter 并通过 Consul Agent API 注册服务（供 Prometheus consul_sd 发现）
# 架构：本机/目标机运行 node_exporter → 注册到 Consul → Prometheus 用 consul_sd_configs 抓取
#
# 单独使用本文件（不必跑 main.sh）：
#   ./exporter.sh http://127.0.0.1:8500
#   ./exporter.sh --consul-token=SECRET http://consul.example.com:8500
#   CONSUL_HTTP_TOKEN=secret ./exporter.sh http://127.0.0.1:8500
# 与 includes 同目录时有 shared.sh 会加载（完整日志）；仅下载本文件时会用简易日志。
#
# 被 main.sh 加载时：由 shared.sh 提供 log / warn；直接执行时见文末 _exporter_cli_main
#
# 环境变量（可选）：
#   EXPORTER_LISTEN_PORT      默认 9100
#   CONSUL_HTTP_ADDR        未传参时 setup_exporter_and_register 可回退使用该 Consul 基址（须含端口）
#   CONSUL_HTTP_TOKEN       Consul ACL Token（请求头 X-Consul-Token）；集群启用 ACL 时注册/写 catalog 通常必需
#   或在 main.sh 使用 --with-consul-token=TOKEN（等价导出 CONSUL_HTTP_TOKEN）
#   CONSUL_SERVICE_ID       覆盖自动生成的服务 ID
#   CONSUL_SERVICE_NAME     默认 shellstack-node-exporter
#   CONSUL_SERVICE_TAGS     额外标签，逗号分隔，追加到默认 tags

EXPORTER_LISTEN_PORT="${EXPORTER_LISTEN_PORT:-9100}"
CONSUL_SERVICE_NAME="${CONSUL_SERVICE_NAME:-shellstack-node-exporter}"

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
  warn "未检测到 exporter 服务监听 ${EXPORTER_LISTEN_PORT}，Consul 健康检查可能失败"
}

# 将参数规范为 Consul HTTP 基址（无尾部斜杠），默认端口 8500
_exporter_normalize_consul_base() {
  local raw="$1"
  local scheme rest authority
  raw="${raw%/}"
  if [[ "$raw" =~ ^https?:// ]]; then
    scheme="${raw%%://*}"
    rest="${raw#*://}"
    authority="${rest%%/*}"
    if [[ "$authority" != *:* ]]; then
      echo "${scheme}://${authority}:8500"
    else
      echo "${scheme}://${authority}"
    fi
  else
    authority="${raw%%/*}"
    if [[ "$authority" != *:* ]]; then
      echo "http://${authority}:8500"
    else
      echo "http://${authority}"
    fi
  fi
}

_exporter_json_escape() {
  # 最小 JSON 字符串转义（反斜杠与双引号）
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

_exporter_consul_register() {
  local consul_base="$1"
  local bind_addr="$2"
  local port="$3"

  if ! command -v curl >/dev/null 2>&1; then
    warn "未找到 curl，无法调用 Consul API；请安装 curl 或手工注册服务"
    return 1
  fi

  local safe_host sid tags_json extra_tag
  safe_host="$(hostname -s 2>/dev/null | tr -cd '[:alnum:]-' | head -c 48)"
  [[ -z "$safe_host" ]] && safe_host="host"
  sid="${CONSUL_SERVICE_ID:-${CONSUL_SERVICE_NAME}-${safe_host}-${port}}"

  tags_json='"shellstack","modsecurity","node-exporter"'
  if [[ -n "${CONSUL_SERVICE_TAGS:-}" ]]; then
    IFS=',' read -ra _extra_tags <<< "${CONSUL_SERVICE_TAGS}"
    for extra_tag in "${_extra_tags[@]}"; do
      extra_tag="$(echo "$extra_tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -n "$extra_tag" ]] || continue
      tags_json+=",\"$(_exporter_json_escape "$extra_tag")\""
    done
  fi

  local check_url
  check_url="http://${bind_addr}:${port}/metrics"

  local payload http_code out
  payload="$(cat <<EOF
{
  "ID": "$(_exporter_json_escape "$sid")",
  "Name": "$(_exporter_json_escape "$CONSUL_SERVICE_NAME")",
  "Tags": [${tags_json}],
  "Address": "$(_exporter_json_escape "$bind_addr")",
  "Port": ${port},
  "Meta": {
    "module": "modsecurity",
    "source": "shellstack-exporter"
  },
  "Check": {
    "HTTP": "$(_exporter_json_escape "$check_url")",
    "Interval": "15s",
    "Timeout": "5s",
    "DeregisterCriticalServiceAfter": "30m"
  }
}
EOF
)"

  local curl_opts=(-fsS -o /tmp/shellstack-consul-reg.out -w "%{http_code}" -X PUT)
  [[ -n "${CONSUL_HTTP_TOKEN:-}" ]] && curl_opts+=(-H "X-Consul-Token: ${CONSUL_HTTP_TOKEN}")
  curl_opts+=(--data-binary "$payload" "${consul_base}/v1/agent/service/register")

  http_code="$(curl "${curl_opts[@]}" 2>>"$LOG_FILE")" || true
  out="$(cat /tmp/shellstack-consul-reg.out 2>/dev/null || true)"
  rm -f /tmp/shellstack-consul-reg.out

  if [[ "$http_code" == "200" ]]; then
    log "已注册到 Consul: service_id=${sid} target=${bind_addr}:${port} consul=${consul_base}"
    return 0
  fi

  warn "Consul 注册失败 HTTP ${http_code:-?}：${out:-（无响应体）}"
  warn "请检查 Consul 地址、网络；若启用 ACL 请设置 CONSUL_HTTP_TOKEN、本脚本 --consul-token= 或 main.sh --with-consul-token=..."
  warn "或手工执行: PUT ${consul_base}/v1/agent/service/register（Header: X-Consul-Token）"
  return 1
}

setup_exporter_and_register() {
  local consul_raw="${1:-${CONSUL_HTTP_ADDR:-}}"
  if [[ -z "$consul_raw" ]]; then
    warn "未提供 Consul 地址（--with-exporter= 或 CONSUL_HTTP_ADDR）"
    return 1
  fi
  log "=========================================="
  log "exporter：安装 node_exporter 并注册到 Consul（Prometheus 经 consul_sd 发现）"
  log "=========================================="

  local consul_base
  consul_base="$(_exporter_normalize_consul_base "$consul_raw")"
  log "Consul HTTP 基址: $consul_base"
  if [[ -z "${CONSUL_HTTP_TOKEN:-}" ]]; then
    log "提示: 未设置 CONSUL_HTTP_TOKEN / --with-consul-token；若 Consul 启用 ACL，注册需带 token（见 --help）"
  fi

  _exporter_install_node_exporter
  _exporter_ensure_service_running

  local ip
  ip="$(_exporter_local_ip)"
  if [[ -z "$ip" ]]; then
    warn "无法识别本机 IP，使用 127.0.0.1 作为注册 Address（请确认 Prometheus 能否访问）"
    ip="127.0.0.1"
  fi

  _exporter_consul_register "$consul_base" "$ip" "${EXPORTER_LISTEN_PORT}"
  log "Exporter 流程结束；Prometheus 侧请配置 consul_sd_configs 指向同一 Consul 集群"
}

# Prometheus 抓取示例（服务名见 CONSUL_SERVICE_NAME，默认 shellstack-node-exporter）：
# scrape_configs:
#   - job_name: shellstack-node-exporter
#     metrics_path: /metrics
#     consul_sd_configs:
#       - server: '127.0.0.1:8500'
#         services: ['shellstack-node-exporter']

# ---------------------------------------------------------------------------
# 直接执行本脚本（不经过 modsecurity/main.sh）
# ---------------------------------------------------------------------------
_exporter_cli_usage() {
  cat <<'EOF'
用法: exporter.sh [选项] <Consul HTTP 地址>
  exporter.sh http://127.0.0.1:8500
  exporter.sh --consul-token=SECRET http://consul.example.com:8500

与 main.sh 相同的环境变量仍可用：CONSUL_HTTP_ADDR、CONSUL_HTTP_TOKEN、EXPORTER_LISTEN_PORT、
CONSUL_SERVICE_NAME、CONSUL_SERVICE_ID、CONSUL_SERVICE_TAGS 等。

选项:
  -h, --help                  显示本帮助
  --consul-token=TOKEN        设置 ACL Token（等价 export CONSUL_HTTP_TOKEN）
  --with-consul-token=TOKEN 同上（与 main.sh 参数名一致）

远程仅拉取本脚本（无 shared.sh 时为简易日志）:
  curl -fsSL https://<站点>/modsecurity/includes/exporter.sh | sudo bash -s -- http://127.0.0.1:8500
  curl -fsSL .../exporter.sh | sudo bash -s -- --consul-token=SECRET http://consul:8500
EOF
}

_exporter_cli_bootstrap() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$here/shared.sh" ]]; then
    # shellcheck source=shared.sh
    source "$here/shared.sh"
  else
    LOG_FILE="${LOG_FILE:-/tmp/shellstack_exporter.log}"
    log() {
      echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
    }
    warn() {
      echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] 警告: $*" | tee -a "$LOG_FILE" >&2
    }
  fi
}

# 被 source 时：本文件路径在 BASH_SOURCE[0]，与调用脚本的 $0 不同，不跑 CLI。
# 直接执行或 curl | bash -s 时：要么 BASH_SOURCE[0]==$0，要么 BASH_SOURCE 为空（stdin 脚本）。
if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  :
else
  case "${1:-}" in
    -h|--help)
      _exporter_cli_usage
      exit 0
      ;;
  esac
  _exporter_cli_bootstrap
  consul_arg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        _exporter_cli_usage
        exit 0
        ;;
      --consul-token=*|--with-consul-token=*)
        CONSUL_HTTP_TOKEN="${1#*=}"
        export CONSUL_HTTP_TOKEN
        shift
        ;;
      --consul-token|--with-consul-token)
        CONSUL_HTTP_TOKEN="${2:-}"
        export CONSUL_HTTP_TOKEN
        shift 2
        ;;
      -*)
        warn "未知选项: $1"
        _exporter_cli_usage
        exit 1
        ;;
      *)
        consul_arg="$1"
        shift
        break
        ;;
    esac
  done
  if [[ $# -gt 0 ]]; then
    warn "多余参数: $*"
    _exporter_cli_usage
    exit 1
  fi
  if [[ -z "$consul_arg" ]]; then
    consul_arg="${CONSUL_HTTP_ADDR:-}"
  fi
  if [[ -z "$consul_arg" ]]; then
    warn "请提供 Consul HTTP 地址（参数或环境变量 CONSUL_HTTP_ADDR）"
    _exporter_cli_usage
    exit 1
  fi
  setup_exporter_and_register "$consul_arg" || exit $?
fi
