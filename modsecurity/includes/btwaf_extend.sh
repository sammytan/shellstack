#!/bin/bash
# 宝塔 BTwaf：默认执行面板 install.sh 安装官方 WAF，再安装 Redis，最后仅覆盖扩展文件（避免全量替换导致无法跟随官方更新）
# 可选：SHELLSTACK_BTWAF_LEGACY_TARBALL=1 时仍支持从站点下载 btwaf.tar.gz 全量覆盖（旧行为）
# 依赖 shared: log warn error LOG_FILE

BTWAF_INSTALL_DIR="${BTWAF_INSTALL_DIR:-/www/server/btwaf}"
BTWAF_NGINX_CONF="${BTWAF_NGINX_CONF:-/www/server/panel/vhost/nginx/btwaf.conf}"
BT_PANEL_INSTALL_DIR="${BT_PANEL_INSTALL_DIR:-/www/server/panel/install}"
BTWAF_PLUGIN_DIR="${BTWAF_PLUGIN_DIR:-/www/server/panel/plugin/btwaf}"
# 为 0 时跳过 bash install.sh install（假定你已手动装过面板 WAF）
SHELLSTACK_BTWAF_PANEL_INSTALL="${SHELLSTACK_BTWAF_PANEL_INSTALL:-1}"
# 为 1 时无视「已安装」检测，仍执行 install.sh install（修复/强制重装；与面板 Check_install 相反）
SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL="${SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL:-0}"
# 手动指定已上传到服务器的 btwaf 扩展目录（须含 lib/cache.lua），优先于脚本旁 btwaf-ext/btwaf
SHELLSTACK_BTWAF_OVERLAY_SRC="${SHELLSTACK_BTWAF_OVERLAY_SRC:-}"
# HTTP 扩展根路径（可访问 .../lib/cache.lua），默认 $BASE_URL/btwaf-ext/btwaf
SHELLSTACK_BTWAF_OVERLAY_BASE_URL="${SHELLSTACK_BTWAF_OVERLAY_BASE_URL:-}"
# 仅 lib/cache.lua 的直接下载地址（本地与 HTTP 根均失败时的兜底）
SHELLSTACK_BTWAF_CACHE_LUA_URL="${SHELLSTACK_BTWAF_CACHE_LUA_URL:-}"
# 为 1 时执行旧逻辑：下载 btwaf.tar.gz 全量解压到 BTWAF_INSTALL_DIR（可与面板安装叠加，一般不建议）
SHELLSTACK_BTWAF_LEGACY_TARBALL="${SHELLSTACK_BTWAF_LEGACY_TARBALL:-0}"
# 为 0 时跳过宝塔 install_soft 安装 Redis
SHELLSTACK_INSTALL_REDIS="${SHELLSTACK_INSTALL_REDIS:-1}"
SHELLSTACK_REDIS_VER="${SHELLSTACK_REDIS_VER:-8.0}"

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

_btwaf_local_tarball_path() {
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd 2>/dev/null)" || return 1
  if [[ -f "$root/btwaf-ext/btwaf.tar.gz" ]]; then
    echo "$root/btwaf-ext/btwaf.tar.gz"
  fi
}

# 与 modsecurity/includes 同级的 btwaf-ext/btwaf（Lua 扩展源码）
_btwaf_shellstack_repo_overlay_dir() {
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd 2>/dev/null)" || return 1
  if [[ -d "$root/btwaf-ext/btwaf" ]]; then
    echo "$root/btwaf-ext/btwaf"
    return 0
  fi
  return 1
}

_shellstack_redis_responds() {
  if command -v redis-cli >/dev/null 2>&1; then
    redis-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null | grep -q PONG && return 0
  fi
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | grep -qE '127\.0\.0\.1:6379|:6379' && return 0
  fi
  return 1
}

_btwaf_chattr_unlock_path() {
  local p="$1"
  [[ -e "$p" ]] || return 0
  chattr -R -ia "$p" 2>>"$LOG_FILE" || chattr -ia "$p" 2>>"$LOG_FILE" || true
}

