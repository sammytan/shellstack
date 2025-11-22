#!/bin/bash

# =====================================================================
# 共享配置和工具函数
# 包含全局变量、颜色定义、日志函数等
# =====================================================================

# 颜色代码
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # 重置颜色

# 基本配置
MODSECURITY_VERSION="${MODSECURITY_VERSION:-3.0.10}"
MODSECURITY_PREFIX="${MODSECURITY_PREFIX:-/usr/local/modsecurity}"
BUILD_DIR="${BUILD_DIR:-/tmp/modsec_core_build_$$}"
LOG_FILE="${LOG_FILE:-/tmp/modsecurity_install.log}"

# 日志函数（需要先定义，供后续使用）
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

info() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] 信息: $1${NC}" | tee -a "$LOG_FILE"
}

# 智能计算 MAKE_JOBS（考虑内存限制）
# 每个编译任务大约需要 1-2GB 内存，根据可用内存自动调整
_calculate_make_jobs() {
  local cpu_cores=$(nproc 2>/dev/null || echo 2)
  local max_jobs=$cpu_cores
  
  # 尝试获取可用内存（MB）
  local available_mem_mb=0
  if command -v free >/dev/null 2>&1; then
    # Linux: 使用 free 命令
    available_mem_mb=$(free -m 2>/dev/null | awk '/^Mem:/ {print $7}' || echo 0)
  elif [[ -f /proc/meminfo ]]; then
    # Linux: 从 /proc/meminfo 读取
    local mem_available=$(grep -i "MemAvailable" /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
    if [[ -n "$mem_available" ]] && [[ "$mem_available" -gt 0 ]]; then
      available_mem_mb=$((mem_available / 1024))
    else
      # 如果没有 MemAvailable，使用 MemFree + Buffers + Cached
      local mem_free=$(grep -i "MemFree" /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
      local buffers=$(grep -i "Buffers" /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
      local cached=$(grep -i "^Cached" /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
      available_mem_mb=$(((mem_free + buffers + cached) / 1024))
    fi
  fi
  
  # 如果成功获取内存信息，根据内存限制并行任务数
  # 每个任务需要约 1.5GB 内存，保留至少 1GB 给系统
  if [[ "$available_mem_mb" -gt 0 ]]; then
    local mem_per_job_mb=1536  # 1.5GB per job
    local reserved_mem_mb=1024  # 保留 1GB 给系统
    local usable_mem_mb=$((available_mem_mb - reserved_mem_mb))
    
    if [[ "$usable_mem_mb" -gt 0 ]]; then
      local mem_based_jobs=$((usable_mem_mb / mem_per_job_mb))
      # 至少保留 1 个任务，最多不超过 CPU 核心数
      if [[ "$mem_based_jobs" -lt 1 ]]; then
        mem_based_jobs=1
      fi
      if [[ "$mem_based_jobs" -lt "$max_jobs" ]]; then
        max_jobs=$mem_based_jobs
      fi
    fi
  fi
  
  # 确保至少为 1，最多不超过 CPU 核心数
  if [[ "$max_jobs" -lt 1 ]]; then
    max_jobs=1
  fi
  
  echo "$max_jobs"
}

# 如果用户没有手动设置 MAKE_JOBS，则自动计算
if [[ -z "$MAKE_JOBS" ]] || [[ "$MAKE_JOBS" == "auto" ]]; then
  MAKE_JOBS=$(_calculate_make_jobs)
  info "自动检测到合适的并行编译任务数: $MAKE_JOBS"
fi

# 依赖版本配置
LIBMAXMINDDB_VERSION="${LIBMAXMINDDB_VERSION:-1.12.1}"
GEOIPUPDATE_VERSION="${GEOIPUPDATE_VERSION:-5.1.1}"
YAJL_VERSION="${YAJL_VERSION:-2.1.0}"
LUA_VERSION="${LUA_VERSION:-5.4.6}"
GIT_VERSION="${GIT_VERSION:-2.44.0}"
LMDB_VERSION="${LMDB_VERSION:-0.9.31}"
SSDEEP_VERSION="${SSDEEP_VERSION:-2.14.1}"

# GeoIP 相关变量
GEOIP_DIR="${GEOIP_DIR:-/usr/local/share/GeoIP}"
GEOIP_PROVIDER="${GEOIP_PROVIDER:-dbip}"  # 默认使用 DB-IP Lite，可选: dbip, maxmind
MAXMIND_ACCOUNT_ID="${MAXMIND_ACCOUNT_ID:-149923}"
MAXMIND_LICENSE_KEY="${MAXMIND_LICENSE_KEY:-yvUg6Atv3ZT6tZ9p}"
ENABLE_GEOIP_AUTO_UPDATE="${ENABLE_GEOIP_AUTO_UPDATE:-1}"  # 默认启用自动更新
GEOIP_UPDATE_FREQUENCY="${GEOIP_UPDATE_FREQUENCY:-monthly}"  # DB-IP Lite 通常每月更新
DBIP_DB_URL="${DBIP_DB_URL:-https://download.db-ip.com/free/dbip-country-lite-$(date +%Y-%m).mmdb}"

# 系统信息（由 os_check.sh 设置）
DISTRO="${DISTRO:-unknown}"
SYSTEM_TYPE="${SYSTEM_TYPE:-unknown}"

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
  if ldconfig -p 2>/dev/null | grep -q "lib$lib_name"; then
    return 0
  fi

  return 1
}

# 检查库开发包
check_dev() {
  local lib_name="$1"

  # 检查pkg-config
  if check_command pkg-config && pkg-config --exists "$lib_name" 2>/dev/null; then
    return 0
  fi

  # 检查头文件
  for path in /usr/include /usr/local/include; do
    if [ -d "$path/$lib_name" ] || ls "$path"/"$lib_name"*.h >/dev/null 2>&1 2>/dev/null; then
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

# 初始化日志文件
init_log() {
  touch "$LOG_FILE"
  log "=========================================="
  log "ModSecurity 安装日志开始"
  log "安装路径: $MODSECURITY_PREFIX"
  log "日志文件: $LOG_FILE"
  log "=========================================="
}

# 加载模块函数
load_module() {
  local module_file="$1"
  if [ -f "$module_file" ]; then
    source "$module_file"
  else
    error "无法加载模块: $module_file"
  fi
}

# 获取脚本目录（robust 方法，处理当前目录无效的情况）
if command -v realpath >/dev/null 2>&1; then
  SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}" 2>/dev/null)")"
elif command -v readlink >/dev/null 2>&1; then
  SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)")"
else
  SCRIPT_PATH="${BASH_SOURCE[0]}"
  if [[ "$SCRIPT_PATH" == /* ]]; then
    SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
  else
    SCRIPT_DIR="$( (cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd) || dirname "$SCRIPT_PATH" )"
  fi
fi
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

