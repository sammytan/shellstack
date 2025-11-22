#!/bin/bash

# =====================================================================
# Helper 脚本 - 可以被 source 到当前 shell，提供自动查找功能
# 使用方法: source /path/to/mosecurity/helper.sh
# 然后就可以在任何地方运行: mosecurity [参数]
# =====================================================================

_mosecurity_find_script() {
  local search_paths=(
    "/data/wwwroot/shellstack/shellstack/mosecurity"
    "/data/wwwroot/shellstack/mosecurity"
    "$HOME/shellstack/mosecurity"
    "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)"
  )
  
  for path in "${search_paths[@]}"; do
    if [[ -f "$path/main.sh" ]]; then
      echo "$path/main.sh"
      return 0
    fi
  done
  
  return 1
}

mosecurity() {
  local script_path="$(_mosecurity_find_script)"
  
  if [[ -z "$script_path" ]] || [[ ! -f "$script_path" ]]; then
    echo "错误: 找不到 mosecurity/main.sh" >&2
    echo "请确保脚本存在于以下位置之一:" >&2
    echo "  - /data/wwwroot/shellstack/shellstack/mosecurity/main.sh" >&2
    echo "  - /data/wwwroot/shellstack/mosecurity/main.sh" >&2
    echo "  - \$HOME/shellstack/mosecurity/main.sh" >&2
    return 1
  fi
  
  bash "$script_path" "$@"
}

# 如果直接执行此脚本（而不是source），则自动运行main.sh
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  mosecurity "$@"
fi

