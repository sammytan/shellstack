#!/bin/bash

# =====================================================================
# ModSecurity 核心库安装
# 默认安装，支持多版本选择
# =====================================================================

# 编译安装 ModSecurity
build_modsecurity() {
  log "开始编译安装 ModSecurity $MODSECURITY_VERSION..."

  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"

  log "克隆 ModSecurity 仓库..."
  if [ -d ModSecurity ]; then
    rm -rf ModSecurity
  fi

  git clone --depth 1 https://github.com/SpiderLabs/ModSecurity.git >> "$LOG_FILE" 2>&1 || error "无法克隆 ModSecurity 仓库"
  cd ModSecurity

  # 获取所有可用的版本标签
  git fetch --tags >> "$LOG_FILE" 2>&1 || warn "获取标签失败"

  # 检查并切换到指定版本
  log "检查版本: $MODSECURITY_VERSION..."
  
  # 检查版本格式并切换
  local version_tag=""
  if git tag | grep -q "^v$MODSECURITY_VERSION$"; then
    version_tag="v$MODSECURITY_VERSION"
  elif git tag | grep -q "^v3/$MODSECURITY_VERSION$"; then
    version_tag="v3/$MODSECURITY_VERSION"
  elif git tag | grep -q "$MODSECURITY_VERSION"; then
    version_tag=$(git tag | grep "$MODSECURITY_VERSION" | head -n1)
    log "找到相似版本标签: $version_tag"
  fi

  if [ -n "$version_tag" ]; then
    log "切换到版本: $version_tag"
    git checkout "$version_tag" >> "$LOG_FILE" 2>&1 || error "无法切换到版本 $version_tag"
  elif [ "$MODSECURITY_VERSION" = "latest" ] || [ "$MODSECURITY_VERSION" = "master" ]; then
    log "使用最新的 master 分支..."
    git checkout v3/master >> "$LOG_FILE" 2>&1 || git checkout master >> "$LOG_FILE" 2>&1 || warn "无法切换到 master 分支，使用当前分支"
  else
    warn "未找到版本 $MODSECURITY_VERSION，使用最新的 master 分支"
    git checkout v3/master >> "$LOG_FILE" 2>&1 || git checkout master >> "$LOG_FILE" 2>&1 || warn "使用当前分支"
  fi

  log "初始化子模块..."
  git submodule update --init --recursive >> "$LOG_FILE" 2>&1 || warn "子模块初始化可能不完整"

  log "运行构建脚本..."
  if [ -f ./build.sh ]; then
    ./build.sh >> "$LOG_FILE" 2>&1 || error "构建脚本运行失败"
  else
    warn "未找到 build.sh，尝试使用 autogen.sh..."
    if [ -f ./autogen.sh ]; then
      ./autogen.sh >> "$LOG_FILE" 2>&1 || error "autogen.sh 运行失败"
    else
      error "未找到构建脚本"
    fi
  fi

  # 设置库路径和环境变量
  export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/local/lib/pkgconfig"
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/x86_64-linux-gnu:/usr/lib64:/usr/lib:/usr/local/lib"
  export LDFLAGS="-L/usr/local/lib -L/usr/lib64 -L/usr/lib -L/usr/lib/x86_64-linux-gnu"
  export CPPFLAGS="-I/usr/local/include -I/usr/include"

  # 配置选项
  local configure_opts=(
    "--prefix=$MODSECURITY_PREFIX"
    "--enable-shared"
    "--disable-static"
    "--with-pcre2"
    "--with-libxml"
    "--with-curl=/usr"
    "--with-yajl"
    "--with-lua"
  )

  # 检查 MaxMindDB 支持
  if check_lib maxminddb || check_dev libmaxminddb; then
    configure_opts+=("--with-maxminddb=/usr/local")
    log "启用 MaxMindDB 支持"
  else
    warn "MaxMindDB 未找到，跳过 MaxMindDB 支持"
  fi

  # 检查 LMDB 支持
  if check_lib lmdb || check_dev lmdb; then
    configure_opts+=("--with-lmdb=/usr/local")
    log "启用 LMDB 支持"
  fi

  # 检查 SSDEEP 支持
  if check_lib fuzzy || check_dev fuzzy; then
    configure_opts+=("--with-ssdeep=/usr/local")
    log "启用 SSDEEP 支持"
  fi

  log "配置 ModSecurity..."
  ./configure "${configure_opts[@]}" \
              CXXFLAGS="-std=c++17 -fpermissive" >> "$LOG_FILE" 2>&1 || error "配置失败，请检查日志: $LOG_FILE"

  log "编译 ModSecurity (并行任务数: $MAKE_JOBS)..."
  
  # 检查日志中是否有内存不足的错误
  if ! make -j"$MAKE_JOBS" >> "$LOG_FILE" 2>&1; then
    # 检查是否是内存不足导致的错误
    if grep -qi "Killed\|signal terminated\|out of memory\|cannot allocate memory" "$LOG_FILE" 2>/dev/null; then
      warn "编译失败，疑似内存不足"
      warn "当前并行任务数: $MAKE_JOBS"
      
      # 尝试减少并行任务数重试
      local retry_jobs=$((MAKE_JOBS / 2))
      if [[ "$retry_jobs" -lt 1 ]]; then
        retry_jobs=1
      fi
      
      if [[ "$retry_jobs" -lt "$MAKE_JOBS" ]]; then
        warn "尝试使用更少的并行任务数重试: $retry_jobs"
        log "重新编译 ModSecurity (并行任务数: $retry_jobs)..."
        if ! make -j"$retry_jobs" >> "$LOG_FILE" 2>&1; then
          error "编译失败（即使使用 $retry_jobs 个并行任务）。请检查日志: $LOG_FILE\n建议:\n  1. 使用 --jobs=1 进行单线程编译\n  2. 增加系统交换空间 (swap)\n  3. 关闭其他占用内存的程序"
        fi
      else
        error "编译失败，疑似内存不足。请检查日志: $LOG_FILE\n建议:\n  1. 使用 --jobs=1 进行单线程编译: bash main.sh --jobs=1\n  2. 增加系统交换空间 (swap)\n  3. 关闭其他占用内存的程序\n  4. 检查系统内存: free -h"
      fi
    else
      error "编译失败，请检查日志: $LOG_FILE"
    fi
  fi

  log "安装 ModSecurity..."
  make install >> "$LOG_FILE" 2>&1 || error "安装失败，请检查日志: $LOG_FILE"

  # 更新库缓存
  ldconfig >> "$LOG_FILE" 2>&1 || warn "ldconfig 失败，可能需要手动更新库缓存"

  # 创建 pkgconfig 文件（如果不存在）
  mkdir -p "$MODSECURITY_PREFIX/lib/pkgconfig"
  if [ ! -f "$MODSECURITY_PREFIX/lib/pkgconfig/libmodsecurity.pc" ]; then
    log "创建 pkgconfig 文件..."
    cat > "$MODSECURITY_PREFIX/lib/pkgconfig/libmodsecurity.pc" << EOF
prefix=$MODSECURITY_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libmodsecurity
Description: ModSecurity - 开源 Web 应用防火墙库
Version: $MODSECURITY_VERSION
Libs: -L\${libdir} -lmodsecurity
Cflags: -I\${includedir}
EOF
  fi

  log "ModSecurity 核心库安装完成"
}

