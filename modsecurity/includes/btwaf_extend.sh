#!/bin/bash
# 从 ShellStack 站点下载 btwaf.tar.gz 并覆盖展开到 /www/server/btwaf（宝塔 BTwaf 目录）
# 依赖 shared: log warn error LOG_FILE；可选环境变量: SHELLSTACK_BASE_URL / BTWAF_TAR_URL / BTWAF_INSTALL_DIR

BTWAF_INSTALL_DIR="${BTWAF_INSTALL_DIR:-/www/server/btwaf}"

# 解析压缩包解压后的「内容根目录」（兼容包里为 btwaf/、btwaf/btwaf/ 或扁平结构）
_btwaf_resolve_extracted_root() {
  local stage="$1"
  if [[ -d "$stage/btwaf/btwaf" ]] && [[ -f "$stage/btwaf/btwaf/waf.lua" || -d "$stage/btwaf/btwaf/lib" ]]; then
    echo "$stage/btwaf/btwaf"
  elif [[ -d "$stage/btwaf" ]] && [[ -f "$stage/btwaf/waf.lua" || -d "$stage/btwaf/lib" ]]; then
    echo "$stage/btwaf"
  else
    echo "$stage"
  fi
}

extend_btwaf_cache_bundle() {
  local base="${SHELLSTACK_BASE_URL:-${BASE_URL:-https://shellstack.910918920801.xyz}}"
  local url="${BTWAF_TAR_URL:-$base/btwaf/btwaf.tar.gz}"
  local dest="$BTWAF_INSTALL_DIR"

  log "=========================================="
  log "扩展 BTwaf：下载并覆盖 $dest"
  log "URL: $url"
  log "=========================================="

  local tmp
  tmp="$(mktemp /tmp/btwaf-bundle.XXXXXX.tar.gz)"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$tmp" >>"$LOG_FILE" 2>&1 || rm -f "$tmp"
  fi
  if [[ ! -s "$tmp" ]] && command -v wget >/dev/null 2>&1; then
    wget -q -O "$tmp" "$url" >>"$LOG_FILE" 2>&1 || rm -f "$tmp"
  fi
  if [[ ! -s "$tmp" ]]; then
    error "无法下载 btwaf.tar.gz: $url（可设置 BTWAF_TAR_URL 覆盖地址）"
  fi

  local stage
  stage="$(mktemp -d /tmp/btwaf-staging.XXXXXX)"
  if ! tar -xzf "$tmp" -C "$stage" >>"$LOG_FILE" 2>&1; then
    rm -rf "$stage" "$tmp"
    error "解压 btwaf.tar.gz 失败，请查看 $LOG_FILE"
  fi
  rm -f "$tmp"

  local root
  root="$(_btwaf_resolve_extracted_root "$stage")"
  if [[ ! -d "$root" ]]; then
    rm -rf "$stage"
    error "解压结果无效: $stage"
  fi

  mkdir -p "$dest"
  if ! \cp -a "$root"/. "$dest"/; then
    rm -rf "$stage"
    error "复制到 $dest 失败"
  fi
  rm -rf "$stage"

  if [[ ! -f "$dest/waf.lua" ]] && [[ ! -f "$dest/init.lua" ]]; then
    warn "未在 $dest 发现 waf.lua 或 init.lua，请确认 btwaf.tar.gz 打包目录是否与宝塔 BTwaf 一致"
  fi

  log "BTwaf 已更新至 $dest（内容根: $root）"
}
