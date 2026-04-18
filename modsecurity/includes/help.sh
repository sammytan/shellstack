#!/bin/bash

# =====================================================================
# 帮助和信息查看功能
# 包含 verify_install, cleanup, show_info 等函数
# =====================================================================

# 验证安装
verify_install() {
  log "验证 ModSecurity 安装..."

  local lib_file=""
  if [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so.3" ]; then
    lib_file="$MODSECURITY_PREFIX/lib/libmodsecurity.so.3"
  elif [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so" ]; then
    lib_file="$MODSECURITY_PREFIX/lib/libmodsecurity.so"
  fi

  if [ -z "$lib_file" ]; then
    error "安装失败: 核心库不存在 ($MODSECURITY_PREFIX/lib/libmodsecurity.so*)"
  fi

  log "找到库文件: $lib_file"

  # 检查依赖库
  log "检查依赖库..."
  local missing_deps=()
  
  for dep in libpcre libxml2 libcurl libyajl liblua libmaxminddb; do
    if ! ldd "$lib_file" 2>/dev/null | grep -q "$dep"; then
      missing_deps+=("$dep")
    fi
  done

  if [ ${#missing_deps[@]} -gt 0 ]; then
    warn "以下依赖库未链接: ${missing_deps[*]}"
  else
    log "所有依赖库已正确链接"
  fi

  # 检查 GeoIP/MaxMindDB 支持
  if ldd "$lib_file" 2>/dev/null | grep -q "libGeoIP\|libmaxminddb"; then
    log "✓ GeoIP/MaxMindDB 支持已启用"
  else
    warn "GeoIP/MaxMindDB 支持未启用"
  fi

  # 检查 curl 支持
  if ldd "$lib_file" 2>/dev/null | grep -q "libcurl"; then
    log "✓ CURL 支持已启用"
  else
    warn "CURL 支持未启用"
  fi

  # 检查头文件
  if [ -d "$MODSECURITY_PREFIX/include/modsecurity" ]; then
    log "✓ 头文件已正确安装"
  else
    warn "头文件可能未正确安装"
  fi

  # 检查 pkg-config
  if pkg-config --exists libmodsecurity 2>/dev/null; then
    local installed_version=$(pkg-config --modversion libmodsecurity 2>/dev/null)
    log "✓ ModSecurity 版本: $installed_version"
  fi

  log "ModSecurity 安装验证完成"
}

# 清理临时文件
cleanup() {
  log "清理临时文件..."
  
  if [ -d "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR"
    log "已清理构建目录: $BUILD_DIR"
  fi

  log "清理完成"
}

# 显示安装信息
show_info() {
  echo
  log "=========================================="
  log "ModSecurity 安装信息"
  log "=========================================="
  echo
  log "安装目录: $MODSECURITY_PREFIX"
  
  # 库文件信息
  local lib_file=""
  if [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so.3" ]; then
    lib_file="$MODSECURITY_PREFIX/lib/libmodsecurity.so.3"
  elif [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so" ]; then
    lib_file="$MODSECURITY_PREFIX/lib/libmodsecurity.so"
  fi
  
  if [ -n "$lib_file" ]; then
    log "库文件: $lib_file"
    if command -v ldd >/dev/null 2>&1; then
      local file_size=$(ls -lh "$lib_file" 2>/dev/null | awk '{print $5}')
      log "库文件大小: $file_size"
    fi
  else
    warn "未找到库文件"
  fi

  # 头文件信息
  if [ -d "$MODSECURITY_PREFIX/include/modsecurity" ]; then
    log "头文件目录: $MODSECURITY_PREFIX/include/modsecurity"
    local header_count=$(find "$MODSECURITY_PREFIX/include/modsecurity" -name "*.h" 2>/dev/null | wc -l)
    log "头文件数量: $header_count"
  else
    warn "未找到头文件目录"
  fi

  # pkg-config 信息
  if pkg-config --exists libmodsecurity 2>/dev/null; then
    local installed_version=$(pkg-config --modversion libmodsecurity 2>/dev/null)
    local cflags=$(pkg-config --cflags libmodsecurity 2>/dev/null)
    local libs=$(pkg-config --libs libmodsecurity 2>/dev/null)
    
    log "版本: $installed_version"
    log "编译选项: $cflags"
    log "链接选项: $libs"
  fi

  # GeoIP 信息（默认目录可自动创建；未启用 --enable-geoip 时不告警）
  echo
  log "GeoIP 信息:"
  GEOIP_DIR="${GEOIP_DIR:-/usr/local/share/GeoIP}"
  if ! mkdir -p "$GEOIP_DIR" 2>/dev/null; then
    warn "无法创建 GeoIP 目录: $GEOIP_DIR"
  else
    log "数据库目录: $GEOIP_DIR"
    local db_files
    db_files=$(find "$GEOIP_DIR" -name "*.mmdb" 2>/dev/null | wc -l | tr -d '[:space:]')
    db_files=${db_files:-0}
    log "数据库文件数量: $db_files"

    if [ "$db_files" -gt 0 ]; then
      if [ -f "${GEOIP_DIR}/dbip-country-lite.mmdb" ]; then
        local db_size=$(ls -lh "${GEOIP_DIR}/dbip-country-lite.mmdb" 2>/dev/null | awk '{print $5}')
        local db_date=$(stat -c %y "${GEOIP_DIR}/dbip-country-lite.mmdb" 2>/dev/null | cut -d' ' -f1 || stat -f "%Sm" -t "%Y-%m-%d" "${GEOIP_DIR}/dbip-country-lite.mmdb" 2>/dev/null || echo "未知")
        log "  - DB-IP Lite: dbip-country-lite.mmdb ($db_size, 更新日期: $db_date)"
      fi
      find "$GEOIP_DIR" -name "GeoLite2-*.mmdb" 2>/dev/null | while read -r db_file; do
        local db_size=$(ls -lh "$db_file" 2>/dev/null | awk '{print $5}')
        local db_date=$(stat -c %y "$db_file" 2>/dev/null | cut -d' ' -f1 || stat -f "%Sm" -t "%Y-%m-%d" "$db_file" 2>/dev/null || echo "未知")
        log "  - MaxMind: $(basename "$db_file") ($db_size, 更新日期: $db_date)"
      done
    else
      if [ "${ENABLE_GEOIP:-0}" = "1" ]; then
        warn "未找到 GeoIP 数据库文件（.mmdb）"
        log "提示: 检查 GeoIP 安装步骤或手动将 .mmdb 放入 $GEOIP_DIR"
      else
        log "尚未安装 GeoIP 数据库（未使用 --enable-geoip 时可忽略）"
      fi
    fi
  fi

  # 使用示例
  echo
  log "使用示例:"
  echo "  编译时链接库:"
  echo "    gcc your_code.c -L$MODSECURITY_PREFIX/lib -lmodsecurity -I$MODSECURITY_PREFIX/include"
  echo
  echo "  使用 pkg-config:"
  echo "    gcc \$(pkg-config --cflags --libs libmodsecurity) your_code.c"
  echo

  log "日志文件: $LOG_FILE"
  echo
}

# 显示帮助信息
show_help() {
  cat << EOF
ModSecurity 核心库安装脚本
==========================

使用方法:
  $0 [选项]

选项:
  --prefix=PATH          设置 ModSecurity 安装路径 (默认: /usr/local/modsecurity)
  --version=VERSION      设置 ModSecurity 版本 (默认: 3.0.10)
  --enable-geoip         启用 GeoIP 支持 (可选，默认使用 DB-IP Lite)
  --geoip-provider=PROVIDER  设置 GeoIP 提供商: dbip (默认,免费) 或 maxmind (需要API Key)
  --maxmind              使用 MaxMind 作为 GeoIP 提供商
  --dbip                 使用 DB-IP Lite 作为 GeoIP 提供商（默认，免费）
  --enable-security      启用 fail2ban 配置 (fail2ban, SSH 加固)
  --enable-openresty     安装 OpenResty (可选)
  --enable-kernel-opt    启用 Google BBR 内核优化 (默认启用)
  --enable-terminal      启用终端配置 (默认启用)
  --disable-kernel-opt   禁用 Google BBR 内核优化
  --disable-terminal     禁用终端配置
  --jobs=N               设置并行编译任务数 (默认: 自动检测，根据内存和CPU核心数)
  --install-bt           安装宝塔面板（BT11）；若已安装则自动跳过。可与 --force/--deploy-conf 连用
  --extend-btwaf-cache   宝塔：执行面板 btwaf install（已装则跳过）、Redis、再下发扩展 Lua；本地无 btwaf-ext 时从 \$SHELLSTACK_BASE_URL/btwaf-ext/btwaf/ 下载；见 SHELLSTACK_BTWAF_OVERLAY_SRC / SHELLSTACK_BTWAF_CACHE_LUA_URL
  --force                **可独立、可组合**：任意多个主参数可与**同一个** --force 写在同一行，**只对已写出的项分别加强**（不自动追加未出现的 --deploy-conf / --bt-openresty / --extend-btwaf-cache）。也可**只**写单一主参数 + --force，或**仅**裸 --force。概要：--bt-openresty --force → MODSECURITY_FORCE_BT_NGINX_REBUILD 等；--deploy-conf --force → 刷新 nginx http 注入块（未同时 --bt-openresty 时不强制 Nginx 重编）；仅 --extend-btwaf-cache --force 不重编 Nginx；--version / --prefix + --force → 已安装 libmodsecurity 时跳过 [y/N] 直接重编。**命令行仅有** --force（及如 --disable-* 等未触发主流程的选项）时为「一键全套」。**仅** --with-exporter 时 --force 只作用于 exporter
  --with-exporter[=ADDR] 安装 node exporter 并注册 Consul。**ADDR 可省略**（用 exporter 内置 Consul）；**可指定**如 http://10.0.0.1:8500 或 10.0.0.1:8500。写法：--with-exporter=URL、--with-exporter URL、或单独 --with-exporter。若命令行仅有本参数与/或 --with-consul-token（及可选 --disable-kernel-opt / --disable-terminal），则**不执行** ModSecurity 主安装，仅 exporter 独立流程。
  --with-consul-token[=TOKEN]  Consul ACL（等价 CONSUL_HTTP_TOKEN）。**TOKEN 可省略**（用内置 Token）；**可指定**密钥。单独使用也会启用 exporter 独立流程。写法：--with-consul-token=SECRET、--with-consul-token SECRET、或单独 --with-consul-token。可与 --with-exporter 任意组合（只指定其一则另一项用内置）。
  --deploy-conf          宝塔环境：部署 ModSecurity / OWASP CRS / custom 规则、nginx.conf 引用，并在 nginx.conf 与 enable-php-*.conf 中开启 FastCGI 缓存（需宝塔 Nginx）
  --bt-openresty=VER    宝塔 nginx.sh 的 OpenResty 版本键（默认 openresty127，可选 openresty 等）；**重编时默认一并静态编译 nginx-module-vts**（https://github.com/vozlt/nginx-module-vts，登记 panel/install/nginx/nginx_module_vts）；不需要额外参数。关闭：SHELLSTACK_WITH_NGINX_MODULE_VTS=0；源码/标签：NGINX_MODULE_VTS_DIR、NGINX_MODULE_VTS_GIT_TAG；--deploy-conf 注入本机状态：SHELLSTACK_VTS_LISTEN_PORT、SHELLSTACK_DEPLOY_NGINX_MODULE_VTS
  说明: 使用 --deploy-conf 或 --bt-openresty 时须已安装宝塔面板与 BTwaf；--extend-btwaf-cache 仅需宝塔面板（将调用面板 WAF 安装脚本并下发扩展）。
  说明: --deploy-conf 写入 nginx.conf 时仅在 \`nginx -V\` 含 modsecurity 时注入 modsecurity 指令；默认在宝塔 \`/www/server/panel/vhost/nginx\` 下 phpMyAdmin 站点配置（\`*phpmyadmin*.conf\` 等）每个 \`server{}\` 内写入 \`modsecurity off;\`（避免 CRS 误拦 SQL/导入）；不需要可设 SHELLSTACK_DEPLOY_PHPMYADMIN_MODSECURITY_OFF=0，或改目录 SHELLSTACK_BT_PANEL_VHOST_NGINX。SHELLSTACK_DEPLOY_FASTCGI_CACHE=0 可关闭 fastcgi 共享区与 enable-php 缓存；编译 ModSecurity-nginx 后可用 SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK=1 删除旧块并重注入。
  说明: --deploy-conf 从 ModSecurity 仓库复制 modsecurity.conf-recommended / unicode.mapping；若 git 失败会回退从 raw.githubusercontent.com/owasp-modsecurity/ModSecurity 下载（MODSECURITY_CONF_SAMPLES_TAG 默认 v3.0.10）。
  说明: --extend-btwaf-cache 环境变量：SHELLSTACK_BTWAF_PANEL_INSTALL=0 跳过面板 install.sh；已安装 BTwaf（/www/server/btwaf/socket 存在）默认不重复 install；SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL=1 强制重装；SHELLSTACK_BTWAF_OVERLAY_SRC=目录 指定本地扩展；SHELLSTACK_BTWAF_OVERLAY_BASE_URL=URL 覆盖 HTTP 根；SHELLSTACK_BTWAF_CACHE_LUA_URL=单文件 仅拉 cache.lua；SHELLSTACK_BTWAF_HTTP_DEBUG=1 拉取 cache.lua 校验失败时输出样本；SHELLSTACK_BTWAF_DOWNLOAD_UA= 自定义下载 User-Agent；SHELLSTACK_BTWAF_OFFICIAL_REF=目录 指定官方参考树（含 resty/redis.lua），用于补齐 /www/server/btwaf/lib/resty/redis.lua（与 init.lua 的 package.path 一致；不下载）；SHELLSTACK_INSTALL_REDIS=0 跳过 Redis；SHELLSTACK_REDIS_VER 可填宝塔版本号（如 8.0.5/8.2.3/8.4.0，传 8.0/8.2 会自动映射）；页缓存 Lua 连接 Redis 默认 127.0.0.1:6379，可设 SHELLSTACK_REDIS_HOST / SHELLSTACK_REDIS_PORT / SHELLSTACK_REDIS_DB（nginx 主配置须 env 同名声明）；整页缓存为 **Redis STRING**，键 `btwaf_cms_cache:`+md5(签名串)，**SETEX** 控制 TTL；签名段与默认 TTL 在 `lib/cache.lua` 的 `PAGE_CACHE_SIGN_COMPONENTS` / `PAGE_CACHE_TTL_SECONDS`（无需为键形状设环境变量）；SHELLSTACK_BTWAF_LEGACY_TARBALL=1 旧版全量 tar；SHELLSTACK_BTWAF_OVERLAY_INIT_LUA=1 覆盖 init.lua。
  说明: --with-exporter 会尝试通过包管理器安装 node_exporter（**CentOS/RHEL 7** 等会先装 **epel-release** 并试 EPEL 包名如 golang-github-prometheus-node-exporter；仓库仍无时从 **GitHub** 安装官方二进制并写 systemd，见 exporter.sh 的 SHELLSTACK_NODE_EXPORTER_VERSION / SHELLSTACK_EXPORTER_SKIP_NODE_EXPORTER_BINARY_FALLBACK）（默认端口 9100，可设 EXPORTER_LISTEN_PORT），配置 textfile 采集（每分钟）：shellstack_process_up（nginx/mysql/redis/宝塔面板）、shellstack_php_fpm_up（扫描 /www/server/php/*/）、shellstack_nginx_stub_*、**nginx-module-vts**（shellstack_nginx_vts_scrape_ok 与同文件 nginx_vts_*，默认抓取 127.0.0.1:8898/nginx-vts-status/format/prometheus；SHELLSTACK_NGINX_VTS_PROM_URL / SHELLSTACK_VTS_LISTEN_PORT / SHELLSTACK_NGINX_VTS_PROM_DISABLE 见 exporter.sh 头注释）；并向 Consul 注册。stub 默认探测常见 URL；失败时**仅当已检测到宝塔 Nginx**（存在 /www/server/nginx/sbin/nginx 与 conf/nginx.conf）才在 nginx.conf 的 http{} 内 include \`/www/server/nginx/conf/shellstack_status.conf\`：同文件内含 \`stub_status\`（默认 127.0.0.1:8899/nginx_stub_status）及按 \`php-fpm master\`→\`php-fpm.conf\`→\`include\` 解析各 pool 的 \`listen\` 与 \`pm.status_path\` 生成的 \`location = /shellstack-fpm-status-<ver>\`（Nginx 内 \`SCRIPT_NAME\`/\`REQUEST_URI\` 与解析到的 path 一致；未配置时回退 \`/status\`）；旧版 \`shellstack_stub_status.conf\` 会自动迁移为该文件名；仅有面板目录未装 Nginx 则跳过注入。指标含 shellstack_nginx_workers_total、stub 的 active/reading/writing/waiting 及 accepts/**handled**/requests 累计（与 stub_status 标准输出一致）。关闭注入设 SHELLSTACK_NGINX_STUB_INJECT=0，改端口设 SHELLSTACK_NGINX_STUB_LISTEN_PORT。常规系统指标为 node_exporter 默认（node_*）。**root 且未设 SHELLSTACK_EXPORTER_SKIP_FIREWALL=1 时**，会按本机环境依次尝试 **firewalld → ufw → iptables（含 iptables-nft / iptables-legacy）→ nft** 放行 metrics 端口：**默认仅允许 CONSUL_HTTP_ADDR 解析出的 Consul 主机 IPv4**；多源或 CIDR 用 EXPORTER_METRICS_ALLOW_FROM（逗号分隔）；关闭自动配防火墙用 SHELLSTACK_EXPORTER_SKIP_FIREWALL=1。**root 且未设 SHELLSTACK_EXPORTER_SKIP_HOSTNAME=1** 时，在安装 node_exporter 前将静态主机名设为「二位地区码-公网IPv4」（IP 内点号改为连字符，如 HK-1-2-3-4，避免 \`HK-1.2.3.4\` 在 SSH 提示符里只显示首段）；公网 IP 依次轮询 ipify、ipinfo.io/ip、ifconfig.me、icanhazip、ident.me、AWS checkip 等，地区码由 ip-api.com 与 ipinfo.io 互补；可设 SHELLSTACK_EXPORTER_PUBLIC_IP / SHELLSTACK_EXPORTER_GEO_CODE / SHELLSTACK_EXPORTER_GEO_HOSTNAME 覆盖。Consul 注册默认带扩展 **Tags/Meta**（主机名、系统、是否宝塔、textfile 路径与是否注入 node_exporter 等）；额外标签/元数据用 CONSUL_SERVICE_TAGS、CONSUL_SERVICE_META；脚本还会在 Meta 写入各服务**注册瞬间**快照（svc_nginx_up、svc_mysql_up、svc_redis_up、svc_baota_panel_up、svc_php_fpm_masters_up、svc_nginx_stub_reachable、meta_snapshot_note），**仅重新向 Consul 注册时更新**，实时状态以 Prometheus 的 shellstack_* 为准。/metrics 中 smartmon_ 等前缀来自本机其它 node_exporter 采集器；shellstack_ 前缀来自 textfile（若缺失请查 node_exporter 是否带 --collector.textfile.directory 及 /var/log/shellstack-node-exporter-textfile.log）。**Consul HTTP 健康检查里的 Output 会截断**，不能据此判断是否有网络/带宽指标；请在可访问 9100 的机器上执行 `curl -sS 'http://IP:9100/metrics' | grep -E 'shellstack_host_network|node_network_'`（下载≈receive、上传≈transmit；累计 counter 用 `rate(...[5m])` 得字节/秒）。textfile 含 **主机摘要** shellstack_host_*（负载、内存占用比、CPU/iowait 短采样、根分区使用率、整盘读写字节/秒、非 lo 网卡收发字节/秒；细粒度与历史仍以 node_* 为准）、宝塔侧 **Nginx**（stub 连接数、accepts/requests、worker 数）、**PHP-FPM**（按版本 up + workers）、**MySQL**（mysqladmin extended-status：线程与 Queries）、**Redis**（INFO：内存、连接数、ops/s）；MySQL/Redis 需本机 mysqladmin/redis-cli 可连；MySQL 若 **root 需密码**（否则 extended-status 报 Access denied）请配置 **/root/.my.cnf**（[client] user/password，chmod 600）或 exporter 环境变量 **SHELLSTACK_MYSQL_DEFAULTS_FILE** / **SHELLSTACK_MYSQL_USER**+**SHELLSTACK_MYSQL_PASSWORD**（部署时 export 可写入 cron，见 exporter.sh 头注释）；socket 用 **SHELLSTACK_MYSQL_SOCKET**；Redis 见 **SHELLSTACK_REDIS_SOCKET** 等。关闭主机摘要：SHELLSTACK_TEXTFILE_SKIP_HOST_METRICS=1（须写入 cron 环境或导出后手跑采集脚本）。Consul 默认见 exporter.sh（自动 export + /etc/profile.d/shellstack-consul-env.sh）；SHELLSTACK_EXPORTER_NO_BUILTIN_TOKEN=1、SHELLSTACK_EXPORTER_SKIP_PERSIST_ENV=1 见 exporter 头注释。
  说明: \`/var/log/shellstack-node-exporter-textfile.log\`：**安装/重跑 exporter 时**会将 textfile 脚本首次执行的输出 **tee** 到此文件并追加一行部署标记；**之后**由 cron 每分钟追加（采集脚本 stdout 含一行 OK 心跳）。若长期只有一行、无每分钟追加，请检查 \`systemctl status cron\`。**node_exporter** 本体日志见 \`journalctl -u prometheus-node-exporter -e\` 或 \`journalctl -u node_exporter -e\`（RHEL 二进制回退常用后者）。
  说明: 与 ModSecurity/宝塔 安装类参数（如 --version、--deploy-conf、--bt-openresty、--extend-btwaf-cache 等）**同时未出现**时，--with-exporter / --with-consul-token 触发 **exporter 独立流程**（不跑主安装）。**此场景下若再加 --force**，表示**仅强制重跑 exporter**，**不会**动宝塔 Nginx。**--with-exporter / --with-consul-token 可省略 = 后的值**（走内置默认）。其它情况下 **--force 按「写了哪些主参数」逐项加强**：可多参数 + 共用 `--force`（例如 deploy、bt-openresty、extend 三项都写则三项的强制逻辑都会生效），也可单参数 + `--force`；**不会**自动拼上未写的 deploy / bt-openresty / extend。需要「显式全套」时请写齐参数 + `--force`，或单独裸 \`--force\`。若要在同一条命令里先完整安装 ModSecurity 再注册 exporter，须带上至少一个主安装类参数。EXPORTER_CONSUL_ADDR 与 EXPORTER_PROMETHEUS_SERVER（已弃用）等价。
  说明: --install-bt 使用 BT11 安装命令下载并执行 install_panel.sh（默认地址: https://bt11.btmb.cc/install/install_panel.sh）；可用 BT_INSTALL_SCRIPT_URL / BT_INSTALL_ARG 覆盖。
  说明: 未显式使用 --bt-openresty / --deploy-conf 时不会触发宝塔 Nginx 重编译；仅 --extend-btwaf-cache（即使加 --force，只要未同时写 --deploy-conf 或 --bt-openresty）也不会重装 Nginx。
  说明: 若 Nginx 已含 ModSecurity 且与当前 --bt-openresty 版本一致，将跳过重复编译；强制重编可设 MODSECURITY_FORCE_BT_NGINX_REBUILD=1。
  --help                 显示此帮助信息
  --verify               验证已安装的 ModSecurity
  --info                 显示安装信息
  --cleanup              清理临时文件

示例:
  # 默认安装
  $0

  # 指定版本和路径
  $0 --version=3.0.9 --prefix=/opt/modsecurity

  # 启用 GeoIP（默认使用 DB-IP Lite，免费）
  $0 --enable-geoip

  # 使用 MaxMind 作为 GeoIP 提供商（需要 API Key）
  $0 --enable-geoip --geoip-provider=maxmind

  # 启用所有可选功能
  $0 --enable-geoip --enable-security --enable-openresty

  # 验证安装
  $0 --verify

  # 查看安装信息
  $0 --info

  # 如果遇到内存不足错误，使用单线程编译
  $0 --jobs=1

  # 手动设置并行任务数（例如：2个任务）
  $0 --jobs=2

  # 宝塔：同步 BTwaf 资源包并部署 WAF/ModSecurity 配置
  $0 --extend-btwaf-cache --deploy-conf

  # 仅重跑 BTwaf 扩展（--force 不会触发 Nginx 重编，除非同时加 --deploy-conf 或 --bt-openresty）
  $0 --extend-btwaf-cache --force

  # 裸 --force：一键全套（openresty + deploy + extend；若要指定版本键请先写 --bt-openresty=openresty127）
  $0 --force

  # 只强制其中一步（不会触发未写出的 deploy / extend / 重编）
  $0 --deploy-conf --force
  $0 --bt-openresty=openresty127 --force

  # 多参数共用同一 --force（各自加强；未写的不自动追加）
  $0 --bt-openresty=openresty127 --deploy-conf --extend-btwaf-cache --force

  # 先安装宝塔（--force 不会自动展开为 Nginx 全套，除非仅裸 --force）
  $0 --install-bt --force

  # 仅 exporter + Consul（不编译 ModSecurity；pipe 时首参须为 modsecurity）。以下均为合法：全内置 / 只改 Consul / 只改 Token / 两项都指定
  curl -fsSL https://shellstack.example/shellstack.sh | sudo bash -s modsecurity --with-exporter --with-consul-token
  curl -fsSL https://shellstack.example/shellstack.sh | sudo bash -s modsecurity --with-exporter=http://10.0.0.10:8500 --with-consul-token
  curl -fsSL https://shellstack.example/shellstack.sh | sudo bash -s modsecurity --with-exporter --with-consul-token=your-secret-id
  curl -fsSL https://shellstack.example/shellstack.sh | sudo bash -s modsecurity --with-exporter=http://10.0.0.10:8500 --with-consul-token=your-secret-id
  curl -fsSL https://shellstack.example/shellstack.sh | sudo bash -s modsecurity --with-exporter http://10.0.0.10:8500 --with-consul-token your-secret-id

  # 本地：安装 exporter 并注册到 Consul
  $0 --with-exporter=http://10.0.0.10:8500

  # Consul ACL（任选其一；仅 token 也会走 exporter 独立流程）
  $0 --with-exporter=http://10.0.0.10:8500 --with-consul-token=your-secret-id
  CONSUL_HTTP_TOKEN=your-secret-id $0 --with-exporter=http://10.0.0.10:8500
  $0 --with-consul-token=your-secret-id

  # 在 main.sh 中仅使用 exporter（关闭默认内核/终端优化）
  $0 --with-exporter=http://consul.example.com:8500 --disable-kernel-opt --disable-terminal

  # 远程：用 ShellStack 拉取并执行本模块（bash -s 后第一项必须是 modsecurity，其余为 main.sh 参数；勿用 bash shellstack.sh）
  curl -fsSL https://shellstack.example/shellstack.sh | sudo bash -s modsecurity --bt-openresty=openresty127 --deploy-conf --extend-btwaf-cache --with-exporter=http://consul:8500 --with-consul-token=secret
  # 远程：仅 exporter 并强制重跑 exporter（--force 不触发 ModSecurity 主安装）
  curl -fsSL https://shellstack.example/shellstack.sh | sudo bash -s modsecurity --with-exporter --with-consul-token --force
  # 远程：主流程强制（须带如 --deploy-conf）+ exporter
  curl -fsSL https://shellstack.example/shellstack.sh | sudo bash -s modsecurity --with-exporter --with-consul-token --deploy-conf --force
  CONSUL_HTTP_TOKEN=secret curl -fsSL https://shellstack.example/shellstack.sh | sudo bash -s modsecurity --with-exporter=http://consul:8500

  # 仅安装 node_exporter + Consul 注册（不跑完整 modsecurity/main.sh）：直接执行 includes/exporter.sh
  sudo bash /path/to/modsecurity/includes/exporter.sh http://127.0.0.1:8500
  curl -fsSL https://shellstack.example/modsecurity/includes/exporter.sh | sudo bash -s -- --consul-token=secret http://consul:8500

  # 宝塔面板：安装 libmodsecurity、升级 OpenResty 并编译 ModSecurity-nginx，并下发 CRS/自定义规则
  $0 --deploy-conf

  # 指定宝塔 OpenResty 版本键（与 /www/server/panel/install/nginx.sh 一致，如 openresty）
  $0 --bt-openresty=openresty --deploy-conf

支持的系统:
  - Ubuntu/Debian
  - CentOS/RHEL/Fedora
  - Rocky Linux/AlmaLinux
  - Arch Linux/Manjaro
  - OpenSUSE/SUSE

支持的 ModSecurity 版本:
  - 3.0.0 及更高版本
  - 使用 'latest' 或 'master' 安装最新版本

GeoIP 提供商说明:
  - DB-IP Lite (默认): 免费，无需 API Key，每月更新
    数据库文件: /usr/local/share/GeoIP/dbip-country-lite.mmdb
    更新脚本: /usr/local/bin/update-dbip-lite.sh
  
  - MaxMind (可选): 需要 API Key，更精确，需要账户
    配置文件: /usr/local/etc/GeoIP.conf
    需要设置: MAXMIND_ACCOUNT_ID 和 MAXMIND_LICENSE_KEY

更多信息:
  安装日志: $LOG_FILE
  DB-IP Lite: https://db-ip.com/db/download/ip-to-country-lite
  MaxMind: https://www.maxmind.com/en/accounts/current/license-key
EOF
}

