#!/bin/bash

# =====================================================================
# ModSecurity 核心库独立安装脚本 (支持GeoIP和MaxMindDB)
# 只安装ModSecurity核心库，不涉及任何Nginx/OpenResty
# =====================================================================

set -e

# 颜色代码
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # 重置颜色

# 基本配置
MODSECURITY_VERSION="3.0.10"
MODSECURITY_PREFIX="/usr/local/modsecurity"
BUILD_DIR="/tmp/modsec_core_build_$$"
MAKE_JOBS="$(nproc 2>/dev/null || echo 2)"
LOG_FILE="/tmp/modsecurity_install.log"

# 依赖版本配置
LIBMAXMINDDB_VERSION="1.12.1"  # MaxMind DB 库版本，用于读取数据库
GEOIPUPDATE_VERSION="5.1.1"   # GeoIP 更新工具版本，用于更新数据库
YAJL_VERSION="2.1.0"
LUA_VERSION="5.4.6"
GIT_VERSION="2.44.0"  # 添加 git 版本
LMDB_VERSION="0.9.31"  # LMDB 版本
SSDEEP_VERSION="2.14.1"  # SSDEEP 版本


# --- GeoIP 相关变量 ---
GEOIP_DIR="/usr/local/share/GeoIP"
MAXMIND_ACCOUNT_ID="149923"
MAXMIND_LICENSE_KEY="yvUg6Atv3ZT6tZ9p"
ENABLE_GEOIP_AUTO_UPDATE=0
GEOIP_UPDATE_FREQUENCY="weekly"  #

# 日志函数
log() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] 警告: $1${NC}" | tee -a "$LOG_FILE" >&2
}

error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] 错误: $1${NC}" | tee -a "$LOG_FILE" >&2
  exit 1
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix=*)
      MODSECURITY_PREFIX="${1#*=}"
      shift
      ;;
    --prefix)
      MODSECURITY_PREFIX="$2"
      shift 2
      ;;
    --version=*)
      MODSECURITY_VERSION="${1#*=}"
      shift
      ;;
    --version)
      MODSECURITY_VERSION="$2"
      shift 2
      ;;
    --help)
      echo "ModSecurity核心库安装脚本 (带GeoIP/MaxMindDB支持)"
      echo
      echo "使用方法: $0 [选项]"
      echo "选项:"
      echo "  --prefix=PATH          设置ModSecurity安装路径 (默认: /usr/local/modsecurity)"
      echo "  --version=VERSION      设置ModSecurity版本 (默认: 3.0.10)"
      echo "  --help                 显示此帮助信息"
      exit 0
      ;;
    *)
      warn "未知参数: $1"
      shift
      ;;
  esac
done

# 创建日志文件
touch "$LOG_FILE"
log "开始安装ModSecurity核心库(支持GeoIP)..."
log "安装路径: $MODSECURITY_PREFIX"
log "日志文件: $LOG_FILE"

# 检查命令是否存在
check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# 检查库是否存在
check_lib() {
  local lib_name="$1"

  # 检查多种可能的库文件路径
  for path in /usr/lib /usr/lib64 /usr/local/lib /usr/lib/x86_64-linux-gnu /lib /lib64; do
    if ls "$path"/lib"$lib_name"*.so* >/dev/null 2>&1; then
      return 0
    fi
  done

  # 尝试使用ldconfig查找
  if ldconfig -p | grep -q "lib$lib_name"; then
    return 0
  fi

  return 1
}

# 检查库开发包
check_dev() {
  local lib_name="$1"

  # 检查pkg-config
  if check_command pkg-config && pkg-config --exists "$lib_name"; then
    return 0
  fi

  # 检查头文件
  for path in /usr/include /usr/local/include; do
    if [ -d "$path/$lib_name" ] || ls "$path"/"$lib_name"*.h >/dev/null 2>&1; then
      return 0
    fi
  done

  return 1
}

# 检查是否为root用户
check_root() {
  if [ "$(id -u)" != "0" ]; then
    error "此脚本需要以root用户运行"
  fi
}

# 检测发行版并安装依赖
install_dependencies() {
  log "安装ModSecurity依赖..."

  # 检测Linux发行版
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
  elif command -v lsb_release >/dev/null 2>&1; then
    DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
  else
    DISTRO="unknown"
  fi

  log "检测到发行版: $DISTRO"

  # 检查并安装关键依赖
  log "检查关键依赖..."

  # 检查curl
  if ! check_lib curl || ! check_dev libcurl; then
    log "未找到curl开发库，尝试安装..."
    CURL_MISSING=1
  else
    log "找到curl库"
    CURL_MISSING=0
  fi

  # 检查GeoIP
  if ! check_lib GeoIP || ! check_dev geoip; then
    log "未找到GeoIP开发库，尝试安装..."
    GEOIP_MISSING=1
  else
    log "找到GeoIP库"
    GEOIP_MISSING=0
  fi

  # 检查MaxMindDB
  if ! check_lib maxminddb || ! check_dev libmaxminddb; then
    log "未找到MaxMindDB开发库，尝试安装..."
    MAXMINDDB_MISSING=1
  else
    log "找到MaxMindDB库"
    MAXMINDDB_MISSING=0
  fi

  # 根据发行版安装依赖
  case "$DISTRO" in
    ubuntu|debian)
      log "使用apt安装依赖..."
      # 更新包列表
      apt update >> "$LOG_FILE" 2>&1

      # 安装基础依赖
      apt install -y build-essential automake libtool pkg-config git wget \
                    libpcre2-dev libssl-dev libxml2-dev >> "$LOG_FILE" 2>&1

      # 安装其他依赖
      if [ $CURL_MISSING -eq 1 ]; then
        log "安装curl开发库..."
        apt install -y libcurl4-openssl-dev >> "$LOG_FILE" 2>&1 || warn "curl开发库安装失败"
      fi

      if [ $GEOIP_MISSING -eq 1 ]; then
        log "安装GeoIP开发库..."
        apt install -y libgeoip-dev >> "$LOG_FILE" 2>&1 || warn "GeoIP开发库安装失败"
      fi

      if [ $MAXMINDDB_MISSING -eq 1 ]; then
        log "安装MaxMindDB开发库..."
        apt install -y libmaxminddb-dev >> "$LOG_FILE" 2>&1 || warn "MaxMindDB开发库安装失败"
      fi

      # 其他选项依赖
      log "安装其他可选依赖..."
      apt install -y liblua5.3-dev libyajl-dev >> "$LOG_FILE" 2>&1 || warn "部分可选依赖安装失败"
      ;;

    centos|rhel|fedora|rocky|almalinux)
      if check_command dnf; then
        PKG_CMD="dnf"
      else
        PKG_CMD="yum"
      fi

      log "使用$PKG_CMD安装依赖..."
      # 更新包列表
      $PKG_CMD update -y >> "$LOG_FILE" 2>&1

      # 安装EPEL仓库（如果尚未安装）
      if ! $PKG_CMD list installed epel-release >/dev/null 2>&1; then
        log "安装EPEL仓库..."
        if [ "$PKG_CMD" = "dnf" ]; then
          $PKG_CMD install -y epel-release >> "$LOG_FILE" 2>&1 || warn "EPEL仓库安装失败"
        else
          $PKG_CMD install -y epel-release >> "$LOG_FILE" 2>&1 || warn "EPEL仓库安装失败"
        fi
      fi

      # 安装基础依赖
      $PKG_CMD install -y gcc gcc-c++ make automake libtool pkgconfig git wget \
                         pcre2-devel openssl-devel libxml2-devel >> "$LOG_FILE" 2>&1

      # 安装其他依赖
      if [ $CURL_MISSING -eq 1 ]; then
        log "安装curl开发库..."
        $PKG_CMD install -y libcurl-devel >> "$LOG_FILE" 2>&1 || warn "curl开发库安装失败"
      fi

      if [ $GEOIP_MISSING -eq 1 ]; then
        log "安装GeoIP开发库..."
        $PKG_CMD install -y libmaxminddb-devel >> "$LOG_FILE" 2>&1 || warn "MaxMindDB开发库安装失败"
      fi

      if [ $MAXMINDDB_MISSING -eq 1 ]; then
        log "安装MaxMindDB开发库..."
        $PKG_CMD install -y libmaxminddb-devel >> "$LOG_FILE" 2>&1 || warn "MaxMindDB开发库安装失败"
      fi

      # 其他选项依赖
      log "安装其他可选依赖..."
      $PKG_CMD install -y lua-devel yajl-devel >> "$LOG_FILE" 2>&1 || warn "部分可选依赖安装失败"
      ;;

    arch|manjaro)
      log "使用pacman安装依赖..."
      pacman -Syu --noconfirm >> "$LOG_FILE" 2>&1

      # 安装基础依赖
      pacman -S --noconfirm gcc make automake libtool pkgconf git wget \
                              pcre2 openssl libxml2 >> "$LOG_FILE" 2>&1

      # 安装其他依赖
      if [ $CURL_MISSING -eq 1 ]; then
        log "安装curl开发库..."
        pacman -S --noconfirm curl >> "$LOG_FILE" 2>&1 || warn "curl开发库安装失败"
      fi

      if [ $GEOIP_MISSING -eq 1 ]; then
        log "安装GeoIP开发库..."
        pacman -S --noconfirm geoip >> "$LOG_FILE" 2>&1 || warn "GeoIP开发库安装失败"
      fi

      if [ $MAXMINDDB_MISSING -eq 1 ]; then
        log "安装MaxMindDB开发库..."
        pacman -S --noconfirm libmaxminddb >> "$LOG_FILE" 2>&1 || warn "MaxMindDB开发库安装失败"
      fi

      # 其他选项依赖
      log "安装其他可选依赖..."
      pacman -S --noconfirm lua yajl >> "$LOG_FILE" 2>&1 || warn "部分可选依赖安装失败"
      ;;

    opensuse*|suse*)
      log "使用zypper安装依赖..."
      zypper refresh >> "$LOG_FILE" 2>&1

      # 安装基础依赖
      zypper install -y gcc gcc-c++ make automake libtool pkg-config git wget \
                            pcre2-devel libopenssl-devel libxml2-devel >> "$LOG_FILE" 2>&1

      # 安装其他依赖
      if [ $CURL_MISSING -eq 1 ]; then
        log "安装curl开发库..."
        zypper install -y libcurl-devel >> "$LOG_FILE" 2>&1 || warn "curl开发库安装失败"
      fi

      if [ $GEOIP_MISSING -eq 1 ]; then
        log "安装GeoIP开发库..."
        zypper install -y geoip-devel >> "$LOG_FILE" 2>&1 || warn "GeoIP开发库安装失败"
      fi

      if [ $MAXMINDDB_MISSING -eq 1 ]; then
        log "安装MaxMindDB开发库..."
        zypper install -y libmaxminddb-devel >> "$LOG_FILE" 2>&1 || warn "MaxMindDB开发库安装失败"
      fi

      # 其他选项依赖
      log "安装其他可选依赖..."
      zypper install -y lua-devel libyajl-devel >> "$LOG_FILE" 2>&1 || warn "部分可选依赖安装失败"
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

  log "依赖安装完成"
}

