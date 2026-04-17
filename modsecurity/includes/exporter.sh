#!/bin/bash
# 安装 node exporter 并通过 Consul Agent API 注册服务（供 Prometheus consul_sd 发现）
# 架构：本机/目标机运行 node_exporter → 注册到 Consul → Prometheus 用 consul_sd_configs 抓取
#
# 指标覆盖：
#   - 常规系统：CPU/内存/负载/磁盘空间/磁盘 IO/网络流量 等由 node_exporter 默认 collectors 提供
#     （node_cpu_*、node_memory_*、node_load*、node_filesystem_*、node_disk_*、node_network_* 等）
#   - 宝塔 / Nginx / PHP-FPM / MySQL / Redis：本脚本安装 textfile 采集脚本 + cron，输出 shellstack_* 指标
#   - Nginx 连接负载：若本机可访问 stub_status（见下方 URL），输出 shellstack_nginx_* 指标
#
# 单独使用本文件（不必跑 main.sh）：
#   ./exporter.sh
#   ./exporter.sh http://127.0.0.1:8500
#   ./exporter.sh --consul-token=SECRET http://consul.example.com:8500
#   CONSUL_HTTP_TOKEN=secret ./exporter.sh http://127.0.0.1:8500
# 与 includes 同目录时有 shared.sh 会加载（完整日志）；仅下载本文件时会用简易日志。
#
# 被 main.sh 加载时：由 shared.sh 提供 log / warn；直接执行时见文末 _exporter_cli_main
#
# 环境变量（可选）：
#   EXPORTER_LISTEN_PORT      默认 9100
#   CONSUL_HTTP_ADDR        未传参时回退；再回退内置默认 Consul（见 SHELLSTACK_EXPORTER_DEFAULT_CONSUL_ADDR）
#   CONSUL_HTTP_TOKEN       未设置时自动使用内置默认，并写入 /etc/profile.d/shellstack-consul-env.sh
#   SHELLSTACK_EXPORTER_NO_BUILTIN_TOKEN=1  不注入内置 Token、不写 Token 到 profile.d（自行 export）
#   SHELLSTACK_EXPORTER_SKIP_PERSIST_ENV=1  不写入 /etc/profile.d/shellstack-consul-env.sh
#   SHELLSTACK_EXPORTER_DEFAULT_CONSUL_ADDR / SHELLSTACK_EXPORTER_DEFAULT_CONSUL_TOKEN 覆盖内置默认
#   SHELLSTACK_NGINX_STUB_URLS   逗号分隔的 stub_status URL；未设置且探测失败时会尝试自动注入见下
#   SHELLSTACK_NGINX_STUB_INJECT  默认 1：stub 全失败且存在 /www/server/nginx 时注入独立 127.0.0.1 端口 stub；设 0 关闭
#   SHELLSTACK_NGINX_STUB_LISTEN_PORT  注入时监听端口，默认 8899（仅 127.0.0.1）
#   CONSUL_SERVICE_ID       覆盖自动生成的服务 ID（默认 {hostname}-{CONSUL_SERVICE_NAME}-{port}，hostname 见下方函数）
#   CONSUL_SERVICE_NAME     默认 shellstack-node-exporter
#   CONSUL_SERVICE_TAGS     额外标签，逗号分隔，追加到默认 tags
#   CONSUL_SERVICE_META     额外 Meta，逗号分隔 key=value（勿与脚本内置键重复以免 JSON 冲突）；与脚本自动写入的 Meta 合并
#   EXPORTER_METRICS_ALLOW_FROM / SHELLSTACK_EXPORTER_METRICS_ALLOW_FROM  逗号分隔 IPv4 或 CIDR；若设置则仅放行这些源访问 metrics 端口，不再从 Consul 地址推导
#   SHELLSTACK_EXPORTER_SKIP_FIREWALL=1  不尝试配置本机防火墙（9100 等须自行放行）
#   防火墙自动匹配（root）：firewalld → ufw → iptables/iptables-nft/iptables-legacy → nft（inet filter input 或 ip filter INPUT）
#   部署 exporter 前（root）：将静态主机名设为「ISO 国家/地区二位码-公网IPv4」，如 HK-156.239.6.130
#     公网 IP：依次尝试 ipify / ipinfo.io/ip / ifconfig.me / icanhazip / ident.me / AWS checkip 等多个出口探测 URL
#     地区码：ip-api.com（HTTP）与 ipinfo.io/json（HTTPS）互为补充
#   SHELLSTACK_EXPORTER_SKIP_HOSTNAME=1     不修改主机名
#   SHELLSTACK_EXPORTER_PUBLIC_IP=a.b.c.d   手工公网 IP（跳过出口 IP 探测）
#   SHELLSTACK_EXPORTER_GEO_CODE=HK         手工区域码（二位大写字母；与 PUBLIC_IP 可只设其一，另一项走 API）
#   SHELLSTACK_EXPORTER_GEO_HOSTNAME=NAME    完全指定主机名（跳过 Geo/IP 拼接）
#   SHELLSTACK_EXPORTER_FORCE=1  由 main.sh 在「仅 exporter + --force」时设置：强制重跑 exporter 各步骤（不触发 ModSecurity 主流程）

EXPORTER_LISTEN_PORT="${EXPORTER_LISTEN_PORT:-9100}"
CONSUL_SERVICE_NAME="${CONSUL_SERVICE_NAME:-shellstack-node-exporter}"

# 内置默认 Consul（本流程自动注入当前 shell，并持久化到 profile.d，无需手敲 export）
SHELLSTACK_EXPORTER_DEFAULT_CONSUL_ADDR="${SHELLSTACK_EXPORTER_DEFAULT_CONSUL_ADDR:-http://47.243.128.122:8500}"
SHELLSTACK_EXPORTER_DEFAULT_CONSUL_TOKEN="${SHELLSTACK_EXPORTER_DEFAULT_CONSUL_TOKEN:-4c3ff895-c21c-4e1c-a0c3-8bf64cdb2897}"

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

# 多个公开「出口 IPv4」探测接口（任一连通即可）；优先 ipv4.* 专用端点减少拿到 IPv6 文本的情况
_exporter_fetch_public_ip_only() {
  local ip url
  local -a urls=(
    'https://ipv4.icanhazip.com'
    'https://api.ipify.org'
    'https://ipinfo.io/ip'
    'https://ifconfig.me/ip'
    'https://icanhazip.com'
    'https://ident.me'
    'https://checkip.amazonaws.com'
    'https://ipecho.net/plain'
    'https://wtfismyip.com/text'
  )
  for url in "${urls[@]}"; do
    ip="$(curl -fsS -m 7 -H 'Accept: text/plain' "$url" 2>/dev/null | tr -d '[:space:]')"
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && { printf '%s' "$ip"; return 0; }
  done
  return 1
}

