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

  # GeoIP 信息
  echo
  log "GeoIP 信息:"
  if [ -d "$GEOIP_DIR" ]; then
    log "数据库目录: $GEOIP_DIR"
    local db_files=$(find "$GEOIP_DIR" -name "*.mmdb" 2>/dev/null | wc -l)
    log "数据库文件数量: $db_files"
    
    if [ $db_files -gt 0 ]; then
      # 检查 DB-IP Lite
      if [ -f "${GEOIP_DIR}/dbip-country-lite.mmdb" ]; then
        local db_size=$(ls -lh "${GEOIP_DIR}/dbip-country-lite.mmdb" 2>/dev/null | awk '{print $5}')
        local db_date=$(stat -c %y "${GEOIP_DIR}/dbip-country-lite.mmdb" 2>/dev/null | cut -d' ' -f1 || stat -f "%Sm" -t "%Y-%m-%d" "${GEOIP_DIR}/dbip-country-lite.mmdb" 2>/dev/null || echo "未知")
        log "  - DB-IP Lite: dbip-country-lite.mmdb ($db_size, 更新日期: $db_date)"
      fi
      
      # 检查 MaxMind GeoLite2
      find "$GEOIP_DIR" -name "GeoLite2-*.mmdb" 2>/dev/null | while read -r db_file; do
        local db_size=$(ls -lh "$db_file" 2>/dev/null | awk '{print $5}')
        local db_date=$(stat -c %y "$db_file" 2>/dev/null | cut -d' ' -f1 || stat -f "%Sm" -t "%Y-%m-%d" "$db_file" 2>/dev/null || echo "未知")
        log "  - MaxMind: $(basename "$db_file") ($db_size, 更新日期: $db_date)"
      done
    else
      warn "未找到 GeoIP 数据库文件"
      log "提示: 使用 --enable-geoip 安装 GeoIP 支持"
    fi
  else
    warn "GeoIP 数据库目录不存在"
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