# 与宝塔 /www/server/panel/plugin/btwaf/install.sh 末尾 Check_install 一致：仅当不存在 /www/server/btwaf/socket 时才应跑完整 Install_btwaf
_btwaf_panel_btwaf_already_installed() {
  [[ -d /www/server/btwaf/socket ]]
}

_btwaf_run_panel_btwaf_install() {
  local ins="$BTWAF_PLUGIN_DIR/install.sh"
  if [[ ! -f "$ins" ]]; then
    error "未找到面板 BTwaf 安装脚本: $ins。请先在宝塔「软件商店」安装「宝塔网站防火墙」插件后再执行 --extend-btwaf-cache。"
  fi
  if [[ "${SHELLSTACK_BTWAF_PANEL_INSTALL:-1}" != "1" ]]; then
    log "SHELLSTACK_BTWAF_PANEL_INSTALL=0，跳过面板 install.sh install"
    return 0
  fi
  if [[ "${SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL:-0}" != "1" ]] && _btwaf_panel_btwaf_already_installed; then
    log "检测到 BTwaf 已安装（存在 /www/server/btwaf/socket，与面板 install.sh 中 Check_install 判定一致），跳过 install.sh install"
    return 0
  fi
  if [[ "${SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL:-0}" == "1" ]]; then
    log "SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL=1，将强制执行面板 install.sh install"
  fi
  log "执行面板 BTwaf 安装: cd $BTWAF_PLUGIN_DIR && bash install.sh install"
  if ( cd "$BTWAF_PLUGIN_DIR" && bash install.sh install >>"$LOG_FILE" 2>&1 ); then
    log "面板 BTwaf install.sh install 已执行完成（日志见 $LOG_FILE）"
  else
    warn "面板 BTwaf install.sh 退出非 0，请检查 $LOG_FILE；若 WAF 已可用可设 SHELLSTACK_BTWAF_PANEL_INSTALL=0 跳过"
  fi
}

_btwaf_install_redis_via_panel() {
  [[ "${SHELLSTACK_INSTALL_REDIS:-1}" == "1" ]] || return 0
  if _shellstack_redis_responds; then
    log "检测到 Redis 已在 127.0.0.1:6379 可用，跳过 install_soft 安装"
    return 0
  fi
  local soft_install="$BT_PANEL_INSTALL_DIR/install_soft.sh"
  if [[ ! -f "$soft_install" ]]; then
    warn "未找到 $soft_install，无法自动安装 Redis；请手动安装 Redis 并监听 6379"
    return 0
  fi
  log "通过宝塔 install_soft 安装 Redis ${SHELLSTACK_REDIS_VER}（与面板一致）..."
  if ( cd "$BT_PANEL_INSTALL_DIR" && bash install_soft.sh 4 install redis "${SHELLSTACK_REDIS_VER}" >>"$LOG_FILE" 2>&1 ); then
    log "install_soft redis 已执行（详见 $LOG_FILE）"
  else
    warn "install_soft 安装 Redis 可能失败，请检查 $LOG_FILE 并确认 redis-cli ping"
  fi
}

_btwaf_ensure_nginx_btwaf_conf_cache_shared() {
  local conf="$BTWAF_NGINX_CONF"
  [[ -f "$conf" ]] || {
    warn "未找到 $conf，跳过 lua_shared_dict cache_shared 注入（请确认 WAF 已正确安装）"
    return 0
  }
  if grep -qF 'lua_shared_dict cache_shared' "$conf" 2>/dev/null; then
    log "$conf 已包含 lua_shared_dict cache_shared，跳过"
    return 0
  fi
  _btwaf_chattr_unlock_path "$conf"
  if grep -qF 'lua_shared_dict ualru' "$conf" 2>/dev/null; then
    sed -i '/lua_shared_dict ualru/a lua_shared_dict cache_shared 5000m;' "$conf"
  else
    sed -i '/^[[:space:]]*init_by_lua_file/i lua_shared_dict cache_shared 5000m;' "$conf"
  fi
  log "已向 $conf 注入 lua_shared_dict cache_shared 5000m;"
}

