#!/bin/bash
# 自动生成 modules.txt 文件

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_FILE="$SCRIPT_DIR/modules.txt"

echo "# ShellStack 模块列表" > "$MODULES_FILE"
echo "# 此文件由 generate-modules-list.sh 自动生成" >> "$MODULES_FILE"
echo "# 每行一个模块名，以 # 开头的行为注释" >> "$MODULES_FILE"
echo "" >> "$MODULES_FILE"

# 扫描目录，找出所有模块
for dir in "$SCRIPT_DIR"/*; do
  if [[ -d "$dir" ]] && [[ -n "$(basename "$dir")" ]] && [[ "$(basename "$dir")" != ".*" ]]; then
    module_name="$(basename "$dir")"
    
    # 检查是否是模块（有入口文件）
    if [[ -f "$dir/main.sh" ]] || [[ -f "$dir/install.sh" ]] || [[ -f "$dir/run.sh" ]]; then
      echo "$module_name" >> "$MODULES_FILE"
      echo "发现模块: $module_name"
    fi
  fi
done

echo ""
echo "模块列表已生成: $MODULES_FILE"

