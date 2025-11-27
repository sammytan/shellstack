#!/bin/bash
set -e

# =====================================================================
# ShellStack - 模块化 Shell 脚本管理工具
# 支持远程调用和本地执行
# =====================================================================

BASE_URL="${BASE_URL:-https://shellstack.910918920801.xyz}"

# 获取脚本目录（支持远程和本地模式）
_get_script_dir() {
  # 如果 BASH_SOURCE[0] 存在且是文件，说明是本地执行
  if [[ -n "${BASH_SOURCE[0]}" ]] && [[ -f "${BASH_SOURCE[0]}" ]]; then
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    return 0
  fi
  
  # 远程模式下，尝试从环境变量获取
  if [[ -n "$SHELLSTACK_MODULE_DIR" ]] && [[ "$SHELLSTACK_MODULE_DIR" != http* ]]; then
    echo "$(dirname "$SHELLSTACK_MODULE_DIR")"
    return 0
  fi
  
  # 如果都失败，返回当前目录
  echo "$(pwd)"
}

SCRIPT_DIR="$(_get_script_dir)"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # 重置颜色

# 日志函数
log() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] 警告: $1${NC}" >&2
}

error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] 错误: $1${NC}" >&2
  exit 1
}

info() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] 信息: $1${NC}"
}