_btwaf_ensure_init_requires_cache_module() {
  local init="$BTWAF_INSTALL_DIR/init.lua"
  [[ -f "$init" ]] || return 0
  if grep -qF 'require "cache"' "$init" 2>/dev/null; then
    log "init.lua 已包含 require \"cache\"，跳过插入"
    return 0
  fi
  _btwaf_chattr_unlock_path "$init"
  if grep -q 'Json = require "cjson"' "$init" 2>/dev/null; then
    sed -i '/Json = require "cjson"/a cache = require "cache"' "$init"
    log "已在 init.lua 中 Json = require \"cjson\" 之后插入 cache = require \"cache\""
    return 0
  fi
  if command -v perl >/dev/null 2>&1; then
    if perl -i -pe 'BEGIN{$d=0} if(!$d && /=\s*require\s*\(?["'\'']cjson["'\'']\)?/){$_ .= "cache = require \"cache\"\n"; $d=1}' "$init" 2>>"$LOG_FILE"; then
      if grep -qF 'require "cache"' "$init" 2>/dev/null; then
        log "已通过 perl 在 init.lua 首处 require cjson 后插入 cache = require \"cache\""
        return 0
      fi
    fi
  fi
  warn "无法在 init.lua 中自动插入 cache = require \"cache\"（请安装 perl 或设 SHELLSTACK_BTWAF_OVERLAY_INIT_LUA=1 并保留仓库 btwaf-ext/btwaf/init.lua）"
}

# 返回可读的 btwaf 扩展目录（含 lib/cache.lua）：SHELLSTACK_BTWAF_OVERLAY_SRC > 与 includes 同级的 btwaf-ext/btwaf
_btwaf_resolve_local_overlay_src() {
  if [[ -n "${SHELLSTACK_BTWAF_OVERLAY_SRC:-}" ]]; then
    local o="${SHELLSTACK_BTWAF_OVERLAY_SRC}"
    if [[ -d "$o" ]] && [[ -f "$o/lib/cache.lua" ]]; then
      echo "$o"
      return 0
    fi
    warn "SHELLSTACK_BTWAF_OVERLAY_SRC 无效或缺少 lib/cache.lua: $o"
  fi
  local repo
  repo="$(_btwaf_shellstack_repo_overlay_dir 2>/dev/null)" || true
  if [[ -n "$repo" ]] && [[ -f "$repo/lib/cache.lua" ]]; then
    echo "$repo"
    return 0
  fi
  return 1
}

# 从站点拉取与仓库同路径的扩展文件（至少 lib/cache.lua）
_btwaf_fetch_overlay_via_http() {
  local stage
  stage="$(mktemp -d /tmp/btwaf-overlay.XXXXXX)"
  mkdir -p "$stage/lib"
  local root="${SHELLSTACK_BASE_URL:-${BASE_URL:-https://shellstack.910918920801.xyz}}"
  root="${root%/}"
  local bases=()
  if [[ -n "${SHELLSTACK_BTWAF_OVERLAY_BASE_URL:-}" ]]; then
    bases+=("${SHELLSTACK_BTWAF_OVERLAY_BASE_URL%/}")
  else
    bases+=(
      "$root/btwaf-ext/btwaf"
      "$root/modsecurity/btwaf-overlay"
    )
  fi
  local b
  for b in "${bases[@]}"; do
    [[ -n "$b" ]] || continue
    rm -f "$stage/lib/cache.lua" "$stage/body.lua" "$stage/waf.lua"
    log "尝试下载 BTwaf 扩展: $b/lib/cache.lua"
    if _btwaf_try_download_to "$b/lib/cache.lua" "$stage/lib/cache.lua" && [[ -s "$stage/lib/cache.lua" ]]; then
      log "已下载 lib/cache.lua"
      if _btwaf_try_download_to "$b/body.lua" "$stage/body.lua" && [[ -s "$stage/body.lua" ]]; then
        log "已下载 body.lua"
      fi
      if _btwaf_try_download_to "$b/waf.lua" "$stage/waf.lua" && [[ -s "$stage/waf.lua" ]]; then
        log "已下载 waf.lua"
      fi
      echo "$stage"
      return 0
    fi
  done
  rm -rf "$stage"
  return 1
}

