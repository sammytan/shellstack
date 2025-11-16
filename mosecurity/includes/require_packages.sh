#!/bin/bash

# =====================================================================
# 依赖包安装和编译
# =====================================================================

# 安装基础工具
install_basic_tools() {
  log "安装基础工具..."

  eval "$PKG_UPDATE" >> "$LOG_FILE" 2>&1

  case "$SYSTEM_TYPE" in
    debian)
      eval "$PKG_INSTALL build-essential wget tar gzip git gcc g++" >> "$LOG_FILE" 2>&1
      GCC_VERSION=$(gcc --version 2>/dev/null | head -n1 | awk '{print $3}' | cut -d. -f1 || echo "unknown")
      log "检测到 GCC 版本: $GCC_VERSION"
      ;;
    redhat)
      eval "$PKG_INSTALL gcc gcc-c++ make wget tar gzip git" >> "$LOG_FILE" 2>&1
      ;;
    arch)
      eval "$PKG_INSTALL base-devel wget tar gzip git gcc" >> "$LOG_FILE" 2>&1
      ;;
    suse)
      eval "$PKG_INSTALL gcc gcc-c++ make wget tar gzip git" >> "$LOG_FILE" 2>&1
      ;;
    *)
      warn "不支持的系统类型: $SYSTEM_TYPE"
      ;;
  esac

  # 验证基础工具安装
  for cmd in gcc make wget tar gzip git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      error "基础工具 $cmd 安装失败"
    fi
  done

  log "基础工具安装完成"
}

