#!/bin/bash

# =====================================================================
# GeoIP 数据库安装和配置（选装）
# 默认使用 DB-IP Lite（免费），可选 MaxMind（需要 API Key）
# =====================================================================

# 安装 Go 语言环境（用于编译 geoipupdate）
install_go() {
  local required_version="1.19"
  local install_version="1.21.0"
  
  if command -v go >/dev/null 2>&1; then
    local current_version=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo "0.0")
    
    if [ -n "$current_version" ] && [ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" = "$required_version" ]; then
      log "Go 版本 $current_version 满足要求"
      return 0
    fi
  fi

  log "安装 Go $install_version..."
  cd /tmp
  
  # 下载 Go
  local go_arch="amd64"
  [ "$ARCH" = "arm64" ] && go_arch="arm64"
  
  wget "https://go.dev/dl/go${install_version}.linux-${go_arch}.tar.gz" >> "$LOG_FILE" 2>&1 || error "下载 Go 失败"
  
  # 移除旧版本
  rm -rf /usr/local/go
  rm -f /usr/bin/go /usr/bin/gofmt /usr/local/bin/go /usr/local/bin/gofmt 2>/dev/null || true
  
  # 安装新版本
  tar -C /usr/local -xzf "go${install_version}.linux-${go_arch}.tar.gz"
  
  # 创建符号链接
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  ln -sf /usr/local/go/bin/go /usr/bin/go 2>/dev/null || true
  ln -sf /usr/local/go/bin/gofmt /usr/bin/gofmt 2>/dev/null || true
  
  rm -f "go${install_version}.linux-${go_arch}.tar.gz"
  
  # 验证安装
  export PATH="/usr/local/go/bin:$PATH"
  if ! command -v go >/dev/null 2>&1; then
    error "Go 安装失败"
  fi
  
  log "Go 安装成功"
}

# 安装 geoipupdate 工具
install_geoipupdate() {
  if command -v geoipupdate >/dev/null 2>&1; then
    log "geoipupdate 已安装"
    return 0
  fi

  log "安装 geoipupdate 工具..."

  # 安装 Go（如果需要）
  install_go

  # 安装编译依赖
  case "$SYSTEM_TYPE" in
    debian)
      eval "$PKG_INSTALL build-essential wget tar gzip git gcc make automake libtool pandoc" >> "$LOG_FILE" 2>&1
      ;;
    redhat)
      eval "$PKG_INSTALL gcc make automake libtool wget tar gzip git pandoc" >> "$LOG_FILE" 2>&1
      ;;
    *)
      warn "无法自动安装编译依赖，请手动安装后继续"
      return 1
      ;;
  esac

  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"

  # 设置 Go 环境
  export PATH="/usr/local/go/bin:$PATH"
  export GOPATH="$HOME/go"
  export GO111MODULE=on
  export GOPROXY=direct

  # 下载源码
  wget "https://github.com/maxmind/geoipupdate/archive/refs/tags/v${GEOIPUPDATE_VERSION}.tar.gz" >> "$LOG_FILE" 2>&1 || error "无法下载 geoipupdate 源码包"
  
  tar xzf "v${GEOIPUPDATE_VERSION}.tar.gz"
  cd "geoipupdate-${GEOIPUPDATE_VERSION}"

  # 验证 Go 版本
  local build_go_version=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo "unknown")
  if [ "$build_go_version" = "unknown" ] || [ "$(printf '%s\n' "1.19" "$build_go_version" | sort -V | head -n1)" != "1.19" ]; then
    error "Go 版本不满足要求 (需要 1.19+)"
  fi

  # 清理并构建
  go clean -modcache 2>/dev/null || true
  
  # 修改 go.mod（如果需要）
  if [ -f "go.mod" ]; then
    cp go.mod go.mod.bak
    sed -i '/toolchain/d' go.mod 2>/dev/null || true
    sed -i '/retract/d' go.mod 2>/dev/null || true
  fi

  # 构建
  make -j"$MAKE_JOBS" >> "$LOG_FILE" 2>&1 || error "构建 geoipupdate 失败"

  # 安装文件
  mkdir -p /usr/local/bin /usr/local/etc /usr/local/share/man/man1 /usr/local/share/man/man5

  if [ -f "build/geoipupdate" ]; then
    cp build/geoipupdate /usr/local/bin/
    chmod +x /usr/local/bin/geoipupdate
  else
    error "未找到构建的 geoipupdate 可执行文件"
  fi

  [ -f "build/GeoIP.conf" ] && cp build/GeoIP.conf /usr/local/etc/ && chmod 644 /usr/local/etc/GeoIP.conf
  [ -f "build/geoipupdate.1" ] && cp build/geoipupdate.1 /usr/local/share/man/man1/ && chmod 644 /usr/local/share/man/man1/geoipupdate.1
  [ -f "build/GeoIP.conf.5" ] && cp build/GeoIP.conf.5 /usr/local/share/man/man5/ && chmod 644 /usr/local/share/man/man5/GeoIP.conf.5

  ln -sf /usr/local/bin/geoipupdate /usr/bin/geoipupdate 2>/dev/null || true
  mandb 2>/dev/null || true

  log "geoipupdate 安装完成"
}