# 检测是否在远程模式下运行（通过 curl 管道）
is_remote_mode() {
  # 检查脚本文件是否存在且可访问（本地模式）
  if [[ -n "${BASH_SOURCE[0]}" ]] && [[ -f "${BASH_SOURCE[0]}" ]] && [[ -r "${BASH_SOURCE[0]}" ]]; then
    # 进一步检查：如果脚本路径是绝对路径或相对路径且文件存在，则是本地模式
    local script_path="${BASH_SOURCE[0]}"
    if [[ "$script_path" == /* ]] || [[ -f "$script_path" ]]; then
      return 1  # 本地模式
    fi
  fi
  
  # 检查是否从 stdin 读取（管道模式）
  if [[ ! -t 0 ]]; then
    return 0  # 远程模式（从管道读取）
  fi
  
  # 默认：如果无法确定，假设是本地模式
  return 1
}

# 获取所有可用模块
get_available_modules() {
  local modules=()
  
  if is_remote_mode; then
    # 远程模式：尝试从服务器获取模块列表
    local modules_list_url="${BASE_URL}/modules.txt"
    local temp_list=$(mktemp)
    
    # 尝试下载模块列表文件
    if curl -fsSL "$modules_list_url" -o "$temp_list" 2>/dev/null; then
      # 成功获取模块列表
      while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过空行和注释行
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*#.*$ ]] && continue
        # 去除前后空格
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -n "$line" ]] && modules+=("$line")
      done < "$temp_list"
      rm -f "$temp_list"
    else
      # 如果无法获取模块列表，尝试检测已知模块
      # 通过尝试访问模块入口文件来检测
      local known_modules=("modsecurity")
      for module in "${known_modules[@]}"; do
        # 尝试访问模块的入口文件
        for entry in "main.sh" "run.sh" "install.sh"; do
          local test_url="${BASE_URL}/${module}/${entry}"
          if curl -fsSL -o /dev/null -w "%{http_code}" "$test_url" 2>/dev/null | grep -q "200"; then
            modules+=("$module")
            break
          fi
        done
      done
    fi
  else
    # 本地模式：扫描目录
    if [[ -d "$SCRIPT_DIR" ]]; then
      for dir in "$SCRIPT_DIR"/*; do
        if [[ -d "$dir" ]] && [[ -n "$(basename "$dir")" ]] && [[ "$(basename "$dir")" != ".*" ]]; then
          local module_name="$(basename "$dir")"
          # 检查模块是否有入口文件（main.sh 或 install.sh）
          if [[ -f "$dir/main.sh" ]] || [[ -f "$dir/install.sh" ]] || [[ -f "$dir/run.sh" ]]; then
            modules+=("$module_name")
          fi
        fi
      done
    fi
  fi
  
  # 输出模块列表（每行一个）
  if [[ ${#modules[@]} -gt 0 ]]; then
    printf '%s\n' "${modules[@]}"
  fi
}

# 列出所有可用模块
list_modules() {
  echo -e "${CYAN}=========================================="
  echo -e "ShellStack - 可用模块列表"
  echo -e "==========================================${NC}"
  echo ""
  
  local modules
  modules=($(get_available_modules))
  
  if [[ ${#modules[@]} -eq 0 ]]; then
    warn "未找到任何可用模块"
    if is_remote_mode; then
      echo ""
      echo -e "${YELLOW}提示:${NC} 如果这是首次使用，请确保服务器已正确部署。"
      echo ""
    fi
    return 1
  fi
  
  if is_remote_mode; then
    echo -e "${GREEN}远程模式 - 找到 ${#modules[@]} 个模块:${NC}"
  else
    echo -e "${GREEN}本地模式 - 找到 ${#modules[@]} 个模块:${NC}"
  fi
  echo ""
  
  for module in "${modules[@]}"; do
    local desc=""
    
    if is_remote_mode; then
      # 远程模式：尝试获取模块描述
      local readme_url="${BASE_URL}/${module}/README.md"
      local temp_readme=$(mktemp)
      if curl -fsSL "$readme_url" -o "$temp_readme" 2>/dev/null; then
        desc=$(head -n 3 "$temp_readme" | grep -v "^#" | head -n 1 | sed 's/^[[:space:]]*//' | cut -c1-60)
      fi
      rm -f "$temp_readme"
    else
      # 本地模式：读取本地 README.md
      local module_dir="$SCRIPT_DIR/$module"
      if [[ -f "$module_dir/README.md" ]]; then
        desc=$(head -n 3 "$module_dir/README.md" | grep -v "^#" | head -n 1 | sed 's/^[[:space:]]*//' | cut -c1-60)
      fi
    fi
    
    if [[ -n "$desc" ]]; then
      printf "  ${CYAN}%-15s${NC} - %s\n" "$module" "$desc"
    else
      printf "  ${CYAN}%-15s${NC}\n" "$module"
    fi
  done
  
  echo ""
  echo -e "${BLUE}使用方法:${NC}"
  if is_remote_mode; then
    echo "  curl ${BASE_URL}/shellstack.sh | bash -s <module> [参数]"
  else
    echo "  ./shellstack.sh <module> [参数]"
    echo "  或"
    echo "  curl ${BASE_URL}/shellstack.sh | bash -s <module> [参数]"
  fi
  echo ""
}

# 获取模块入口脚本路径
get_module_entry() {
  local module_name="$1"
  local module_dir="$SCRIPT_DIR/$module_name"
  
  # 优先级：run.sh > main.sh > install.sh
  if [[ -f "$module_dir/run.sh" ]]; then
    echo "$module_dir/run.sh"
  elif [[ -f "$module_dir/main.sh" ]]; then
    echo "$module_dir/main.sh"
  elif [[ -f "$module_dir/install.sh" ]]; then
    echo "$module_dir/install.sh"
  else
    return 1
  fi
}

# 远程下载并执行模块
download_and_execute_module() {
  local module_name="$1"
  shift
  local args=("$@")
  
  log "正在从远程服务器下载模块: $module_name"
  
  # 尝试下载模块的主脚本
  local temp_script=$(mktemp)
  local module_url="${BASE_URL}/${module_name}/main.sh"
  
  # 尝试不同的入口文件名
  for entry in "main.sh" "run.sh" "install.sh"; do
    module_url="${BASE_URL}/${module_name}/${entry}"
    if curl -fsSL "$module_url" -o "$temp_script" 2>/dev/null; then
      log "成功下载模块脚本: $module_url"
      chmod +x "$temp_script"
      
      # 设置环境变量，让子脚本知道它在远程模式下运行
      export SHELLSTACK_REMOTE=1
      export SHELLSTACK_BASE_URL="$BASE_URL"
      export SHELLSTACK_MODULE_DIR="${BASE_URL}/${module_name}"
      
      # 执行脚本并传递参数
      bash "$temp_script" "${args[@]}"
      local exit_code=$?
      
      # 清理临时文件
      rm -f "$temp_script"
      
      return $exit_code
    fi
  done
  
  # 如果所有尝试都失败
  error "无法下载模块 $module_name，请检查模块名称是否正确"
}

# 本地执行模块
execute_module_local() {
  local module_name="$1"
  shift
  local args=("$@")
  
  local entry_script=$(get_module_entry "$module_name")
  
  if [[ -z "$entry_script" ]] || [[ ! -f "$entry_script" ]]; then
    error "模块 '$module_name' 不存在或没有入口脚本"
  fi
  
  log "执行模块: $module_name"
  
  # 设置环境变量
  export SHELLSTACK_REMOTE=0
  export SHELLSTACK_BASE_URL="$BASE_URL"
  export SHELLSTACK_MODULE_DIR="$SCRIPT_DIR/$module_name"
  
  # 执行模块脚本
  bash "$entry_script" "${args[@]}"
}

# 显示帮助信息
show_help() {
  echo -e "${CYAN}ShellStack - 模块化 Shell 脚本管理工具${NC}"
  echo ""
  echo -e "${GREEN}用法:${NC}"
  echo "  shellstack.sh [选项] [模块名] [模块参数...]"
  echo ""
  echo -e "${GREEN}选项:${NC}"
  echo "  --list, -l              列出所有可用模块"
  echo "  --help, -h              显示此帮助信息"
  echo "  --version, -v           显示版本信息"
  echo ""
  echo -e "${GREEN}示例:${NC}"
  echo "  # 列出所有模块"
  echo "  curl ${BASE_URL}/shellstack.sh | bash -s --list"
  echo ""
  echo "  # 安装 modsecurity 模块"
  echo "  curl ${BASE_URL}/shellstack.sh | bash -s modsecurity"
  echo ""
  echo "  # 安装 modsecurity 模块并传递参数"
  echo "  curl ${BASE_URL}/shellstack.sh | bash -s modsecurity --version=3.0.10 --enable-geoip"
  echo ""
  echo "  # 本地使用"
  echo "  ./shellstack.sh --list"
  echo "  ./shellstack.sh modsecurity --version=3.0.10"
  echo ""
  echo -e "${GREEN}模块说明:${NC}"
  echo "  每个模块都是一个独立的目录，包含安装脚本和相关文件。"
  echo "  模块可以通过远程 URL 下载执行，也可以本地执行。"
  echo ""
}

# 主函数
main() {
  # 解析命令行参数
  case "${1:-}" in
    --list|-l)
      list_modules
      exit 0
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    --version|-v)
      echo "ShellStack v1.0.0"
      exit 0
      ;;
    "")
      # 没有参数，列出模块
      list_modules
      exit 0
      ;;
    *)
      # 第一个参数是模块名
      local module_name="$1"
      shift
      
      if is_remote_mode; then
        # 远程模式：下载并执行
        download_and_execute_module "$module_name" "$@"
      else
        # 本地模式：直接执行
        execute_module_local "$module_name" "$@"
      fi
      ;;
  esac
}

# 执行主函数
main "$@"
