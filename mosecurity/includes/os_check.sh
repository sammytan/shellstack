#!/bin/bash

# =====================================================================
# 系统检测和版本检查
# =====================================================================

# 检测 Linux 发行版
detect_distro() {
  log "检测 Linux 发行版..."

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="$ID"
    DISTRO_VERSION="${VERSION_ID:-}"
  elif command -v lsb_release >/dev/null 2>&1; then
    DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    DISTRO_VERSION=$(lsb_release -sr)
  elif [ -f /etc/debian_version ]; then
    DISTRO="debian"
    DISTRO_VERSION=$(cat /etc/debian_version)
  elif [ -f /etc/redhat-release ]; then
    if grep -q "CentOS" /etc/redhat-release; then
      DISTRO="centos"
      DISTRO_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    elif grep -q "Red Hat" /etc/redhat-release; then
      DISTRO="rhel"
      DISTRO_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    elif grep -q "Rocky" /etc/redhat-release; then
      DISTRO="rocky"
      DISTRO_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    elif grep -q "AlmaLinux" /etc/redhat-release; then
      DISTRO="almalinux"
      DISTRO_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    elif grep -q "Fedora" /etc/redhat-release; then
      DISTRO="fedora"
      DISTRO_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    else
      DISTRO="rhel"
      DISTRO_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    fi
  elif [ -f /etc/arch-release ]; then
    DISTRO="arch"
  elif [ -f /etc/SuSE-release ]; then
    DISTRO="opensuse"
  else
    DISTRO="unknown"
    warn "无法识别的发行版"
  fi

  # 设置系统类型
  case "$DISTRO" in
    ubuntu|debian)
      SYSTEM_TYPE="debian"
      ;;
    centos|rhel|fedora|rocky|almalinux)
      SYSTEM_TYPE="redhat"
      ;;
    arch|manjaro)
      SYSTEM_TYPE="arch"
      ;;
    opensuse*|suse*)
      SYSTEM_TYPE="suse"
      ;;
    *)
      SYSTEM_TYPE="unknown"
      ;;
  esac

  log "检测到发行版: $DISTRO ${DISTRO_VERSION:-}(未知版本)"
  log "系统类型: $SYSTEM_TYPE"

  # 导出变量供其他模块使用
  export DISTRO DISTRO_VERSION SYSTEM_TYPE

  return 0
}

# 检查系统架构
detect_architecture() {
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)
      ARCH="amd64"
      ;;
    aarch64|arm64)
      ARCH="arm64"
      ;;
    *)
      warn "未测试的架构: $ARCH"
      ;;
  esac
  log "系统架构: $ARCH"
  export ARCH
}

# 检查系统是否支持
check_system_support() {
  case "$DISTRO" in
    ubuntu|debian|centos|rhel|fedora|rocky|almalinux|arch|manjaro|opensuse*|suse*)
      log "系统 $DISTRO 受支持"
      return 0
      ;;
    *)
      warn "系统 $DISTRO 可能不受支持，继续安装..."
      return 0
      ;;
  esac
}

# 获取包管理器
get_package_manager() {
  case "$SYSTEM_TYPE" in
    debian)
      PKG_CMD="apt"
      PKG_UPDATE="apt-get update"
      PKG_INSTALL="apt-get install -y"
      ;;
    redhat)
      if check_command dnf; then
        PKG_CMD="dnf"
        PKG_UPDATE="dnf check-update || true"
        PKG_INSTALL="dnf install -y"
      else
        PKG_CMD="yum"
        PKG_UPDATE="yum check-update || true"
        PKG_INSTALL="yum install -y"
      fi
      ;;
    arch)
      PKG_CMD="pacman"
      PKG_UPDATE="pacman -Syu --noconfirm"
      PKG_INSTALL="pacman -S --noconfirm"
      ;;
    suse)
      PKG_CMD="zypper"
      PKG_UPDATE="zypper refresh"
      PKG_INSTALL="zypper install -y"
      ;;
    *)
      warn "无法确定包管理器"
      PKG_CMD="unknown"
      ;;
  esac

  export PKG_CMD PKG_UPDATE PKG_INSTALL
  log "包管理器: $PKG_CMD"
}

# 初始化系统检测
init_os_check() {
  detect_distro
  detect_architecture
  check_system_support
  get_package_manager
}