_btwaf_overlay_repo_lua_files() {
  local dest="$BTWAF_INSTALL_DIR"
  mkdir -p "$dest/lib"
  local src=""
  local tmp_stage=""

  if src="$(_btwaf_resolve_local_overlay_src 2>/dev/null)" && [[ -n "$src" ]]; then
    log "使用本地扩展源: $src"
  else
    log "未找到本地 btwaf-ext/btwaf（或 SHELLSTACK_BTWAF_OVERLAY_SRC），尝试从 HTTP 下载扩展 Lua..."
    if tmp_stage="$(_btwaf_fetch_overlay_via_http)"; then
      src="$tmp_stage"
    fi
  fi

  if [[ -n "$src" ]] && [[ -f "$src/lib/cache.lua" ]]; then
    local files=(lib/cache.lua body.lua waf.lua)
    local f
    for f in "${files[@]}"; do
      if [[ -f "$src/$f" ]]; then
        _btwaf_chattr_unlock_path "$dest/$f"
        if \cp -a "$src/$f" "$dest/$f" 2>>"$LOG_FILE"; then
          log "已覆盖: $dest/$f"
        else
          warn "复制失败: $f"
        fi
      else
        [[ "$f" == "lib/cache.lua" ]] && warn "扩展源缺少必要文件: $f"
      fi
    done
    if [[ -f "$src/init.lua" ]] && [[ "${SHELLSTACK_BTWAF_OVERLAY_INIT_LUA:-0}" == "1" ]]; then
      _btwaf_chattr_unlock_path "$dest/init.lua"
      \cp -a "$src/init.lua" "$dest/init.lua" && log "已按 SHELLSTACK_BTWAF_OVERLAY_INIT_LUA=1 覆盖 init.lua"
    fi
  fi

  [[ -n "$tmp_stage" ]] && rm -rf "$tmp_stage"

  if [[ ! -f "$dest/lib/cache.lua" ]] && [[ -n "${SHELLSTACK_BTWAF_CACHE_LUA_URL:-}" ]]; then
    log "尝试从 SHELLSTACK_BTWAF_CACHE_LUA_URL 下载 lib/cache.lua"
    _btwaf_chattr_unlock_path "$dest/lib/cache.lua"
    if _btwaf_try_download_to "${SHELLSTACK_BTWAF_CACHE_LUA_URL}" "$dest/lib/cache.lua" && [[ -s "$dest/lib/cache.lua" ]]; then
      log "已写入 $dest/lib/cache.lua（单文件 URL）"
    else
      warn "SHELLSTACK_BTWAF_CACHE_LUA_URL 下载失败"
    fi
  fi

  chmod 644 "$dest/body.lua" "$dest/lib/cache.lua" "$dest/waf.lua" 2>/dev/null || true
}