# 下载并更新 DB-IP Lite 数据库
download_dbip_lite() {
  log "下载 DB-IP Lite 数据库..."

  # 创建数据库目录
  mkdir -p "${GEOIP_DIR}"
  chmod 755 "${GEOIP_DIR}"

  # 尝试下载当前月份的数据库
  local current_year_month=$(date +%Y-%m)
  local db_url="https://download.db-ip.com/free/dbip-country-lite-${current_year_month}.mmdb"
  local db_file="${GEOIP_DIR}/dbip-country-lite.mmdb"

  log "尝试下载: $db_url"

  # 尝试下载当前月份
  if wget -O "$db_file.tmp" "$db_url" >> "$LOG_FILE" 2>&1; then
    if [ -f "$db_file.tmp" ] && [ -s "$db_file.tmp" ]; then
      mv "$db_file.tmp" "$db_file"
      log "DB-IP Lite 数据库下载成功"
      
      # 设置文件权限
      chmod 644 "$db_file"
      
      # 创建符号链接（如果需要）
      ln -sf "dbip-country-lite.mmdb" "${GEOIP_DIR}/GeoLite2-Country.mmdb" 2>/dev/null || true
      
      return 0
    fi
  fi

  # 如果当前月份失败，尝试上个月
  warn "当前月份数据库不可用，尝试下载上个月..."
  local last_month=$(date -d "last month" +%Y-%m 2>/dev/null || date -v-1m +%Y-%m 2>/dev/null || echo "")
  
  if [ -n "$last_month" ]; then
    db_url="https://download.db-ip.com/free/dbip-country-lite-${last_month}.mmdb"
    log "尝试下载: $db_url"
    
    if wget -O "$db_file.tmp" "$db_url" >> "$LOG_FILE" 2>&1; then
      if [ -f "$db_file.tmp" ] && [ -s "$db_file.tmp" ]; then
        mv "$db_file.tmp" "$db_file"
        log "DB-IP Lite 数据库下载成功（使用上个月版本）"
        chmod 644 "$db_file"
        ln -sf "dbip-country-lite.mmdb" "${GEOIP_DIR}/GeoLite2-Country.mmdb" 2>/dev/null || true
        return 0
      fi
    fi
  fi

  # 尝试通用下载页面
  warn "尝试从通用下载页面获取..."
  if wget -O "$db_file.tmp" "https://download.db-ip.com/free/dbip-country-lite-latest.mmdb" >> "$LOG_FILE" 2>&1; then
    if [ -f "$db_file.tmp" ] && [ -s "$db_file.tmp" ]; then
      mv "$db_file.tmp" "$db_file"
      log "DB-IP Lite 数据库下载成功（最新版本）"
      chmod 644 "$db_file"
      ln -sf "dbip-country-lite.mmdb" "${GEOIP_DIR}/GeoLite2-Country.mmdb" 2>/dev/null || true
      return 0
    fi
  fi

  error "无法下载 DB-IP Lite 数据库，请检查网络连接或手动下载"
}

