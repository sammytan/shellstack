#!/bin/bash

# =====================================================================
# OpenResty 安装（选装）
# 默认不启用
# =====================================================================

# 安装 OpenResty
install_openresty() {
  log "开始安装 OpenResty..."

  local OPENRESTY_VERSION="${OPENRESTY_VERSION:-1.21.4.1}"
  local OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"

  log "OpenResty 版本: $OPENRESTY_VERSION"
  log "安装路径: $OPENRESTY_PREFIX"

  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"

  # 下载 OpenResty
  log "下载 OpenResty..."
  wget "https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz" >> "$LOG_FILE" 2>&1 || error "下载 OpenResty 失败"
  
  tar xzf "openresty-${OPENRESTY_VERSION}.tar.gz"
  cd "openresty-${OPENRESTY_VERSION}"

  # 配置 OpenResty（包含 ModSecurity 支持）
  log "配置 OpenResty..."
  
  local configure_opts=(
    "--prefix=$OPENRESTY_PREFIX"
    "--with-http_ssl_module"
    "--with-http_realip_module"
    "--with-http_stub_status_module"
    "--with-http_gzip_static_module"
    "--with-pcre-jit"
    "--with-file-aio"
    "--with-threads"
    "--with-stream"
    "--with-stream_ssl_module"
    "--without-http_redis2_module"
    "--add-module=$BUILD_DIR/ModSecurity-nginx"
  )

  # 检查 ModSecurity 是否已安装
  if [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so" ] || [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so.3" ]; then
    configure_opts+=("--add-module=$BUILD_DIR/ModSecurity-nginx")
    log "检测到 ModSecurity，将启用 ModSecurity 支持"
    
    # 下载 ModSecurity-nginx 连接器
    if [ ! -d "$BUILD_DIR/ModSecurity-nginx" ]; then
      log "下载 ModSecurity-nginx 连接器..."
      cd "$BUILD_DIR"
      git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git >> "$LOG_FILE" 2>&1 || error "下载 ModSecurity-nginx 失败"
      cd "openresty-${OPENRESTY_VERSION}"
    fi
  else
    warn "未检测到 ModSecurity，OpenResty 将安装但不包含 ModSecurity 支持"
  fi

  ./configure "${configure_opts[@]}" >> "$LOG_FILE" 2>&1 || error "配置 OpenResty 失败"

  # 编译和安装
  log "编译 OpenResty..."
  make -j"$MAKE_JOBS" >> "$LOG_FILE" 2>&1 || error "编译 OpenResty 失败"

  log "安装 OpenResty..."
  make install >> "$LOG_FILE" 2>&1 || error "安装 OpenResty 失败"

  # 创建系统服务
  log "创建 OpenResty 系统服务..."
  cat > /etc/systemd/system/openresty.service << EOF
[Unit]
Description=The OpenResty Application Platform
After=network.target

[Service]
Type=forking
PIDFile=$OPENRESTY_PREFIX/nginx/logs/nginx.pid
ExecStartPre=$OPENRESTY_PREFIX/nginx/sbin/nginx -t -c $OPENRESTY_PREFIX/nginx/conf/nginx.conf
ExecStart=$OPENRESTY_PREFIX/nginx/sbin/nginx -c $OPENRESTY_PREFIX/nginx/conf/nginx.conf
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload >> "$LOG_FILE" 2>&1 || warn "重载 systemd 失败"
  systemctl enable openresty >> "$LOG_FILE" 2>&1 || warn "启用 OpenResty 服务失败"

  # 创建符号链接
  ln -sf "$OPENRESTY_PREFIX/nginx/sbin/nginx" /usr/local/bin/openresty 2>/dev/null || true
  ln -sf "$OPENRESTY_PREFIX/nginx/sbin/nginx" /usr/local/bin/nginx 2>/dev/null || true

  log "OpenResty 安装完成"
  log "安装路径: $OPENRESTY_PREFIX"
  log "配置文件: $OPENRESTY_PREFIX/nginx/conf/nginx.conf"
  log "使用命令 'systemctl start openresty' 启动服务"
  log "使用命令 '$OPENRESTY_PREFIX/bin/openresty' 执行 OpenResty 命令"
}

