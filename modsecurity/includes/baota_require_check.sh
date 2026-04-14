#!/bin/bash
# 使用 --bt-openresty / --deploy-conf / --extend-btwaf-cache 前校验宝塔面板与 BTwaf
# 依赖: log、error（shared.sh）

# 返回 0：检测到 BTwaf 典型目录或面板插件
_shellstack_detect_btwaf_installed() {
  if [[ -d /www/server/btwaf ]] && { [[ -f /www/server/btwaf/waf.lua ]] || [[ -f /www/server/btwaf/init.lua ]]; }; then
    return 0
  fi
  if [[ -d /www/server/panel/plugin/btwaf ]]; then
    return 0
  fi
  return 1
}

# 返回 0：检测到宝塔面板（兼容不同版本目录结构）
_shellstack_detect_baota_panel() {
  # 1) 目录/文件特征
  if [[ -d /www/server/panel ]]; then
    if [[ -f /www/server/panel/class/common.py ]] || [[ -d /www/server/panel/class ]] || [[ -f /www/server/panel/BT-Panel ]]; then
      return 0
    fi
  fi

  # 2) 进程特征（BT-Panel / BT-Task）
  if command -v pgrep >/dev/null 2>&1; then
    if pgrep -f '/www/server/panel/BT-Panel|/www/server/panel/BT-Task' >/dev/null 2>&1; then
      return 0
    fi
  fi

  return 1
}

# 若用户传了宝塔相关参数，未满足环境则终止
shellstack_require_baota_btwaf_for_modsecurity_flags() {
  local need=0
  [[ "${EXTEND_BTWAF_CACHE:-0}" == "1" ]] && need=1
  [[ "${DEPLOY_MODSEC_CONF:-0}" == "1" ]] && need=1
  [[ "${BT_OPENRESTY_FROM_CLI:-0}" == "1" ]] && need=1
  [[ "$need" -eq 0 ]] && return 0

  local lines=()

  if ! _shellstack_detect_baota_panel; then
    lines+=("未检测到宝塔面板：/www/server/panel 不存在，或缺少 class/common.py、BT-Panel 等典型文件。")
    lines+=("请先安装宝塔 Linux 面板后再使用 --bt-openresty / --deploy-conf / --extend-btwaf-cache。")
  fi

  # --extend-btwaf-cache 会在安装流程中执行面板 BTwaf 安装脚本并下发扩展文件，不要求事先已部署 /www/server/btwaf
  if [[ "${EXTEND_BTWAF_CACHE:-0}" == "1" ]]; then
    if [[ ${#lines[@]} -gt 0 ]]; then
      error "$(printf '%s\n' "${lines[@]}")"
    fi
    log "环境检查: 已检测到宝塔面板；--extend-btwaf-cache 将安装/同步 BTwaf 与 Redis 扩展。"
    return 0
  fi

  if ! _shellstack_detect_btwaf_installed; then
    lines+=("未检测到宝塔网站防火墙（BTwaf）：")
    lines+=("  - 期望 /www/server/btwaf 下存在 waf.lua 或 init.lua（面板已部署 WAF），或")
    lines+=("  - 已安装面板插件目录 /www/server/panel/plugin/btwaf")
    lines+=("请在宝塔「软件商店」安装「宝塔网站防火墙」并完成部署后再执行上述参数；或先使用 --extend-btwaf-cache 自动安装扩展。")
  fi

  if [[ ${#lines[@]} -gt 0 ]]; then
    error "$(printf '%s\n' "${lines[@]}")"
  fi

  log "环境检查: 已检测到宝塔面板与 BTwaf，继续执行宝塔相关选项。"
}
