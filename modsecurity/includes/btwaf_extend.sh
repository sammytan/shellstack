#!/bin/bash
# 从 ShellStack 站点或本地仓库获取 btwaf.tar.gz 并覆盖展开到 /www/server/btwaf
# 依赖 shared: log warn error LOG_FILE；可选: SHELLSTACK_BASE_URL / BTWAF_TAR_URL / BTWAF_INSTALL_DIR

BTWAF_INSTALL_DIR="${BTWAF_INSTALL_DIR:-/www/server/btwaf}"

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

# 下载 URL 到文件；成功且非空则返回 0
_btwaf_try_download_to() {
  local url="$1"
  local out="$2"
  rm -f "$out"
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL --connect-timeout 15 --max-time 180 "$url" -o "$out" >>"$LOG_FILE" 2>&1 && [[ -s "$out" ]]; then
      return 0
    fi
  fi
  rm -f "$out"
  if command -v wget >/dev/null 2>&1; then
    if wget -q -O "$out" --timeout=180 "$url" >>"$LOG_FILE" 2>&1 && [[ -s "$out" ]]; then
      return 0
    fi
  fi
  rm -f "$out"
  return 1
}

# 与 shellstack 仓库同级的 btwaf-ext/btwaf.tar.gz（本地 git 检出或完整拷贝时可用）
_btwaf_local_tarball_path() {
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd 2>/dev/null)" || return 1
  if [[ -f "$root/btwaf-ext/btwaf.tar.gz" ]]; then
    echo "$root/btwaf-ext/btwaf.tar.gz"
  fi
}

extend_btwaf_cache_bundle() {
  local base="${SHELLSTACK_BASE_URL:-${BASE_URL:-https://shellstack.910918920801.xyz}}"
  local dest="$BTWAF_INSTALL_DIR"
  local tmp
  tmp="$(mktemp /tmp/btwaf-bundle.XXXXXX.tar.gz)"
  local got=0
  local u

  log "=========================================="
  log "扩展 BTwaf：下载并覆盖 $dest"
  log "=========================================="

  if [[ -n "${BTWAF_TAR_URL:-}" ]]; then
    log "使用 BTWAF_TAR_URL: $BTWAF_TAR_URL"
    if _btwaf_try_download_to "$BTWAF_TAR_URL" "$tmp"; then
      got=1
    fi
  else
    for u in \
      "$base/btwaf/btwaf.tar.gz" \
      "$base/btwaf-ext/btwaf.tar.gz" \
      "$base/modsecurity/btwaf/btwaf.tar.gz"; do
      log "尝试下载: $u"
      if _btwaf_try_download_to "$u" "$tmp"; then
        got=1
        break
      fi
    done
    if [[ "$got" -eq 0 ]]; then
      u="$(_btwaf_local_tarball_path)"
      if [[ -n "$u" ]]; then
        log "远程地址均不可用，使用本地仓库中的: $u"
        if cp -f "$u" "$tmp" 2>>"$LOG_FILE" && [[ -s "$tmp" ]]; then
          got=1
        fi
      fi
    fi
  fi

  if [[ "$got" -eq 0 ]]; then
    rm -f "$tmp"
    error "无法获取 btwaf.tar.gz（常见原因：站点未部署该文件返回 404）。请将仓库 btwaf-ext/btwaf.tar.gz 上传到站点路径之一: \$BASE/btwaf/ 或 \$BASE/btwaf-ext/，或设置 BTWAF_TAR_URL 为可访问的完整 URL。BASE 当前为: $base"
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
