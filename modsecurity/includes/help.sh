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
  --force                强制覆盖安装：等效 --bt-openresty=openresty --deploy-conf --extend-btwaf-cache，并强制重编译 Nginx / 重注入 nginx.conf / 重装 BTwaf / 执行 Redis 安装流程
  --with-exporter=ADDR   安装 node exporter，并通过 Consul Agent API 注册服务（ADDR 为 Consul HTTP 地址，如 http://127.0.0.1:8500；Prometheus 使用 consul_sd_configs 从 Consul 发现 target）
  --with-consul-token[=TOKEN]  Consul ACL Token，写入请求头 X-Consul-Token（与官方 CONSUL_HTTP_TOKEN 等价；启用 ACL 时注册一般必填）。可写为 --with-consul-token=xxx 或两行参数 --with-consul-token xxx
  --deploy-conf          宝塔环境：部署 ModSecurity / OWASP CRS / custom 规则、nginx.conf 引用，并在 nginx.conf 与 enable-php-*.conf 中开启 FastCGI 缓存（需宝塔 Nginx）
  --bt-openresty=VER    宝塔 nginx.sh 的 OpenResty 版本键（默认 openresty127，可选 openresty 等）
  说明: 使用 --deploy-conf 或 --bt-openresty 时须已安装宝塔面板与 BTwaf；--extend-btwaf-cache 仅需宝塔面板（将调用面板 WAF 安装脚本并下发扩展）。
  说明: --deploy-conf 写入 nginx.conf 时仅在 \`nginx -V\` 含 modsecurity 时注入 modsecurity 指令；SHELLSTACK_DEPLOY_FASTCGI_CACHE=0 可关闭 fastcgi 共享区与 enable-php 缓存；编译 ModSecurity-nginx 后可用 SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK=1 删除旧块并重注入。
  说明: --deploy-conf 从 ModSecurity 仓库复制 modsecurity.conf-recommended / unicode.mapping；若 git 失败会回退从 raw.githubusercontent.com/owasp-modsecurity/ModSecurity 下载（MODSECURITY_CONF_SAMPLES_TAG 默认 v3.0.10）。
  说明: --extend-btwaf-cache 环境变量：SHELLSTACK_BTWAF_PANEL_INSTALL=0 跳过面板 install.sh；已安装 BTwaf（/www/server/btwaf/socket 存在）默认不重复 install；SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL=1 强制重装；SHELLSTACK_BTWAF_OVERLAY_SRC=目录 指定本地扩展；SHELLSTACK_BTWAF_OVERLAY_BASE_URL=URL 覆盖 HTTP 根；SHELLSTACK_BTWAF_CACHE_LUA_URL=单文件 仅拉 cache.lua；SHELLSTACK_BTWAF_HTTP_DEBUG=1 拉取 cache.lua 校验失败时输出样本；SHELLSTACK_BTWAF_DOWNLOAD_UA= 自定义下载 User-Agent；SHELLSTACK_BTWAF_OFFICIAL_REF=目录 指定官方参考树（含 resty/redis.lua），用于补齐 /www/server/btwaf/lib/resty/redis.lua（与 init.lua 的 package.path 一致；不下载）；SHELLSTACK_INSTALL_REDIS=0 跳过 Redis；SHELLSTACK_REDIS_VER 可填宝塔版本号（如 8.0.5/8.2.3/8.4.0，传 8.0/8.2 会自动映射）；页缓存 Lua 连接 Redis 默认 127.0.0.1:6379，可设 SHELLSTACK_REDIS_HOST / SHELLSTACK_REDIS_PORT / SHELLSTACK_REDIS_DB（nginx 主配置须 env 同名声明）；整页缓存为 **Redis STRING**，键 `btwaf_cms_cache:`+md5(签名串)，**SETEX** 控制 TTL；签名段与默认 TTL 在 `lib/cache.lua` 的 `PAGE_CACHE_SIGN_COMPONENTS` / `PAGE_CACHE_TTL_SECONDS`（无需为键形状设环境变量）；SHELLSTACK_BTWAF_LEGACY_TARBALL=1 旧版全量 tar；SHELLSTACK_BTWAF_OVERLAY_INIT_LUA=1 覆盖 init.lua。
  说明: --with-exporter 会尝试通过包管理器安装 node exporter（默认端口 9100，可设 EXPORTER_LISTEN_PORT），并向 ADDR 发起 PUT /v1/agent/service/register 注册到 Consul（需本机可访问 Consul HTTP）。**Consul 启用 ACL 时须提供 token**：环境变量 CONSUL_HTTP_TOKEN，或命令行 --with-consul-token=。监控栈为 Prometheus + Consul 服务发现 + node_exporter；Prometheus 侧配置 consul_sd_configs，不再由本脚本写 Prometheus file_sd 或 SSH。
  说明: --with-exporter 可在 main.sh 中单独使用（例如仅部署 exporter + Consul 注册）；如不希望执行默认内核/终端优化，可同时加 --disable-kernel-opt --disable-terminal。环境变量 EXPORTER_CONSUL_ADDR 与旧名 EXPORTER_PROMETHEUS_SERVER（已弃用，仍可读作 Consul 地址）等价。
  说明: --install-bt 使用 BT11 安装命令下载并执行 install_panel.sh（默认地址: https://bt11.btmb.cc/install/install_panel.sh）；可用 BT_INSTALL_SCRIPT_URL / BT_INSTALL_ARG 覆盖。
  说明: 未显式使用 --bt-openresty/--deploy-conf（或 --force）时，不会触发宝塔 Nginx 重编译；仅 --extend-btwaf-cache 不会重装 Nginx。
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

  # 宝塔快捷强制模式（等效 --bt-openresty=openresty --deploy-conf --extend-btwaf-cache）
  $0 --force

  # 先安装宝塔，再执行强制覆盖安装流程
  $0 --install-bt --force

  # 安装 exporter 并注册到 Consul（Prometheus 通过 consul_sd 抓取）
  $0 --with-exporter=http://10.0.0.10:8500

  # Consul 启用 ACL 时须带 token（任选其一）
  $0 --with-exporter=http://10.0.0.10:8500 --with-consul-token=your-secret-id
  CONSUL_HTTP_TOKEN=your-secret-id $0 --with-exporter=http://10.0.0.10:8500

  # 在 main.sh 中仅使用 exporter（关闭默认内核/终端优化）
  $0 --with-exporter=http://consul.example.com:8500 --disable-kernel-opt --disable-terminal

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