# 编译安装ModSecurity
build_modsecurity() {
  log "创建构建目录..."
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"

  log "克隆ModSecurity仓库..."
  git clone --depth 1 https://github.com/SpiderLabs/ModSecurity.git >> "$LOG_FILE" 2>&1 || error "无法克隆ModSecurity仓库"
  cd ModSecurity

  # 检查是否指定了版本
  if [ "$MODSECURITY_VERSION" != "3.0.10" ]; then
    log "切换到指定版本: $MODSECURITY_VERSION..."
    if git tag | grep -q "v$MODSECURITY_VERSION"; then
      git checkout "v$MODSECURITY_VERSION" >> "$LOG_FILE" 2>&1 || warn "无法切换到v$MODSECURITY_VERSION，使用默认版本"
    else
      warn "版本 v$MODSECURITY_VERSION 不存在，使用最新的master分支"
    fi
  else
    log "使用默认v3/master分支..."
    git checkout v3/master >> "$LOG_FILE" 2>&1 || warn "无法切换到v3/master，使用当前分支"
  fi

  log "初始化子模块..."
  git submodule update --init >> "$LOG_FILE" 2>&1 || warn "子模块初始化可能不完整"

  log "运行构建脚本..."
  ./build.sh >> "$LOG_FILE" 2>&1 || error "构建脚本运行失败"

  # 设置库路径 - 确保能找到所有依赖
  export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/local/lib/pkgconfig"
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/x86_64-linux-gnu:/usr/lib64:/usr/lib:/usr/local/lib"
  export LDFLAGS="-L/usr/local/lib -L/usr/lib64 -L/usr/lib -L/usr/lib/x86_64-linux-gnu"
  export CPPFLAGS="-I/usr/local/include -I/usr/include"

  # 添加 GeoIP 特定的路径
  export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/usr/lib/pkgconfig"
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib"
  export LDFLAGS="$LDFLAGS -L/usr/lib"
  export CPPFLAGS="$CPPFLAGS -I/usr/include"

  log "配置ModSecurity(启用MaxMindDB支持)..."
  ./configure --prefix="$MODSECURITY_PREFIX" \
              --enable-shared \
              --disable-static \
              --with-pcre2 \
              --with-libxml \
              --with-curl=/usr \
              --with-yajl \
              --with-lua \
              --with-maxminddb=/usr/local \
              --with-lmdb=/usr/local \
              --with-ssdeep=/usr/local \
              CXXFLAGS="-std=c++17 -fpermissive" >> "$LOG_FILE" 2>&1 || error "配置失败，请检查日志: $LOG_FILE"


  log "编译ModSecurity..."
  make -j"$MAKE_JOBS" >> "$LOG_FILE" 2>&1 || error "编译失败，请检查日志: $LOG_FILE"

  log "安装ModSecurity..."
  make install >> "$LOG_FILE" 2>&1 || error "安装失败，请检查日志: $LOG_FILE"

  # 更新库缓存
  ldconfig >> "$LOG_FILE" 2>&1 || warn "ldconfig失败，可能需要手动更新库缓存"

  # 创建pkgconfig文件 (如果不存在)
  if [ ! -f "$MODSECURITY_PREFIX/lib/pkgconfig/libmodsecurity.pc" ]; then
    log "创建pkgconfig文件..."
    mkdir -p "$MODSECURITY_PREFIX/lib/pkgconfig"
    cat << EOF | tee "$MODSECURITY_PREFIX/lib/pkgconfig/libmodsecurity.pc" > /dev/null
prefix=$MODSECURITY_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libmodsecurity
Description: ModSecurity - 开源Web应用防火墙库
Version: $MODSECURITY_VERSION
Libs: -L\${libdir} -lmodsecurity
Cflags: -I\${includedir}
EOF
  fi
}

