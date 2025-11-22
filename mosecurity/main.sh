#!/bin/bash

# =====================================================================
# ModSecurity 核心库安装脚本 - 主入口文件
# 支持多系统多版本的 ModSecurity 安装
# =====================================================================

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INCLUDES_DIR="$SCRIPT_DIR/includes"

# 加载共享配置和工具函数
source "$INCLUDES_DIR/shared.sh"

# 功能开关（默认配置）
ENABLE_GEOIP=0
ENABLE_SECURITY=0
ENABLE_OPENRESTY=0
ENABLE_KERNEL_OPT=1
ENABLE_TERMINAL=1

# 解析命令行参数
parse_args() {
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
      --enable-geoip)
        ENABLE_GEOIP=1
        shift
        ;;
      --geoip-provider=*)
        GEOIP_PROVIDER="${1#*=}"
        shift
        ;;
      --geoip-provider)
        GEOIP_PROVIDER="$2"
        shift 2
        ;;
      --maxmind)
        GEOIP_PROVIDER="maxmind"
        ENABLE_GEOIP=1
        shift
        ;;
      --dbip)
        GEOIP_PROVIDER="dbip"
        ENABLE_GEOIP=1
        shift
        ;;
      --enable-security)
        ENABLE_SECURITY=1
        shift
        ;;
      --enable-openresty)
        ENABLE_OPENRESTY=1
        shift
        ;;
      --enable-kernel-opt)
        ENABLE_KERNEL_OPT=1
        shift
        ;;
      --enable-terminal)
        ENABLE_TERMINAL=1
        shift
        ;;
      --disable-kernel-opt)
        ENABLE_KERNEL_OPT=0
        shift
        ;;
      --disable-terminal)
        ENABLE_TERMINAL=0
        shift
        ;;
      --help|-h)
        # 加载帮助模块
        source "$INCLUDES_DIR/help.sh"
        show_help
        exit 0
        ;;
      --verify)
        # 加载必要的模块
        source "$INCLUDES_DIR/os_check.sh"
        source "$INCLUDES_DIR/modsecurity.sh"
        source "$INCLUDES_DIR/help.sh"
        
        verify_modsecurity_install
        exit 0
        ;;
      --info)
        # 加载必要的模块
        source "$INCLUDES_DIR/os_check.sh"
        source "$INCLUDES_DIR/help.sh"
        
        show_info
        exit 0
        ;;
      --cleanup)
        # 加载必要的模块
        source "$INCLUDES_DIR/help.sh"
        
        cleanup
        exit 0
        ;;
      *)
        warn "未知参数: $1"
        echo "使用 --help 查看帮助信息"
        shift
        ;;
    esac
  done
}

# 加载所有模块
load_modules() {
  log "加载模块..."
  
  # 加载系统检测模块
  source "$INCLUDES_DIR/os_check.sh"
  
  # 加载依赖包安装模块
  source "$INCLUDES_DIR/require_packages.sh"
  
  # 加载 ModSecurity 核心模块
  source "$INCLUDES_DIR/modsecurity.sh"
  
  # 加载帮助模块
  source "$INCLUDES_DIR/help.sh"
  
  # 条件加载其他模块
  if [ "$ENABLE_GEOIP" = "1" ]; then
    source "$INCLUDES_DIR/geoip.sh"
    # 导出 GeoIP 提供商设置
    export GEOIP_PROVIDER="${GEOIP_PROVIDER:-dbip}"
  fi
  
  if [ "$ENABLE_KERNEL_OPT" = "1" ]; then
    source "$INCLUDES_DIR/google_bbr_kernel.sh"
  fi
  
  if [ "$ENABLE_TERMINAL" = "1" ]; then
    source "$INCLUDES_DIR/terminal.sh"
  fi
  
  if [ "$ENABLE_SECURITY" = "1" ]; then
    source "$INCLUDES_DIR/fail2ban.sh"
  fi
  
  if [ "$ENABLE_OPENRESTY" = "1" ]; then
    source "$INCLUDES_DIR/openresty.sh"
  fi
  
  log "模块加载完成"
}

# 主安装流程
main_install() {
  log "=========================================="
  log "开始 ModSecurity 安装流程"
  log "=========================================="
  
  # 检查 root 权限
  check_root
  
  # 初始化日志
  init_log
  
  # 系统检测
  log "检测系统环境..."
  init_os_check
  
  # 检查是否已安装
  if [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so" ] || [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so.3" ]; then
    log "检测到已安装的 ModSecurity"
    read -p "是否重新安装？[y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log "操作已取消，退出"
      exit 0
    fi
  fi
  
  # 安装基础工具
  install_basic_tools
  
  # 安装系统依赖
  install_system_dependencies
  
  # 编译安装依赖库
  compile_dependencies
  
  # 安装 ModSecurity 核心库
  install_modsecurity
  
  # 可选功能安装
  if [ "$ENABLE_GEOIP" = "1" ]; then
    log "安装 GeoIP 支持..."
    install_geoip
  else
    log "跳过 GeoIP 安装（使用 --enable-geoip 启用）"
  fi
  
  # Google BBR 内核优化（默认启用）
  if [ "$ENABLE_KERNEL_OPT" = "1" ]; then
    log "进行 Google BBR 内核优化..."
    install_google_bbr_kernel
  else
    log "跳过 Google BBR 内核优化"
  fi
  
  # 终端配置（默认启用）
  if [ "$ENABLE_TERMINAL" = "1" ]; then
    log "配置终端..."
    setup_terminal
  else
    log "跳过终端配置"
  fi
  
  # 安全配置（默认不启用）
  if [ "$ENABLE_SECURITY" = "1" ]; then
    log "安装和配置 fail2ban..."
    install_fail2ban
  else
    log "跳过 fail2ban 配置（使用 --enable-security 启用）"
  fi
  
  # OpenResty 安装（默认不启用）
  if [ "$ENABLE_OPENRESTY" = "1" ]; then
    log "安装 OpenResty..."
    install_openresty
  else
    log "跳过 OpenResty 安装（使用 --enable-openresty 启用）"
  fi
  
  # 验证安装
  verify_modsecurity_install
  
  # 清理临时文件
  cleanup
  
  # 显示安装信息
  show_info
  
  log "=========================================="
  log "ModSecurity 安装完成！"
  log "=========================================="
}

# 主函数
main() {
  # 解析命令行参数
  parse_args "$@"
  
  # 检查特殊命令（如 --help, --verify 等）
  # 这些命令在 parse_args 中已处理并退出
  
  # 加载所有必要的模块
  load_modules
  
  # 执行主安装流程
  main_install
}

# 执行主函数
main "$@"

