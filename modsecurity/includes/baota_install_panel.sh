#!/bin/bash
# 安装宝塔面板（BT11）
# 依赖: shared.sh 提供 log/warn/error/LOG_FILE

BT_INSTALL_SCRIPT_URL="${BT_INSTALL_SCRIPT_URL:-https://bt11.btmb.cc/install/install_panel.sh}"
BT_INSTALL_ARG="${BT_INSTALL_ARG:-bt11.btmb.cc}"

_bt_panel_already_installed() {
  [[ -d /www/server/panel ]] && [[ -f /www/server/panel/BT-Panel || -d /www/server/panel/class ]]
}

install_baota_panel_if_requested() {
  if _bt_panel_already_installed; then
    log "检测到宝塔面板已安装，跳过 --install-bt"
    return 0
  fi

  log "=========================================="
  log "--install-bt：开始安装宝塔面板"
  log "脚本地址: ${BT_INSTALL_SCRIPT_URL}"
  log "=========================================="

  local installer="install_panel.sh"
  rm -f "$installer"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSLo "$installer" "$BT_INSTALL_SCRIPT_URL" >>"$LOG_FILE" 2>&1 || error "下载宝塔安装脚本失败: $BT_INSTALL_SCRIPT_URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$installer" "$BT_INSTALL_SCRIPT_URL" >>"$LOG_FILE" 2>&1 || error "下载宝塔安装脚本失败: $BT_INSTALL_SCRIPT_URL"
  else
    error "缺少 curl/wget，无法下载宝塔安装脚本"
  fi

  yes | bash "$installer" "$BT_INSTALL_ARG" >>"$LOG_FILE" 2>&1 || error "宝塔安装失败，请查看 $LOG_FILE"

  if _bt_panel_already_installed; then
    log "宝塔面板安装完成"
  else
    error "安装命令执行后未检测到宝塔面板目录，请检查 $LOG_FILE"
  fi
}
