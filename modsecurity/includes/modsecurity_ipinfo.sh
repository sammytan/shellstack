#!/bin/bash
# 出口 IP 地区判断（ipinfo.io），用于自动选择 GitHub / Gitee 克隆顺序
# 依赖: log、warn；须在 modsecurity_clone_env.sh 之后 source

MODSECURITY_AUTO_MIRROR_BY_IP="${MODSECURITY_AUTO_MIRROR_BY_IP:-1}"
MODSECURITY_IPINFO_COUNTRY_URL="${MODSECURITY_IPINFO_COUNTRY_URL:-https://ipinfo.io/country}"

# 返回两位国家码（大写），失败则无输出。中国大陆为 CN
_modsecurity_ipinfo_country_code() {
  local url="${MODSECURITY_IPINFO_COUNTRY_URL:-https://ipinfo.io/country}"
  local code=""
  if command -v curl >/dev/null 2>&1; then
    code=$(curl -fsSL --connect-timeout 4 --max-time 12 "$url" 2>/dev/null)
  elif command -v wget >/dev/null 2>&1; then
    code=$(wget -qO- --timeout=12 "$url" 2>/dev/null)
  else
    return 1
  fi
  code=$(echo "$code" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
  [[ "$code" =~ ^[A-Z]{2}$ ]] && echo "$code"
}

# 根据环境变量与 IP 地区，写入「是否 GitHub 优先」及原因（nameref：$1、$2 为变量名）
_modsecurity_clone_mirror_decision() {
  local -n _ms_out_github_first="$1"
  local -n _ms_out_reason="$2"
  _ms_out_github_first=0
  _ms_out_reason=""
  if [[ "${MODSECURITY_PREFER_GITHUB:-}" == "1" ]] || [[ "${MODSECURITY_PREFER_GITEE:-}" == "0" ]]; then
    _ms_out_github_first=1
    _ms_out_reason="已手动指定 GitHub 优先（MODSECURITY_PREFER_GITHUB=1 或 MODSECURITY_PREFER_GITEE=0）"
  elif [[ "${MODSECURITY_AUTO_MIRROR_BY_IP:-1}" != "1" ]]; then
    _ms_out_github_first=0
    _ms_out_reason="已关闭 MODSECURITY_AUTO_MIRROR_BY_IP，默认 Gitee 优先"
  else
    local cc
    cc=$(_modsecurity_ipinfo_country_code) || true
    if [[ -n "$cc" ]]; then
      if [[ "$cc" == "CN" ]]; then
        _ms_out_github_first=0
        _ms_out_reason="ipinfo.io 判断出口 IP 位于中国大陆（$cc），Gitee 优先"
      else
        _ms_out_github_first=1
        _ms_out_reason="ipinfo.io 判断出口 IP 区域为 $cc（非中国大陆），GitHub 优先"
      fi
    else
      _ms_out_github_first=0
      _ms_out_reason="无法从 ipinfo.io 获取国家码，回退 Gitee 优先"
      warn "无法从 ${MODSECURITY_IPINFO_COUNTRY_URL:-https://ipinfo.io/country} 获取地区（超时或受限）。可设置 MODSECURITY_PREFER_GITHUB=1 强制 GitHub，或检查网络。"
    fi
  fi
}