# 验证安装
verify_install() {
  log "验证ModSecurity安装..."

  if [ ! -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so" ]; then
    error "安装失败: 核心库不存在 ($MODSECURITY_PREFIX/lib/libmodsecurity.so)"
  fi

  log "检查GeoIP支持..."
  if ldd "$MODSECURITY_PREFIX/lib/libmodsecurity.so" | grep -q "libGeoIP\|libmaxminddb"; then
    log "验证成功: ModSecurity已成功链接到GeoIP库"
  else
    warn "ModSecurity未链接到GeoIP库，GeoIP功能可能不可用"
  fi

  # 检查curl支持
  log "检查curl支持..."
  if ldd "$MODSECURITY_PREFIX/lib/libmodsecurity.so" | grep -q "libcurl"; then
    log "验证成功: ModSecurity已成功链接到curl库"
  else
    warn "ModSecurity未正确链接到curl库，某些功能可能不可用"
  fi

  # 检查包含文件
  if [ -d "$MODSECURITY_PREFIX/include/modsecurity" ]; then
    log "头文件已正确安装"
  else
    warn "头文件可能未正确安装"
  fi

  log "ModSecurity核心库安装验证完成"
}

# 清理临时文件
cleanup() {
  log "清理临时文件..."
  cd /tmp
  rm -rf "$BUILD_DIR"
  log "清理完成"
}

# 显示安装信息
show_info() {
  echo
  log "=== ModSecurity核心库安装信息 ==="
  log "安装目录: $MODSECURITY_PREFIX"
  log "库文件: $MODSECURITY_PREFIX/lib/libmodsecurity.so"
  log "头文件: $MODSECURITY_PREFIX/include/modsecurity"

  if [ -f "/usr/local/share/GeoIP/GeoLite2-Country.mmdb" ]; then
    log "GeoIP数据库: /usr/local/share/GeoIP/GeoLite2-Country.mmdb"
  else
    log "GeoIP数据库: 未安装"
  fi

  echo
  log "如需在应用中使用ModSecurity，请链接以下库:"
  echo "  -L$MODSECURITY_PREFIX/lib -lmodsecurity"
  echo
  log "安装日志文件: $LOG_FILE"
  echo
}

# 设置GeoIP自动更新
setup_geoip_updates() {
  log "设置GeoIP数据库自动更新..."

  # 检查geoipupdate工具是否安装
  if ! command -v geoipupdate &> /dev/null; then
    log "安装geoipupdate工具..."

    case "$DISTRO" in
      ubuntu|debian)
        log "在 Debian/Ubuntu 系统上从源码编译安装 geoipupdate..."
        cd "$BUILD_DIR"

        # 安装编译依赖
        apt-get update
        apt-get install -y build-essential wget tar gzip git gcc make automake libtool pandoc

        # 安装 Go 语言环境
        log "安装 Go 语言环境..."
        INSTALL_GO_FROM_SOURCE=0
        
        if ! command -v go >/dev/null 2>&1; then
          # 尝试通过包管理器安装
          log "通过包管理器安装 Go..."
          apt-get install -y golang || {
            # 如果包管理器安装失败，从源码安装
            log "通过包管理器安装 Go 失败，尝试从源码安装..."
            INSTALL_GO_FROM_SOURCE=1
          }
        fi
        
        # 检查当前 Go 版本（无论从哪个分支安装的）
        if command -v go >/dev/null 2>&1; then
          CURRENT_GO_VERSION=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo "0.0")
          REQUIRED_GO_VERSION="1.19"
          
          # 比较版本
          if [ -z "$CURRENT_GO_VERSION" ] || [ "$(printf '%s\n' "$REQUIRED_GO_VERSION" "$CURRENT_GO_VERSION" | sort -V | head -n1)" != "$REQUIRED_GO_VERSION" ]; then
            log "当前 Go 版本 ($CURRENT_GO_VERSION) 不兼容，需要 Go 1.19+，从源码安装 Go 1.21.0..."
            INSTALL_GO_FROM_SOURCE=1
          else
            log "当前 Go 版本 ($CURRENT_GO_VERSION) 满足要求"
          fi
        fi
        
        # 如果需要从源码安装 Go
        if [ "$INSTALL_GO_FROM_SOURCE" = "1" ]; then
          log "从源码安装 Go 1.21.0..."
          cd /tmp
          rm -f go1.21.0.linux-amd64.tar.gz
          wget "https://go.dev/dl/go1.21.0.linux-amd64.tar.gz" || error "下载 Go 1.21.0 失败"
          
          # 移除旧版本的 Go（如果存在）
          rm -rf /usr/local/go
          # 移除包管理器安装的 go（如果存在）
          rm -f /usr/bin/go /usr/bin/gofmt /usr/local/bin/go /usr/local/bin/gofmt
          
          # 安装新版本
          tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
          
          # 创建符号链接，确保优先使用新版本
          ln -sf /usr/local/go/bin/go /usr/local/bin/go
          ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
          ln -sf /usr/local/go/bin/go /usr/bin/go || true
          ln -sf /usr/local/go/bin/gofmt /usr/bin/gofmt || true
          
          rm -f go1.21.0.linux-amd64.tar.gz
          cd "$BUILD_DIR"
        fi

        # 验证 Go 安装并确认版本
        if ! command -v go >/dev/null 2>&1; then
          error "Go 语言环境安装失败"
        fi
        
        # 确保使用正确的 Go 版本（优先使用 /usr/local/go/bin）
        export PATH="/usr/local/go/bin:/usr/local/bin:$PATH"
        
        # 再次验证版本
        FINAL_GO_VERSION=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo "unknown")
        log "确认 Go 版本: $FINAL_GO_VERSION"
        
        if [ "$FINAL_GO_VERSION" = "unknown" ] || [ -z "$FINAL_GO_VERSION" ]; then
          error "无法获取 Go 版本信息"
        fi
        
        # 验证版本是否满足要求
        REQUIRED_GO_VERSION="1.19"
        if [ "$(printf '%s\n' "$REQUIRED_GO_VERSION" "$FINAL_GO_VERSION" | sort -V | head -n1)" != "$REQUIRED_GO_VERSION" ]; then
          error "Go 版本 ($FINAL_GO_VERSION) 仍然不满足要求 (需要 1.19+)"
        fi

        # 设置 Go 环境变量
        export GOPATH="$HOME/go"
        export PATH="/usr/local/go/bin:$GOPATH/bin:$PATH"
        export GO111MODULE=on
        export GOPROXY=direct

        # 下载源码包
        if ! wget "https://github.com/maxmind/geoipupdate/archive/refs/tags/v${GEOIPUPDATE_VERSION}.tar.gz"; then
          error "无法下载 geoipupdate 源码包"
        fi

        tar xzf "v${GEOIPUPDATE_VERSION}.tar.gz"
        cd "geoipupdate-${GEOIPUPDATE_VERSION}"

        # 在构建前再次验证 Go 版本
        log "构建前验证 Go 版本..."
        export PATH="/usr/local/go/bin:/usr/local/bin:$PATH"
        BUILD_GO_VERSION=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo "unknown")
        log "构建使用的 Go 版本: $BUILD_GO_VERSION"
        
        if [ "$BUILD_GO_VERSION" = "unknown" ] || [ -z "$BUILD_GO_VERSION" ]; then
          error "无法获取 Go 版本信息，无法继续构建"
        fi
        
        REQUIRED_GO_VERSION="1.19"
        if [ "$(printf '%s\n' "$REQUIRED_GO_VERSION" "$BUILD_GO_VERSION" | sort -V | head -n1)" != "$REQUIRED_GO_VERSION" ]; then
          error "Go 版本 ($BUILD_GO_VERSION) 不满足要求 (需要 1.19+)，无法构建 geoipupdate"
        fi

        # 清理 Go 模块缓存
        go clean -modcache

        # 修改 go.mod 文件以使用兼容的 Go 版本
        if [ -f "go.mod" ]; then
          # 备份原文件
          cp go.mod go.mod.bak

          # 修改 Go 版本要求 - 保持原版本，不降级
          sed -i '/toolchain/d' go.mod
          sed -i '/retract/d' go.mod

          log "go.mod 文件已修改"
        fi

        # 直接使用 make 构建
        make -j"$MAKE_JOBS"

        # 手动安装文件
        log "安装 geoipupdate 文件..."
        mkdir -p /usr/local/bin
        mkdir -p /usr/local/etc
        mkdir -p /usr/local/share/man/man1
        mkdir -p /usr/local/share/man/man5

        # 复制可执行文件
        cp build/geoipupdate /usr/local/bin/
        chmod +x /usr/local/bin/geoipupdate

        # 复制配置文件
        cp build/GeoIP.conf /usr/local/etc/
        chmod 644 /usr/local/etc/GeoIP.conf

        # 复制手册页
        if [ -f build/geoipupdate.1 ]; then
          cp build/geoipupdate.1 /usr/local/share/man/man1/
          chmod 644 /usr/local/share/man/man1/geoipupdate.1
        fi
        if [ -f build/GeoIP.conf.5 ]; then
          cp build/GeoIP.conf.5 /usr/local/share/man/man5/
          chmod 644 /usr/local/share/man/man5/GeoIP.conf.5
        fi

        # 创建符号链接
        ln -sf /usr/local/bin/geoipupdate /usr/bin/geoipupdate || true

        # 更新手册页缓存
        mandb || true
        ;;
      centos|rhel|fedora|rocky|almalinux)
        log "在 CentOS/RHEL 系统上从源码编译安装 geoipupdate..."
        cd "$BUILD_DIR"

        # 安装 Go 语言环境
        log "安装 Go 语言环境..."
        INSTALL_GO_FROM_SOURCE=0
        
        if ! command -v go >/dev/null 2>&1; then
          # 尝试通过包管理器安装
          log "通过包管理器安装 Go..."
          if command -v dnf >/dev/null 2>&1; then
            dnf install -y golang pandoc || {
              log "通过包管理器安装 Go 失败，尝试从源码安装..."
              INSTALL_GO_FROM_SOURCE=1
            }
          else
            yum install -y golang pandoc || {
              log "通过包管理器安装 Go 失败，尝试从源码安装..."
              INSTALL_GO_FROM_SOURCE=1
            }
          fi
        fi
        
        # 检查当前 Go 版本（无论从哪个分支安装的）
        if command -v go >/dev/null 2>&1; then
          CURRENT_GO_VERSION=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo "0.0")
          REQUIRED_GO_VERSION="1.19"
          
          # 比较版本
          if [ -z "$CURRENT_GO_VERSION" ] || [ "$(printf '%s\n' "$REQUIRED_GO_VERSION" "$CURRENT_GO_VERSION" | sort -V | head -n1)" != "$REQUIRED_GO_VERSION" ]; then
            log "当前 Go 版本 ($CURRENT_GO_VERSION) 不兼容，需要 Go 1.19+，从源码安装 Go 1.21.0..."
            INSTALL_GO_FROM_SOURCE=1
          else
            log "当前 Go 版本 ($CURRENT_GO_VERSION) 满足要求"
          fi
        fi
        
        # 如果需要从源码安装 Go
        if [ "$INSTALL_GO_FROM_SOURCE" = "1" ]; then
          log "从源码安装 Go 1.21.0..."
          cd /tmp
          rm -f go1.21.0.linux-amd64.tar.gz
          wget "https://go.dev/dl/go1.21.0.linux-amd64.tar.gz" || error "下载 Go 1.21.0 失败"
          
          # 移除旧版本的 Go（如果存在）
          rm -rf /usr/local/go
          # 移除包管理器安装的 go（如果存在）
          rm -f /usr/bin/go /usr/bin/gofmt /usr/local/bin/go /usr/local/bin/gofmt
          
          # 安装新版本
          tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
          
          # 创建符号链接，确保优先使用新版本
          ln -sf /usr/local/go/bin/go /usr/local/bin/go
          ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
          ln -sf /usr/local/go/bin/go /usr/bin/go || true
          ln -sf /usr/local/go/bin/gofmt /usr/bin/gofmt || true
          
          rm -f go1.21.0.linux-amd64.tar.gz
          cd "$BUILD_DIR"
        fi

        # 验证 Go 安装并确认版本
        if ! command -v go >/dev/null 2>&1; then
          error "Go 语言环境安装失败"
        fi
        
        # 确保使用正确的 Go 版本（优先使用 /usr/local/go/bin）
        export PATH="/usr/local/go/bin:/usr/local/bin:$PATH"
        
        # 再次验证版本
        FINAL_GO_VERSION=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo "unknown")
        log "确认 Go 版本: $FINAL_GO_VERSION"
        
        if [ "$FINAL_GO_VERSION" = "unknown" ] || [ -z "$FINAL_GO_VERSION" ]; then
          error "无法获取 Go 版本信息"
        fi
        
        # 验证版本是否满足要求
        REQUIRED_GO_VERSION="1.19"
        if [ "$(printf '%s\n' "$REQUIRED_GO_VERSION" "$FINAL_GO_VERSION" | sort -V | head -n1)" != "$REQUIRED_GO_VERSION" ]; then
          error "Go 版本 ($FINAL_GO_VERSION) 仍然不满足要求 (需要 1.19+)"
        fi

        # 设置 Go 环境变量
        export GOPATH="$HOME/go"
        export PATH="/usr/local/go/bin:$GOPATH/bin:$PATH"
        export GO111MODULE=on
        export GOPROXY=direct

        # 下载源码包
        if ! wget "https://github.com/maxmind/geoipupdate/archive/refs/tags/v${GEOIPUPDATE_VERSION}.tar.gz"; then
          error "无法下载 geoipupdate 源码包"
        fi

        tar xzf "v${GEOIPUPDATE_VERSION}.tar.gz"
        cd "geoipupdate-${GEOIPUPDATE_VERSION}"

        # 在构建前再次验证 Go 版本
        log "构建前验证 Go 版本..."
        export PATH="/usr/local/go/bin:/usr/local/bin:$PATH"
        BUILD_GO_VERSION=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo "unknown")
        log "构建使用的 Go 版本: $BUILD_GO_VERSION"
        
        if [ "$BUILD_GO_VERSION" = "unknown" ] || [ -z "$BUILD_GO_VERSION" ]; then
          error "无法获取 Go 版本信息，无法继续构建"
        fi
        
        REQUIRED_GO_VERSION="1.19"
        if [ "$(printf '%s\n' "$REQUIRED_GO_VERSION" "$BUILD_GO_VERSION" | sort -V | head -n1)" != "$REQUIRED_GO_VERSION" ]; then
          error "Go 版本 ($BUILD_GO_VERSION) 不满足要求 (需要 1.19+)，无法构建 geoipupdate"
        fi

        # 清理 Go 模块缓存
        go clean -modcache

        # 修改 go.mod 文件以使用兼容的 Go 版本
        if [ -f "go.mod" ]; then
          # 备份原文件
          cp go.mod go.mod.bak

          # 修改 Go 版本要求 - 保持原版本，不降级
          sed -i '/toolchain/d' go.mod
          sed -i '/retract/d' go.mod

          log "go.mod 文件已修改"
        fi

        # 安装编译依赖
        if command -v dnf >/dev/null 2>&1; then
          dnf install -y gcc make automake libtool
        else
          yum install -y gcc make automake libtool
        fi

        # 直接使用 make 构建
        make -j"$MAKE_JOBS"

        # 手动安装文件
        log "安装 geoipupdate 文件..."
        mkdir -p /usr/local/bin
        mkdir -p /usr/local/etc
        mkdir -p /usr/local/share/man/man1
        mkdir -p /usr/local/share/man/man5

        # 复制可执行文件
        cp build/geoipupdate /usr/local/bin/
        chmod +x /usr/local/bin/geoipupdate

        # 复制配置文件
        cp build/GeoIP.conf /usr/local/etc/
        chmod 644 /usr/local/etc/GeoIP.conf

        # 复制手册页
        if [ -f build/geoipupdate.1 ]; then
          cp build/geoipupdate.1 /usr/local/share/man/man1/
          chmod 644 /usr/local/share/man/man1/geoipupdate.1
        fi
        if [ -f build/GeoIP.conf.5 ]; then
          cp build/GeoIP.conf.5 /usr/local/share/man/man5/
          chmod 644 /usr/local/share/man/man5/GeoIP.conf.5
        fi

        # 创建符号链接
        ln -sf /usr/local/bin/geoipupdate /usr/bin/geoipupdate || true

        # 更新手册页缓存
        mandb || true
        ;;
      *)
        warn "无法自动安装geoipupdate，请手动安装后继续"
        log "您可以从https://github.com/maxmind/geoipupdate/releases下载安装"
        if ! command -v geoipupdate &> /dev/null; then
          warn "未找到geoipupdate，跳过自动更新设置"
          return 1
        fi
        ;;
    esac
  fi

  # 创建必要的目录
  log "创建必要的目录..."
  mkdir -p "${GEOIP_DIR}"
  mkdir -p /usr/local/etc
  mkdir -p /usr/local/var/GeoIP

  # 设置目录权限
  chmod 755 "${GEOIP_DIR}"
  chmod 755 /usr/local/var/GeoIP

  # 生成配置文件
  log "生成 GeoIP 配置文件..."
  cat << EOF | tee /usr/local/etc/GeoIP.conf > /dev/null