# 安装系统依赖包
install_system_dependencies() {
  log "安装ModSecurity系统依赖..."

  # 检查关键依赖
  CURL_MISSING=0
  GEOIP_MISSING=0
  MAXMINDDB_MISSING=0

  if ! check_lib curl || ! check_dev libcurl; then
    log "未找到curl开发库"
    CURL_MISSING=1
  fi

  if ! check_lib GeoIP || ! check_dev geoip; then
    log "未找到GeoIP开发库"
    GEOIP_MISSING=1
  fi

  if ! check_lib maxminddb || ! check_dev libmaxminddb; then
    log "未找到MaxMindDB开发库"
    MAXMINDDB_MISSING=1
  fi

  eval "$PKG_UPDATE" >> "$LOG_FILE" 2>&1

  case "$DISTRO" in
    ubuntu|debian)
      eval "$PKG_INSTALL build-essential automake libtool pkg-config \
                    libpcre2-dev libssl-dev libxml2-dev" >> "$LOG_FILE" 2>&1

      [ $CURL_MISSING -eq 1 ] && \
        eval "$PKG_INSTALL libcurl4-openssl-dev" >> "$LOG_FILE" 2>&1 || warn "curl开发库安装失败"

      [ $GEOIP_MISSING -eq 1 ] && \
        eval "$PKG_INSTALL libgeoip-dev" >> "$LOG_FILE" 2>&1 || warn "GeoIP开发库安装失败"

      [ $MAXMINDDB_MISSING -eq 1 ] && \
        eval "$PKG_INSTALL libmaxminddb-dev" >> "$LOG_FILE" 2>&1 || warn "MaxMindDB开发库安装失败"

      eval "$PKG_INSTALL liblua5.3-dev libyajl-dev" >> "$LOG_FILE" 2>&1 || warn "部分可选依赖安装失败"
      ;;

    centos|rhel|fedora|rocky|almalinux)
      # 安装EPEL仓库（如果需要）
      if ! rpm -q epel-release >/dev/null 2>&1; then
        log "安装EPEL仓库..."
        eval "$PKG_INSTALL epel-release" >> "$LOG_FILE" 2>&1 || warn "EPEL仓库安装失败"
      fi

      eval "$PKG_INSTALL gcc gcc-c++ make automake libtool pkgconfig \
                    pcre2-devel openssl-devel libxml2-devel" >> "$LOG_FILE" 2>&1

      [ $CURL_MISSING -eq 1 ] && \
        eval "$PKG_INSTALL libcurl-devel" >> "$LOG_FILE" 2>&1 || warn "curl开发库安装失败"

      [ $GEOIP_MISSING -eq 1 ] && \
        eval "$PKG_INSTALL libmaxminddb-devel" >> "$LOG_FILE" 2>&1 || warn "GeoIP开发库安装失败"

      [ $MAXMINDDB_MISSING -eq 1 ] && \
        eval "$PKG_INSTALL libmaxminddb-devel" >> "$LOG_FILE" 2>&1 || warn "MaxMindDB开发库安装失败"

      eval "$PKG_INSTALL lua-devel yajl-devel" >> "$LOG_FILE" 2>&1 || warn "部分可选依赖安装失败"
      ;;

    arch|manjaro)
      eval "$PKG_INSTALL gcc make automake libtool pkgconf \
                    pcre2 openssl libxml2" >> "$LOG_FILE" 2>&1

      [ $CURL_MISSING -eq 1 ] && \
        eval "$PKG_INSTALL curl" >> "$LOG_FILE" 2>&1 || warn "curl开发库安装失败"

      [ $GEOIP_MISSING -eq 1 ] && \
        eval "$PKG_INSTALL geoip" >> "$LOG_FILE" 2>&1 || warn "GeoIP开发库安装失败"

      [ $MAXMINDDB_MISSING -eq 1 ] && \
        eval "$PKG_INSTALL libmaxminddb" >> "$LOG_FILE" 2>&1 || warn "MaxMindDB开发库安装失败"

      eval "$PKG_INSTALL lua yajl" >> "$LOG_FILE" 2>&1 || warn "部分可选依赖安装失败"
      ;;

    opensuse*|suse*)
      eval "$PKG_INSTALL gcc gcc-c++ make automake libtool pkg-config \
                    pcre2-devel libopenssl-devel libxml2-devel" >> "$LOG_FILE" 2>&1

      [ $CURL_MISSING -eq 1 ] && \
        eval "$PKG_INSTALL libcurl-devel" >> "$LOG_FILE" 2>&1 || warn "curl开发库安装失败"

      [ $GEOIP_MISSING -eq 1 ] && \
        eval "$PKG_INSTALL geoip-devel" >> "$LOG_FILE" 2>&1 || warn "GeoIP开发库安装失败"

      [ $MAXMINDDB_MISSING -eq 1 ] && \
        eval "$PKG_INSTALL libmaxminddb-devel" >> "$LOG_FILE" 2>&1 || warn "MaxMindDB开发库安装失败"

      eval "$PKG_INSTALL lua-devel libyajl-devel" >> "$LOG_FILE" 2>&1 || warn "部分可选依赖安装失败"
      ;;

    *)
      warn "未识别的发行版: $DISTRO"
      log "请确保以下依赖已经安装:"
      echo "- C/C++编译器 (gcc, g++)"
      echo "- PCRE2库和开发包"
      echo "- OpenSSL库和开发包"
      echo "- libxml2库和开发包"
      echo "- libcurl库和开发包"
      echo "- GeoIP库和开发包"
      echo "- MaxMindDB库和开发包"
      echo "- Lua库和开发包"
      echo "- YAJL库和开发包"
      echo "- Git, Automake, Libtool, pkgconfig"

      read -p "要继续吗？(y/n) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        error "依赖未满足，退出"
      fi
      ;;
  esac

  log "系统依赖安装完成"
}

# 编译安装 YAJL
compile_yajl() {
  log "编译安装 YAJL $YAJL_VERSION..."

  # 检查并安装 CMake
  if ! command -v cmake >/dev/null 2>&1; then
    log "安装 CMake..."
    case "$SYSTEM_TYPE" in
      debian)
        apt-get update && apt-get install -y cmake
        ;;
      redhat)
        eval "$PKG_INSTALL cmake" >> "$LOG_FILE" 2>&1
        ;;
      *)
        error "无法自动安装 CMake，请手动安装后重试"
        ;;
    esac
  fi

  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"

  # 尝试多个下载源
  if ! wget "https://github.com/lloyd/yajl/archive/refs/tags/$YAJL_VERSION.tar.gz" -O yajl.tar.gz 2>>"$LOG_FILE"; then
    log "尝试备用下载源..."
    if ! wget "https://codeload.github.com/lloyd/yajl/tar.gz/refs/tags/$YAJL_VERSION" -O yajl.tar.gz 2>>"$LOG_FILE"; then
      error "无法下载 YAJL"
    fi
  fi

  tar xzf yajl.tar.gz
  cd "yajl-$YAJL_VERSION"

  # 使用 CMake 构建
  mkdir -p build
  cd build
  cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local >> "$LOG_FILE" 2>&1
  make -j"$MAKE_JOBS" >> "$LOG_FILE" 2>&1
  make install >> "$LOG_FILE" 2>&1
  ldconfig >> "$LOG_FILE" 2>&1 || true

  log "YAJL 安装完成"
}

