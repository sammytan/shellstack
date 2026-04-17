#!/bin/bash
# 安装 node exporter 并通过 Consul Agent API 注册服务（供 Prometheus consul_sd 发现）
# 架构：本机/目标机运行 node_exporter → 注册到 Consul → Prometheus 用 consul_sd_configs 抓取
#
# 指标覆盖：
#   - 常规系统：CPU/内存/负载/磁盘空间/磁盘 IO/网络流量 等由 node_exporter 默认 collectors 提供
#     （node_cpu_*、node_memory_*、node_load*、node_filesystem_*、node_disk_*、node_network_* 等）
#   - 同一 /metrics 下 textfile 另写 shellstack_host_* 摘要（负载/内存占比/CPU&iowait 短采样/根分区/整盘扇区与网卡字节速率），便于与 shellstack_ 业务指标同面板；细粒度仍以 node_* 为准
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
#   SHELLSTACK_NGINX_STUB_INJECT  默认 1：stub 全失败且**宝塔 Nginx 已安装**（/www/server/nginx/sbin/nginx + conf/nginx.conf）时注入 127.0.0.1 专用 server；仅有面板未装 Nginx 则跳过；设 0 关闭
#   SHELLSTACK_NGINX_STUB_LISTEN_PORT  注入时监听端口，默认 8899（仅 127.0.0.1）；片段文件为 /www/server/nginx/conf/shellstack_status.conf（含 stub_status + 探测到的 PHP-FPM status location，pool 需启用 pm.status_path=/status）
#   CONSUL_SERVICE_ID       覆盖自动生成的服务 ID（默认 {hostname}-{CONSUL_SERVICE_NAME}-{port}，hostname 见下方函数）
#   CONSUL_SERVICE_NAME     默认 shellstack-node-exporter
#   CONSUL_SERVICE_TAGS     额外标签，逗号分隔，追加到默认 tags
#   CONSUL_SERVICE_META     额外 Meta，逗号分隔 key=value（勿与脚本内置键重复以免 JSON 冲突）；与脚本自动写入的 Meta 合并
#   Consul Service Meta 仅在每次「注册/重新注册」时写入（含 svc_*_up 等快照），不会随 textfile 每分钟刷新；实时状态与负载请用 Prometheus 查询 shellstack_*
#   EXPORTER_METRICS_ALLOW_FROM / SHELLSTACK_EXPORTER_METRICS_ALLOW_FROM  逗号分隔 IPv4 或 CIDR；若设置则仅放行这些源访问 metrics 端口，不再从 Consul 地址推导
#   SHELLSTACK_EXPORTER_SKIP_FIREWALL=1  不尝试配置本机防火墙（9100 等须自行放行）
#   防火墙自动匹配（root）：firewalld → ufw → iptables/iptables-nft/iptables-legacy → nft（inet filter input 或 ip filter INPUT）
#   部署 exporter 前（root）：将静态主机名设为「二位地区码-公网IPv4」（IPv4 中 . 改为 -，单标签），如 HK-156-239-6-130（避免 HK-156.239.x.x 被 SSH/hostname -s 截成 HK-156）
#     公网 IP：依次尝试 ipify / ipinfo.io/ip / ifconfig.me / icanhazip / ident.me / AWS checkip 等多个出口探测 URL
#     地区码：ip-api.com（HTTP）与 ipinfo.io/json（HTTPS）互为补充
#   SHELLSTACK_EXPORTER_SKIP_HOSTNAME=1     不修改主机名
#   SHELLSTACK_EXPORTER_PUBLIC_IP=a.b.c.d   手工公网 IP（跳过出口 IP 探测）
#   SHELLSTACK_EXPORTER_GEO_CODE=HK         手工区域码（二位大写字母；与 PUBLIC_IP 可只设其一，另一项走 API）
#   SHELLSTACK_EXPORTER_GEO_HOSTNAME=NAME    完全指定主机名（跳过 Geo/IP 拼接）
#   SHELLSTACK_EXPORTER_FORCE=1  由 main.sh 在「仅 exporter + --force」时设置：强制重跑 exporter 各步骤（不触发 ModSecurity 主流程）
#   textfile 采集（cron）可选：SHELLSTACK_MYSQL_SOCKET=socket路径；
#     MySQL root 等需密码时（否则 mysqladmin 报 Access denied）：任选其一
#     — SHELLSTACK_MYSQL_DEFAULTS_FILE=/root/.my.cnf（推荐，文件 chmod 600；[client] 含 user/password）
#     — SHELLSTACK_MYSQL_USER= SHELLSTACK_MYSQL_PASSWORD=（部署 exporter 时若已 export，会写入 cron 行；密码亦可见于 /etc/cron.d，敏感环境请用 defaults-file）
#   SHELLSTACK_REDIS_SOCKET=  SHELLSTACK_REDIS_HOST / SHELLSTACK_REDIS_PORT
#   nginx-module-vts（与 baota_modsec_deploy 的 shellstack_vts.conf 一致）：textfile 每分钟抓取
#     http://127.0.0.1:${SHELLSTACK_VTS_LISTEN_PORT:-8898}/nginx-vts-status/format/prometheus
#     并原样写入同 .prom（指标名多为 nginx_vts_*）；SHELLSTACK_NGINX_VTS_PROM_URL 可覆盖完整 URL；
#     SHELLSTACK_NGINX_VTS_PROM_DISABLE=1 关闭抓取（shellstack_nginx_vts_scrape_ok=0）
#   SHELLSTACK_TEXTFILE_SKIP_HOST_METRICS=1  不在 textfile 中写入 shellstack_host_*（仅用 node_exporter 的 node_*）
#   日志：/var/log/shellstack-node-exporter-textfile.log = exporter 首次执行 textfile 时 tee 至此 + 部署标记行，之后 cron 每分钟追加；指标仍在 .prom。**prometheus-node-exporter** 用 journalctl（如 journalctl -u prometheus-node-exporter -e）。
#   CentOS/RHEL 7：默认仓库无 node_exporter 时脚本会尝试启用 epel-release 并安装 golang-github-prometheus-node-exporter；仍失败则从 GitHub 下载官方二进制至 /usr/local/bin 并写入 systemd 单元（见下）。
#   SHELLSTACK_NODE_EXPORTER_VERSION  二进制回退时的发行版号，默认 1.7.0（兼容 glibc 2.17 等老系统）
#   SHELLSTACK_EXPORTER_SKIP_NODE_EXPORTER_BINARY_FALLBACK=1  禁止 GitHub 二进制回退（仅包管理器安装）

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
    # 单标签主机名：把 IPv4 的 . 换成 -，否则含点主机名在多标签语义下会被 SSH \\h、hostname -s 显示成首段（如 HK-156.239.4.2 → HK-156）
    name="${cc}-${ip//./-}"
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

_exporter_yum_ensure_epel_release() {
  command -v yum >/dev/null 2>&1 || return 0
  [[ -f /etc/redhat-release ]] || return 0
  if yum repolist enabled 2>/dev/null | grep -qiE '(^|[[:space:]])epel(/|[[:space:]])'; then
    return 0
  fi
  if rpm -q epel-release >/dev/null 2>&1; then
    return 0
  fi
  log "尝试安装 epel-release（便于 CentOS/RHEL 7 等从 EPEL 安装 node_exporter）"
  yum install -y epel-release >>"$LOG_FILE" 2>&1 || true
}

_exporter_node_exporter_go_arch() {
  case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64 | arm64) echo arm64 ;;
    armv7l) echo armv7 ;;
    ppc64le) echo ppc64le ;;
    s390x) echo s390x ;;
    *) echo "" ;;
  esac
}

# 无发行版包或包名不匹配时：官方 release 二进制 + systemd（RHEL 系常见 /etc/sysconfig/node_exporter）
_exporter_install_node_exporter_binary_fallback() {
  [[ "${SHELLSTACK_EXPORTER_SKIP_NODE_EXPORTER_BINARY_FALLBACK:-}" == "1" ]] && {
    warn "已设置 SHELLSTACK_EXPORTER_SKIP_NODE_EXPORTER_BINARY_FALLBACK=1，跳过官方二进制回退"
    return 1
  }
  local ver arch url tmpdir tgz ex binpath
  ver="${SHELLSTACK_NODE_EXPORTER_VERSION:-1.7.0}"
  arch="$(_exporter_node_exporter_go_arch)"
  if [[ -z "$arch" ]]; then
    warn "无法根据 uname -m 选择 node_exporter 架构，跳过二进制回退"
    return 1
  fi
  binpath="/usr/local/bin/node_exporter"
  url="https://github.com/prometheus/node_exporter/releases/download/v${ver}/node_exporter-${ver}.linux-${arch}.tar.gz"
  tmpdir="$(mktemp -d)" || return 1
  tgz="${tmpdir}/node_exporter.tgz"
  if ! curl -fsSL "$url" -o "$tgz" >>"$LOG_FILE" 2>&1; then
    rm -rf "$tmpdir"
    warn "下载 node_exporter 失败（请检查网络或版本号）: $url"
    return 1
  fi
  if ! tar -xzf "$tgz" -C "$tmpdir" >>"$LOG_FILE" 2>&1; then
    rm -rf "$tmpdir"
    warn "解压 node_exporter 归档失败"
    return 1
  fi
  ex="$(find "$tmpdir" -maxdepth 3 -type f -name node_exporter 2>/dev/null | head -1)"
  if [[ -z "$ex" || ! -f "$ex" ]]; then
    rm -rf "$tmpdir"
    warn "解压后未找到 node_exporter 可执行文件"
    return 1
  fi
  if ! install -m 0755 "$ex" "$binpath" >>"$LOG_FILE" 2>&1; then
    if ! cp -f "$ex" "$binpath" >>"$LOG_FILE" 2>&1 || ! chmod 0755 "$binpath" >>"$LOG_FILE" 2>&1; then
      rm -rf "$tmpdir"
      warn "无法写入 $binpath"
      return 1
    fi
  fi
  rm -rf "$tmpdir"

  if ! systemctl list-unit-files 2>/dev/null | grep -qE '^node_exporter\.service|^prometheus-node-exporter\.service'; then
    umask 022
    mkdir -p /etc/sysconfig 2>/dev/null || true
    if [[ ! -f /etc/sysconfig/node_exporter ]]; then
      {
        echo "# 由 shellstack exporter 二进制回退生成；textfile 等参数由脚本合并至此"
        echo "NODE_EXPORTER_OPTS=\"--web.listen-address=:${EXPORTER_LISTEN_PORT}\""
      } >"/etc/sysconfig/node_exporter"
    fi
    cat >/etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter (shellstack binary fallback)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
Group=nobody
EnvironmentFile=-/etc/sysconfig/node_exporter
ExecStart=${binpath} \$NODE_EXPORTER_OPTS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
    log "已写入 systemd 单元 /etc/systemd/system/node_exporter.service 与 /etc/sysconfig/node_exporter（二进制回退）"
  fi
  log "已通过 GitHub 官方二进制安装 node_exporter 至 ${binpath}（v${ver}，${arch}）"
  return 0
}