# GeoIP Update Configuration
# 由ModSecurity安装脚本自动生成 $(date)

# MaxMind账户信息
AccountID ${MAXMIND_ACCOUNT_ID}
LicenseKey ${MAXMIND_LICENSE_KEY}

# 需要更新的数据库
EditionIDs GeoLite2-Country GeoLite2-City

# 数据库目录
DatabaseDirectory ${GEOIP_DIR}

# 其他设置
LockFile /usr/local/var/GeoIP/.geoipupdate.lock
EOF

  # 设置配置文件权限
  chmod 644 /usr/local/etc/GeoIP.conf

  # 首次更新数据库
  log "执行首次 GeoIP 数据库更新..."
  if ! geoipupdate -v; then
    warn "首次数据库更新失败，请检查配置和网络连接"
  else
    log "首次数据库更新成功"
  fi

  # 设置定时任务
  log "设置定时更新任务..."
  CRON_FILE="/etc/cron.d/geoipupdate"

  # 根据更新频率设置 cron 表达式
  case "$GEOIP_UPDATE_FREQUENCY" in
    "daily")
      CRON_SCHEDULE="0 3 * * *"
      ;;
    "weekly")
      CRON_SCHEDULE="0 3 * * 1"
      ;;
    "monthly")
      CRON_SCHEDULE="0 3 1 * *"
      ;;
    *)
      warn "未知的更新频率: $GEOIP_UPDATE_FREQUENCY，使用每周更新"
      CRON_SCHEDULE="0 3 * * 1"
      ;;
  esac

  # 创建 cron 任务文件
  cat << EOF | tee "$CRON_FILE" > /dev/null
