#!/bin/bash

# =====================================================================
# 自动启动脚本 - 自动找到 main.sh 并执行
# 即使当前工作目录无效也能正常工作
# =====================================================================

# 获取此脚本的目录
_get_wrapper_dir() {
  local script_path="${BASH_SOURCE[0]}"
  
  # 如果已经是绝对路径
  if [[ "$script_path" == /* ]]; then
    echo "$(dirname "$script_path")"
    return 0
  fi
  
  # 使用 realpath
  if command -v realpath >/dev/null 2>&1; then
    local resolved="$(realpath "$script_path" 2>/dev/null)"
    if [[ -n "$resolved" ]] && [[ "$resolved" == /* ]]; then
      echo "$(dirname "$resolved")"
      return 0
    fi
  fi
  
  # 使用 readlink -f
  if command -v readlink >/dev/null 2>&1; then
    local resolved="$(readlink -f "$script_path" 2>/dev/null)"
    if [[ -n "$resolved" ]] && [[ "$resolved" == /* ]]; then
      echo "$(dirname "$resolved")"
      return 0
    fi
  fi
  
  # Linux: 使用 /proc/self/fd/
  if [[ -L /proc/self/fd/255 ]] 2>/dev/null; then
    local resolved="$(readlink /proc/self/fd/255 2>/dev/null)"
    if [[ -n "$resolved" ]] && [[ "$resolved" == /* ]]; then
      echo "$(dirname "$resolved")"
      return 0
    fi
  fi
  
  # 使用 $0
  if [[ "$0" == /* ]]; then
    echo "$(dirname "$0")"
    return 0
  fi
  
  return 1
}

WRAPPER_DIR="$(_get_wrapper_dir)"
if [[ -z "$WRAPPER_DIR" ]] || [[ ! -d "$WRAPPER_DIR" ]]; then
  echo "错误: 无法确定脚本目录" >&2
  exit 1
fi

MAIN_SCRIPT="$WRAPPER_DIR/main.sh"

if [[ ! -f "$MAIN_SCRIPT" ]]; then
  echo "错误: 找不到 main.sh: $MAIN_SCRIPT" >&2
  exit 1
fi

# 使用绝对路径执行主脚本
exec bash "$MAIN_SCRIPT" "$@"