# 编译安装 Lua
compile_lua() {
  log "编译安装 Lua $LUA_VERSION..."
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"
  
  wget "https://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz" 2>>"$LOG_FILE" || error "下载 Lua 失败"
  tar xzf "lua-$LUA_VERSION.tar.gz"
  cd "lua-$LUA_VERSION"
  
  make -j"$MAKE_JOBS" linux >> "$LOG_FILE" 2>&1
  make install INSTALL_TOP=/usr/local >> "$LOG_FILE" 2>&1
  ldconfig >> "$LOG_FILE" 2>&1 || true
  
  log "Lua 安装完成"
}

# 编译安装 LMDB
compile_lmdb() {
  log "编译安装 LMDB $LMDB_VERSION..."
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"
  
  wget "https://github.com/LMDB/lmdb/archive/refs/tags/LMDB_$LMDB_VERSION.tar.gz" 2>>"$LOG_FILE" || error "下载 LMDB 失败"
  tar xzf "LMDB_$LMDB_VERSION.tar.gz"
  cd "lmdb-LMDB_$LMDB_VERSION/libraries/liblmdb"
  
  make -j"$MAKE_JOBS" >> "$LOG_FILE" 2>&1
  make install >> "$LOG_FILE" 2>&1
  ldconfig >> "$LOG_FILE" 2>&1 || true
  
  log "LMDB 安装完成"
}

# 编译安装 SSDEEP
compile_ssdeep() {
  log "编译安装 SSDEEP $SSDEEP_VERSION..."
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"
  
  wget "https://github.com/ssdeep-project/ssdeep/releases/download/release-$SSDEEP_VERSION/ssdeep-$SSDEEP_VERSION.tar.gz" 2>>"$LOG_FILE" || error "下载 SSDEEP 失败"
  tar xzf "ssdeep-$SSDEEP_VERSION.tar.gz"
  cd "ssdeep-$SSDEEP_VERSION"
  
  ./configure --prefix=/usr/local >> "$LOG_FILE" 2>&1
  make -j"$MAKE_JOBS" >> "$LOG_FILE" 2>&1
  make install >> "$LOG_FILE" 2>&1
  ldconfig >> "$LOG_FILE" 2>&1 || true
  
  log "SSDEEP 安装完成"
}

# 编译安装 libmaxminddb
compile_libmaxminddb() {
  log "编译安装 libmaxminddb $LIBMAXMINDDB_VERSION..."
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"
  
  wget "https://github.com/maxmind/libmaxminddb/releases/download/$LIBMAXMINDDB_VERSION/libmaxminddb-$LIBMAXMINDDB_VERSION.tar.gz" 2>>"$LOG_FILE" || error "下载 libmaxminddb 失败"
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
}

# 检查并编译安装所有依赖
compile_dependencies() {
  log "开始检查并编译安装依赖..."

  mkdir -p "$BUILD_DIR"

  # 确保 git 已安装
  if ! check_command git; then
    log "Git 未安装，尝试通过包管理器安装..."
    eval "$PKG_INSTALL git" >> "$LOG_FILE" 2>&1 || error "Git 安装失败"
  fi

  export PATH="/usr/local/bin:$PATH"

  # 检查并编译安装 libmaxminddb
  if ! check_lib maxminddb || ! check_dev libmaxminddb; then
    compile_libmaxminddb
  else
    log "libmaxminddb 已安装，跳过编译"
  fi

  # 检查并编译安装 LMDB
  if ! check_lib lmdb || ! check_dev lmdb; then
    compile_lmdb
  else
    log "LMDB 已安装，跳过编译"
  fi

  # 检查并编译安装 SSDEEP
  if ! check_lib fuzzy || ! check_dev fuzzy; then
    compile_ssdeep
  else
    log "SSDEEP 已安装，跳过编译"
  fi

  # 检查并编译安装 YAJL
  if ! check_lib yajl || ! check_dev yajl; then
    compile_yajl
  else
    log "YAJL 已安装，跳过编译"
  fi

  # 检查并编译安装 Lua
  if ! check_lib lua || ! check_dev lua; then
    compile_lua
  else
    log "Lua 已安装，跳过编译"
  fi

  log "依赖编译安装完成"
}