_exporter_install_node_exporter() {
  if command -v node_exporter >/dev/null 2>&1 || command -v prometheus-node-exporter >/dev/null 2>&1; then
    log "检测到 node_exporter / prometheus-node-exporter 已存在，跳过仓库/二进制安装"
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update >>"$LOG_FILE" 2>&1 || true
    apt-get install -y prometheus-node-exporter >>"$LOG_FILE" 2>&1 || \
      apt-get install -y node-exporter >>"$LOG_FILE" 2>&1 || \
      warn "APT 安装 node exporter 失败，请检查源或手动安装"
  elif command -v dnf >/dev/null 2>&1; then
    local dnf_ok=0
    for pkg in node_exporter golang-github-prometheus-node-exporter prometheus-node-exporter; do
      if dnf install -y "$pkg" >>"$LOG_FILE" 2>&1; then
        dnf_ok=1
        break
      fi
    done
    if [[ "$dnf_ok" -eq 0 ]]; then
      warn "DNF 未能安装 node_exporter（已依次尝试 node_exporter / golang-github-prometheus-node-exporter / prometheus-node-exporter）"
      _exporter_install_node_exporter_binary_fallback || true
    fi
  elif command -v yum >/dev/null 2>&1; then
    _exporter_yum_ensure_epel_release
    local yum_ok=0
    for pkg in golang-github-prometheus-node-exporter prometheus-node-exporter node_exporter; do
      if yum install -y "$pkg" >>"$LOG_FILE" 2>&1; then
        yum_ok=1
        log "已通过 YUM 安装包: $pkg"
        break
      fi
    done
    if [[ "$yum_ok" -eq 0 ]]; then
      warn "YUM 未能从已启用仓库安装 node_exporter（CentOS 7 等需 epel-release；已尝试 golang-github-prometheus-node-exporter / prometheus-node-exporter / node_exporter）"
      _exporter_install_node_exporter_binary_fallback || warn "二进制回退失败，请手动安装 node_exporter 并确保监听 ${EXPORTER_LISTEN_PORT}"
    fi
  else
    warn "未识别的包管理器，尝试官方二进制回退"
    _exporter_install_node_exporter_binary_fallback || warn "无法自动安装 node_exporter"
  fi

  if ! command -v node_exporter >/dev/null 2>&1 && command -v prometheus-node-exporter >/dev/null 2>&1; then
    if [[ ! -x /usr/local/bin/node_exporter ]]; then
      ln -sf "$(command -v prometheus-node-exporter)" /usr/local/bin/node_exporter 2>>"$LOG_FILE" || true
    fi
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

# 宝塔环境 Nginx 是否已安装（存在官方二进制与主配置，才允许改 nginx.conf）
_exporter_baota_nginx_installed() {
  [[ -x /www/server/nginx/sbin/nginx ]] && [[ -f /www/server/nginx/conf/nginx.conf ]]
}

# 从 ps 行解析该版本 PHP-FPM 主配置文件（宝塔：master process (/www/server/php/XX/etc/php-fpm.conf)）
_exporter_baota_php_fpm_master_conf_for_ver() {
  local ver="$1" line conf
  while read -r line; do
    [[ "$line" == *"/www/server/php/${ver}/"* ]] || continue
    [[ "$line" == *"master process"* ]] || continue
    conf="$(printf '%s' "$line" | sed -n 's/.*master process (\(\/www\/server\/php\/[^)]*php-fpm\.conf\)).*/\1/p')"
    [[ -f "$conf" ]] && { printf '%s\n' "$conf"; return 0; }
  done < <(pgrep -af 'php-fpm: master process' 2>/dev/null || true)
  conf="/www/server/php/${ver}/etc/php-fpm.conf"
  [[ -f "$conf" ]] && printf '%s\n' "$conf"
}

# 收集主配置中的 include 及主文件本身（供解析 pool 的 listen / pm.status_path）
_exporter_baota_collect_php_fpm_pool_files() {
  local master="$1" d line pat f
  [[ -f "$master" ]] || return 1
  d="$(dirname "$master")"
  shopt -s nullglob
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*include[[:space:]]*= ]] || continue
    pat="${line#*=}"
    pat="${pat%%;*}"
    pat="$(echo "$pat" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$pat" ]] && continue
    [[ "$pat" != /* ]] && pat="${d}/${pat}"
    for f in $pat; do
      [[ -f "$f" ]] && printf '%s\n' "$f"
    done
  done < <(grep -E '^[[:space:]]*include[[:space:]]*=' "$master" 2>/dev/null || true)
  shopt -u nullglob
  printf '%s\n' "$master"
}

# 在 pool 配置中查找 listen 与 sock 一致的段，输出 pm.status_path（缺省则 /status）
_exporter_baota_pm_status_path_for_listen() {
  local sock="$1" ver="$2" master
  local -a files=()
  master="$(_exporter_baota_php_fpm_master_conf_for_ver "$ver")"
  [[ -z "$master" || ! -f "$master" ]] && { echo "/status"; return 0; }
  mapfile -t files < <(_exporter_baota_collect_php_fpm_pool_files "$master" | sort -u)
  [[ ${#files[@]} -eq 0 ]] && { echo "/status"; return 0; }
  awk -v tsock="$sock" '
  function norm(s) {
    gsub(/\r/,"",s)
    gsub(/^[ \t]+|[ \t]+$/,"",s)
    gsub(/^["\x27]+|["\x27]+$/,"",s)
    gsub(/^unix:/,"",s)
    return s
  }
  BEGIN { done=0; have_l=0; have_s=0; lv=""; sv="" }
  function flush() {
    if (done || !have_l) return
    if (norm(lv) != norm(tsock)) return
    if (have_s && sv != "") {
      p = norm(sv)
      if (p !~ /^\//) p = "/" p
      print p
    } else print "/status"
    done = 1
  }
  /^[ \t]*;/ { next }
  /^[ \t]*\[/ {
    flush()
    have_l = 0; have_s = 0; lv = ""; sv = ""
  }
  /^listen[ \t]*=[ \t]*/ {
    sub(/^listen[ \t]*=[ \t]*/, "")
    sub(/[ \t;#].*$/,"")
    lv = $0
    have_l = 1
  }
  /^pm\.status_path[ \t]*=[ \t]*/ {
    sub(/^pm\.status_path[ \t]*=[ \t]*/, "")
    sub(/[ \t;#].*$/,"")
    sv = $0
    have_s = 1
  }
  END {
    flush()
    if (!done) print "/status"
  }
  ' "${files[@]}" 2>/dev/null
}

# 列出本机宝塔 PHP-FPM status：每行 location标签\\tsocket\\tpm.status_path（path 来自 pool 与 listen 匹配）
_exporter_baota_list_php_fpm_status_sockets() {
  local line ver sock s base st
  declare -A seen=()
  shopt -s nullglob
  while read -r line; do
    [[ "$line" =~ /www/server/php/([^/]+)/ ]] || continue
    ver="${BASH_REMATCH[1]}"
    sock=""
    if [[ -S "/tmp/php-cgi-${ver}.sock" ]]; then
      sock="/tmp/php-cgi-${ver}.sock"
    elif [[ -S "/www/server/php/${ver}/var/run/php-fpm.sock" ]]; then
      sock="/www/server/php/${ver}/var/run/php-fpm.sock"
    fi
    [[ -z "$sock" ]] && continue
    [[ -n "${seen[$ver]:-}" ]] && continue
    seen[$ver]=1
    st="$(_exporter_baota_pm_status_path_for_listen "$sock" "$ver" | tail -n 1)"
    [[ -z "$st" ]] && st="/status"
    printf '%s\t%s\t%s\n' "${ver//./_}" "$sock" "$st"
  done < <(pgrep -af 'php-fpm: master process' 2>/dev/null | sort -u)
  for s in /tmp/php-cgi-*.sock; do
    [[ -S "$s" ]] || continue
    base="${s#/tmp/php-cgi-}"
    base="${base%.sock}"
    [[ -n "${seen[$base]:-}" ]] && continue
    seen[$base]=1
    st="$(_exporter_baota_pm_status_path_for_listen "$s" "$base" | tail -n 1)"
    [[ -z "$st" ]] && st="/status"
    printf '%s\t%s\t%s\n' "${base//./_}" "$s" "$st"
  done
  shopt -u nullglob
}

# 在 nginx.conf 的 http {} 内插入 include shellstack_status.conf（适配宝塔：http 与 { 常分两行）
_exporter_baota_nginx_conf_ensure_shellstack_include() {
  local ngx_main="$1"
  local line='        include /www/server/nginx/conf/shellstack_status.conf;'
  local bak="${ngx_main}.bak-shellstack"
  local inserted=0

  grep -qF 'shellstack_status.conf' "$ngx_main" 2>/dev/null && return 0

  cp -a "$ngx_main" "$bak" 2>>"${LOG_FILE:-/dev/null}" || {
    warn "无法备份 ${ngx_main}，跳过插入 include"
    return 1
  }

  if command -v perl >/dev/null 2>&1; then
    SHELLSTACK_INC_LINE="$line" perl -0777 -i -pe 's/(^http[ \t]*\r?\n[ \t]*\{)/$1\n$ENV{SHELLSTACK_INC_LINE}/m' "$ngx_main" 2>>"$LOG_FILE" || true
    grep -qF 'shellstack_status.conf' "$ngx_main" 2>/dev/null && inserted=1
  fi

  if [[ "$inserted" -eq 0 ]]; then
    cp -a "$bak" "$ngx_main" 2>/dev/null || true
    _incf="$(mktemp)" || true
    if [[ -n "$_incf" ]]; then
      printf '%s\n' "$line" >"$_incf"
      sed -i '/^[[:space:]]*http[[:space:]]*{/r '"$_incf" "$ngx_main" 2>>"$LOG_FILE" || true
      rm -f "$_incf"
      grep -qF 'shellstack_status.conf' "$ngx_main" 2>/dev/null && inserted=1
    fi
  fi

  if [[ "$inserted" -eq 0 ]]; then
    cp -a "$bak" "$ngx_main" 2>/dev/null || true
    _incf="$(mktemp)" || true
    if [[ -n "$_incf" ]]; then
      printf '%s\n' "$line" >"$_incf"
      sed -i '/^[[:space:]]*include[[:space:]]\+proxy\.conf;/r '"$_incf" "$ngx_main" 2>>"$LOG_FILE" || true
      rm -f "$_incf"
      grep -qF 'shellstack_status.conf' "$ngx_main" 2>/dev/null && inserted=1
    fi
  fi

  if [[ "$inserted" -eq 0 ]]; then
    cp -a "$bak" "$ngx_main" 2>/dev/null || true
    rm -f "$bak" 2>/dev/null || true
    warn "无法在 nginx.conf 自动插入 shellstack_status.conf（未匹配 http{ 同行、http 换行 {、或 include proxy.conf）。请手工在 http {} 内加入: $line"
    return 1
  fi
  log "已向 nginx.conf 插入 include shellstack_status.conf（已适配宝塔「http」与「{」分两行）"
  return 0
}

# 当前二进制是否静态/动态编入了 ModSecurity-nginx 连接器（无则不得写 modsecurity 指令）
_exporter_nginx_has_modsecurity_connector() {
  local ngx_bin="$1" v
  [[ -x "$ngx_bin" ]] || return 1
  v="$("$ngx_bin" -V 2>&1)" || return 1
  case $v in
    *ngx_http_modsecurity_module*) return 0 ;;
  esac
  if printf '%s' "$v" | grep -qiE -- '--add-(dynamic-)?module=[^ ]*[Mm]od[Ss]ecurity'; then
    return 0
  fi
  if printf '%s' "$v" | grep -qiF 'modsecurity-nginx'; then
    return 0
  fi
  return 1
}

# 写入 /www/server/nginx/conf/shellstack_status.conf：127.0.0.1 stub_status + 各 PHP-FPM pm.status_path（默认 URI /status）
_exporter_write_baota_shellstack_status_conf() {
  local port="$1"
  local ngx_bin="${2:-/www/server/nginx/sbin/nginx}"
  local out="/www/server/nginx/conf/shellstack_status.conf"
  local fcgi_line="fastcgi_params"
  local root_dir="/www/server/nginx/html"
  local _fpmstub="/tmp/.shellstack_fpm_status_stub"
  local _has_ms=0
  [[ -d "$root_dir" ]] || root_dir="/tmp"
  [[ -f /www/server/nginx/conf/fastcgi.conf ]] && fcgi_line="/www/server/nginx/conf/fastcgi.conf"
  if _exporter_nginx_has_modsecurity_connector "$ngx_bin"; then
    _has_ms=1
  fi
  # FPM status 需要指向存在的 SCRIPT_FILENAME；fastcgi.conf 否则会拼成 \$document_root/shellstack-fpm-status-xx → File not found
  touch "$_fpmstub" 2>/dev/null || true
  chmod 0644 "$_fpmstub" 2>/dev/null || true

  {
    echo "# shellstack exporter 生成：127.0.0.1:${port}，仅供本机采集；重跑 --with-exporter 会覆盖"
    echo "# Nginx: GET /nginx_stub_status"
    echo "# PHP-FPM: GET /shellstack-fpm-status-<tag>；SCRIPT_NAME/REQUEST_URI 与 pool 中 pm.status_path 一致（由 ps→php-fpm.conf→include 解析）；占位文件 ${_fpmstub}"
    echo "# FPM 经 unix socket 时 REMOTE_ADDR 常为空，各 location 内强制 REMOTE_ADDR=127.0.0.1"
    echo "server {"
    echo "    listen 127.0.0.1:${port};"
    echo "    server_name 127.0.0.1;"
    if [[ "$_has_ms" -eq 1 ]]; then
      echo "    # 已检测到 ModSecurity-nginx 模块：继承 http{} 的 modsecurity on 会拦 stub/status，本 server 关闭"
      echo "    modsecurity off;"
    fi
    echo "    root ${root_dir};"
    echo "    location /nginx_stub_status {"
    echo "        stub_status on;"
    echo "        access_log off;"
    echo "        # 仅监听 127.0.0.1 时已等效隔离；勿用 allow 127.0.0.1：http 级 real_ip 可能改写 \$remote_addr 致误拒"
    echo "        allow all;"
    echo "    }"
  } >"$out"

  local tag sk stpath
  while IFS=$'\t' read -r tag sk stpath; do
    [[ -n "$tag" && -n "$sk" ]] || continue
    [[ -n "$stpath" ]] || stpath="/status"
    {
      echo "    # pm.status_path=${stpath} listen=${sk}"
      echo "    location = /shellstack-fpm-status-${tag} {"
      echo "        access_log off;"
      if [[ "$_has_ms" -eq 1 ]]; then
        echo "        modsecurity off;"
      fi
      echo "        allow all;"
      echo "        include ${fcgi_line};"
      echo "        fastcgi_pass unix:${sk};"
      echo "        fastcgi_param SCRIPT_FILENAME ${_fpmstub};"
      echo "        fastcgi_param SCRIPT_NAME ${stpath};"
      echo "        fastcgi_param REQUEST_URI ${stpath};"
      echo "        fastcgi_param REQUEST_METHOD GET;"
      echo "        fastcgi_param QUERY_STRING \"\";"
      echo "        fastcgi_param PATH_INFO \"\";"
      echo "        fastcgi_param REMOTE_ADDR 127.0.0.1;"
      echo "        fastcgi_param REMOTE_PORT 0;"
      echo "        fastcgi_param SERVER_ADDR 127.0.0.1;"
      echo "        fastcgi_param SERVER_NAME 127.0.0.1;"
      echo "        fastcgi_param SERVER_PORT ${port};"
      echo "    }"
    } >>"$out"
  done < <(_exporter_baota_list_php_fpm_status_sockets)

  echo "}" >>"$out"
  chmod 644 "$out" 2>/dev/null || true
}

# 在宝塔 nginx.conf 的 http{} 内 include shellstack_status.conf（仅 127.0.0.1：stub + PHP-FPM status）
_exporter_inject_baota_nginx_stub_status() {
  local port="${1:-8899}"
  local ngx_bin="/www/server/nginx/sbin/nginx"
  local ngx_main="/www/server/nginx/conf/nginx.conf"
  local snip="/www/server/nginx/conf/shellstack_status.conf"
  local _nfpm=0 _fpm_hint="" tag sk _st

  if ! _exporter_baota_nginx_installed; then
    warn "未检测到宝塔 Nginx（需要可执行文件 ${ngx_bin} 与主配置 ${ngx_main}），跳过 stub / status 注入"
    return 1
  fi

  if ss -lnt 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
    if ss -lnt 2>/dev/null | grep -qE "127\.0\.0\.1:${port}"; then
      log "检测到 127.0.0.1:${port} 已在监听，将仅刷新 ${snip} 内容"
    else
      warn "端口 ${port} 已被占用且非 127.0.0.1:${port}，跳过注入（可设 SHELLSTACK_NGINX_STUB_LISTEN_PORT）"
      return 1
    fi
  fi

  while IFS=$'\t' read -r tag sk _st; do
    [[ -n "$tag" ]] || continue
    _nfpm=$((_nfpm + 1))
    _fpm_hint+=" http://127.0.0.1:${port}/shellstack-fpm-status-${tag}"
  done < <(_exporter_baota_list_php_fpm_status_sockets)

  _exporter_write_baota_shellstack_status_conf "$port" "$ngx_bin"

  if grep -qF 'shellstack_stub_status.conf' "$ngx_main" 2>/dev/null; then
    sed -i.bak-shellstack-mig 's|shellstack_stub_status\.conf|shellstack_status.conf|g' "$ngx_main" 2>>"$LOG_FILE" || true
    rm -f /www/server/nginx/conf/shellstack_stub_status.conf 2>/dev/null || true
    log "已将 nginx.conf 中 shellstack_stub_status.conf 引用迁移为 shellstack_status.conf"
  fi

  if grep -qF 'include /www/server/nginx/conf/shellstack_status.conf' "$ngx_main" 2>/dev/null; then
    log "nginx.conf 已包含 shellstack_status.conf，已刷新片段（stub + ${_nfpm} 个 PHP-FPM status location）"
  elif ! _exporter_baota_nginx_conf_ensure_shellstack_include "$ngx_main"; then
    return 1
  fi

  if ! "$ngx_bin" -t >>"$LOG_FILE" 2>&1; then
    if [[ -f "${ngx_main}.bak-shellstack" ]]; then
      cp -a "${ngx_main}.bak-shellstack" "$ngx_main" 2>>"$LOG_FILE" && warn "nginx -t 未通过，已从 ${ngx_main}.bak-shellstack 恢复 nginx.conf"
    else
      warn "nginx -t 未通过，请检查 ${snip} 与 nginx.conf 语法"
    fi
    return 1
  fi
  rm -f "${ngx_main}.bak-shellstack" 2>/dev/null || true

  # 宝塔环境优先 /etc/init.d/nginx reload，再回退 systemctl / nginx -s reload
  if [[ -x /etc/init.d/nginx ]] && /etc/init.d/nginx reload >>"$LOG_FILE" 2>&1; then
    log "已写入 ${snip} 并已执行 /etc/init.d/nginx reload：stub http://127.0.0.1:${port}/nginx_stub_status${_fpm_hint}（FPM 需 pool 启用 pm.status_path=/status）"
    return 0
  fi
  if systemctl reload nginx >>"$LOG_FILE" 2>&1; then
    log "已写入 ${snip} 并已 systemctl reload nginx：stub 与上同${_fpm_hint}"
    return 0
  fi
  if "$ngx_bin" -s reload >>"$LOG_FILE" 2>&1; then
    log "已写入 ${snip} 并已 ${ngx_bin} -s reload：stub 与上同${_fpm_hint}"
    return 0
  fi
  warn "配置已写入 ${snip} 但重载失败，请手动: nginx -t && /etc/init.d/nginx reload"
  return 1
}

# 向 ARGS / NODE_EXPORTER_OPTS / OPTIONS 等「VAR=\"…\"」行合并 --collector.textfile.directory（Debian default 与 RHEL sysconfig）
_exporter_merge_textfile_into_env_file() {
  local f="$1" var="$2" dir="$3"
  [[ -f "$f" ]] || return 1
  if [[ "${SHELLSTACK_EXPORTER_FORCE:-}" == "1" ]] && grep -qE "^${var}=" "$f" 2>/dev/null; then
    sed -i.bak-shellstack-force "s/[[:space:]]\{1,\}--collector\.textfile\.directory=[^\"[:space:]]*//g" "$f" 2>/dev/null || true
    if ! grep -qF 'collector.textfile.directory' "$f" 2>/dev/null; then
      sed -i.bak-shellstack "s|^${var}=\"\\(.*\\)\"|${var}=\"\\1 --collector.textfile.directory=${dir}\"|" "$f" 2>/dev/null || true
    fi
  elif grep -qF 'collector.textfile.directory' "$f" 2>/dev/null; then
    :
  elif grep -qE "^${var}=" "$f" 2>/dev/null; then
    sed -i.bak-shellstack "s|^${var}=\"\\(.*\\)\"|${var}=\"\\1 --collector.textfile.directory=${dir}\"|" "$f" 2>/dev/null || true
  else
    echo "${var}=\"--collector.textfile.directory=${dir}\"" >>"$f"
  fi
  return 0
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
    _exporter_merge_textfile_into_env_file "/etc/default/prometheus-node-exporter" ARGS "$dir"
  elif [[ -f /etc/sysconfig/node_exporter ]]; then
    _exporter_merge_textfile_into_env_file "/etc/sysconfig/node_exporter" NODE_EXPORTER_OPTS "$dir"
  elif [[ -f /etc/default/node_exporter ]]; then
    # prometheus-rpm / 部分 RPM：OPTIONS= 与 /usr/bin/node_exporter
    _exporter_merge_textfile_into_env_file "/etc/default/node_exporter" OPTIONS "$dir"
  elif [[ "$svc" == "prometheus-node-exporter" ]]; then
    f="/etc/default/prometheus-node-exporter"
    if [[ ! -f "$f" ]]; then
      mkdir -p /etc/default 2>/dev/null || true
      umask 022
      {
        echo "# generated by shellstack exporter.sh"
        echo "ARGS=\"--collector.textfile.directory=${dir}\""
      } >"$f" 2>>"$LOG_FILE" || true
    fi
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
  if systemctl restart "$svc" >>"$LOG_FILE" 2>&1; then
    log "已重启 $svc（使 /etc/default、/etc/sysconfig 或 systemd drop-in 中的 textfile 等参数生效）"
  else
    warn "重启 $svc 以应用 textfile 目录失败，请手动检查: systemctl status $svc"
  fi
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
# Prometheus textfile collector：宝塔栈 + nginx stub_status + nginx-module-vts Prometheus（由 exporter.sh 部署）
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

# set -u 时 Bash 4.2 等对空数组 "${_mextra[@]}" 会报错；用长度判断再展开
_mysqladmin_x() {
  if [[ ${#_mextra[@]} -gt 0 ]]; then
    "$_madmin" "${_mextra[@]}" "$@"
  else
    "$_madmin" "$@"
  fi
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
  echo "# HELP shellstack_nginx_workers_total Nginx worker 进程数（负载侧写）"
  echo "# TYPE shellstack_nginx_workers_total gauge"
  echo "# HELP shellstack_nginx_stub_accepts_total stub_status accepts（累计）"
  echo "# TYPE shellstack_nginx_stub_accepts_total counter"
  echo "# HELP shellstack_nginx_stub_handled_total stub_status handled（累计）"
  echo "# TYPE shellstack_nginx_stub_handled_total counter"
  echo "# HELP shellstack_nginx_stub_requests_total stub_status requests（累计）"
  echo "# TYPE shellstack_nginx_stub_requests_total counter"
  echo "# HELP shellstack_nginx_vts_scrape_ok nginx-module-vts /format/prometheus 是否抓取成功（1/0）；模块指标见同文件 nginx_vts_*"
  echo "# TYPE shellstack_nginx_vts_scrape_ok gauge"
  echo "# HELP shellstack_php_fpm_workers_total 各版本 PHP-FPM pool 进程数"
  echo "# TYPE shellstack_php_fpm_workers_total gauge"
  echo "# HELP shellstack_redis_ping_ok redis-cli PING 是否成功（1/0）"
  echo "# TYPE shellstack_redis_ping_ok gauge"
  echo "# HELP shellstack_redis_used_memory_bytes Redis used_memory"
  echo "# TYPE shellstack_redis_used_memory_bytes gauge"
  echo "# HELP shellstack_redis_connected_clients Redis connected_clients"
  echo "# TYPE shellstack_redis_connected_clients gauge"
  echo "# HELP shellstack_redis_instantaneous_ops_per_sec Redis ops/s"
  echo "# TYPE shellstack_redis_instantaneous_ops_per_sec gauge"
  echo "# HELP shellstack_mysql_extstatus_ok mysqladmin extended-status 是否成功（1/0）"
  echo "# TYPE shellstack_mysql_extstatus_ok gauge"
  echo "# HELP shellstack_mysql_threads_connected 全局 Threads_connected"
  echo "# TYPE shellstack_mysql_threads_connected gauge"
  echo "# HELP shellstack_mysql_threads_running 全局 Threads_running"
  echo "# TYPE shellstack_mysql_threads_running gauge"
  echo "# HELP shellstack_mysql_queries_total 全局 Queries（累计）"
  echo "# TYPE shellstack_mysql_queries_total counter"
  echo "# HELP shellstack_mysql_uptime_seconds 全局 Uptime（秒）"
  echo "# TYPE shellstack_mysql_uptime_seconds gauge"
  echo "# HELP shellstack_host_load1 1 分钟负载（与 node_load1 同源类数据；摘要）"
  echo "# TYPE shellstack_host_load1 gauge"
  echo "# HELP shellstack_host_load5 5 分钟负载"
  echo "# TYPE shellstack_host_load5 gauge"
  echo "# HELP shellstack_host_load15 15 分钟负载"
  echo "# TYPE shellstack_host_load15 gauge"
  echo "# HELP shellstack_host_memory_total_bytes /proc/meminfo MemTotal"
  echo "# TYPE shellstack_host_memory_total_bytes gauge"
  echo "# HELP shellstack_host_memory_avail_bytes MemAvailable 或回退 MemFree"
  echo "# TYPE shellstack_host_memory_avail_bytes gauge"
  echo "# HELP shellstack_host_memory_used_ratio 估算 (total-avail)/total，0~1"
  echo "# TYPE shellstack_host_memory_used_ratio gauge"
  echo "# HELP shellstack_host_cpu_usage_ratio 约 0.25s 采样 CPU 非 idle 占比，0~1（细粒度见 node_cpu_seconds_total）"
  echo "# TYPE shellstack_host_cpu_usage_ratio gauge"
  echo "# HELP shellstack_host_cpu_iowait_ratio 同上采样 iowait 占比，0~1"
  echo "# TYPE shellstack_host_cpu_iowait_ratio gauge"
  echo "# HELP shellstack_host_root_filesystem_total_bytes 根挂载总空间（df -B1 /）"
  echo "# TYPE shellstack_host_root_filesystem_total_bytes gauge"
  echo "# HELP shellstack_host_root_filesystem_avail_bytes 根挂载可用"
  echo "# TYPE shellstack_host_root_filesystem_avail_bytes gauge"
  echo "# HELP shellstack_host_root_filesystem_used_ratio 已用/总，0~1"
  echo "# TYPE shellstack_host_root_filesystem_used_ratio gauge"
  echo "# HELP shellstack_host_disk_read_bytes_per_second 整盘扇区读字节/秒（较 node_disk_* 粗；排除 loop/ram，按整块设备名聚合）"
  echo "# TYPE shellstack_host_disk_read_bytes_per_second gauge"
  echo "# HELP shellstack_host_disk_write_bytes_per_second 整盘扇区写字节/秒"
  echo "# TYPE shellstack_host_disk_write_bytes_per_second gauge"
  echo "# HELP shellstack_host_network_receive_bytes_total 网卡累计收字节（下载）；与 node_network_receive_bytes_total 同语义，便于 textfile 内直接 rate()"
  echo "# TYPE shellstack_host_network_receive_bytes_total counter"
  echo "# HELP shellstack_host_network_transmit_bytes_total 网卡累计发字节（上传）"
  echo "# TYPE shellstack_host_network_transmit_bytes_total counter"
  echo "# HELP shellstack_host_network_receive_bytes_per_second 非 lo 收字节/秒（多网卡合计，由两次采集差分）"
  echo "# TYPE shellstack_host_network_receive_bytes_per_second gauge"
  echo "# HELP shellstack_host_network_transmit_bytes_per_second 非 lo 发字节/秒（合计）"
  echo "# TYPE shellstack_host_network_transmit_bytes_per_second gauge"

  if [[ -d /www/server/panel ]]; then
    echo "shellstack_baota_paths_detected 1"
  else
    echo "shellstack_baota_paths_detected 0"
  fi
  echo "shellstack_exporter_textfile_info 1"

  # 主机层摘要（与 node_exporter 的 node_* 互补；设 SHELLSTACK_TEXTFILE_SKIP_HOST_METRICS=1 可关闭）
  if [[ "${SHELLSTACK_TEXTFILE_SKIP_HOST_METRICS:-}" != "1" ]]; then
    if [[ -r /proc/loadavg ]]; then
      read -r _hl1 _hl5 _hl15 _rest < /proc/loadavg
      echo "shellstack_host_load1 ${_hl1:-0}"
      echo "shellstack_host_load5 ${_hl5:-0}"
      echo "shellstack_host_load15 ${_hl15:-0}"
    else
      echo "shellstack_host_load1 0"
      echo "shellstack_host_load5 0"
      echo "shellstack_host_load15 0"
    fi
    _mt=0
    _ma=0
    if [[ -r /proc/meminfo ]]; then
      _mt="$(awk '/^MemTotal:/ {gsub(/kB/,"",$2); print $2*1024; exit}' /proc/meminfo)"
      _ma="$(awk '/^MemAvailable:/ {gsub(/kB/,"",$2); print $2*1024; exit}' /proc/meminfo)"
      if [[ -z "$_ma" || "$_ma" == "0" ]]; then
        _ma="$(awk '/^MemFree:/{gsub(/kB/,"",$2);f=$2} /^Buffers:/{gsub(/kB/,"",$2);b=$2} /^Cached:/{gsub(/kB/,"",$2);c=$2} END{print (f+0+b+0+c+0)*1024}' /proc/meminfo)"
      fi
    fi
    [[ "$_mt" =~ ^[0-9]+$ ]] || _mt=0
    [[ "$_ma" =~ ^[0-9]+$ ]] || _ma=0
    echo "shellstack_host_memory_total_bytes ${_mt}"
    echo "shellstack_host_memory_avail_bytes ${_ma}"
    if [[ "$_mt" -gt 0 ]]; then
      awk -v t="$_mt" -v a="$_ma" 'BEGIN { printf "shellstack_host_memory_used_ratio %.6f\n", (t-a)/t }'
    else
      echo "shellstack_host_memory_used_ratio 0"
    fi
    if [[ -r /proc/stat ]]; then
      read -r _id1 _io1 _tt1 <<<"$(awk '/^cpu / { t=0; for(i=2;i<=8;i++) t+=$i; print $5, $6, t; exit}' /proc/stat)"
      sleep 0.25
      read -r _id2 _io2 _tt2 <<<"$(awk '/^cpu / { t=0; for(i=2;i<=8;i++) t+=$i; print $5, $6, t; exit}' /proc/stat)"
    else
      _id1=0
      _io1=0
      _tt1=0
      _id2=0
      _io2=0
      _tt2=0
    fi
    if [[ "${_tt2:-0}" -gt "${_tt1:-0}" ]]; then
      _dtt=$((_tt2 - _tt1))
      _did=$((_id2 - _id1))
      _dio=$((_io2 - _io1))
      awk -v dtt="$_dtt" -v did="$_did" -v dio="$_dio" 'BEGIN {
        if (dtt <= 0) { print "shellstack_host_cpu_usage_ratio 0"; print "shellstack_host_cpu_iowait_ratio 0"; exit }
        printf "shellstack_host_cpu_usage_ratio %.6f\n", (dtt - did - dio) / dtt
        printf "shellstack_host_cpu_iowait_ratio %.6f\n", dio / dtt
      }'
    else
      echo "shellstack_host_cpu_usage_ratio 0"
      echo "shellstack_host_cpu_iowait_ratio 0"
    fi
    _fsz=0
    _fav=0
    _fus=0
    if _dfout="$(df -B1 / 2>/dev/null | awk 'END {print $2, $3, $4}')"; then
      read -r _fsz _fus _fav <<<"$_dfout"
    fi
    [[ "$_fsz" =~ ^[0-9]+$ ]] || _fsz=0
    [[ "$_fav" =~ ^[0-9]+$ ]] || _fav=0
    [[ "$_fus" =~ ^[0-9]+$ ]] || _fus=0
    echo "shellstack_host_root_filesystem_total_bytes ${_fsz}"
    echo "shellstack_host_root_filesystem_avail_bytes ${_fav}"
    if [[ "$_fsz" -gt 0 ]]; then
      awk -v u="$_fus" -v t="$_fsz" 'BEGIN { printf "shellstack_host_root_filesystem_used_ratio %.6f\n", u/t }'
    else
      echo "shellstack_host_root_filesystem_used_ratio 0"
    fi
    _host_whole_disk() {
      [[ "$1" =~ ^sd[a-z]$ ]] && return 0
      [[ "$1" =~ ^vd[a-z]$ ]] && return 0
      [[ "$1" =~ ^xvd[a-z]$ ]] && return 0
      [[ "$1" =~ ^nvme[0-9]+n[0-9]+$ ]] && return 0
      [[ "$1" =~ ^mmcblk[0-9]+$ ]] && return 0
      return 1
    }
    _dsr=0
    _dsw=0
    if [[ -r /proc/diskstats ]]; then
      while read -r _maj _min _dname _r1 _r2 _rsect _ru _w1 _w2 _wsect _wu _; do
        [[ "$_dname" =~ ^(loop|ram) ]] && continue
        _host_whole_disk "$_dname" || continue
        [[ "$_rsect" =~ ^[0-9]+$ ]] && _dsr=$((_dsr + _rsect))
        [[ "$_wsect" =~ ^[0-9]+$ ]] && _dsw=$((_dsw + _wsect))
      done < /proc/diskstats
    fi
    _nrx=0
    _ntx=0
    _host_net_label_esc() {
      local s="$1"
      s="${s//\\/\\\\}"
      s="${s//\"/\\\"}"
      printf '%s' "$s"
    }
    if [[ -r /proc/net/dev ]]; then
      while IFS= read -r _nl; do
        [[ "$_nl" =~ ^[[:space:]]*([^[:space:]:]+):[[:space:]]*(.*)$ ]] || continue
        _ndev="${BASH_REMATCH[1]}"
        _nrest="${BASH_REMATCH[2]}"
        [[ "$_ndev" == "lo" ]] && continue
        read -r _nbrx _np1 _np2 _np3 _np4 _np5 _np6 _np7 _nbtx _ <<< "$_nrest"
        [[ "$_nbrx" =~ ^[0-9]+$ ]] || continue
        [[ "$_nbtx" =~ ^[0-9]+$ ]] || continue
        _nrx=$((_nrx + _nbrx))
        _ntx=$((_ntx + _nbtx))
        _nde="$(_host_net_label_esc "$_ndev")"
        printf 'shellstack_host_network_receive_bytes_total{device="%s"} %s\n' "$_nde" "$_nbrx"
        printf 'shellstack_host_network_transmit_bytes_total{device="%s"} %s\n' "$_nde" "$_nbtx"
      done < /proc/net/dev
    fi
    [[ "$_nrx" =~ ^[0-9]+$ ]] || _nrx=0
    [[ "$_ntx" =~ ^[0-9]+$ ]] || _ntx=0
    _hnow="$(date +%s)"
    _hstate="$DIR/.shellstack_host_prev_netdisk"
    _drbps=0
    _dwbps=0
    _nrbps=0
    _ntbps=0
    if [[ -f "$_hstate" ]]; then
      read -r _hts _hnrx _hntx _hdsr _hdsw < "$_hstate"
      if [[ "$_hts" =~ ^[0-9]+$ ]]; then
        _hdt=$((_hnow - _hts))
        [[ "$_hdt" -lt 1 ]] && _hdt=1
        if [[ "$_nrx" -ge "${_hnrx:-0}" && "$_ntx" -ge "${_hntx:-0}" ]]; then
          _nrbps="$(awk -v d=$((_nrx - _hnrx)) -v t="$_hdt" 'BEGIN { if (t>0) printf "%.3f", d/t; else print "0" }')"
          _ntbps="$(awk -v d=$((_ntx - _hntx)) -v t="$_hdt" 'BEGIN { if (t>0) printf "%.3f", d/t; else print "0" }')"
        fi
        if [[ "$_dsr" -ge "${_hdsr:-0}" && "$_dsw" -ge "${_hdsw:-0}" ]]; then
          _drbps="$(awk -v d=$(( (_dsr - _hdsr) * 512 )) -v t="$_hdt" 'BEGIN { if (t>0) printf "%.3f", d/t; else print "0" }')"
          _dwbps="$(awk -v d=$(( (_dsw - _hdsw) * 512 )) -v t="$_hdt" 'BEGIN { if (t>0) printf "%.3f", d/t; else print "0" }')"
        fi
      fi
    fi
    printf '%s %s %s %s %s\n' "$_hnow" "$_nrx" "$_ntx" "$_dsr" "$_dsw" > "${_hstate}.new" 2>/dev/null && mv -f "${_hstate}.new" "$_hstate" 2>/dev/null || true
    echo "shellstack_host_disk_read_bytes_per_second ${_drbps:-0}"
    echo "shellstack_host_disk_write_bytes_per_second ${_dwbps:-0}"
    echo "shellstack_host_network_receive_bytes_per_second ${_nrbps:-0}"
    echo "shellstack_host_network_transmit_bytes_per_second ${_ntbps:-0}"
  else
    echo "shellstack_host_load1 0"
    echo "shellstack_host_load5 0"
    echo "shellstack_host_load15 0"
    echo "shellstack_host_memory_total_bytes 0"
    echo "shellstack_host_memory_avail_bytes 0"
    echo "shellstack_host_memory_used_ratio 0"
    echo "shellstack_host_cpu_usage_ratio 0"
    echo "shellstack_host_cpu_iowait_ratio 0"
    echo "shellstack_host_root_filesystem_total_bytes 0"
    echo "shellstack_host_root_filesystem_avail_bytes 0"
    echo "shellstack_host_root_filesystem_used_ratio 0"
    echo "shellstack_host_disk_read_bytes_per_second 0"
    echo "shellstack_host_disk_write_bytes_per_second 0"
    echo "shellstack_host_network_receive_bytes_per_second 0"
    echo "shellstack_host_network_transmit_bytes_per_second 0"
  fi

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
  _nw=0
  _nw="$(pgrep -cf 'nginx: worker process' 2>/dev/null)" || _nw=0
  [[ "$_nw" =~ ^[0-9]+$ ]] || _nw=0
  echo "shellstack_nginx_workers_total ${_nw:-0}"

  # MySQL / MariaDB
  if systemctl is-active --quiet mysqld 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
    emit_up mysql systemd 1
  elif pgrep -x mysqld >/dev/null 2>&1 || pgrep -x mariadbd >/dev/null 2>&1; then
    emit_up mysql process 1
  else
    emit_up mysql none 0
  fi

  _madmin=""
  for _cand in /www/server/mysql/bin/mysqladmin /www/server/mariadb/bin/mysqladmin /usr/bin/mysqladmin; do
    [[ -x "$_cand" ]] && { _madmin="$_cand"; break; }
  done
  [[ -z "$_madmin" ]] && command -v mysqladmin >/dev/null 2>&1 && _madmin="$(command -v mysqladmin)"
  _mextra=()
  if [[ -n "${SHELLSTACK_MYSQL_DEFAULTS_FILE:-}" && -f "${SHELLSTACK_MYSQL_DEFAULTS_FILE}" ]]; then
    _mextra=(--defaults-file="${SHELLSTACK_MYSQL_DEFAULTS_FILE}")
  elif [[ -n "${SHELLSTACK_MYSQL_PASSWORD:-}" ]]; then
    _mextra=(-u"${SHELLSTACK_MYSQL_USER:-root}" --password="${SHELLSTACK_MYSQL_PASSWORD}")
  elif [[ -n "${SHELLSTACK_MYSQL_USER:-}" ]]; then
    _mextra=(-u"${SHELLSTACK_MYSQL_USER}")
  fi
  _msock=""
  for _s in ${SHELLSTACK_MYSQL_SOCKET:-} /tmp/mysql.sock /run/mysqld/mysqld.sock /var/run/mysqld/mysqld.sock /www/server/data/mysql.sock; do
    [[ -z "$_s" ]] && continue
    [[ -S "$_s" ]] || continue
    if [[ -n "$_madmin" ]] && _mysqladmin_x --socket="$_s" --connect-timeout=2 ping >/dev/null 2>&1; then
      _msock="$_s"
      break
    fi
  done
  if [[ -n "$_madmin" && -n "$_msock" ]]; then
    _mst="$(_mysqladmin_x --socket="$_msock" --connect-timeout=2 extended-status 2>/dev/null || true)"
    if [[ -n "$_mst" ]] && echo "$_mst" | grep -qE 'Variable_name|Threads_connected'; then
      echo "shellstack_mysql_extstatus_ok 1"
      _v="$(echo "$_mst" | awk -F'|' 'NF>=3 { gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); if ($2=="Threads_connected") { gsub(/^[[:space:]]+|[[:space:]]+$/,"",$3); print $3+0; exit } }')"
      [[ "$_v" =~ ^[0-9]+$ ]] && echo "shellstack_mysql_threads_connected $_v" || echo "shellstack_mysql_threads_connected 0"
      _v="$(echo "$_mst" | awk -F'|' 'NF>=3 { gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); if ($2=="Threads_running") { gsub(/^[[:space:]]+|[[:space:]]+$/,"",$3); print $3+0; exit } }')"
      [[ "$_v" =~ ^[0-9]+$ ]] && echo "shellstack_mysql_threads_running $_v" || echo "shellstack_mysql_threads_running 0"
      _v="$(echo "$_mst" | awk -F'|' 'NF>=3 { gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); if ($2=="Uptime") { gsub(/^[[:space:]]+|[[:space:]]+$/,"",$3); print $3+0; exit } }')"
      [[ "$_v" =~ ^[0-9]+$ ]] && echo "shellstack_mysql_uptime_seconds $_v" || echo "shellstack_mysql_uptime_seconds 0"
      _v="$(echo "$_mst" | awk -F'|' 'NF>=3 { gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); if ($2=="Queries") { gsub(/^[[:space:]]+|[[:space:]]+$/,"",$3); print $3+0; exit } }')"
      [[ "$_v" =~ ^[0-9]+$ ]] && echo "shellstack_mysql_queries_total $_v" || echo "shellstack_mysql_queries_total 0"
    else
      echo "shellstack_mysql_extstatus_ok 0"
      echo "shellstack_mysql_threads_connected 0"
      echo "shellstack_mysql_threads_running 0"
      echo "shellstack_mysql_uptime_seconds 0"
      echo "shellstack_mysql_queries_total 0"
    fi
  else
    echo "shellstack_mysql_extstatus_ok 0"
    echo "shellstack_mysql_threads_connected 0"
    echo "shellstack_mysql_threads_running 0"
    echo "shellstack_mysql_uptime_seconds 0"
    echo "shellstack_mysql_queries_total 0"
  fi

  # Redis
  if systemctl is-active --quiet redis 2>/dev/null || systemctl is-active --quiet redis-server 2>/dev/null; then
    emit_up redis systemd 1
  elif pgrep -x redis-server >/dev/null 2>&1; then
    emit_up redis process 1
  else
    emit_up redis none 0
  fi

  _rcli=""
  for _cand in /www/server/redis/src/redis-cli /www/server/redis/redis-cli; do
    [[ -x "$_cand" ]] && { _rcli="$_cand"; break; }
  done
  [[ -z "$_rcli" ]] && command -v redis-cli >/dev/null 2>&1 && _rcli="$(command -v redis-cli)"
  if [[ -n "$_rcli" ]]; then
    _inf=""
    if [[ -n "${SHELLSTACK_REDIS_SOCKET:-}" ]]; then
      if "$_rcli" -s "${SHELLSTACK_REDIS_SOCKET}" ping >/dev/null 2>&1; then
        echo "shellstack_redis_ping_ok 1"
        _inf="$("$_rcli" -s "${SHELLSTACK_REDIS_SOCKET}" INFO 2>/dev/null || true)"
      else
        echo "shellstack_redis_ping_ok 0"
      fi
    elif [[ -n "${SHELLSTACK_REDIS_HOST:-}" ]]; then
      if "$_rcli" -h "${SHELLSTACK_REDIS_HOST}" -p "${SHELLSTACK_REDIS_PORT:-6379}" ping >/dev/null 2>&1; then
        echo "shellstack_redis_ping_ok 1"
        _inf="$("$_rcli" -h "${SHELLSTACK_REDIS_HOST}" -p "${SHELLSTACK_REDIS_PORT:-6379}" INFO 2>/dev/null || true)"
      else
        echo "shellstack_redis_ping_ok 0"
      fi
    else
      if "$_rcli" ping >/dev/null 2>&1; then
        echo "shellstack_redis_ping_ok 1"
        _inf="$("$_rcli" INFO 2>/dev/null || true)"
      elif [[ -S /tmp/redis.sock ]] && "$_rcli" -s /tmp/redis.sock ping >/dev/null 2>&1; then
        echo "shellstack_redis_ping_ok 1"
        _inf="$("$_rcli" -s /tmp/redis.sock INFO 2>/dev/null || true)"
      elif [[ -S /www/server/redis/redis.sock ]] && "$_rcli" -s /www/server/redis/redis.sock ping >/dev/null 2>&1; then
        echo "shellstack_redis_ping_ok 1"
        _inf="$("$_rcli" -s /www/server/redis/redis.sock INFO 2>/dev/null || true)"
      elif [[ -S /www/server/redis/run/redis.sock ]] && "$_rcli" -s /www/server/redis/run/redis.sock ping >/dev/null 2>&1; then
        echo "shellstack_redis_ping_ok 1"
        _inf="$("$_rcli" -s /www/server/redis/run/redis.sock INFO 2>/dev/null || true)"
      else
        echo "shellstack_redis_ping_ok 0"
      fi
    fi
    if [[ -n "$_inf" ]]; then
      _v="$(echo "$_inf" | awk -F: 'tolower($1)=="used_memory" {gsub(/\r/,"",$2); print $2+0; exit}')"
      [[ "$_v" =~ ^[0-9]+$ ]] && echo "shellstack_redis_used_memory_bytes $_v" || echo "shellstack_redis_used_memory_bytes 0"
      _v="$(echo "$_inf" | awk -F: 'tolower($1)=="connected_clients" {gsub(/\r/,"",$2); print $2+0; exit}')"
      [[ "$_v" =~ ^[0-9]+$ ]] && echo "shellstack_redis_connected_clients $_v" || echo "shellstack_redis_connected_clients 0"
      _v="$(echo "$_inf" | awk -F: 'tolower($1)=="instantaneous_ops_per_sec" {gsub(/\r/,"",$2); print $2+0; exit}')"
      [[ "$_v" =~ ^[0-9]+$ ]] && echo "shellstack_redis_instantaneous_ops_per_sec $_v" || echo "shellstack_redis_instantaneous_ops_per_sec 0"
    else
      echo "shellstack_redis_used_memory_bytes 0"
      echo "shellstack_redis_connected_clients 0"
      echo "shellstack_redis_instantaneous_ops_per_sec 0"
    fi
  else
    echo "shellstack_redis_ping_ok 0"
    echo "shellstack_redis_used_memory_bytes 0"
    echo "shellstack_redis_connected_clients 0"
    echo "shellstack_redis_instantaneous_ops_per_sec 0"
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
          _pc=0
          _pc="$(pgrep -af 'php-fpm: pool' 2>/dev/null | grep -cF "/www/server/php/${ver}/" || true)"
          [[ "$_pc" =~ ^[0-9]+$ ]] || _pc=0
          printf 'shellstack_php_fpm_workers_total{version="%s"} %s\n' "$ver" "$_pc"
        else
          printf 'shellstack_php_fpm_up{version="%s"} 0\n' "$ver"
          printf 'shellstack_php_fpm_workers_total{version="%s"} 0\n' "$ver"
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
      if echo "$body" | grep -q 'server accepts handled requests'; then
        _al="$(echo "$body" | awk '/server accepts handled requests/{getline; print; exit}')"
        _a1="$(echo "$_al" | awk '{print $1}')"
        _a2="$(echo "$_al" | awk '{print $2}')"
        _a3="$(echo "$_al" | awk '{print $3}')"
        [[ "$_a1" =~ ^[0-9]+$ ]] && echo "shellstack_nginx_stub_accepts_total $_a1"
        [[ "$_a2" =~ ^[0-9]+$ ]] && echo "shellstack_nginx_stub_handled_total $_a2"
        [[ "$_a3" =~ ^[0-9]+$ ]] && echo "shellstack_nginx_stub_requests_total $_a3"
      else
        echo "shellstack_nginx_stub_accepts_total 0"
        echo "shellstack_nginx_stub_handled_total 0"
        echo "shellstack_nginx_stub_requests_total 0"
      fi
      parsed=1
      break
    fi
  done
  if [[ "$parsed" -eq 0 ]]; then
    echo "shellstack_nginx_stub_active_connections 0"
    echo "shellstack_nginx_stub_reading 0"
    echo "shellstack_nginx_stub_writing 0"
    echo "shellstack_nginx_stub_waiting 0"
    echo "shellstack_nginx_stub_accepts_total 0"
    echo "shellstack_nginx_stub_handled_total 0"
    echo "shellstack_nginx_stub_requests_total 0"
  fi

  # nginx-module-vts：/nginx-vts-status/format/prometheus（与 shellstack_vts.conf 默认端口 8898 一致）
  if [[ "${SHELLSTACK_NGINX_VTS_PROM_DISABLE:-}" == "1" ]]; then
    echo "shellstack_nginx_vts_scrape_ok 0"
  else
    _vts_url="${SHELLSTACK_NGINX_VTS_PROM_URL:-}"
    if [[ -z "$_vts_url" ]]; then
      _vts_url="http://127.0.0.1:${SHELLSTACK_VTS_LISTEN_PORT:-8898}/nginx-vts-status/format/prometheus"
    fi
    _vts_tmp="$(mktemp 2>/dev/null || echo "/tmp/shellstack-vts.$$.prom")"
    if curl -fsS -m 3 "$_vts_url" -o "$_vts_tmp" 2>/dev/null && [[ -s "$_vts_tmp" ]]; then
      echo "shellstack_nginx_vts_scrape_ok 1"
      cat "$_vts_tmp"
    else
      echo "shellstack_nginx_vts_scrape_ok 0"
    fi
    rm -f "$_vts_tmp" 2>/dev/null || true
  fi
} >"$TMP"
mv -f "$TMP" "$OUT"
chmod 644 "$OUT" 2>/dev/null || true
# 指标写入 .prom，成功时原先不写 stdout；cron 重定向到 /var/log/shellstack-node-exporter-textfile.log 会为空。打一行心跳便于确认定时任务在执行。
_ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"
_sz="$(wc -c <"$OUT" 2>/dev/null | tr -d '[:space:]')"
echo "${_ts} shellstack-node-exporter-textfile: OK wrote ${OUT} (${_sz:-0} bytes)"
EOSCRIPT
  chmod 755 "$bin"

  local stub_port inject_url default_urls effective_urls
  stub_port="${SHELLSTACK_NGINX_STUB_LISTEN_PORT:-8899}"
  inject_url="http://127.0.0.1:${stub_port}/nginx_stub_status"
  default_urls="http://127.0.0.1/nginx_status,http://127.0.0.1/stub_status,http://127.0.0.1/nginx_stub_status"
  effective_urls="${SHELLSTACK_NGINX_STUB_URLS:-$default_urls}"

  if ! _exporter_nginx_stub_urls_probe_ok "$effective_urls"; then
    if [[ "${SHELLSTACK_NGINX_STUB_INJECT:-1}" != "0" ]]; then
      if _exporter_baota_nginx_installed; then
        log "未探测到可用 stub_status，尝试写入 shellstack_status.conf 并在 nginx.conf 中 include（127.0.0.1:${stub_port}）..."
        if _exporter_inject_baota_nginx_stub_status "$stub_port"; then
          effective_urls="${inject_url},${effective_urls}"
        else
          warn "stub 自动注入未成功，shellstack_nginx_stub_* 可能为 0（可手动配置 stub 或设 SHELLSTACK_NGINX_STUB_URLS）"
        fi
      elif [[ -d /www/server/panel ]]; then
        log "已检测到宝塔面板目录，但尚未安装或未就绪 Nginx（无 /www/server/nginx/sbin/nginx 与 conf/nginx.conf），跳过 stub 注入"
      fi
    fi
  fi

  local cronf="/etc/cron.d/shellstack-node-exporter-textfile"
  local tlog="/var/log/shellstack-node-exporter-textfile.log"
  touch "$tlog" 2>/dev/null || tlog="/tmp/shellstack-node-exporter-textfile.log"
  touch "$tlog" 2>/dev/null || true
  chmod 0644 "$tlog" 2>/dev/null || true
  local _mysql_cron=""
  if [[ -n "${SHELLSTACK_MYSQL_DEFAULTS_FILE:-}" ]]; then
    _mysql_cron+=" SHELLSTACK_MYSQL_DEFAULTS_FILE=$(printf '%q' "${SHELLSTACK_MYSQL_DEFAULTS_FILE}")"
  fi
  if [[ -n "${SHELLSTACK_MYSQL_USER:-}" ]]; then
    _mysql_cron+=" SHELLSTACK_MYSQL_USER=$(printf '%q' "${SHELLSTACK_MYSQL_USER}")"
  fi
  if [[ -n "${SHELLSTACK_MYSQL_PASSWORD:-}" ]]; then
    _mysql_cron+=" SHELLSTACK_MYSQL_PASSWORD=$(printf '%q' "${SHELLSTACK_MYSQL_PASSWORD}")"
  fi
  if [[ -n "${SHELLSTACK_MYSQL_SOCKET:-}" ]]; then
    _mysql_cron+=" SHELLSTACK_MYSQL_SOCKET=$(printf '%q' "${SHELLSTACK_MYSQL_SOCKET}")"
  fi
  local _vts_cron=""
  if [[ -n "${SHELLSTACK_NGINX_VTS_PROM_URL:-}" ]]; then
    _vts_cron+=" SHELLSTACK_NGINX_VTS_PROM_URL=$(printf '%q' "${SHELLSTACK_NGINX_VTS_PROM_URL}")"
  fi
  if [[ -n "${SHELLSTACK_VTS_LISTEN_PORT:-}" ]]; then
    _vts_cron+=" SHELLSTACK_VTS_LISTEN_PORT=$(printf '%q' "${SHELLSTACK_VTS_LISTEN_PORT}")"
  fi
  if [[ "${SHELLSTACK_NGINX_VTS_PROM_DISABLE:-}" == "1" ]]; then
    _vts_cron+=" SHELLSTACK_NGINX_VTS_PROM_DISABLE=1"
  fi
  cat >"$cronf" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
* * * * * root TEXTFILE_DIR=$dir SHELLSTACK_NGINX_STUB_URLS=$effective_urls${_mysql_cron}${_vts_cron} $bin >>$tlog 2>&1
EOF
  chmod 644 "$cronf" 2>/dev/null || true

  # 首次执行原只写入 LOG_FILE，用户查看 $tlog 会误以为未运行；同时 tee 到 $tlog（与 cron 同一文件）
  if [[ -n "${LOG_FILE:-}" ]]; then
    TEXTFILE_DIR="$dir" SHELLSTACK_NGINX_STUB_URLS="$effective_urls" \
      SHELLSTACK_MYSQL_DEFAULTS_FILE="${SHELLSTACK_MYSQL_DEFAULTS_FILE:-}" \
      SHELLSTACK_MYSQL_USER="${SHELLSTACK_MYSQL_USER:-}" \
      SHELLSTACK_MYSQL_PASSWORD="${SHELLSTACK_MYSQL_PASSWORD:-}" \
      SHELLSTACK_MYSQL_SOCKET="${SHELLSTACK_MYSQL_SOCKET:-}" \
      SHELLSTACK_NGINX_VTS_PROM_URL="${SHELLSTACK_NGINX_VTS_PROM_URL:-}" \
      SHELLSTACK_VTS_LISTEN_PORT="${SHELLSTACK_VTS_LISTEN_PORT:-}" \
      SHELLSTACK_NGINX_VTS_PROM_DISABLE="${SHELLSTACK_NGINX_VTS_PROM_DISABLE:-}" \
      bash "$bin" 2>&1 | tee -a "$LOG_FILE" "$tlog"
  else
    TEXTFILE_DIR="$dir" SHELLSTACK_NGINX_STUB_URLS="$effective_urls" \
      SHELLSTACK_MYSQL_DEFAULTS_FILE="${SHELLSTACK_MYSQL_DEFAULTS_FILE:-}" \
      SHELLSTACK_MYSQL_USER="${SHELLSTACK_MYSQL_USER:-}" \
      SHELLSTACK_MYSQL_PASSWORD="${SHELLSTACK_MYSQL_PASSWORD:-}" \
      SHELLSTACK_MYSQL_SOCKET="${SHELLSTACK_MYSQL_SOCKET:-}" \
      SHELLSTACK_NGINX_VTS_PROM_URL="${SHELLSTACK_NGINX_VTS_PROM_URL:-}" \
      SHELLSTACK_VTS_LISTEN_PORT="${SHELLSTACK_VTS_LISTEN_PORT:-}" \
      SHELLSTACK_NGINX_VTS_PROM_DISABLE="${SHELLSTACK_NGINX_VTS_PROM_DISABLE:-}" \
      bash "$bin" 2>&1 | tee -a "$tlog"
  fi
  [[ "${PIPESTATUS[0]:-0}" -ne 0 ]] && warn "首次执行 textfile 采集脚本失败（退出码 ${PIPESTATUS[0]}）"
  {
    echo "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date) shellstack-exporter: textfile 首次执行结束（上方若有采集脚本输出亦已记入本文件）；此后依赖 cron 每分钟写入"
  } >>"$tlog" 2>/dev/null || true
  log "已部署宝塔/服务 textfile 采集: $bin → $dir/shellstack_baota.prom（cron: $cronf）"
  log "stub_status 探测 URL 列表（cron 已写入）: $effective_urls"
  log "nginx-module-vts：textfile 每分钟附加同 URL 的 Prometheus 指标（默认 127.0.0.1:8898/nginx-vts-status/format/prometheus；SHELLSTACK_NGINX_VTS_PROM_URL / SHELLSTACK_VTS_LISTEN_PORT 可覆盖，部署时 export 可写入 cron）"
  log "textfile 本次运行的终端输出已写入 $tlog（与 cron 共用）；之后每分钟由 cron 追加一行（请确保已启用: systemctl enable --now cron）"
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q '^cron\.service'; then
    systemctl is-active --quiet cron 2>/dev/null || warn "cron 服务未运行，textfile 不会每分钟执行；请执行: systemctl enable --now cron（Debian/Ubuntu 包名通常为 cron）"
  fi
  if [[ "${SHELLSTACK_EXPORTER_FORCE:-}" == "1" ]]; then
    log "--force：已覆盖 $bin 与 $cronf；若本机已安装 node_exporter 服务，上方应有「已重启 … 使 textfile 生效」类日志"
  fi
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

# 注册 Consul 时探测栈服务，写入 Meta（**仅注册瞬间快照**；实时指标见 Prometheus shellstack_*）
_exporter_stack_service_meta_probes() {
  local n m r b phpstub phplist _pd _pv
  n=0
  if [[ -x /www/server/nginx/sbin/nginx ]]; then
    if pgrep -x nginx >/dev/null 2>&1 || pgrep -f '/www/server/nginx/sbin/nginx' >/dev/null 2>&1; then
      n=1
    fi
  elif systemctl is-active --quiet nginx 2>/dev/null; then
    n=1
  else
    pgrep -x nginx >/dev/null 2>&1 && n=1
  fi
  m=0
  if systemctl is-active --quiet mysqld 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
    m=1
  elif pgrep -x mysqld >/dev/null 2>&1 || pgrep -x mariadbd >/dev/null 2>&1; then
    m=1
  fi
  r=0
  if systemctl is-active --quiet redis 2>/dev/null || systemctl is-active --quiet redis-server 2>/dev/null; then
    r=1
  elif pgrep -x redis-server >/dev/null 2>&1; then
    r=1
  fi
  b=0
  if pgrep -f 'BT-Panel' >/dev/null 2>&1 || pgrep -f '/www/server/panel/BT-Panel' >/dev/null 2>&1; then
    b=1
  fi
  phplist=""
  if [[ -d /www/server/php ]]; then
    for _pd in /www/server/php/*/; do
      [[ -d "$_pd" ]] || continue
      _pv="$(basename "$_pd")"
      if pgrep -af 'php-fpm: master process' 2>/dev/null | grep -qF "/www/server/php/${_pv}/"; then
        phplist+="${_pv}+"
      fi
    done
    phplist="${phplist%+}"
  fi
  [[ ${#phplist} -gt 100 ]] && phplist="${phplist:0:97}..."
  phpstub=0
  local _su
  local _stubp="${SHELLSTACK_NGINX_STUB_LISTEN_PORT:-8899}"
  for _su in "http://127.0.0.1:${_stubp}/nginx_stub_status" http://127.0.0.1/nginx_status http://127.0.0.1/stub_status; do
    if curl -fsS -m 1 "$_su" 2>/dev/null | grep -q 'Active connections'; then
      phpstub=1
      break
    fi
  done
  _exporter_meta_kv svc_nginx_up "$n"
  _exporter_meta_kv svc_mysql_up "$m"
  _exporter_meta_kv svc_redis_up "$r"
  _exporter_meta_kv svc_baota_panel_up "$b"
  _exporter_meta_kv svc_php_fpm_masters_up "$phplist"
  _exporter_meta_kv svc_nginx_stub_reachable "$phpstub"
}

_exporter_consul_service_meta_json() {
  local bind_addr="$1" port="$2" tdir="${3:-}"
  local hn geo pip os_pretty bt tsize texist seen pair k v

  hn="$(hostname 2>/dev/null || echo unknown)"
  geo=""
  pip=""
  _hnu="$(printf '%s' "$hn" | tr '[:lower:]' '[:upper:]')"
  if [[ "$_hnu" =~ ^([A-Z]{2})-([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})$ ]]; then
    geo="${BASH_REMATCH[1]}"
    pip="${BASH_REMATCH[2]}"
  elif [[ "$_hnu" =~ ^([A-Z]{2})-([0-9]{1,3})-([0-9]{1,3})-([0-9]{1,3})-([0-9]{1,3})$ ]]; then
    geo="${BASH_REMATCH[1]}"
    pip="${BASH_REMATCH[2]}.${BASH_REMATCH[3]}.${BASH_REMATCH[4]}.${BASH_REMATCH[5]}"
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
  _exporter_meta_kv meta_snapshot_note "register-time; live=Prometheus shellstack_*"

  _exporter_stack_service_meta_probes

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
    warn "进程参数中未检测到 --collector.textfile.directory，shellstack_* 可能不会出现在 /metrics；请检查 Debian/Ubuntu: /etc/default/prometheus-node-exporter；RHEL/CentOS: /etc/sysconfig/node_exporter 或 /etc/default/node_exporter；并 systemctl cat prometheus-node-exporter / node_exporter"
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