# 配置 DB-IP Lite 自动更新
setup_dbip_updates() {
  log "配置 DB-IP Lite 数据库自动更新..."

  # 首次下载数据库
  download_dbip_lite

  # 创建更新脚本
  local update_script="/usr/local/bin/update-dbip-lite.sh"
  cat > "$update_script" << 'SCRIPT_EOF'
#!/bin/bash
# DB-IP Lite 数据库自动更新脚本

GEOIP_DIR="${GEOIP_DIR:-/usr/local/share/GeoIP}"
LOG_FILE="/var/log/dbip-update.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "开始更新 DB-IP Lite 数据库..."

mkdir -p "$GEOIP_DIR"
db_file="$GEOIP_DIR/dbip-country-lite.mmdb"

# 尝试下载当前月份
current_year_month=$(date +%Y-%m)
db_url="https://download.db-ip.com/free/dbip-country-lite-${current_year_month}.mmdb"

if wget -O "${db_file}.tmp" "$db_url" 2>>"$LOG_FILE" && [ -f "${db_file}.tmp" ] && [ -s "${db_file}.tmp" ]; then
  mv "${db_file}.tmp" "$db_file"
  chmod 644 "$db_file"
  ln -sf "dbip-country-lite.mmdb" "$GEOIP_DIR/GeoLite2-Country.mmdb" 2>/dev/null || true
  log "DB-IP Lite 数据库更新成功"
else
  # 尝试最新版本
  if wget -O "${db_file}.tmp" "https://download.db-ip.com/free/dbip-country-lite-latest.mmdb" 2>>"$LOG_FILE" && [ -f "${db_file}.tmp" ] && [ -s "${db_file}.tmp" ]; then
    mv "${db_file}.tmp" "$db_file"
    chmod 644 "$db_file"
    ln -sf "dbip-country-lite.mmdb" "$GEOIP_DIR/GeoLite2-Country.mmdb" 2>/dev/null || true
    log "DB-IP Lite 数据库更新成功（最新版本）"
  else
    log "警告: DB-IP Lite 数据库更新失败"
  fi
fi
SCRIPT_EOF

  chmod +x "$update_script"

  # 设置定时任务（如果启用）
  if [ "$ENABLE_GEOIP_AUTO_UPDATE" = "1" ]; then
    log "设置定时更新任务..."
    local cron_file="/etc/cron.d/dbip-update"
    
    # 根据更新频率设置 cron 表达式（DB-IP Lite 通常每月更新）
    local cron_schedule
    case "$GEOIP_UPDATE_FREQUENCY" in
      "daily")
        cron_schedule="0 3 * * *"
        ;;
      "weekly")
        cron_schedule="0 3 * * 1"
        ;;
      "monthly")
        cron_schedule="0 3 1 * *"  # 每月1号凌晨3点
        ;;
      *)
        cron_schedule="0 3 1 * *"  # 默认每月更新
        ;;
    esac

    cat > "$cron_file" << EOF
# DB-IP Lite 数据库自动更新
# 由 ModSecurity 安装脚本自动生成 $(date '+%Y-%m-%d %H:%M:%S')
${cron_schedule} root $update_script >> /var/log/dbip-update.log 2>&1
EOF

    chmod 644 "$cron_file"
    touch /var/log/dbip-update.log
    chmod 644 /var/log/dbip-update.log

    log "DB-IP Lite 自动更新已配置"
    log "更新频率: ${GEOIP_UPDATE_FREQUENCY}"
    log "更新脚本: $update_script"
  else
    log "DB-IP Lite 自动更新未启用（设置 ENABLE_GEOIP_AUTO_UPDATE=1 以启用）"
  fi

  log "DB-IP Lite 配置完成"
  log "数据库目录: ${GEOIP_DIR}"
  log "数据库文件: ${GEOIP_DIR}/dbip-country-lite.mmdb"
}

# 配置 MaxMind GeoIP 自动更新（可选，需要 API Key）
setup_maxmind_updates() {
  log "配置 MaxMind GeoIP 数据库自动更新..."

  # 安装 geoipupdate（如果需要）
  install_geoipupdate

  # 创建必要的目录
  mkdir -p "${GEOIP_DIR}" /usr/local/etc /usr/local/var/GeoIP
  chmod 755 "${GEOIP_DIR}" /usr/local/var/GeoIP

  # 检查 MaxMind 凭据
  if [ -z "$MAXMIND_ACCOUNT_ID" ] || [ -z "$MAXMIND_LICENSE_KEY" ]; then
    warn "MaxMind 账户信息未配置，请设置 MAXMIND_ACCOUNT_ID 和 MAXMIND_LICENSE_KEY"
    return 1
  fi

  # 生成配置文件
  cat > /usr/local/etc/GeoIP.conf << EOF
# GeoIP Update Configuration (MaxMind)
# 由 ModSecurity 安装脚本自动生成 $(date '+%Y-%m-%d %H:%M:%S')

# MaxMind 账户信息
AccountID ${MAXMIND_ACCOUNT_ID}
LicenseKey ${MAXMIND_LICENSE_KEY}

# 需要更新的数据库
EditionIDs GeoLite2-Country GeoLite2-City

# 数据库目录
DatabaseDirectory ${GEOIP_DIR}

# 其他设置
LockFile /usr/local/var/GeoIP/.geoipupdate.lock
EOF

  chmod 644 /usr/local/etc/GeoIP.conf

  # 首次更新数据库
  log "执行首次 MaxMind GeoIP 数据库更新..."
  if geoipupdate -v >> "$LOG_FILE" 2>&1; then
    log "首次数据库更新成功"
  else
    warn "首次数据库更新失败，请检查配置和网络连接"
  fi

  # 设置定时任务（如果启用）
  if [ "$ENABLE_GEOIP_AUTO_UPDATE" = "1" ]; then
    log "设置定时更新任务..."
    local cron_file="/etc/cron.d/geoipupdate"
    
    # 根据更新频率设置 cron 表达式
    local cron_schedule
    case "$GEOIP_UPDATE_FREQUENCY" in
      "daily")
        cron_schedule="0 3 * * *"
        ;;
      "weekly")
        cron_schedule="0 3 * * 1"
        ;;
      "monthly")
        cron_schedule="0 3 1 * *"
        ;;
      *)
        cron_schedule="0 3 * * 1"
        ;;
    esac

    cat > "$cron_file" << EOF