# GeoIP 数据库自动更新
# 由 ModSecurity 安装脚本自动生成 $(date)
${CRON_SCHEDULE} root /usr/local/bin/geoipupdate -v >> /var/log/geoipupdate.log 2>&1
EOF

  chmod 644 "$CRON_FILE"

  # 创建日志文件
  touch /var/log/geoipupdate.log
  chmod 644 /var/log/geoipupdate.log

  log "GeoIP 更新设置完成"
  log "配置文件位置: /usr/local/etc/GeoIP.conf"
  log "数据库目录: ${GEOIP_DIR}"
  log "更新日志: /var/log/geoipupdate.log"
  log "定时任务: ${CRON_FILE}"
  log "更新频率: ${GEOIP_UPDATE_FREQUENCY}"

  return 0
}

# 编译安装函数
compile_libmaxminddb() {
  log "编译安装 libmaxminddb $LIBMAXMINDDB_VERSION..."
  cd "$BUILD_DIR"
  wget "https://github.com/maxmind/libmaxminddb/releases/download/$LIBMAXMINDDB_VERSION/libmaxminddb-$LIBMAXMINDDB_VERSION.tar.gz"
  tar xzf "libmaxminddb-$LIBMAXMINDDB_VERSION.tar.gz"
  cd "libmaxminddb-$LIBMAXMINDDB_VERSION"

  ./configure --prefix=/usr/local
  make -j"$MAKE_JOBS"
  make install
  ldconfig

  # 创建符号链接
  ln -sf /usr/local/lib/libmaxminddb.so.0 /usr/lib64/libmaxminddb.so.0 || true
  ln -sf /usr/local/lib/libmaxminddb.so.0 /usr/lib/libmaxminddb.so.0 || true
  log "libmaxminddb 安装完成"
}

compile_geoip() {
  log "编译安装 GeoIP 支持..."
  cd "$BUILD_DIR"

  # 检查并编译安装 libmaxminddb
  if ! check_lib maxminddb || ! check_dev libmaxminddb; then
    log "libmaxminddb 未安装，开始编译安装..."
    cd "$BUILD_DIR"
    wget "https://github.com/maxmind/libmaxminddb/releases/download/$LIBMAXMINDDB_VERSION/libmaxminddb-$LIBMAXMINDDB_VERSION.tar.gz"
    tar xzf "libmaxminddb-$LIBMAXMINDDB_VERSION.tar.gz"
    cd "libmaxminddb-$LIBMAXMINDDB_VERSION"

    ./configure --prefix=/usr/local
    make -j"$MAKE_JOBS"
    make install
    ldconfig

    # 创建符号链接
    ln -sf /usr/local/lib/libmaxminddb.so.0 /usr/lib64/libmaxminddb.so.0 || true
    ln -sf /usr/local/lib/libmaxminddb.so.0 /usr/lib/libmaxminddb.so.0 || true
  else
    log "libmaxminddb 已安装，跳过编译"
  fi

  # 检查 geoipupdate
  if ! check_command geoipupdate; then
    log "geoipupdate 未安装，开始安装..."
    cd "$BUILD_DIR"
    wget "https://github.com/maxmind/geoipupdate/releases/download/v$GEOIPUPDATE_VERSION/geoipupdate_${GEOIPUPDATE_VERSION}_linux_amd64.tar.gz"
    tar xzf "geoipupdate_${GEOIPUPDATE_VERSION}_linux_amd64.tar.gz"

    # 检查解压后的目录结构
    if [ -f "geoipupdate_${GEOIPUPDATE_VERSION}_linux_amd64/geoipupdate" ]; then
      cp "geoipupdate_${GEOIPUPDATE_VERSION}_linux_amd64/geoipupdate" /usr/local/bin/
    elif [ -f "geoipupdate" ]; then
      cp "geoipupdate" /usr/local/bin/
    else
      error "无法找到 geoipupdate 可执行文件"
    fi

    chmod +x /usr/local/bin/geoipupdate

    # 验证安装
    if ! command -v geoipupdate >/dev/null 2>&1; then
      error "geoipupdate 安装失败"
    fi
  else
    log "geoipupdate 已安装，跳过安装"
  fi

  # 创建 GeoIP 配置
  if [ ! -f /etc/GeoIP.conf ]; then
    log "创建 GeoIP 配置文件..."
    mkdir -p /etc
    cat << EOF | tee /etc/GeoIP.conf > /dev/null
# GeoIP Update Configuration
# 由ModSecurity安装脚本自动生成 $(date)

# MaxMind账户信息
AccountID 149923
LicenseKey yvUg6Atv3ZT6tZ9p

# 需要更新的数据库
EditionIDs GeoLite2-Country GeoLite2-City

# 数据库目录
DatabaseDirectory /usr/local/share/GeoIP
EOF
  fi

  # 创建数据库目录
  mkdir -p /usr/local/share/GeoIP

  # 执行一次更新
  log "更新 GeoIP 数据库..."
  if ! sudo /usr/local/bin/geoipupdate -f /etc/GeoIP.conf -v 2>&1 | tee -a "$LOG_FILE"; then
    error "GeoIP 数据库更新失败，请检查日志文件: $LOG_FILE"
  fi

  log "GeoIP 数据库更新成功"
}