# 验证 ModSecurity 安装
verify_modsecurity_install() {
  log "验证 ModSecurity 安装..."

  if [ ! -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so" ] && [ ! -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so.3" ]; then
    error "安装失败: 核心库不存在 ($MODSECURITY_PREFIX/lib/libmodsecurity.so*)"
  fi

  local lib_file=""
  if [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so.3" ]; then
    lib_file="$MODSECURITY_PREFIX/lib/libmodsecurity.so.3"
  elif [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so" ]; then
    lib_file="$MODSECURITY_PREFIX/lib/libmodsecurity.so"
  fi

  if [ -n "$lib_file" ]; then
    log "找到库文件: $lib_file"

    # 检查 GeoIP/MaxMindDB 支持
    if ldd "$lib_file" 2>/dev/null | grep -q "libGeoIP\|libmaxminddb"; then
      log "验证成功: ModSecurity 已成功链接到 GeoIP/MaxMindDB 库"
    else
      warn "ModSecurity 未链接到 GeoIP/MaxMindDB 库，GeoIP 功能可能不可用"
    fi

    # 检查 curl 支持
    if ldd "$lib_file" 2>/dev/null | grep -q "libcurl"; then
      log "验证成功: ModSecurity 已成功链接到 curl 库"
    else
      warn "ModSecurity 未正确链接到 curl 库，某些功能可能不可用"
    fi
  fi

  # 检查头文件
  if [ -d "$MODSECURITY_PREFIX/include/modsecurity" ]; then
    log "头文件已正确安装"
  else
    warn "头文件可能未正确安装"
  fi

  # 检查 pkg-config
  if pkg-config --exists libmodsecurity 2>/dev/null; then
    local installed_version=$(pkg-config --modversion libmodsecurity 2>/dev/null)
    log "ModSecurity 版本: $installed_version"
  fi

  log "ModSecurity 核心库安装验证完成"
}

# 安装 ModSecurity（主函数）
install_modsecurity() {
  log "=========================================="
  log "开始安装 ModSecurity 核心库"
  log "版本: $MODSECURITY_VERSION"
  log "安装路径: $MODSECURITY_PREFIX"
  log "=========================================="

  # 检查是否已安装
  if [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so" ] || [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so.3" ]; then
    log "检测到已安装的 ModSecurity"
    read -p "是否重新安装？[y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log "操作已取消，退出"
      return 0
    fi
  fi

  # 构建和安装
  build_modsecurity

  # 验证安装
  verify_modsecurity_install

  log "ModSecurity 核心库安装成功！"
}