# MaxMind GeoIP 数据库自动更新
# 由 ModSecurity 安装脚本自动生成 $(date '+%Y-%m-%d %H:%M:%S')
${cron_schedule} root /usr/local/bin/geoipupdate -v >> /var/log/geoipupdate.log 2>&1
EOF

    chmod 644 "$cron_file"
    touch /var/log/geoipupdate.log
    chmod 644 /var/log/geoipupdate.log

    log "MaxMind GeoIP 自动更新已配置"
    log "更新频率: ${GEOIP_UPDATE_FREQUENCY}"
  else
    log "MaxMind GeoIP 自动更新未启用（设置 ENABLE_GEOIP_AUTO_UPDATE=1 以启用）"
  fi

  log "MaxMind GeoIP 配置完成"
  log "配置文件: /usr/local/etc/GeoIP.conf"
  log "数据库目录: ${GEOIP_DIR}"
}

# 配置 GeoIP 自动更新（根据提供商选择）
setup_geoip_updates() {
  # 根据提供商选择配置方法
  case "${GEOIP_PROVIDER:-dbip}" in
    maxmind)
      log "使用 MaxMind 作为 GeoIP 提供商"
      setup_maxmind_updates
      ;;
    dbip|*)
      log "使用 DB-IP Lite 作为 GeoIP 提供商（默认，免费）"
      setup_dbip_updates
      ;;
  esac
}

# 安装 GeoIP 支持（主函数）
install_geoip() {
  log "=========================================="
  log "开始安装 GeoIP 支持"
  log "=========================================="
  log "GeoIP 提供商: ${GEOIP_PROVIDER:-dbip} (默认: DB-IP Lite，免费)"

  # 确保 libmaxminddb 已安装（两种提供商都需要 libmaxminddb）
  if ! check_lib maxminddb || ! check_dev libmaxminddb; then
    log "libmaxminddb 未安装，开始编译安装..."
    # compile_libmaxminddb 函数应该在 require_packages.sh 中已定义
    if declare -f compile_libmaxminddb > /dev/null; then
      compile_libmaxminddb
    else
      # 如果函数不存在，直接编译安装
      log "编译安装 libmaxminddb $LIBMAXMINDDB_VERSION..."
      mkdir -p "$BUILD_DIR"
      cd "$BUILD_DIR"
      
      wget "https://github.com/maxmind/libmaxminddb/releases/download/$LIBMAXMINDDB_VERSION/libmaxminddb-$LIBMAXMINDDB_VERSION.tar.gz" >> "$LOG_FILE" 2>&1 || error "下载 libmaxminddb 失败"
      tar xzf "libmaxminddb-$LIBMAXMINDDB_VERSION.tar.gz"
      cd "libmaxminddb-$LIBMAXMINDDB_VERSION"
      
      ./configure --prefix=/usr/local >> "$LOG_FILE" 2>&1
      make -j"$MAKE_JOBS" >> "$LOG_FILE" 2>&1
      make install >> "$LOG_FILE" 2>&1
      ldconfig >> "$LOG_FILE" 2>&1 || true
      
      # 创建符号链接
      ln -sf /usr/local/lib/libmaxminddb.so.0 /usr/lib64/libmaxminddb.so.0 2>/dev/null || true
      ln -sf /usr/local/lib/libmaxminddb.so.0 /usr/lib/libmaxminddb.so.0 2>/dev/null || true
      
      log "libmaxminddb 安装完成"
    fi
  fi

  # 根据提供商配置 GeoIP 更新
  setup_geoip_updates

  log "=========================================="
  log "GeoIP 支持安装完成"
  log "=========================================="
  
  # 显示数据库信息
  if [ "${GEOIP_PROVIDER:-dbip}" = "dbip" ]; then
    if [ -f "${GEOIP_DIR}/dbip-country-lite.mmdb" ]; then
      local db_size=$(ls -lh "${GEOIP_DIR}/dbip-country-lite.mmdb" 2>/dev/null | awk '{print $5}')
      log "DB-IP Lite 数据库已安装: ${GEOIP_DIR}/dbip-country-lite.mmdb ($db_size)"
      log "注意: DB-IP Lite 数据库与 MaxMind GeoLite2 格式兼容"
    fi
  else
    if [ -f "${GEOIP_DIR}/GeoLite2-Country.mmdb" ]; then
      local db_size=$(ls -lh "${GEOIP_DIR}/GeoLite2-Country.mmdb" 2>/dev/null | awk '{print $5}')
      log "MaxMind GeoLite2 数据库已安装: ${GEOIP_DIR}/GeoLite2-Country.mmdb ($db_size)"
    fi
  fi
}