compile_yajl() {
  log "编译安装 YAJL $YAJL_VERSION..."

  # 检查并安装 CMake
  if ! command -v cmake >/dev/null 2>&1; then
    log "安装 CMake..."
    if [ -f /etc/debian_version ]; then
      apt-get update
      apt-get install -y cmake
    elif [ -f /etc/redhat-release ]; then
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y cmake
      else
        yum install -y cmake
      fi
    else
      error "无法自动安装 CMake，请手动安装后重试"
    fi
  fi

  cd "$BUILD_DIR"

  # 尝试多个下载源
  if ! wget "https://github.com/lloyd/yajl/archive/refs/tags/$YAJL_VERSION.tar.gz" -O yajl.tar.gz; then
    log "尝试备用下载源..."
    if ! wget "https://codeload.github.com/lloyd/yajl/tar.gz/refs/tags/$YAJL_VERSION" -O yajl.tar.gz; then
      error "无法下载 YAJL"
    fi
  fi

  # 验证下载的文件
  if ! file yajl.tar.gz | grep -q "gzip compressed data"; then
    error "下载的 YAJL 文件格式不正确"
  fi

  tar xzf yajl.tar.gz
  cd "yajl-$YAJL_VERSION"

  # 使用 CMake 构建
  mkdir build
  cd build
  cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local
  make -j"$MAKE_JOBS"
  make install
  ldconfig
  log "YAJL 安装完成"
}

compile_lua() {
  log "编译安装 Lua $LUA_VERSION..."
  cd "$BUILD_DIR"
  wget "https://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz"
  tar xzf "lua-$LUA_VERSION.tar.gz"
  cd "lua-$LUA_VERSION"
  make -j"$MAKE_JOBS" linux
  make install
  ldconfig
  log "Lua 安装完成"
}

# 编译安装 LMDB
compile_lmdb() {
  log "编译安装 LMDB $LMDB_VERSION..."
  cd "$BUILD_DIR"
  wget "https://github.com/LMDB/lmdb/archive/refs/tags/LMDB_$LMDB_VERSION.tar.gz"
  tar xzf "LMDB_$LMDB_VERSION.tar.gz"
  cd "lmdb-LMDB_$LMDB_VERSION/libraries/liblmdb"

  make -j"$MAKE_JOBS"
  make install
  ldconfig
  log "LMDB 安装完成"
}

# 编译安装 SSDEEP
compile_ssdeep() {
  log "编译安装 SSDEEP $SSDEEP_VERSION..."
  cd "$BUILD_DIR"
  wget "https://github.com/ssdeep-project/ssdeep/releases/download/release-$SSDEEP_VERSION/ssdeep-$SSDEEP_VERSION.tar.gz"
  tar xzf "ssdeep-$SSDEEP_VERSION.tar.gz"
  cd "ssdeep-$SSDEEP_VERSION"

  ./configure --prefix=/usr/local
  make -j"$MAKE_JOBS"
  make install
  ldconfig
  log "SSDEEP 安装完成"
}

# 检查并编译安装依赖
compile_dependencies() {
  log "开始检查依赖..."

  # 创建临时构建目录
  mkdir -p "$BUILD_DIR"

  # 检查并编译安装 git
  if ! check_command git; then
    log "Git 未安装，开始编译安装..."
    compile_git
  else
    log "Git 已安装，跳过编译"
  fi

  # 确保 PATH 包含 /usr/local/bin
  export PATH="/usr/local/bin:$PATH"

  # 验证 git 安装
  if ! command -v git >/dev/null 2>&1; then
    error "Git 安装失败，请检查日志: $LOG_FILE"
  fi

  # 检查并编译安装 libmaxminddb
  if ! check_lib maxminddb || ! check_dev libmaxminddb; then
    log "libmaxminddb 未安装，开始编译安装..."
    cd "$BUILD_DIR"
    wget "https://github.com/maxmind/libmaxminddb/releases/download/$LIBMAXMINDDB_VERSION/libmaxminddb-$LIBMAXMINDDB_VERSION.tar.gz"
    tar xzf "libmaxminddb-$LIBMAXMINDDB_VERSION.tar.gz"
    cd "libmaxminddb-$LIBMAXMINDDB_VERSION"

    ./configure --prefix=/usr/local
    make -j"$MAKE_JOBS"
    make install
    ldconfig

    # 创建符号链接
    ln -sf /usr/local/lib/libmaxminddb.so.0 /usr/lib64/libmaxminddb.so.0 || true
    ln -sf /usr/local/lib/libmaxminddb.so.0 /usr/lib/libmaxminddb.so.0 || true
  else
    log "libmaxminddb 已安装，跳过编译"
  fi

  # 检查并编译安装 LMDB
  if ! check_lib lmdb || ! check_dev lmdb; then
    log "LMDB 未安装，开始编译安装..."
    compile_lmdb
  else
    log "LMDB 已安装，跳过编译"
  fi

  # 检查并编译安装 SSDEEP
  if ! check_lib fuzzy || ! check_dev fuzzy; then
    log "SSDEEP 未安装，开始编译安装..."
    compile_ssdeep
  else
    log "SSDEEP 已安装，跳过编译"
  fi

  # 检查并编译安装 YAJL
  if ! check_lib yajl || ! check_dev yajl; then
    log "YAJL 未安装，开始编译安装..."
    compile_yajl
  else
    log "YAJL 已安装，跳过编译"
  fi

  # 检查并编译安装 Lua
  if ! check_lib lua || ! check_dev lua; then
    log "Lua 未安装，开始编译安装..."
    compile_lua
  else
    log "Lua 已安装，跳过编译"
  fi

  # 清理构建目录
  rm -rf "$BUILD_DIR"
  log "依赖检查完成"
}

# 安装基础工具
install_basic_tools() {
  log "安装基础工具..."

  # 检测系统类型
  if [ -f /etc/debian_version ]; then
    log "检测到 Debian/Ubuntu 系统"
    apt-get update
    apt-get install -y build-essential wget tar gzip git gcc g++
    # 检查 gcc 版本
    GCC_VERSION=$(gcc --version | head -n1 | awk '{print $3}' | cut -d. -f1)
    log "检测到 GCC 版本: $GCC_VERSION"
  elif [ -f /etc/redhat-release ]; then
    log "检测到 RedHat/CentOS 系统"
    if command -v dnf >/dev/null 2>&1; then
      log "使用 dnf 安装基础工具"
      dnf install -y gcc gcc-c++ make wget tar gzip git
    else
      log "使用 yum 安装基础工具"
      yum install -y gcc gcc-c++ make wget tar gzip git
    fi
  else
    error "不支持的系统类型"
  fi

  # 验证基础工具安装
  for cmd in gcc g++ make wget tar gzip git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      error "基础工具 $cmd 安装失败"
    fi
  done

  log "基础工具安装完成"
}

