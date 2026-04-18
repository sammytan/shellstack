#!/bin/bash

# =====================================================================
# ModSecurity 核心库安装脚本 - 主入口文件
# 支持多系统多版本的 ModSecurity 安装
# =====================================================================

# 获取脚本目录（robust 方法，处理当前目录无效的情况）
# 使用多种方法尝试获取脚本的绝对路径
_get_script_dir() {
  local script_path="${BASH_SOURCE[0]}"
  
  # 方法1: 如果已经是绝对路径
  if [[ "$script_path" == /* ]]; then
    echo "$(dirname "$script_path")"
    return 0
  fi
  
  # 方法2: 使用 realpath
  if command -v realpath >/dev/null 2>&1; then
    local resolved="$(realpath "$script_path" 2>/dev/null)"
    if [[ -n "$resolved" ]] && [[ "$resolved" == /* ]]; then
      echo "$(dirname "$resolved")"
      return 0
    fi
  fi
  
  # 方法3: 使用 readlink -f
  if command -v readlink >/dev/null 2>&1; then
    local resolved="$(readlink -f "$script_path" 2>/dev/null)"
    if [[ -n "$resolved" ]] && [[ "$resolved" == /* ]]; then
      echo "$(dirname "$resolved")"
      return 0
    fi
  fi
  
  # 方法4: Linux 特有 - 使用 /proc/self/fd/ (当当前目录无效时很有用)
  if [[ -L /proc/self/fd/255 ]] 2>/dev/null; then
    local resolved="$(readlink /proc/self/fd/255 2>/dev/null)"
    if [[ -n "$resolved" ]] && [[ "$resolved" == /* ]]; then
      echo "$(dirname "$resolved")"
      return 0
    fi
  fi
  
  # 方法5: 尝试通过 $0 获取（如果通过绝对路径调用）
  if [[ "$0" == /* ]]; then
    echo "$(dirname "$0")"
    return 0
  fi
  
  # 方法6: 尝试使用 cd（在 subshell 中，避免影响当前 shell）
  local dir_part="$(dirname "$script_path")"
  if [[ "$dir_part" != "." ]] && [[ "$dir_part" != "$script_path" ]]; then
    local resolved="$( (cd "$dir_part" 2>/dev/null && pwd) 2>/dev/null )"
    if [[ -n "$resolved" ]] && [[ "$resolved" == /* ]]; then
      echo "$resolved"
      return 0
    fi
  fi
  
  # 方法7: 如果 script_path 是相对路径，尝试从 PATH 查找
  if command -v "$script_path" >/dev/null 2>&1; then
    local full_path="$(command -v "$script_path")"
    if [[ -n "$full_path" ]] && [[ "$full_path" == /* ]]; then
      echo "$(dirname "$full_path")"
      return 0
    fi
  fi
  
  # 如果所有方法都失败，返回空
  return 1
}

SCRIPT_DIR="$(_get_script_dir)"
# 验证脚本目录是否有效
if [[ -z "$SCRIPT_DIR" ]] || [[ ! -d "$SCRIPT_DIR" ]]; then
  echo "错误: 无法确定脚本目录（当前工作目录可能无效）" >&2
  echo "" >&2
  echo "解决方案:" >&2
  echo "  1. 使用绝对路径运行脚本:" >&2
  echo "     bash /data/wwwroot/shellstack/shellstack/mosecurity/main.sh" >&2
  echo "" >&2
  echo "  2. 或者先切换到有效目录:" >&2
  echo "     cd / && bash /data/wwwroot/shellstack/shellstack/mosecurity/main.sh" >&2
  echo "" >&2
  echo "  3. 或者使用 run.sh wrapper（如果可用）:" >&2
  echo "     bash /data/wwwroot/shellstack/shellstack/mosecurity/run.sh" >&2
  exit 1
fi

INCLUDES_DIR="$SCRIPT_DIR/includes"

# 验证 includes 目录是否存在
if [[ ! -d "$INCLUDES_DIR" ]]; then
  echo "错误: 找不到 includes 目录: $INCLUDES_DIR" >&2
  exit 1
fi

# 加载共享配置和工具函数
source "$INCLUDES_DIR/shared.sh"

# 功能开关（默认配置）
ENABLE_GEOIP=0
ENABLE_SECURITY=0
ENABLE_OPENRESTY=0
ENABLE_KERNEL_OPT=1
ENABLE_TERMINAL=1
ENABLE_EXPORTER=0
# Consul HTTP 基址（例 http://127.0.0.1:8500）；兼容旧环境变量 EXPORTER_PROMETHEUS_SERVER
EXPORTER_CONSUL_ADDR="${EXPORTER_CONSUL_ADDR:-${EXPORTER_PROMETHEUS_SERVER:-}}"
INSTALL_BAOTA_PANEL=0
# 宝塔：从站点下载 btwaf.tar.gz 覆盖 /www/server/btwaf
EXTEND_BTWAF_CACHE=0
# 宝塔：部署 nginx.conf / CRS / 自定义规则（需配合 --deploy-conf）
DEPLOY_MODSEC_CONF=0
# 宝塔 nginx.sh 的 OpenResty 版本参数：openresty | openresty127 等
BT_OPENRESTY_VERSION="${BT_OPENRESTY_VERSION:-openresty127}"
# 是否从命令行传入 --bt-openresty（用于与默认区分，触发宝塔环境预检）
BT_OPENRESTY_FROM_CLI=0
# nginx-module-vts 默认随 --bt-openresty / --deploy-conf 触发的重编一并编译；设 0 关闭：SHELLSTACK_WITH_NGINX_MODULE_VTS=0
SHELLSTACK_WITH_NGINX_MODULE_VTS="${SHELLSTACK_WITH_NGINX_MODULE_VTS:-1}"
# 为 1 时表示用户还请求了 ModSecurity/宝塔 等主流程；与 ENABLE_EXPORTER 组合用于「仅 exporter」独立模式
SHELLSTACK_MAIN_NON_EXPORTER_WORK=0
# --force 先记入此变量，parse_args 结束后在 _shellstack_apply_cli_force_resolution 中判定：仅 exporter 时转为 SHELLSTACK_EXPORTER_FORCE
SHELLSTACK_CLI_FORCE=0
# 是否在命令行显式传入（用于区分「仅 --extend-btwaf-cache --force」与全套强制，避免误触发 Nginx 重编）
SHELLSTACK_CLI_REQUESTED_DEPLOY_CONF=0
SHELLSTACK_CLI_REQUESTED_BT_OPENRESTY=0
SHELLSTACK_CLI_REQUESTED_PREFIX=0
SHELLSTACK_CLI_REQUESTED_VERSION=0

# 解析完参数后：--force 只加强「命令行已出现」的对应步骤（多项可同开，各自命中独立分支）；裸 --force 仍为「一键全套」
_shellstack_apply_cli_force_resolution() {
  unset SHELLSTACK_EXPORTER_FORCE 2>/dev/null || true
  if [[ "${SHELLSTACK_CLI_FORCE:-0}" != "1" ]]; then
    return 0
  fi
  if [[ "$ENABLE_EXPORTER" == "1" ]] && [[ "${SHELLSTACK_MAIN_NON_EXPORTER_WORK:-0}" == "0" ]]; then
    export SHELLSTACK_EXPORTER_FORCE=1
    log "启用 --force（仅作用于 exporter）：将强制重跑主机名/textfile/防火墙/Consul 注册等 exporter 步骤；不启动 ModSecurity/宝塔主流程。"
    log "提示: 需要重编宝塔 Nginx / 部署 CRS 等时，请显式加上 --bt-openresty、--deploy-conf、--extend-btwaf-cache 等；--force 不会自动替你展开这些参数。"
    return 0
  fi
  # 仅 --extend-btwaf-cache（未显式 --deploy-conf / --bt-openresty）时：--force 不展开为 Nginx 重编与配置部署
  if [[ "${EXTEND_BTWAF_CACHE:-0}" == "1" ]] && \
     [[ "${SHELLSTACK_CLI_REQUESTED_DEPLOY_CONF:-0}" != "1" ]] && \
     [[ "${SHELLSTACK_CLI_REQUESTED_BT_OPENRESTY:-0}" != "1" ]]; then
    log "启用 --force（仅作用于 --extend-btwaf-cache）：不触发宝塔 Nginx/OpenResty 重编与 --deploy-conf；仅重跑 BTwaf 扩展流程（面板 install 仍遵循 SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL，默认已装则跳过）。"
    log "提示: 若需连同 Nginx 重编与 CRS/配置一并强制，请加上 --bt-openresty 或 --deploy-conf 后再使用 --force。"
    return 0
  fi

  local _ss_baota=0
  [[ "${SHELLSTACK_CLI_REQUESTED_DEPLOY_CONF:-0}" == "1" ]] && _ss_baota=1
  [[ "${SHELLSTACK_CLI_REQUESTED_BT_OPENRESTY:-0}" == "1" ]] && _ss_baota=1
  [[ "${EXTEND_BTWAF_CACHE:-0}" == "1" ]] && _ss_baota=1

  if [[ "$_ss_baota" == "1" ]]; then
    log "启用 --force：按命令行已指定的宝塔类参数分别加强（不自动追加未出现的 --deploy-conf / --bt-openresty / --extend-btwaf-cache）。"
    if [[ "${SHELLSTACK_CLI_REQUESTED_BT_OPENRESTY:-0}" == "1" ]]; then
      MODSECURITY_FORCE_BT_NGINX_REBUILD=1
      SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK=1
      export MODSECURITY_FORCE_BT_NGINX_REBUILD
      export SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK
      log "  → --bt-openresty：MODSECURITY_FORCE_BT_NGINX_REBUILD=1，SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK=1"
    fi
    if [[ "${SHELLSTACK_CLI_REQUESTED_DEPLOY_CONF:-0}" == "1" ]]; then
      SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK=1
      export SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK
      log "  → --deploy-conf：SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK=1（未带 --bt-openresty 时不强制 Nginx 重编）"
    fi
    if [[ "${EXTEND_BTWAF_CACHE:-0}" == "1" ]]; then
      SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL=1
      SHELLSTACK_INSTALL_REDIS=1
      export SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL
      export SHELLSTACK_INSTALL_REDIS
      log "  → --extend-btwaf-cache：SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL=1，SHELLSTACK_INSTALL_REDIS=1"
    fi
  fi

  if [[ "${SHELLSTACK_CLI_REQUESTED_VERSION:-0}" == "1" ]] || [[ "${SHELLSTACK_CLI_REQUESTED_PREFIX:-0}" == "1" ]]; then
    export SHELLSTACK_FORCE_LIBMODSECURITY_REBUILD=1
    log "启用 --force：已指定 --version 或 --prefix，将跳过「已安装 libmodsecurity」时的交互确认并进入重新编译流程。"
  fi

  # 裸 --force（及未将 SHELLSTACK_MAIN_NON_EXPORTER_WORK 置 1 的选项，如仅 --disable-*）：保持「一键全套」
  if [[ "$_ss_baota" != "1" ]] && \
     [[ "${SHELLSTACK_CLI_REQUESTED_VERSION:-0}" != "1" ]] && \
     [[ "${SHELLSTACK_CLI_REQUESTED_PREFIX:-0}" != "1" ]] && \
     [[ "${SHELLSTACK_MAIN_NON_EXPORTER_WORK:-0}" == "0" ]]; then
    if [[ "${BT_OPENRESTY_FROM_CLI:-0}" != "1" ]]; then
      BT_OPENRESTY_VERSION="openresty"
      BT_OPENRESTY_FROM_CLI=1
      export BT_OPENRESTY_VERSION
    fi
    DEPLOY_MODSEC_CONF=1
    EXTEND_BTWAF_CACHE=1
    MODSECURITY_FORCE_BT_NGINX_REBUILD=1
    SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK=1
    SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL=1
    SHELLSTACK_INSTALL_REDIS=1
    export MODSECURITY_FORCE_BT_NGINX_REBUILD
    export SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK
    export SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL
    export SHELLSTACK_INSTALL_REDIS
    SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
    log "启用 --force：未指定其它主安装参数时，按「一键全套」强制执行 Nginx 重编、--deploy-conf、--extend-btwaf-cache（OpenResty 默认键 openresty，可先写 --bt-openresty=VER 再 --force 指定版本键）。"
  fi
}

# 解析命令行参数
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix=*)
        MODSECURITY_PREFIX="${1#*=}"
        SHELLSTACK_CLI_REQUESTED_PREFIX=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift
        ;;
      --prefix)
        MODSECURITY_PREFIX="$2"
        SHELLSTACK_CLI_REQUESTED_PREFIX=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift 2
        ;;
      --version=*)
        MODSECURITY_VERSION="${1#*=}"
        SHELLSTACK_CLI_REQUESTED_VERSION=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift
        ;;
      --version)
        MODSECURITY_VERSION="$2"
        SHELLSTACK_CLI_REQUESTED_VERSION=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift 2
        ;;
      --enable-geoip)
        ENABLE_GEOIP=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift
        ;;
      --geoip-provider=*)
        GEOIP_PROVIDER="${1#*=}"
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift
        ;;
      --geoip-provider)
        GEOIP_PROVIDER="$2"
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift 2
        ;;
      --maxmind)
        GEOIP_PROVIDER="maxmind"
        ENABLE_GEOIP=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift
        ;;
      --dbip)
        GEOIP_PROVIDER="dbip"
        ENABLE_GEOIP=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift
        ;;
      --enable-security)
        ENABLE_SECURITY=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift
        ;;
      --enable-openresty)
        ENABLE_OPENRESTY=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift
        ;;
      --enable-kernel-opt)
        ENABLE_KERNEL_OPT=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift
        ;;
      --enable-terminal)
        ENABLE_TERMINAL=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
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
      --jobs=*)
        MAKE_JOBS="${1#*=}"
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift
        ;;
      --jobs)
        MAKE_JOBS="$2"
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift 2
        ;;
      --extend-btwaf-cache)
        EXTEND_BTWAF_CACHE=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift
        ;;
      --install-bt)
        INSTALL_BAOTA_PANEL=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift
        ;;
      --force)
        # 语义见 _shellstack_apply_cli_force_resolution：与各主参数独立组合；裸 --force 仍为「一键全套」
        SHELLSTACK_CLI_FORCE=1
        shift
        ;;
      --deploy-conf)
        DEPLOY_MODSEC_CONF=1
        SHELLSTACK_CLI_REQUESTED_DEPLOY_CONF=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        shift
        ;;
      --with-exporter=*)
        ENABLE_EXPORTER=1
        EXPORTER_CONSUL_ADDR="${1#*=}"
        EXPORTER_CONSUL_ADDR="$(echo -n "$EXPORTER_CONSUL_ADDR" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        export EXPORTER_CONSUL_ADDR
        shift
        ;;
      --with-exporter)
        ENABLE_EXPORTER=1
        if [[ -n "${2:-}" ]] && [[ "${2:-}" != -* ]]; then
          EXPORTER_CONSUL_ADDR="$(echo -n "$2" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
          shift 2
        else
          EXPORTER_CONSUL_ADDR=""
          shift
        fi
        export EXPORTER_CONSUL_ADDR
        ;;
      --with-consul-token=*)
        ENABLE_EXPORTER=1
        CONSUL_HTTP_TOKEN="${1#*=}"
        CONSUL_HTTP_TOKEN="$(echo -n "$CONSUL_HTTP_TOKEN" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        export CONSUL_HTTP_TOKEN
        shift
        ;;
      --with-consul-token)
        ENABLE_EXPORTER=1
        if [[ -n "${2:-}" ]] && [[ "${2:-}" != -* ]]; then
          CONSUL_HTTP_TOKEN="$(echo -n "$2" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
          shift 2
        else
          CONSUL_HTTP_TOKEN=""
          shift
        fi
        export CONSUL_HTTP_TOKEN
        ;;
      --bt-openresty=*)
        BT_OPENRESTY_VERSION="${1#*=}"
        BT_OPENRESTY_FROM_CLI=1
        SHELLSTACK_CLI_REQUESTED_BT_OPENRESTY=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        export BT_OPENRESTY_VERSION
        shift
        ;;
      --bt-openresty)
        BT_OPENRESTY_VERSION="$2"
        BT_OPENRESTY_FROM_CLI=1
        SHELLSTACK_CLI_REQUESTED_BT_OPENRESTY=1
        SHELLSTACK_MAIN_NON_EXPORTER_WORK=1
        export BT_OPENRESTY_VERSION
        shift 2
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
  _shellstack_apply_cli_force_resolution
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

  if [ "$ENABLE_EXPORTER" = "1" ]; then
    source "$INCLUDES_DIR/exporter.sh"
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
  
  # 是否重新编译 libmodsecurity（否：沿用现有库，仍继续宝塔连接器与可选 --deploy-conf）
  SKIP_LIB_REINSTALL=0
  if [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so" ] || [ -f "$MODSECURITY_PREFIX/lib/libmodsecurity.so.3" ]; then
    log "检测到已安装的 ModSecurity 核心库"
    if [[ "${SHELLSTACK_FORCE_LIBMODSECURITY_REBUILD:-0}" == "1" ]]; then
      log "因 --force 与 --version / --prefix：跳过确认，将重新编译 libmodsecurity"
    else
      read -p "是否重新编译安装 libmodsecurity？[y/N] " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        SKIP_LIB_REINSTALL=1
        log "跳过 libmodsecurity 重新编译，继续后续步骤（宝塔 OpenResty / ModSecurity-nginx / --deploy-conf）"
      fi
    fi
  fi

  if [ "$SKIP_LIB_REINSTALL" != "1" ]; then
    install_basic_tools
    install_system_dependencies
    compile_dependencies
    install_modsecurity
  else
    install_basic_tools
    install_system_dependencies
  fi

  # 宝塔：仅在显式需要时才升级/重编译 OpenResty + ModSecurity-nginx
  # 触发条件：--bt-openresty（含 --force 覆盖）或 --deploy-conf
  if [[ "${BT_OPENRESTY_FROM_CLI:-0}" == "1" || "${DEPLOY_MODSEC_CONF:-0}" == "1" ]]; then
    source "$INCLUDES_DIR/baota_modsec_connector.sh"
    baota_install_openresty_with_modsecurity_connector
  else
    log "未使用 --bt-openresty/--deploy-conf，跳过宝塔 Nginx 重编译流程（仅执行核心库与可选扩展）。"
  fi

  if [ "$DEPLOY_MODSEC_CONF" = "1" ]; then
    log "=========================================="
    log "--deploy-conf：写入 Nginx ModSecurity / CRS 配置"
    log "=========================================="
    source "$INCLUDES_DIR/baota_modsec_deploy.sh"
    baota_deploy_modsecurity_conf
  else
    log "未使用 --deploy-conf，跳过 Nginx / CRS 配置文件写入"
  fi

  if [ "$EXTEND_BTWAF_CACHE" = "1" ]; then
    source "$INCLUDES_DIR/btwaf_extend.sh"
    extend_btwaf_cache_bundle
  else
    log "未使用 --extend-btwaf-cache，跳过 BTwaf 包覆盖"
  fi

  if [ "$ENABLE_EXPORTER" = "1" ]; then
    setup_exporter_and_register "${EXPORTER_CONSUL_ADDR:-}"
  else
    log "未使用 --with-exporter，跳过 exporter 安装与 Consul 注册"
  fi
  
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

  # 仅 --with-exporter / --with-consul-token（及可选 --disable-kernel-opt / --disable-terminal）时：不跑 ModSecurity 主安装，只执行 exporter + Consul
  if [[ "$ENABLE_EXPORTER" == "1" ]] && [[ "${SHELLSTACK_MAIN_NON_EXPORTER_WORK:-0}" == "0" ]]; then
    log "=========================================="
    log "独立任务：仅部署 node_exporter + Consul 注册（可加 --force 仅强制重跑本流程；完整 ModSecurity/宝塔强制请另加 --deploy-conf 等主安装参数）"
    log "=========================================="
    source "$INCLUDES_DIR/exporter.sh"
    setup_exporter_and_register "${EXPORTER_CONSUL_ADDR:-}"
    log "exporter 独立流程结束。"
    exit 0
  fi

  if [[ "$ENABLE_EXPORTER" == "1" ]]; then
    log "提示: 当前将执行 ModSecurity/宝塔主流程（因已出现主安装类参数，例如 --deploy-conf、--bt-openresty、--version、--extend-btwaf-cache 等）。--force 仅加强已写出的对应步骤，不会自动拼齐未指定的参数（裸 --force 除外，见帮助）。"
    log "提示: 「仅 exporter」时 --with-exporter/--with-consul-token 可省略 = 值；此场景下 --force 只强制重跑 exporter，不会触发本段主流程。"
  fi

  # 可选：先安装宝塔面板，再做宝塔相关环境检查
  if [[ "${INSTALL_BAOTA_PANEL:-0}" == "1" ]]; then
    source "$INCLUDES_DIR/baota_install_panel.sh"
    install_baota_panel_if_requested
  fi

  if [[ "${BT_OPENRESTY_FROM_CLI:-0}" == "1" || "${DEPLOY_MODSEC_CONF:-0}" == "1" || "${EXTEND_BTWAF_CACHE:-0}" == "1" ]]; then
    log "参数归一化: BT_OPENRESTY_VERSION=${BT_OPENRESTY_VERSION} (force=${MODSECURITY_FORCE_BT_NGINX_REBUILD:-0}, deploy=${DEPLOY_MODSEC_CONF:-0}, btwaf=${EXTEND_BTWAF_CACHE:-0})"
  fi

  # 宝塔相关参数需已安装宝塔面板与 BTwaf
  # shellcheck source=includes/baota_require_check.sh
  source "$INCLUDES_DIR/baota_require_check.sh"
  shellstack_require_baota_btwaf_for_modsecurity_flags
  
  # 检查特殊命令（如 --help, --verify 等）
  # 这些命令在 parse_args 中已处理并退出
  
  # 加载所有必要的模块
  load_modules
  
  # 执行主安装流程
  main_install
}

# 执行主函数
main "$@"