# 从 ipinfo.io JSON 解析 ip、country（二位码）；stdout 两行：第一行 IP 或空，第二行 country 或空
_exporter_ipinfo_parse_ip_country() {
  local json="$1"
  local ip cc
  [[ -z "$json" ]] && return 1
  ip="$(printf '%s' "$json" | sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p')"
  cc="$(printf '%s' "$json" | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([A-Za-z][A-Za-z]*\)".*/\1/p')"
  printf '%s\n%s\n' "${ip:-}" "${cc:-}"
}

_exporter_apply_geo_public_hostname() {
  local name ip cc json cur

  if [[ "${SHELLSTACK_EXPORTER_SKIP_HOSTNAME:-}" == "1" ]]; then
    log "已跳过主机名设置（SHELLSTACK_EXPORTER_SKIP_HOSTNAME=1）"
    return 0
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    warn "非 root，跳过按「区域码-公网IP」设置主机名（请使用 sudo/root 执行 exporter 流程）"
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    warn "无 curl，无法查询公网 IP/Geo，跳过主机名设置"
    return 0
  fi

  if [[ -n "${SHELLSTACK_EXPORTER_GEO_HOSTNAME:-}" ]]; then
    name="${SHELLSTACK_EXPORTER_GEO_HOSTNAME}"
  else
    ip="${SHELLSTACK_EXPORTER_PUBLIC_IP:-}"
    cc="${SHELLSTACK_EXPORTER_GEO_CODE:-}"
    if [[ -z "$ip" || -z "$cc" ]]; then
      json="$(curl -fsS -m 14 -H 'User-Agent: shellstack-exporter-setup' \
        'http://ip-api.com/json/?fields=status,message,countryCode,query' 2>/dev/null)" || json=""
      if [[ -n "$json" && "$json" == *'"status":"success"'* ]]; then
        [[ -z "$ip" ]] && ip="$(printf '%s' "$json" | sed -n 's/.*"query":"\([0-9][0-9.]*\)".*/\1/p')"
        [[ -z "$cc" ]] && cc="$(printf '%s' "$json" | sed -n 's/.*"countryCode":"\([A-Za-z][A-Za-z]*\)".*/\1/p')"
      fi
    fi
    if [[ -z "$ip" || -z "$cc" ]]; then
      json="$(curl -fsS -m 14 -H 'Accept: application/json' -H 'User-Agent: shellstack-exporter-setup' \
        'https://ipinfo.io/json' 2>/dev/null)" || json=""
      if [[ -n "$json" ]]; then
        local _ipinfo_blob _ii _icc
        _ipinfo_blob="$(_exporter_ipinfo_parse_ip_country "$json")"
        _ii="$(printf '%s' "$_ipinfo_blob" | sed -n '1p')"
        _icc="$(printf '%s' "$_ipinfo_blob" | sed -n '2p')"
        [[ -z "$ip" && -n "$_ii" ]] && ip="$_ii"
        [[ -z "$cc" && -n "$_icc" ]] && cc="$_icc"
      fi
    fi
    if [[ -z "$ip" ]] || ! [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
      ip="$(_exporter_fetch_public_ip_only)" || ip=""
    fi
    if [[ -z "$ip" ]] || ! [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
      warn "无法获得公网 IPv4，跳过主机名设置（可设 SHELLSTACK_EXPORTER_PUBLIC_IP 或 SHELLSTACK_EXPORTER_GEO_HOSTNAME）"
      return 0
    fi
    if [[ -z "$cc" ]]; then
      json="$(curl -fsS -m 14 -H 'Accept: application/json' \
        "https://ipinfo.io/${ip}/json" 2>/dev/null)" || json=""
      if [[ -n "$json" ]]; then
        cc="$(printf '%s' "$json" | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([A-Za-z][A-Za-z]*\)".*/\1/p')"
      fi
    fi
    if [[ -z "$cc" ]]; then
      json="$(curl -fsS -m 14 "http://ip-api.com/json/${ip}?fields=status,message,countryCode" 2>/dev/null)" || json=""
      if [[ -n "$json" && "$json" == *'"status":"success"'* ]]; then
        cc="$(printf '%s' "$json" | sed -n 's/.*"countryCode":"\([A-Za-z][A-Za-z]*\)".*/\1/p')"
      fi
    fi
    cc="$(printf '%s' "$cc" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z')"
    if [[ ${#cc} -ne 2 ]]; then
      cc="XX"
      warn "未得到二位国家/地区码，使用 XX（可设 SHELLSTACK_EXPORTER_GEO_CODE=HK 等）"
    fi
    name="${cc}-${ip}"
  fi

  if ! [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
    warn "目标主机名不符合常见 hostname 规则，跳过: $name"
    return 0
  fi
  if [[ ${#name} -gt 200 ]]; then
    warn "目标主机名过长，跳过"
    return 0
  fi

  cur="$(hostname 2>/dev/null || true)"
  if [[ "$cur" == "$name" ]]; then
    if [[ "${SHELLSTACK_EXPORTER_FORCE:-}" == "1" ]]; then
      log "主机名已是 ${name}（--force：跳过重写），继续 exporter 其它步骤"
    else
      log "主机名已是 ${name}，跳过写入"
    fi
    return 0
  fi

  if command -v hostnamectl >/dev/null 2>&1; then
    if hostnamectl set-hostname --static "$name" >>"$LOG_FILE" 2>&1; then
      log "已设置静态主机名为 ${name}（hostnamectl，供 Consul 注册等使用）"
    else
      warn "hostnamectl set-hostname 失败，尝试 /etc/hostname"
      printf '%s\n' "$name" >/etc/hostname 2>>"$LOG_FILE" || { warn "写入 /etc/hostname 失败"; return 0; }
      hostname "$name" 2>>"$LOG_FILE" || true
      log "已写入 /etc/hostname 并尝试 hostname ${name}"
    fi
  elif [[ -w /etc/hostname ]] || [[ -w / ]]; then
    printf '%s\n' "$name" >/etc/hostname 2>>"$LOG_FILE" || { warn "写入 /etc/hostname 失败"; return 0; }
    command -v hostname >/dev/null 2>&1 && hostname "$name" 2>>"$LOG_FILE" || true
    log "已写入 /etc/hostname 并尝试 hostname ${name}"
  else
    warn "无 hostnamectl 且无法写 /etc/hostname，跳过主机名 ${name}"
    return 0
  fi

  if [[ -f /etc/hosts ]] && grep -qE '^127\.0\.1\.1[[:space:]]' /etc/hosts 2>/dev/null; then
    sed -i.bak-shellstack-host "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1\t${name}/" /etc/hosts 2>>"$LOG_FILE" && \
      log "已同步 /etc/hosts 中 127.0.1.1 为 ${name}（备份: /etc/hosts.bak-shellstack-host）"
  fi
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

_exporter_apply_builtin_consul_defaults() {
  if [[ -z "${CONSUL_HTTP_TOKEN:-}" ]] && [[ "${SHELLSTACK_EXPORTER_NO_BUILTIN_TOKEN:-}" != "1" ]]; then
    CONSUL_HTTP_TOKEN="$SHELLSTACK_EXPORTER_DEFAULT_CONSUL_TOKEN"
    export CONSUL_HTTP_TOKEN
    log "已自动设置 CONSUL_HTTP_TOKEN（内置默认，当前进程已 export）"
  fi
}

# 登录 shell 自动加载（仅当外部未设置同名变量时生效）；便于后续手工 curl Consul 与脚本复用
_exporter_persist_consul_env_for_shells() {
  local addr="$1"
  local tok="${2:-}"
  [[ "${SHELLSTACK_EXPORTER_SKIP_PERSIST_ENV:-}" == "1" ]] && return 0
  local d="/etc/profile.d"
  if [[ ! -d "$d" ]]; then
    warn "无目录 $d，跳过 Consul 环境持久化"
    return 0
  fi
  local f="$d/shellstack-consul-env.sh"
  local qa qt
  qa="$(printf '%q' "$addr")"
  umask 022
  {
    echo "# 由 shellstack exporter.sh 生成；重跑 --with-exporter 会覆盖。未在外部设置变量时才 export。"
    echo "[ -z \"\${CONSUL_HTTP_ADDR:-}\" ] && export CONSUL_HTTP_ADDR=${qa}"
    if [[ -n "$tok" ]]; then
      qt="$(printf '%q' "$tok")"
      echo "[ -z \"\${CONSUL_HTTP_TOKEN:-}\" ] && export CONSUL_HTTP_TOKEN=${qt}"
    fi
  } >"$f"
  chmod 0644 "$f" 2>/dev/null || true
  log "已写入 $f（新 SSH 登录自动加载 CONSUL_HTTP_*；当前会话已 export，无需再手动设置）"
}

_exporter_node_exporter_textfile_dir() {
  local d
  for d in /var/lib/prometheus/node-exporter /var/lib/node_exporter/textfile_collector /var/lib/prometheus/node_exporter; do
    [[ -d "$d" ]] && { echo "$d"; return 0; }
  done
  d="/var/lib/prometheus/node-exporter"
  mkdir -p "$d" 2>/dev/null || true
  echo "$d"
}

_exporter_nginx_stub_urls_probe_ok() {
  local urls="$1" url body
  IFS=',' read -ra _probe_arr <<< "$urls"
  for url in "${_probe_arr[@]}"; do
    url="$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$url" ]] || continue
    body="$(curl -fsS -m 2 "$url" 2>/dev/null || true)"
    [[ -n "$body" ]] && echo "$body" | grep -q 'Active connections' && return 0
  done
  return 1
}

# 在宝塔 nginx.conf 的 http{} 内 include 独立 stub（仅 127.0.0.1），供本机 textfile 采集
_exporter_inject_baota_nginx_stub_status() {
  local port="${1:-8899}"
  local ngx_bin="/www/server/nginx/sbin/nginx"
  local ngx_main="/www/server/nginx/conf/nginx.conf"
  local snip="/www/server/nginx/conf/shellstack_stub_status.conf"
  [[ -x "$ngx_bin" ]] || return 1
  [[ -f "$ngx_main" ]] || return 1

  if ss -lnt 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
    warn "端口 ${port} 已被占用，跳过注入 stub_status（可设 SHELLSTACK_NGINX_STUB_LISTEN_PORT 为其他端口）"
    return 1
  fi

  cat >"$snip" <<EOF
# shellstack exporter 生成：仅 127.0.0.1:${port}，供 Prometheus textfile 读取 stub_status
server {
    listen 127.0.0.1:${port};
    server_name 127.0.0.1;
    location /nginx_stub_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
  chmod 644 "$snip" 2>/dev/null || true

  if grep -qF 'include /www/server/nginx/conf/shellstack_stub_status.conf' "$ngx_main" 2>/dev/null; then
    log "nginx.conf 已包含 shellstack_stub_status.conf，仅刷新片段文件"
  else
    if ! sed -i.bak-shellstack '/^[[:space:]]*http[[:space:]]*{/a\    include /www/server/nginx/conf/shellstack_stub_status.conf;' "$ngx_main" 2>>"$LOG_FILE"; then
      warn "向 nginx.conf 插入 include 失败"
      return 1
    fi
  fi

  if ! "$ngx_bin" -t >>"$LOG_FILE" 2>&1; then
    warn "nginx -t 未通过，回滚 nginx.conf（恢复 sed 备份）"
    if [[ -f "${ngx_main}.bak-shellstack" ]]; then
      mv -f "${ngx_main}.bak-shellstack" "$ngx_main" 2>/dev/null || cp -a "${ngx_main}.bak-shellstack" "$ngx_main" 2>/dev/null || true
    fi
    return 1
  fi
  rm -f "${ngx_main}.bak-shellstack" 2>/dev/null || true

  if "$ngx_bin" -s reload >>"$LOG_FILE" 2>&1; then
    log "已注入 stub_status：http://127.0.0.1:${port}/nginx_stub_status 并重载 Nginx"
    return 0
  fi
  if systemctl reload nginx >>"$LOG_FILE" 2>&1 || /etc/init.d/nginx reload >>"$LOG_FILE" 2>&1; then
    log "已注入 stub_status：http://127.0.0.1:${port}/nginx_stub_status 并重载 Nginx（systemctl/init）"
    return 0
  fi
  warn "stub 配置已写入但重载失败，请手动: nginx -s reload"
  return 1
}

_exporter_patch_node_exporter_textfile_arg() {
  local dir="$1"
  local svc="" f
  if systemctl list-unit-files 2>/dev/null | grep -q '^prometheus-node-exporter\.service'; then
    svc="prometheus-node-exporter"
  elif systemctl list-unit-files 2>/dev/null | grep -q '^node_exporter\.service'; then
    svc="node_exporter"
  fi
  [[ -n "$svc" ]] || return 0

  if [[ -f /etc/default/prometheus-node-exporter ]]; then
    f="/etc/default/prometheus-node-exporter"
    if grep -qF 'collector.textfile.directory' "$f" 2>/dev/null; then
      :
    elif grep -qE '^ARGS=' "$f" 2>/dev/null; then
      sed -i.bak-shellstack "s|^ARGS=\"\\(.*\\)\"|ARGS=\"\\1 --collector.textfile.directory=${dir}\"|" "$f" 2>/dev/null || true
    else
      echo "ARGS=\"--collector.textfile.directory=${dir}\"" >>"$f"
    fi
  elif [[ "$svc" == "prometheus-node-exporter" ]]; then
    # Debian/Ubuntu：单元用 $ARGS；无 /etc/default 文件时新建（勿用 EXTRA_FLAGS，多数包不读）
    f="/etc/default/prometheus-node-exporter"
    if [[ ! -f "$f" ]]; then
      mkdir -p /etc/default 2>/dev/null || true
      umask 022
      {
        echo "# generated by shellstack exporter.sh"
        echo "ARGS=\"--collector.textfile.directory=${dir}\""
      } >"$f" 2>>"$LOG_FILE" || true
    fi
  elif [[ -f /etc/sysconfig/node_exporter ]]; then
    f="/etc/sysconfig/node_exporter"
    grep -qF 'collector.textfile.directory' "$f" 2>/dev/null || echo "NODE_EXPORTER_OPTS=\"--collector.textfile.directory=${dir}\"" >>"$f"
  else
    local drop="/etc/systemd/system/${svc}.service.d"
    mkdir -p "$drop" 2>/dev/null || true
    if [[ -d "$drop" ]]; then
      if [[ "$svc" == "prometheus-node-exporter" ]]; then
        cat >"${drop}/shellstack-textfile.conf" <<EOF
[Service]
Environment="ARGS=--collector.textfile.directory=${dir}"
EOF
      else
        cat >"${drop}/shellstack-textfile.conf" <<EOF
[Service]
Environment="NODE_EXPORTER_OPTS=--collector.textfile.directory=${dir}"
EOF
      fi
    fi
  fi
  systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
  systemctl restart "$svc" >>"$LOG_FILE" 2>&1 || warn "重启 $svc 以应用 textfile 目录失败，请手动检查"
}

_exporter_node_exporter_textfile_arg_in_ps() {
  pgrep -af prometheus-node-exporter 2>/dev/null | grep -qF 'collector.textfile.directory' && return 0
  pgrep -af node_exporter 2>/dev/null | grep -qF 'collector.textfile.directory' && return 0
  return 1
}

_exporter_install_baota_textfile_collector() {
  local dir
  dir="$(_exporter_node_exporter_textfile_dir)"
  mkdir -p "$dir" || true
  _exporter_patch_node_exporter_textfile_arg "$dir"

  local bin="/usr/local/bin/shellstack-node-exporter-textfile.sh"
  cat >"$bin" <<'EOSCRIPT'
#!/bin/bash
# Prometheus textfile collector：宝塔栈 + nginx stub_status（由 exporter.sh 部署）
# 不使用 set -e：systemctl/pgrep 未激活时返回非 0，避免整段采集被中断
set -uo pipefail
DIR="${TEXTFILE_DIR:-/var/lib/prometheus/node-exporter}"
mkdir -p "$DIR"
OUT="$DIR/shellstack_baota.prom"
TMP="$OUT.$$"
trap 'rm -f "$TMP"' EXIT

STUB_URLS="${SHELLSTACK_NGINX_STUB_URLS:-http://127.0.0.1/nginx_status,http://127.0.0.1/stub_status,http://127.0.0.1/nginx_stub_status}"

emit_up() {
  local role="$1" detail="$2" val="$3"
  printf 'shellstack_process_up{role="%s",detail="%s"} %s\n' "$role" "$detail" "$val"
}

{
  echo "# HELP shellstack_exporter_textfile_info shellstack textfile 采集脚本心跳（1=本分钟已执行）"
  echo "# TYPE shellstack_exporter_textfile_info gauge"
  echo "# HELP shellstack_baota_paths_detected 是否检测到宝塔典型目录（/www/server/panel）"
  echo "# TYPE shellstack_baota_paths_detected gauge"
  echo "# HELP shellstack_process_up 关键进程/服务是否存活（1=是）"
  echo "# TYPE shellstack_process_up gauge"
  echo "# HELP shellstack_php_fpm_up 宝塔 PHP 版本目录下 php-fpm master 是否存活"
  echo "# TYPE shellstack_php_fpm_up gauge"
  echo "# HELP shellstack_nginx_stub_active_connections stub_status Active connections"
  echo "# TYPE shellstack_nginx_stub_active_connections gauge"
  echo "# HELP shellstack_nginx_stub_reading stub_status Reading"
  echo "# TYPE shellstack_nginx_stub_reading gauge"
  echo "# HELP shellstack_nginx_stub_writing stub_status Writing"
  echo "# TYPE shellstack_nginx_stub_writing gauge"
  echo "# HELP shellstack_nginx_stub_waiting stub_status Waiting"
  echo "# TYPE shellstack_nginx_stub_waiting gauge"

  if [[ -d /www/server/panel ]]; then
    echo "shellstack_baota_paths_detected 1"
  else
    echo "shellstack_baota_paths_detected 0"
  fi
  echo "shellstack_exporter_textfile_info 1"

  # Nginx（宝塔路径优先）
  if [[ -x /www/server/nginx/sbin/nginx ]]; then
    if pgrep -x nginx >/dev/null 2>&1 || pgrep -f '/www/server/nginx/sbin/nginx' >/dev/null 2>&1; then
      emit_up nginx baota_sbin 1
    else
      emit_up nginx baota_sbin 0
    fi
  elif systemctl is-active --quiet nginx 2>/dev/null; then
    emit_up nginx systemd 1
  else
    pgrep -x nginx >/dev/null 2>&1 && emit_up nginx process 1 || emit_up nginx process 0
  fi

  # MySQL / MariaDB
  if systemctl is-active --quiet mysqld 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
    emit_up mysql systemd 1
  elif pgrep -x mysqld >/dev/null 2>&1 || pgrep -x mariadbd >/dev/null 2>&1; then
    emit_up mysql process 1
  else
    emit_up mysql none 0
  fi

  # Redis
  if systemctl is-active --quiet redis 2>/dev/null || systemctl is-active --quiet redis-server 2>/dev/null; then
    emit_up redis systemd 1
  elif pgrep -x redis-server >/dev/null 2>&1; then
    emit_up redis process 1
  else
    emit_up redis none 0
  fi

  # 宝塔面板
  if pgrep -f 'BT-Panel' >/dev/null 2>&1 || pgrep -f '/www/server/panel/BT-Panel' >/dev/null 2>&1; then
    emit_up baota_panel process 1
  else
    emit_up baota_panel process 0
  fi

  # PHP-FPM：扫描 /www/server/php/<ver>/
  if [[ -d /www/server/php ]]; then
    for d in /www/server/php/*/; do
      [[ -d "$d" ]] || continue
      ver="$(basename "$d")"
      bin="${d}sbin/php-fpm"
      if [[ -x "$bin" ]]; then
        if pgrep -af 'php-fpm: master process' 2>/dev/null | grep -qF "/www/server/php/${ver}/"; then
          printf 'shellstack_php_fpm_up{version="%s"} 1\n' "$ver"
        else
          printf 'shellstack_php_fpm_up{version="%s"} 0\n' "$ver"
        fi
      fi
    done
  fi

  # nginx stub_status（负载/连接数）
  parsed=0
  IFS=',' read -ra _uarr <<< "$STUB_URLS"
  for url in "${_uarr[@]}"; do
    url="$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$url" ]] || continue
    body="$(curl -fsS -m 2 "$url" 2>/dev/null || true)"
    [[ -n "$body" ]] || continue
    if echo "$body" | grep -q 'Active connections'; then
      ac="$(echo "$body" | head -1 | awk '/Active connections/ {print $3}')"
      rd="$(echo "$body" | awk '/Reading:/ {print $2}' | tr -d ',')"
      wr="$(echo "$body" | awk '/Reading:/ {print $4}' | tr -d ',')"
      wt="$(echo "$body" | awk '/Reading:/ {print $6}' | tr -d ',')"
      [[ "$ac" =~ ^[0-9]+$ ]] && echo "shellstack_nginx_stub_active_connections $ac"
      [[ "$rd" =~ ^[0-9]+$ ]] && echo "shellstack_nginx_stub_reading $rd"
      [[ "$wr" =~ ^[0-9]+$ ]] && echo "shellstack_nginx_stub_writing $wr"
      [[ "$wt" =~ ^[0-9]+$ ]] && echo "shellstack_nginx_stub_waiting $wt"
      parsed=1
      break
    fi
  done
  if [[ "$parsed" -eq 0 ]]; then
    echo "shellstack_nginx_stub_active_connections 0"
    echo "shellstack_nginx_stub_reading 0"
    echo "shellstack_nginx_stub_writing 0"
    echo "shellstack_nginx_stub_waiting 0"
  fi
} >"$TMP"
mv -f "$TMP" "$OUT"
chmod 644 "$OUT" 2>/dev/null || true
EOSCRIPT
  chmod 755 "$bin"

  local stub_port inject_url default_urls effective_urls
  stub_port="${SHELLSTACK_NGINX_STUB_LISTEN_PORT:-8899}"
  inject_url="http://127.0.0.1:${stub_port}/nginx_stub_status"
  default_urls="http://127.0.0.1/nginx_status,http://127.0.0.1/stub_status,http://127.0.0.1/nginx_stub_status"
  effective_urls="${SHELLSTACK_NGINX_STUB_URLS:-$default_urls}"

  if ! _exporter_nginx_stub_urls_probe_ok "$effective_urls"; then
    if [[ -x /www/server/nginx/sbin/nginx ]] && [[ "${SHELLSTACK_NGINX_STUB_INJECT:-1}" != "0" ]]; then
      log "未探测到可用 stub_status，尝试向宝塔 nginx.conf 注入 127.0.0.1:${stub_port} 专用 stub..."
      if _exporter_inject_baota_nginx_stub_status "$stub_port"; then
        effective_urls="${inject_url},${effective_urls}"
      else
        warn "stub 自动注入未成功，shellstack_nginx_stub_* 可能为 0（可手动配置 stub 或设 SHELLSTACK_NGINX_STUB_URLS）"
      fi
    fi
  fi

  local cronf="/etc/cron.d/shellstack-node-exporter-textfile"
  local tlog="/var/log/shellstack-node-exporter-textfile.log"
  touch "$tlog" 2>/dev/null || tlog="/tmp/shellstack-node-exporter-textfile.log"
  touch "$tlog" 2>/dev/null || true
  chmod 0644 "$tlog" 2>/dev/null || true
  cat >"$cronf" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
* * * * * root TEXTFILE_DIR=$dir SHELLSTACK_NGINX_STUB_URLS=$effective_urls $bin >>$tlog 2>&1
EOF
  chmod 644 "$cronf" 2>/dev/null || true

  TEXTFILE_DIR="$dir" SHELLSTACK_NGINX_STUB_URLS="$effective_urls" bash "$bin" >>"$LOG_FILE" 2>&1 || warn "首次执行 textfile 采集脚本失败"
  log "已部署宝塔/服务 textfile 采集: $bin → $dir/shellstack_baota.prom（cron: $cronf）"
  log "stub_status 探测 URL 列表（cron 已写入）: $effective_urls"
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

# 从 Consul 基址 URL 取出 authority 中的主机部分（不含端口；支持 [IPv6] 形式）
_exporter_host_from_consul_base() {
  local raw="$1" rest authority
  raw="${raw%/}"
  if [[ "$raw" =~ ^https?:// ]]; then
    rest="${raw#*://}"
    authority="${rest%%/*}"
  else
    authority="${raw%%/*}"
  fi
  if [[ "$authority" == \[* ]]; then
    printf '%s' "${authority#\[}" | cut -d']' -f1
  else
    printf '%s' "${authority%%:*}"
  fi
}

_exporter_metrics_allow_sources_list() {
  local consul_base="$1"
  local manual="${EXPORTER_METRICS_ALLOW_FROM:-${SHELLSTACK_EXPORTER_METRICS_ALLOW_FROM:-}}"
  local host ip
  if [[ -n "$manual" ]]; then
    echo "$manual" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
    return 0
  fi
  host="$(_exporter_host_from_consul_base "$consul_base")"
  if [[ -z "$host" ]]; then
    return 1
  fi
  if [[ "$host" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    echo "$host"
    return 0
  fi
  ip="$(getent ahostsv4 "$host" 2>/dev/null | awk '/STREAM/ {print $1; exit}')"
  if [[ -n "$ip" ]]; then
    echo "$ip"
    return 0
  fi
  ip="$(getent hosts "$host" 2>/dev/null | awk '{print $1; exit}')"
  if [[ -n "$ip" && "$ip" =~ ^[0-9.]+$ ]]; then
    echo "$ip"
    return 0
  fi
  return 1
}

_exporter_firewall_rule_exists_firewalld() {
  local src="$1" port="$2"
  firewall-cmd --permanent --list-rich-rules 2>/dev/null | grep -qF "source address=\"${src}\"" && \
    firewall-cmd --permanent --list-rich-rules 2>/dev/null | grep -qF "port=\"${port}\""
}

_exporter_firewall_firewalld_active() {
  command -v firewall-cmd >/dev/null 2>&1 || return 1
  if firewall-cmd --state >/dev/null 2>&1; then
    return 0
  fi
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
    return 0
  fi
  return 1
}

_exporter_firewall_ufw_active() {
  command -v ufw >/dev/null 2>&1 || return 1
  # 勿仅用 systemctl：Ubuntu 上 ufw.service 常为 oneshot，is-active 不等于「防火墙已启用」
  ufw status 2>/dev/null | grep -qi 'Status: active'
}

_exporter_firewall_allow_via_firewalld() {
  local port="$1"
  shift
  local srcs=("$@")
  local src any=0
  _exporter_firewall_firewalld_active || return 1
  for src in "${srcs[@]}"; do
    [[ -n "$src" ]] || continue
    if _exporter_firewall_rule_exists_firewalld "$src" "$port"; then
      log "firewalld 已存在放行规则: ${src} -> tcp/${port}"
      continue
    fi
    if firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"${src}\" port port=\"${port}\" protocol=tcp accept" >>"$LOG_FILE" 2>&1; then
      any=1
      log "firewalld 已添加: 允许 ${src} 访问 tcp/${port}"
    else
      warn "firewalld 添加规则失败: ${src} -> ${port}"
    fi
  done
  [[ "$any" -eq 1 ]] && firewall-cmd --reload >>"$LOG_FILE" 2>&1 || true
  return 0
}

_exporter_firewall_allow_via_ufw() {
  local port="$1"
  shift
  local srcs=("$@")
  local src
  _exporter_firewall_ufw_active || return 1
  for src in "${srcs[@]}"; do
    [[ -n "$src" ]] || continue
    if ufw status numbered 2>/dev/null | grep -qE "ALLOW.*${src}.*${port}"; then
      log "ufw 已存在类似放行: ${src} ${port}"
      continue
    fi
    if ufw allow from "$src" to any port "$port" proto tcp >>"$LOG_FILE" 2>&1; then
      log "ufw 已添加: 允许 ${src} 访问 ${port}/tcp"
    else
      warn "ufw 添加规则失败: ${src} -> ${port}"
    fi
  done
  return 0
}

_exporter_iptables_check_rule() {
  local ipt="$1" src="$2" port="$3"
  if "$ipt" -C INPUT -s "$src" -p tcp --dport "$port" -m comment --comment "shellstack-exporter" -j ACCEPT >/dev/null 2>&1; then
    return 0
  fi
  "$ipt" -C INPUT -s "$src" -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1
}

_exporter_iptables_insert_accept() {
  local ipt="$1" src="$2" port="$3"
  if _exporter_iptables_check_rule "$ipt" "$src" "$port"; then
    return 0
  fi
  if "$ipt" -I INPUT 1 -s "$src" -p tcp --dport "$port" -m comment --comment "shellstack-exporter" -j ACCEPT >>"$LOG_FILE" 2>&1; then
    return 0
  fi
  "$ipt" -I INPUT 1 -s "$src" -p tcp --dport "$port" -j ACCEPT >>"$LOG_FILE" 2>&1
}

_exporter_firewall_allow_via_iptables() {
  local port="$1"
  shift
  local srcs=("$@")
  local ipt src
  local ipt_bins=(iptables iptables-nft iptables-legacy)
  local chosen=""
  for ipt in "${ipt_bins[@]}"; do
    command -v "$ipt" >/dev/null 2>&1 || continue
    if "$ipt" -L INPUT -n >/dev/null 2>&1; then
      chosen="$ipt"
      break
    fi
  done
  [[ -n "$chosen" ]] || return 1
  log "使用 ${chosen}（iptables 后端）放行 tcp/${port}"
  for src in "${srcs[@]}"; do
    [[ -n "$src" ]] || continue
    if _exporter_iptables_check_rule "$chosen" "$src" "$port"; then
      log "${chosen} 已存在放行: ${src} -> ${port}"
      continue
    fi
    if _exporter_iptables_insert_accept "$chosen" "$src" "$port"; then
      log "${chosen} 已插入: 允许 ${src} 访问 tcp/${port}"
    else
      warn "${chosen} 插入规则失败（链名非 INPUT 或无权限）: ${src} -> ${port}"
    fi
  done
  return 0
}

_exporter_nft_metrics_comment() {
  local src="$1" port="$2"
  printf 'shellstack-exporter-%s-%s' "${src//\//-}" "$port"
}

_exporter_firewall_nft_input_chain() {
  if nft list chain inet filter input >/dev/null 2>&1; then
    printf '%s %s %s' inet filter input
    return 0
  fi
  if nft list chain ip filter INPUT >/dev/null 2>&1; then
    printf '%s %s %s' ip filter INPUT
    return 0
  fi
  return 1
}

_exporter_firewall_allow_via_nft() {
  local port="$1"
  shift
  local srcs=("$@")
  local src fam tbl ch cmt
  command -v nft >/dev/null 2>&1 || return 1
  read -r fam tbl ch < <(_exporter_firewall_nft_input_chain) || return 1
  for src in "${srcs[@]}"; do
    [[ -n "$src" ]] || continue
    cmt="$(_exporter_nft_metrics_comment "$src" "$port")"
    if nft list ruleset 2>/dev/null | grep -qF "$cmt"; then
      log "nft 已存在（comment ${cmt}）: ${src} -> tcp/${port}"
      continue
    fi
    if nft add rule "$fam" "$tbl" "$ch" tcp dport "$port" ip saddr "$src" accept comment "\"$cmt\"" >>"$LOG_FILE" 2>&1; then
      log "nft 已添加: $fam $tbl $ch 允许 ${src} -> tcp/${port}"
    else
      warn "nft 添加失败（链或族不匹配时可改用手工规则）: ${src} -> ${port}"
    fi
  done
  return 0
}

_exporter_firewall_allow_metrics_sources() {
  local port="$1"
  shift
  local srcs=("$@")

  if [[ ${#srcs[@]} -eq 0 ]]; then
    return 0
  fi

  log "防火墙：按本机环境依次尝试 firewalld → ufw → iptables → nft"

  if _exporter_firewall_firewalld_active; then
    _exporter_firewall_allow_via_firewalld "$port" "${srcs[@]}"
    return 0
  fi
  if _exporter_firewall_ufw_active; then
    _exporter_firewall_allow_via_ufw "$port" "${srcs[@]}"
    return 0
  fi
  if _exporter_firewall_allow_via_iptables "$port" "${srcs[@]}"; then
    return 0
  fi
  if _exporter_firewall_allow_via_nft "$port" "${srcs[@]}"; then
    return 0
  fi

  warn "未匹配到可用防火墙（firewalld/ufw/iptables/nft 均不可用或 INPUT/链不可写），跳过 ${port}/tcp 放行"
}

_exporter_apply_firewall_for_exporter_metrics() {
  local consul_base="$1"
  local port="${2:-$EXPORTER_LISTEN_PORT}"
  local line srcs=()

  if [[ "${SHELLSTACK_EXPORTER_SKIP_FIREWALL:-}" == "1" ]]; then
    log "已跳过防火墙配置（SHELLSTACK_EXPORTER_SKIP_FIREWALL=1）"
    return 0
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    warn "非 root，跳过防火墙：请 root 执行或手工放行 ${port}/tcp（源：Consul 服务器或 EXPORTER_METRICS_ALLOW_FROM）"
    return 0
  fi

  while IFS= read -r line; do
    [[ -n "$line" ]] && srcs+=("$line")
  done < <(_exporter_metrics_allow_sources_list "$consul_base" || true)

  if [[ ${#srcs[@]} -eq 0 ]]; then
    warn "无法得到放行源地址（检查 Consul 主机名解析或设置 EXPORTER_METRICS_ALLOW_FROM=IP）"
    return 0
  fi

  log "node_exporter 端口 ${port}：仅允许以下源访问（与 CONSUL_HTTP_ADDR 或 EXPORTER_METRICS_ALLOW_FROM 一致）：${srcs[*]}"
  _exporter_firewall_allow_metrics_sources "$port" "${srcs[@]}"
}

_exporter_json_escape() {
  # 最小 JSON 字符串转义（反斜杠与双引号）
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# Consul Service Meta JSON 片段（不含外层）；Consul 单值不宜过长，截断 480 字节
_exporter_meta_kv_reset() {
  _EXPORTER_META_JBUF=""
  _EXPORTER_META_JSEP=""
}

_exporter_meta_kv() {
  local k="$1" v="${2:-}"
  v="${v:0:480}"
  _EXPORTER_META_JBUF+="${_EXPORTER_META_JSEP}\"$k\":\"$(_exporter_json_escape "$v")\""
  _EXPORTER_META_JSEP=","
}

_exporter_consul_service_meta_json() {
  local bind_addr="$1" port="$2" tdir="${3:-}"
  local hn geo pip os_pretty bt tsize texist seen pair k v

  hn="$(hostname 2>/dev/null || echo unknown)"
  geo=""
  pip=""
  if [[ "$hn" =~ ^([A-Z][A-Z])-([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    geo="${BASH_REMATCH[1]}"
    pip="${BASH_REMATCH[2]}"
  fi
  os_pretty="unknown"
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    os_pretty="${PRETTY_NAME:-unknown}"
  fi
  bt=0
  [[ -d /www/server/panel ]] && bt=1
  tsize=0
  texist=0
  if [[ -n "$tdir" && -f "${tdir}/shellstack_baota.prom" ]]; then
    texist=1
    tsize="$(wc -c <"${tdir}/shellstack_baota.prom" 2>/dev/null | tr -d '[:space:]')"
  fi
  seen=0
  _exporter_node_exporter_textfile_arg_in_ps && seen=1

  _exporter_meta_kv_reset
  _exporter_meta_kv module modsecurity
  _exporter_meta_kv source shellstack-exporter
  _exporter_meta_kv hostname "$hn"
  _exporter_meta_kv registered_addr "$bind_addr"
  _exporter_meta_kv listen_port "$port"
  _exporter_meta_kv os_pretty "$os_pretty"
  _exporter_meta_kv baota_panel "$bt"
  _exporter_meta_kv textfile_dir "$tdir"
  _exporter_meta_kv textfile_prom shellstack_baota.prom
  _exporter_meta_kv textfile_present "$texist"
  _exporter_meta_kv textfile_bytes "$tsize"
  _exporter_meta_kv node_exporter_textfile_arg "$seen"
  _exporter_meta_kv geo_from_hostname "$geo"
  _exporter_meta_kv public_ip_from_hostname "$pip"
  _exporter_meta_kv shellstack_metrics_prefix "shellstack_"

  if [[ -n "${CONSUL_SERVICE_META:-}" ]]; then
    IFS=',' read -ra _umeta <<< "${CONSUL_SERVICE_META}"
    for pair in "${_umeta[@]}"; do
      pair="$(echo "$pair" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -n "$pair" ]] || continue
      k="${pair%%=*}"
      v="${pair#*=}"
      [[ "$k" == "$pair" ]] && v=""
      k="$(echo "$k" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      v="$(echo "$v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -n "$k" ]] || continue
      _exporter_meta_kv "$k" "$v"
    done
  fi

  printf '{%s}' "$_EXPORTER_META_JBUF"
}

# Consul Service ID 前缀：用当前主机名（完整优先），避免仅用 hostname -s 在部分环境得到过短片段（如 "10"）
_exporter_consul_host_prefix_for_service_id() {
  local h=""
  if [[ -r /etc/hostname ]]; then
    h="$(head -1 /etc/hostname 2>/dev/null | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  fi
  if [[ -z "$h" ]]; then
    h="$(hostname -f 2>/dev/null)"
  fi
  if [[ -z "$h" || "$h" == "(none)" ]]; then
    h="$(hostname 2>/dev/null)"
  fi
  if [[ -z "$h" ]]; then
    h="host"
  fi
  h="$(echo -n "$h" | tr '[:upper:]' '[:lower:]')"
  h="${h//./-}"
  h="$(echo -n "$h" | tr -cd '[:alnum:]-')"
  [[ -z "$h" ]] && h="host"
  if [[ ${#h} -gt 56 ]]; then
    h="${h:0:56}"
  fi
  printf '%s' "$h"
}

_exporter_consul_register() {
  local consul_base="$1"
  local bind_addr="$2"
  local port="$3"
  local textfile_dir="${4:-}"

  if ! command -v curl >/dev/null 2>&1; then
    warn "未找到 curl，无法调用 Consul API；请安装 curl 或手工注册服务"
    return 1
  fi

  local host_prefix sid tags_json extra_tag meta_blob ost
  host_prefix="$(_exporter_consul_host_prefix_for_service_id)"
  sid="${CONSUL_SERVICE_ID:-${host_prefix}-${CONSUL_SERVICE_NAME}-${port}}"

  tags_json='"shellstack","modsecurity","node-exporter","metrics-path=/metrics","shellstack-textfile","prometheus.io/scrape=true"'
  [[ -d /www/server/panel ]] && tags_json+=",\"baota-panel\""
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    ost="${ID:-unknown}-${VERSION_ID:-x}"
    ost="${ost// /_}"
    tags_json+=",\"$(_exporter_json_escape "os=${ost}")\""
  fi
  if [[ -n "${CONSUL_SERVICE_TAGS:-}" ]]; then
    IFS=',' read -ra _extra_tags <<< "${CONSUL_SERVICE_TAGS}"
    for extra_tag in "${_extra_tags[@]}"; do
      extra_tag="$(echo "$extra_tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -n "$extra_tag" ]] || continue
      tags_json+=",\"$(_exporter_json_escape "$extra_tag")\""
    done
  fi

  meta_blob="$(_exporter_consul_service_meta_json "$bind_addr" "$port" "$textfile_dir")"

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
  "Meta": ${meta_blob},
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
    log "已注册到 Consul: service_id=${sid} target=${bind_addr}:${port} consul=${consul_base}（Tags/Meta 已含主机、系统、textfile、宝塔等）"
    return 0
  fi

  warn "Consul 注册失败 HTTP ${http_code:-?}：${out:-（无响应体）}"
  warn "请检查 Consul 地址、网络；若启用 ACL 请设置 CONSUL_HTTP_TOKEN、本脚本 --consul-token= 或 main.sh --with-consul-token=..."
  warn "或手工执行: PUT ${consul_base}/v1/agent/service/register（Header: X-Consul-Token）"
  return 1
}

setup_exporter_and_register() {
  if [[ "${SHELLSTACK_EXPORTER_FORCE:-}" == "1" ]]; then
    log "SHELLSTACK_EXPORTER_FORCE=1：强制重跑 exporter（textfile/cron/防火墙/Consul 等将覆盖/重注册）"
  fi
  _exporter_apply_builtin_consul_defaults

  local consul_raw="${1:-${CONSUL_HTTP_ADDR:-}}"
  if [[ -z "$consul_raw" ]]; then
    consul_raw="$SHELLSTACK_EXPORTER_DEFAULT_CONSUL_ADDR"
    log "未显式提供 Consul 地址，使用内置默认: $consul_raw"
  fi
  CONSUL_HTTP_ADDR="$consul_raw"
  export CONSUL_HTTP_ADDR
  log "已设置 CONSUL_HTTP_ADDR（当前进程与 profile.d，供后续命令复用）"

  local _tok_persist="${CONSUL_HTTP_TOKEN:-}"
  [[ "${SHELLSTACK_EXPORTER_NO_BUILTIN_TOKEN:-}" == "1" ]] && _tok_persist=""
  _exporter_persist_consul_env_for_shells "$consul_raw" "$_tok_persist"

  _exporter_apply_geo_public_hostname

  log "=========================================="
  log "exporter：安装 node_exporter 并注册到 Consul（Prometheus 经 consul_sd 发现）"
  log "=========================================="

  local consul_base
  consul_base="$(_exporter_normalize_consul_base "$consul_raw")"
  log "Consul HTTP 基址: $consul_base"
  if [[ -z "${CONSUL_HTTP_TOKEN:-}" ]]; then
    warn "当前无 CONSUL_HTTP_TOKEN（若 Consul 要求 ACL，请 export 或去掉 SHELLSTACK_EXPORTER_NO_BUILTIN_TOKEN=1）"
  fi

  _exporter_install_node_exporter
  _exporter_ensure_service_running
  _exporter_apply_firewall_for_exporter_metrics "$consul_base" "${EXPORTER_LISTEN_PORT}"
  _exporter_install_baota_textfile_collector

  local ip _tdir
  _tdir="$(_exporter_node_exporter_textfile_dir)"
  if ! _exporter_node_exporter_textfile_arg_in_ps; then
    warn "进程参数中未检测到 --collector.textfile.directory，shellstack_* 可能不会出现在 /metrics；请检查 $(command -v systemctl >/dev/null 2>&1 && echo "/etc/default/prometheus-node-exporter 或 systemctl cat prometheus-node-exporter")"
  else
    log "node_exporter 已启用 textfile 采集目录（与 ${_tdir} 对齐后应出现 shellstack_* 指标）"
  fi

  ip="$(_exporter_local_ip)"
  if [[ -z "$ip" ]]; then
    warn "无法识别本机 IP，使用 127.0.0.1 作为注册 Address（请确认 Prometheus 能否访问）"
    ip="127.0.0.1"
  fi

  _exporter_consul_register "$consul_base" "$ip" "${EXPORTER_LISTEN_PORT}" "$_tdir"
  log "Exporter 流程结束；Prometheus 侧请配置 consul_sd_configs 指向同一 Consul 集群"
  log "说明: /metrics 中 smartmon_* 等来自本机 node_exporter 其它采集器；业务/栈指标搜前缀 shellstack_（若缺失请看 /var/log/shellstack-node-exporter-textfile.log）"
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
用法: exporter.sh [选项] [Consul HTTP 地址]
  exporter.sh
  exporter.sh http://127.0.0.1:8500
  exporter.sh --consul-token=SECRET http://consul.example.com:8500

不传地址时默认使用 SHELLSTACK_EXPORTER_DEFAULT_CONSUL_ADDR（可环境变量覆盖）。
未设置 CONSUL_HTTP_TOKEN 且未指定 SHELLSTACK_EXPORTER_NO_BUILTIN_TOKEN=1 时使用内置 Token。

与 main.sh 相同的环境变量仍可用：CONSUL_HTTP_ADDR、CONSUL_HTTP_TOKEN、EXPORTER_LISTEN_PORT、
CONSUL_SERVICE_NAME、CONSUL_SERVICE_ID、CONSUL_SERVICE_TAGS、CONSUL_SERVICE_META、SHELLSTACK_NGINX_STUB_URLS、
EXPORTER_METRICS_ALLOW_FROM、SHELLSTACK_EXPORTER_SKIP_FIREWALL、
SHELLSTACK_EXPORTER_SKIP_HOSTNAME、SHELLSTACK_EXPORTER_PUBLIC_IP、SHELLSTACK_EXPORTER_GEO_CODE、SHELLSTACK_EXPORTER_GEO_HOSTNAME 等。

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
  setup_exporter_and_register "$consul_arg" || exit $?
fi