# 设置终端颜色和别名
setup_terminal() {
  log "设置终端颜色和别名..."

  # 创建或修改 .bashrc
  if [ -f /root/.bashrc ]; then
    # 备份现有的 .bashrc
    cp /root/.bashrc /root/.bashrc.bak.$(date +%Y%m%d%H%M%S)

    # 添加颜色设置和别名
    cat << 'EOF' >> /root/.bashrc

# ===== 终端颜色设置 (Mocano风格) =====
# 颜色定义
export TERM=xterm-256color
export CLICOLOR=1
export LSCOLORS=ExGxBxDxCxEgEdxbxgxcxd

# 提示符颜色
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# 目录颜色
export LS_COLORS='di=1;34:ln=1;36:so=1;32:pi=1;33:ex=1;31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'

# 常用别名
alias ll='ls -l --color=auto'
alias la='ls -la --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# 设置 less 的颜色
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

# 设置 man 页面的颜色
export MANPAGER="less -R --use-color -Dd+r -Du+b"
EOF
  fi

  # 如果存在 .zshrc，也添加相同的设置
  if [ -f /root/.zshrc ]; then
    # 备份现有的 .zshrc
    cp /root/.zshrc /root/.zshrc.bak.$(date +%Y%m%d%H%M%S)

    # 添加颜色设置和别名
    cat << 'EOF' >> /root/.zshrc

# ===== 终端颜色设置 (Mocano风格) =====
# 颜色定义
export TERM=xterm-256color
export CLICOLOR=1
export LSCOLORS=ExGxBxDxCxEgEdxbxgxcxd

# 提示符颜色
PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '

# 目录颜色
export LS_COLORS='di=1;34:ln=1;36:so=1;32:pi=1;33:ex=1;31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'

# 常用别名
alias ll='ls -l --color=auto'
alias la='ls -la --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# 设置 less 的颜色
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

# 设置 man 页面的颜色
export MANPAGER="less -R --use-color -Dd+r -Du+b"
EOF
  fi

  # 为当前用户也设置相同的配置
  if [ "$(whoami)" != "root" ]; then
    USER_HOME=$(eval echo ~$(whoami))

    # 设置 .bashrc
    if [ -f "$USER_HOME/.bashrc" ]; then
      cp "$USER_HOME/.bashrc" "$USER_HOME/.bashrc.bak.$(date +%Y%m%d%H%M%S)"
      cat << 'EOF' >> "$USER_HOME/.bashrc"

# ===== 终端颜色设置 (Mocano风格) =====
# 颜色定义
export TERM=xterm-256color
export CLICOLOR=1
export LSCOLORS=ExGxBxDxCxEgEdxbxgxcxd

# 提示符颜色
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# 目录颜色
export LS_COLORS='di=1;34:ln=1;36:so=1;32:pi=1;33:ex=1;31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'

# 常用别名
alias ll='ls -l --color=auto'
alias la='ls -la --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# 设置 less 的颜色
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

# 设置 man 页面的颜色
export MANPAGER="less -R --use-color -Dd+r -Du+b"
EOF
    fi

    # 设置 .zshrc
    if [ -f "$USER_HOME/.zshrc" ]; then
      cp "$USER_HOME/.zshrc" "$USER_HOME/.zshrc.bak.$(date +%Y%m%d%H%M%S)"
      cat << 'EOF' >> "$USER_HOME/.zshrc"

# ===== 终端颜色设置 (Mocano风格) =====
# 颜色定义
export TERM=xterm-256color
export CLICOLOR=1
export LSCOLORS=ExGxBxDxCxEgEdxbxgxcxd

# 提示符颜色
PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '

# 目录颜色
export LS_COLORS='di=1;34:ln=1;36:so=1;32:pi=1;33:ex=1;31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'

# 常用别名
alias ll='ls -l --color=auto'
alias la='ls -la --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# 设置 less 的颜色
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

# 设置 man 页面的颜色
export MANPAGER="less -R --use-color -Dd+r -Du+b"
EOF
    fi
  fi

  # 创建全局配置文件
  cat << 'EOF' | tee /etc/profile.d/terminal-colors.sh > /dev/null
# ===== 终端颜色设置 (Mocano风格) =====
# 颜色定义
export TERM=xterm-256color
export CLICOLOR=1
export LSCOLORS=ExGxBxDxCxEgEdxbxgxcxd

# 目录颜色
export LS_COLORS='di=1;34:ln=1;36:so=1;32:pi=1;33:ex=1;31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'

# 设置 less 的颜色
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

# 设置 man 页面的颜色
export MANPAGER="less -R --use-color -Dd+r -Du+b"
EOF

  chmod +x /etc/profile.d/terminal-colors.sh

  log "终端颜色和别名设置完成"
  log "请重新登录或运行 'source /etc/profile.d/terminal-colors.sh' 使设置生效"
}

# 设置基本安全配置
setup_security() {
  log "设置基本安全配置..."

  # 检测系统类型
  if [ -f /etc/debian_version ]; then
    SYSTEM_TYPE="debian"
    LOG_PATH="/var/log/auth.log"
  elif [ -f /etc/redhat-release ]; then
    SYSTEM_TYPE="redhat"
    LOG_PATH="/var/log/secure"
  else
    warn "未知的系统类型，跳过安全设置"
    return 1
  fi

  # 创建文档目录
  mkdir -p /usr/local/share/doc/modsecurity

  # 安装 fail2ban
  if ! command -v fail2ban >/dev/null 2>&1; then
    log "安装 fail2ban..."
    case "$SYSTEM_TYPE" in
      debian)
        apt-get update
        apt-get install -y fail2ban
        ;;
      redhat)
        if command -v dnf >/dev/null 2>&1; then
          dnf install -y epel-release
          dnf install -y fail2ban
        else
          yum install -y epel-release
          yum install -y fail2ban
        fi
        ;;
    esac
  fi

  # 配置 fail2ban
  if [ -f /etc/fail2ban/jail.local ]; then
    mv /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak.$(date +%Y%m%d%H%M%S)
  fi

  # 确保 fail2ban 配置目录存在
  mkdir -p /etc/fail2ban

  cat << EOF | tee /etc/fail2ban/jail.local > /dev/null
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sender = fail2ban@localhost
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = ${LOG_PATH}
maxretry = 3
findtime = 300
bantime = 3600

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
findtime = 300
bantime = 3600

[nginx-botsearch]
enabled = true
filter = nginx-botsearch
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2
findtime = 300
bantime = 3600
EOF

  # 启动 fail2ban
  case "$SYSTEM_TYPE" in
    debian)
      systemctl enable fail2ban
      systemctl restart fail2ban
      ;;
    redhat)
      if command -v systemctl >/dev/null 2>&1; then
        systemctl enable fail2ban
        systemctl restart fail2ban
      else
        chkconfig fail2ban on
        service fail2ban restart
      fi
      ;;
  esac

  # 配置 SSH
  if [ -f /etc/ssh/sshd_config ]; then
    # 备份原配置
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)

    # 修改 SSH 配置
    sed -i 's/#PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config

    # 重启 SSH 服务
    case "$SYSTEM_TYPE" in
      debian)
        systemctl restart sshd
        ;;
      redhat)
        if command -v systemctl >/dev/null 2>&1; then
          systemctl restart sshd
        else
          service sshd restart
        fi
        ;;
    esac
  fi

  # 创建使用说明文件
  cat << 'EOF' | tee /usr/local/share/doc/modsecurity/security-setup.txt > /dev/null
ModSecurity 安全设置说明
=====================

1. Fail2ban 配置
---------------
- 配置文件位置: /etc/fail2ban/jail.local
- 日志文件位置: /var/log/fail2ban.log
- 已配置的防护:
  * SSH 登录保护
  * Nginx HTTP 认证保护
  * Nginx 机器人扫描保护

常用命令:
- 查看状态: fail2ban-client status
- 查看特定 jail 状态: fail2ban-client status sshd
- 解封 IP: fail2ban-client set sshd unbanip <IP地址>
- 查看日志: tail -f /var/log/fail2ban.log

2. SSH 安全配置
--------------
- 配置文件位置: /etc/ssh/sshd_config
- 已启用的安全选项:
  * 禁止密码登录
  * 限制 root 登录
  * 限制最大认证尝试次数

3. 系统兼容性
------------
支持的系统:
- Debian/Ubuntu
- CentOS/RHEL/Fedora
- Rocky Linux/AlmaLinux

4. 故障排除
----------
如果遇到 SSH 登录问题:
1. 检查 fail2ban 状态: systemctl status fail2ban
2. 检查 SSH 服务状态: systemctl status sshd
3. 查看系统日志: journalctl -xe
4. 检查 fail2ban 日志: tail -f /var/log/fail2ban.log

5. 安全建议
----------
1. 定期更新系统和安全补丁
2. 监控 fail2ban 日志
3. 定期检查系统日志
4. 保持 SSH 密钥的安全
5. 定期备份配置文件

6. 配置文件备份
-------------
- SSH 配置备份: /etc/ssh/sshd_config.bak.*
- Fail2ban 配置备份: /etc/fail2ban/jail.local.bak.*