# 若仓库未带 waf.lua，则在官方 waf.lua 的 pcall(btwaf_run) 前注入 access 缓存命中（与 lib/cache.lua 配套）
_btwaf_ensure_waf_cache_hit_hook() {
  local waf="$BTWAF_INSTALL_DIR/waf.lua"
  [[ -f "$waf" ]] || return 0
  if grep -qE 'try_access_cache_hit|shellstack-cache-hit' "$waf" 2>/dev/null; then
    log "waf.lua 已含 Redis access 缓存命中逻辑"
    return 0
  fi
  _btwaf_chattr_unlock_path "$waf"
  if ! command -v perl >/dev/null 2>&1; then
    warn "未检测到 perl，无法自动注入 waf.lua 缓存命中；请从仓库复制 btwaf-ext/btwaf/waf.lua 到 $waf"
    return 0
  fi
  if perl -i -0pe '
BEGIN {
  $b = "-- shellstack-cache-hit\ndo\n    local c = require \"cache\"\n    if c.try_access_cache_hit then\n        c.try_access_cache_hit()\n    end\nend\n\n";
}
s/\n(local ok\s*,\s*error\s*=\s*pcall\s*\(\s*function\s*\(\s*\)\s*\n)/\n$b$1/s
' "$waf" 2>>"$LOG_FILE"; then
    if grep -qE 'try_access_cache_hit|shellstack-cache-hit' "$waf" 2>/dev/null; then
      log "已向 waf.lua 注入 shellstack-cache-hit（pcall 锚点）"
      return 0
    fi
  fi
  warn "未在 waf.lua 中找到「local ok,error = pcall(function()」锚点，无法自动注入；请使用仓库中的 btwaf-ext/btwaf/waf.lua 覆盖"
}

_btwaf_legacy_tarball_bundle() {
  local base="${SHELLSTACK_BASE_URL:-${BASE_URL:-https://shellstack.910918920801.xyz}}"
  local dest="$BTWAF_INSTALL_DIR"
  local tmp
  tmp="$(mktemp /tmp/btwaf-bundle.XXXXXX.tar.gz)"
  local got=0
  local u

  log "=========================================="
  log "扩展 BTwaf（旧版）：下载 btwaf.tar.gz 全量覆盖 $dest"
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
    error "无法获取 btwaf.tar.gz（SHELLSTACK_BTWAF_LEGACY_TARBALL=1）。请上传 btwaf.tar.gz 到站点或设置 BTWAF_TAR_URL"
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
    warn "未在 $dest 发现 waf.lua 或 init.lua，请确认 btwaf.tar.gz 内容"
  fi

  log "BTwaf 全量包已解压至 $dest"
}

extend_btwaf_cache_bundle() {
  log "=========================================="
  log "--extend-btwaf-cache：BTwaf 扩展（面板安装 / Redis / 选择性覆盖）"
  log "=========================================="

  if [[ "${SHELLSTACK_BTWAF_LEGACY_TARBALL:-0}" == "1" ]]; then
    _btwaf_legacy_tarball_bundle
  fi

  _btwaf_run_panel_btwaf_install

  _btwaf_install_redis_via_panel
  _btwaf_overlay_repo_lua_files
  _btwaf_ensure_waf_cache_hit_hook
  _btwaf_ensure_init_requires_cache_module
  _btwaf_ensure_nginx_btwaf_conf_cache_shared

  if [[ ! -f "$BTWAF_INSTALL_DIR/lib/cache.lua" ]]; then
    local _bu="${SHELLSTACK_BASE_URL:-${BASE_URL:-https://shellstack.910918920801.xyz}}"
    _bu="${_bu%/}"
    warn "未找到 $BTWAF_INSTALL_DIR/lib/cache.lua。远程脚本默认从站点拉取扩展，基址为: ${_bu}（与 curl 管道执行时一致，可用环境变量 SHELLSTACK_BASE_URL 覆盖）。请保证可访问: ${_bu}/btwaf-ext/btwaf/lib/cache.lua（把仓库中的 btwaf-ext 目录按此路径发布到站点根目录）。也可设 SHELLSTACK_BTWAF_OVERLAY_SRC=/本机路径/btwaf 或 SHELLSTACK_BTWAF_CACHE_LUA_URL=单文件直链。"
  fi

  log "BTwaf 扩展步骤完成（含 access 阶段 Redis 命中 + body 阶段写入）。升级官方 WAF 后若丢失扩展，请重新执行 --extend-btwaf-cache。"
}