7. 紧急恢复
---------
如果需要恢复 SSH 配置:
1. 使用备份文件: cp /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config
2. 重启 SSH 服务: systemctl restart sshd

如果需要恢复 Fail2ban 配置:
1. 使用备份文件: cp /etc/fail2ban/jail.local.bak.* /etc/fail2ban/jail.local
2. 重启 Fail2ban: systemctl restart fail2ban
EOF

  # 设置文档权限
  chmod 644 /usr/local/share/doc/modsecurity/security-setup.txt

  log "基本安全配置完成"
  log "详细使用说明已保存到: /usr/local/share/doc/modsecurity/security-setup.txt"
  log "请仔细阅读使用说明，特别是故障排除和紧急恢复部分"
}

# 优化内核配置
optimize_kernel() {
  log "开始优化内核配置..."

  # 检测系统类型
  if [ -f /etc/debian_version ]; then
    SYSTEM_TYPE="debian"
    DEBIAN_VERSION=$(cat /etc/debian_version | cut -d. -f1)
  elif [ -f /etc/redhat-release ]; then
    SYSTEM_TYPE="redhat"
  else
    warn "未知的系统类型，跳过内核优化"
    return 1
  fi

  # 创建内核优化文档目录
  mkdir -p /usr/local/share/doc/modsecurity

  # 备份当前内核参数
  log "备份当前内核参数..."
  sysctl -a > /usr/local/share/doc/modsecurity/sysctl.conf.bak.$(date +%Y%m%d%H%M%S)

  # 安装 BBR 内核
  case "$SYSTEM_TYPE" in
    debian)
      log "在 Debian 系统上安装 BBR 内核..."
      apt-get update

      # 检查当前内核版本
      CURRENT_KERNEL=$(uname -r)
      log "当前内核版本: $CURRENT_KERNEL"

      # 检查是否已经支持 BBR
      if grep -q "tcp_bbr" /proc/sys/net/ipv4/tcp_available_congestion_control; then
        log "当前内核已支持 BBR，无需安装新内核"
      else
        # 根据 Debian 版本安装对应的内核
        case "$DEBIAN_VERSION" in
          11|12)
            log "安装 Debian $DEBIAN_VERSION 内核..."
            apt-get install -y linux-image-amd64
            ;;
          10)
            log "安装 Debian 10 内核..."
            apt-get install -y linux-image-amd64
            ;;
          *)
            log "尝试安装最新内核..."
            apt-get install -y linux-image-amd64
            ;;
        esac
      fi
      ;;
    redhat)
      log "在 RedHat/CentOS 系统上安装 BBR 内核..."
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y kernel-ml
      else
        # 添加 ELRepo 仓库
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
        if [ -f /etc/redhat-release ] && grep -q "release 7" /etc/redhat-release; then
          rpm -Uvh https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
        elif [ -f /etc/redhat-release ] && grep -q "release 8" /etc/redhat-release; then
          rpm -Uvh https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm
        fi
        yum install -y kernel-ml
      fi
      ;;
  esac

  # 确保 sysctl.d 目录存在
  mkdir -p /etc/sysctl.d

  # 配置内核参数
  log "配置内核参数..."
  cat << 'EOF' | tee /etc/sysctl.d/99-sysctl.conf > /dev/null
# 网络优化
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# 文件系统优化
fs.file-max = 2097152
fs.nr_open = 2097152
fs.inotify.max_user_watches = 524288

# 内存优化
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2
vm.vfs_cache_pressure = 50

# 系统限制
kernel.pid_max = 65535
kernel.threads-max = 2097152
kernel.sysrq = 1
EOF

  # 应用内核参数
  sysctl -p /etc/sysctl.d/99-sysctl.conf

  # 设置默认启动内核
  case "$SYSTEM_TYPE" in
    debian)
      # 获取最新内核版本
      NEW_KERNEL=$(dpkg -l | grep linux-image | grep -v linux-image-extra | awk '{print $2}' | sort -V | tail -n1)
      if [ -n "$NEW_KERNEL" ]; then
        log "设置默认启动内核: $NEW_KERNEL"
        if command -v grub-set-default >/dev/null 2>&1; then
          grub-set-default "$NEW_KERNEL"
          update-grub
        else
          # 使用 grub2 命令
          grub2-set-default "$NEW_KERNEL"
          grub2-mkconfig -o /boot/grub2/grub.cfg
        fi
      fi
      ;;
    redhat)
      if command -v grub2-set-default >/dev/null 2>&1; then
        # 获取最新内核版本
        NEW_KERNEL=$(rpm -q kernel-ml | sort -V | tail -n1)
        if [ -n "$NEW_KERNEL" ]; then
          log "设置默认启动内核: $NEW_KERNEL"
          grub2-set-default "$NEW_KERNEL"
          grub2-mkconfig -o /boot/grub2/grub.cfg
        fi
      fi
      ;;
  esac

  # 创建使用说明文档
  cat << 'EOF' | tee /usr/local/share/doc/modsecurity/kernel-optimization.txt > /dev/null
内核优化说明
==========

1. 已安装的优化
-------------
- Google BBR 拥塞控制算法
- TCP 优化参数
- 文件系统优化
- 内存管理优化
- 系统限制优化

2. 配置文件位置
-------------
- 内核参数配置: /etc/sysctl.d/99-sysctl.conf
- 原始参数备份: /usr/local/share/doc/modsecurity/sysctl.conf.bak.*

3. 验证 BBR 是否启用
------------------
运行以下命令检查 BBR 是否启用:
sysctl net.ipv4.tcp_congestion_control

如果输出包含 "bbr"，则表示 BBR 已成功启用。

4. 系统兼容性
-----------
支持的系统:
- Debian 10/11/12
- CentOS/RHEL 7/8
- Rocky Linux/AlmaLinux

5. 故障排除
---------
如果遇到网络问题:
1. 检查当前内核参数: sysctl -a
2. 检查 BBR 状态: sysctl net.ipv4.tcp_congestion_control
3. 查看系统日志: journalctl -xe

6. 恢复默认设置
------------
如果需要恢复默认设置:
1. 使用备份文件: cp /usr/local/share/doc/modsecurity/sysctl.conf.bak.* /etc/sysctl.d/99-sysctl.conf
2. 应用更改: sysctl -p /etc/sysctl.d/99-sysctl.conf

7. 性能监控
---------
建议监控以下指标:
- 网络延迟: ping
- 网络吞吐量: iperf3
- 系统负载: top, htop
- 内存使用: free -m
- 磁盘 I/O: iostat

8. 注意事项
---------
1. 修改内核参数后需要重启系统才能完全生效
2. 建议在修改前备份重要数据
3. 如果系统出现异常，可以使用备份文件恢复
4. 定期检查系统性能，确保优化效果
EOF

  # 设置文档权限
  chmod 644 /usr/local/share/doc/modsecurity/kernel-optimization.txt

  log "内核优化完成"
  log "详细说明已保存到: /usr/local/share/doc/modsecurity/kernel-optimization.txt"
  log "请重启系统以使所有更改生效"
  log "重启后，请运行 'sysctl net.ipv4.tcp_congestion_control' 确认 BBR 已启用"
}

# 主程序
main() {
  # 检查是否为root用户
  check_root

  # 检查是否已安装
  if [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so" ]; then
    log "检测到已安装的ModSecurity"
    read -p "是否重新安装？[y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log "操作已取消，退出"
      exit 0
    fi
  fi

  # 首先安装基础工具
  install_basic_tools

  # 执行安装流程
  install_dependencies
  compile_dependencies
  build_modsecurity
  setup_geoip_updates
  verify_install
  cleanup
  show_info
  setup_terminal
  #setup_security
  optimize_kernel  # 添加内核优化

  log "ModSecurity核心库安装成功！"
}

# 开始执行
main