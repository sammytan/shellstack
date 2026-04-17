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
SHELLSTACK_REDIS_VER="${SHELLSTACK_REDIS_VER:-8.0.5}"
# _btwaf_fetch_overlay_via_http 成功时写入临时目录路径（勿用 $(...) 捕获，log() 会污染 stdout）
_SHELLSTACK_BTWAF_HTTP_STAGE=""

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

# 单次 HTTP 拉取：encoding_mode=auto 时 curl 使用 --compressed；identity 时强制不协商 br/zstd 等（部分环境解压异常时校验失败）
_btwaf_download_one_pass() {
  local url="$1"
  local out="$2"
  local ua="$3"
  local encoding_mode="${4:-auto}"
  rm -f "$out"
  if command -v curl >/dev/null 2>&1; then
    local cargs=(-fsSL -A "$ua" --connect-timeout 15 --max-time 180 -o "$out")
    if [[ "$encoding_mode" == "auto" ]]; then
      cargs=(--compressed "${cargs[@]}")
    else
      cargs=(-H "Accept-Encoding: identity" "${cargs[@]}")
    fi
    if curl "${cargs[@]}" "$url" >>"$LOG_FILE" 2>&1 && [[ -s "$out" ]]; then
      return 0
    fi
  fi
  rm -f "$out"
  if command -v wget >/dev/null 2>&1; then
    local wextra=()
    if [[ "$encoding_mode" == "auto" ]] && wget --help 2>&1 | grep -q -- '--compression'; then
      wextra=(--compression=auto)
    fi
    local wh=()
    if [[ "$encoding_mode" != "auto" ]]; then
      wh=(--header="Accept-Encoding: identity")
    fi
    if wget -q "${wextra[@]}" "${wh[@]}" -U "$ua" -O "$out" --timeout=180 "$url" >>"$LOG_FILE" 2>&1 && [[ -s "$out" ]]; then
      return 0
    fi
  fi
  rm -f "$out"
  return 1
}

# 下载扩展 Lua：先协商压缩；失败或后续校验非 Lua 时由调用方用 identity 再拉（见 _btwaf_fetch_overlay_via_http）
_btwaf_try_download_to() {
  local url="$1"
  local out="$2"
  local ua="${SHELLSTACK_BTWAF_DOWNLOAD_UA:-ShellStack-BTwaf-Extend/1.0 (+https://github.com/shellstack/shellstack)}"
  if _btwaf_download_one_pass "$url" "$out" "$ua" "auto"; then
    return 0
  fi
  _btwaf_download_one_pass "$url" "$out" "$ua" "identity"
}

_btwaf_cache_lua_debug_sample() {
  local f="$1"
  [[ "${SHELLSTACK_BTWAF_HTTP_DEBUG:-0}" == "1" ]] || return 0
  [[ -f "$f" ]] || return 0
  local n hex
  n=$(wc -c <"$f" 2>/dev/null | tr -d ' ')
  hex="$(head -c 48 "$f" 2>/dev/null | od -An -tx1 2>/dev/null | tr -s ' ' | head -c 200)"
  warn "BTWAF_HTTP_DEBUG cache.lua 样本: size=${n:-?} head48hex=${hex:-?}"
  head -n 8 "$f" 2>/dev/null | while IFS= read -r line; do warn "BTWAF_HTTP_DEBUG | $line"; done
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

# 与 overlay 同级：btwaf-ext/btwaf-OFFICIAL（官方全量，仅作本地参考，用于补齐 lib 下缺失的 resty 等）
# 可选覆盖：SHELLSTACK_BTWAF_OFFICIAL_REF=/path/to/btwaf-OFFICIAL
_btwaf_shellstack_official_reference_dir() {
  if [[ -n "${SHELLSTACK_BTWAF_OFFICIAL_REF:-}" ]]; then
    local o="${SHELLSTACK_BTWAF_OFFICIAL_REF}"
    if [[ -f "$o/resty/redis.lua" ]]; then
      echo "$o"
      return 0
    fi
    warn "SHELLSTACK_BTWAF_OFFICIAL_REF 无效或缺少 resty/redis.lua: $o"
  fi
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd 2>/dev/null)" || return 1
  if [[ -f "$root/btwaf-ext/btwaf-OFFICIAL/resty/redis.lua" ]]; then
    echo "$root/btwaf-ext/btwaf-OFFICIAL"
    return 0
  fi
  return 1
}

# init.lua 的 package.path 含 BTWAF_LIB/?.lua，require "resty.redis" 只认 .../lib/resty/redis.lua。
# 官方包常把 resty 放在安装根目录 resty/，若未同步到 lib/resty/ 则 cache.lua 会报 module not found。
# 此处从：① 仓库 btwaf-OFFICIAL ② 已安装的 $BTWAF/resty/redis.lua 复制到 lib/resty/（不依赖 HTTP）。
_btwaf_ensure_lib_resty_redis() {
  local dest="${BTWAF_INSTALL_DIR:-/www/server/btwaf}"
  local target="$dest/lib/resty/redis.lua"
  local src=""

  if [[ -f "$target" ]] && [[ -s "$target" ]]; then
    log "已存在 $target，跳过 resty.redis 补齐"
    return 0
  fi

  if src="$(_btwaf_shellstack_official_reference_dir 2>/dev/null)" && [[ -n "$src" ]]; then
    if [[ -f "$src/resty/redis.lua" ]]; then
      mkdir -p "$dest/lib/resty"
      _btwaf_chattr_unlock_path "$target"
      if \cp -a "$src/resty/redis.lua" "$target" 2>>"$LOG_FILE"; then
        log "已从本地参考目录复制 resty/redis.lua -> $target ($src)"
        chmod 644 "$target" 2>/dev/null || true
        return 0
      fi
    fi
  fi

  if [[ -f "$dest/resty/redis.lua" ]] && [[ -s "$dest/resty/redis.lua" ]]; then
    mkdir -p "$dest/lib/resty"
    _btwaf_chattr_unlock_path "$target"
    if \cp -a "$dest/resty/redis.lua" "$target" 2>>"$LOG_FILE"; then
      log "已从 $dest/resty/redis.lua 复制到 $target（与官方根目录布局一致）"
      chmod 644 "$target" 2>/dev/null || true
      return 0
    fi
  fi

  warn "无法补齐 lib/resty/redis.lua：① 仓库无 btwaf-ext/btwaf-OFFICIAL/resty/redis.lua；② $dest/resty/redis.lua 不存在。cache.lua 将降级（无 Redis 缓存）。克隆完整 shellstack 后重跑 --extend-btwaf-cache，或设 SHELLSTACK_BTWAF_OFFICIAL_REF=官方目录。"
}

_shellstack_redis_responds() {
  local cli
  for cli in /www/server/redis/src/redis-cli /www/server/redis/bin/redis-cli /usr/local/redis/bin/redis-cli redis-cli; do
    if [[ -x "$cli" ]]; then
      "$cli" -h 127.0.0.1 -p 6379 ping 2>/dev/null | grep -q PONG && return 0
    elif [[ "$cli" == redis-cli ]] && command -v redis-cli >/dev/null 2>&1; then
      redis-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null | grep -q PONG && return 0
    fi
  done
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | grep -qE '127\.0\.0\.1:6379|[0-9.]+:6379|\*:6379|:::6379' && return 0
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -lntp 2>/dev/null | grep -qE ':6379' && return 0
  fi
  return 1
}

# 已装 Redis / 6379 已占用则跳过 install_soft（比仅 ping 更宽：进程、端口）
_shellstack_redis_skip_install_soft() {
  if _shellstack_redis_responds; then
    log "Redis 检测: 127.0.0.1:6379 可 ping 或端口已监听"
    return 0
  fi
  if pgrep -x redis-server >/dev/null 2>&1 || pgrep -f '[/]redis-server' >/dev/null 2>&1; then
    log "Redis 检测: 已存在 redis-server 进程，跳过 install_soft（若无法连接请检查密码/绑定地址）"
    return 0
  fi
  if [[ -d /www/server/redis ]] && { [[ -f /www/server/redis/src/redis-server ]] || [[ -x /www/server/redis/src/redis-cli ]] || [[ -x /www/server/redis/bin/redis-cli ]]; }; then
    log "Redis 检测: 已存在宝塔 Redis 安装目录/二进制，跳过 install_soft"
    return 0
  fi
  return 1
}

# 将大版本映射为宝塔软件商店的具体版本号（与 install_soft.sh 参数一致）
_btwaf_normalize_redis_version() {
  local v="${1:-8.0.5}"
  case "$v" in
    latest) echo "8.4.0" ;;
    8|8.0) echo "8.0.5" ;;
    8.2) echo "8.2.3" ;;
    8.4) echo "8.4.0" ;;
    7|7.4) echo "7.4.7" ;;
    7.2) echo "7.2.12" ;;
    7.0) echo "7.0.11" ;;
    6|6.2) echo "6.2.21" ;;
    *) echo "$v" ;;
  esac
}

_btwaf_chattr_unlock_path() {
  local p="$1"
  [[ -e "$p" ]] || return 0
  chattr -R -ia "$p" 2>>"$LOG_FILE" || chattr -ia "$p" 2>>"$LOG_FILE" || true
}

# 与面板 install.sh 中 Check_install 一致（socket），并补充：部分环境 socket 路径不同，但 waf 已部署则视为已装
_btwaf_panel_btwaf_already_installed() {
  if [[ -e /www/server/btwaf/socket ]]; then
    return 0
  fi
  if [[ -f /www/server/btwaf/waf.lua ]] && [[ -f /www/server/btwaf/init.lua ]]; then
    return 0
  fi
  return 1
}

_btwaf_run_panel_btwaf_install() {
  local ins="$BTWAF_PLUGIN_DIR/install.sh"
  if [[ ! -f "$ins" ]]; then
    error "未找到面板 BTwaf 安装脚本: $ins。

请先在宝塔面板中打开「软件商店」，安装「宝塔网站防火墙」，并在面板中进入网站防火墙（WAF）侧完成安装后，再在本机执行：

curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s modsecurity --extend-btwaf-cache"
  fi
  if [[ "${SHELLSTACK_BTWAF_PANEL_INSTALL:-1}" != "1" ]]; then
    log "SHELLSTACK_BTWAF_PANEL_INSTALL=0，跳过面板 install.sh install"
    return 0
  fi
  if [[ "${SHELLSTACK_BTWAF_FORCE_PANEL_INSTALL:-0}" != "1" ]] && _btwaf_panel_btwaf_already_installed; then
    log "预检: BTwaf 已安装（/www/server/btwaf/socket 存在，或 waf.lua+init.lua 已部署），跳过 install.sh install"
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
  if _shellstack_redis_skip_install_soft; then
    return 0
  fi
  local soft_install="$BT_PANEL_INSTALL_DIR/install_soft.sh"
  local redis_ver
  redis_ver="$(_btwaf_normalize_redis_version "${SHELLSTACK_REDIS_VER:-8.0.5}")"
  if [[ ! -f "$soft_install" ]]; then
    warn "未找到 $soft_install，无法自动安装 Redis；请手动安装 Redis 并监听 6379"
    return 0
  fi
  log "通过宝塔 install_soft 安装 Redis ${redis_ver}（与面板版本号一致）..."
  if ( cd "$BT_PANEL_INSTALL_DIR" && bash install_soft.sh 4 install redis "${redis_ver}" >>"$LOG_FILE" 2>&1 ); then
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

# 在官方 header.lua 末尾追加一行：header_filter 阶段把 shellstack 缓存状态写入响应头（对抗 proxy 覆盖 access 阶段 ngx.header）
# 官方 body.lua：run_body 在 body_character_len==0 且非 crawler 时直接 return，eof 从不执行 → Redis 永不写入。
# 去掉该行并在 ngx.arg[1]=whole 后注入 schedule_body_page_cache（与 lib/cache.lua 配套）。
_btwaf_ensure_body_lua_page_cache() {
  local bf="${BTWAF_INSTALL_DIR:-/www/server/btwaf}/body.lua"
  [[ -f "$bf" ]] || {
    warn "未找到 $bf，跳过 body 页缓存修补"
    return 0
  }
  if grep -q 'shellstack_body_page_cache' "$bf" 2>/dev/null; then
    log "body.lua 已含 shellstack_body_page_cache 标记，跳过自动修补"
    return 0
  fi
  _btwaf_chattr_unlock_path "$bf"
  if ! command -v perl >/dev/null 2>&1; then
    warn "未检测到 perl，无法自动修补 body.lua；请使用仓库 btwaf-ext/btwaf/body.lua 覆盖 $bf"
    return 0
  fi
  perl -0777 -i -pe '
  s/\n[ \t]*if BTWAF_RULES\.body_character_len==0 and ngx\.ctx\.crawler_html==false then return false end\n/\n-- shellstack_body_page_cache: removed early return\n/s;
  s/(ngx\.arg\[1\]=whole)\n(\s+end)/$1\n            -- shellstack_body_page_cache\n            do\n                local okc, c = pcall(require, "cache")\n                if okc and c and type(c.schedule_body_page_cache) == "function" then\n                    c.schedule_body_page_cache(180, whole)\n                end\n            end\n$2/s;
' "$bf" 2>>"$LOG_FILE" || true
  if grep -q 'shellstack_body_page_cache' "$bf" 2>/dev/null && grep -q 'schedule_body_page_cache' "$bf" 2>/dev/null; then
    log "已修补 $bf（允许无敏感词规则时仍写入 Redis 页缓存）"
    return 0
  fi
  warn "body.lua 自动修补未完全生效，请手动复制仓库 btwaf-ext/btwaf/body.lua 到 $bf"
}

_btwaf_ensure_header_lua_shellstack_hook() {
  local hf="${BTWAF_INSTALL_DIR:-/www/server/btwaf}/header.lua"
  [[ -f "$hf" ]] || {
    warn "未找到 $hf，跳过 shellstack header_filter 钩子（响应头可能无 X-Shellstack-*）"
    return 0
  }
  if grep -q 'shellstack_header_filter_cache' "$hf" 2>/dev/null; then
    log "header.lua 已含 shellstack header_filter 钩子，跳过"
    return 0
  fi
  _btwaf_chattr_unlock_path "$hf"
  {
    echo ""
    echo "-- shellstack_header_filter_cache (auto by shellstack --extend-btwaf-cache)"
    echo "do"
    echo "  local _ok, _c = pcall(require, \"cache\")"
    echo "  if _ok and _c and type(_c.apply_header_filter_headers) == \"function\" then"
    echo "    _c.apply_header_filter_headers()"
    echo "  end"
    echo "end"
  } >>"$hf"
  log "已向 $hf 追加 shellstack header_filter 钩子（输出 X-Shellstack-Cache*）"
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

# 过滤 404 HTML 等非 Lua 内容（须与 btwaf-ext/btwaf/lib/cache.lua 实际关键字一致）
_btwaf_cache_lua_looks_valid() {
  local f="$1"
  [[ -s "$f" ]] || return 1
  # 仍为 gzip 时（未解压）：前 2 字节 1f 8b
  local magic
  magic="$(head -c 2 "$f" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')"
  if [[ "$magic" == "1f8b" ]]; then
    warn "下载内容仍为 gzip 压缩（1f 8b），请升级 curl（支持 --compressed）或检查站点是否强制返回 br/zstd"
    return 1
  fi
  # 只把「像整页错误 HTML」的判掉：须在某行前部以 <!DOCTYPE html 或 <html 开头（避免 cache.lua 源码里的 "<!doctype html" 子串误伤）
  if head -n 50 "$f" 2>/dev/null | grep -qiE '^[[:space:]]*<!DOCTYPE[[:space:]]+html|^[[:space:]]*<html[[:space:]]' 2>/dev/null; then
    return 1
  fi
  # pcall(require, "resty.redis") 无括号紧挨 require，须直接匹配 resty.redis / 其它稳定锚点
  if grep -qE 'resty\.redis|schedule_body_page_cache|try_access_cache_hit|get_page_cache_hash_key|btwaf_cms_cache' "$f" 2>/dev/null; then
    return 0
  fi
  # 兜底：足够大且前几行像 Lua；或前 2KB 内出现 resty.redis（兼容 UTF-8 BOM 导致首行不匹配 ^--）
  local sz
  sz=$(wc -c <"$f" 2>/dev/null | tr -d ' ')
  [[ "${sz:-0}" -ge 400 ]] || return 1
  if head -n 15 "$f" | grep -qE '^[[:space:]]*(--|local )' 2>/dev/null; then
    return 0
  fi
  if head -c 2048 "$f" 2>/dev/null | grep -qF 'resty.redis' 2>/dev/null; then
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
    # 与仓库目录一致：站点 root 下为 btwaf-ext/btwaf（非 /shellstack/btwaf-ext/，除非你把整站挂在子路径）
    # 子路径发布时：SHELLSTACK_BTWAF_OVERLAY_BASE_URL=https://域名/前缀/btwaf-ext/btwaf
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
    local ua="${SHELLSTACK_BTWAF_DOWNLOAD_UA:-ShellStack-BTwaf-Extend/1.0 (+https://github.com/shellstack/shellstack)}"
    local dlok=0
    if _btwaf_download_one_pass "$b/lib/cache.lua" "$stage/lib/cache.lua" "$ua" "auto" && [[ -s "$stage/lib/cache.lua" ]]; then
      dlok=1
    fi
    if [[ "$dlok" == "1" ]] && ! _btwaf_cache_lua_looks_valid "$stage/lib/cache.lua"; then
      log "lib/cache.lua 校验未通过，改用 Accept-Encoding: identity 重拉: $b/lib/cache.lua"
      _btwaf_cache_lua_debug_sample "$stage/lib/cache.lua"
      dlok=0
      if _btwaf_download_one_pass "$b/lib/cache.lua" "$stage/lib/cache.lua" "$ua" "identity" && [[ -s "$stage/lib/cache.lua" ]]; then
        dlok=1
      fi
    fi
    if [[ "$dlok" == "1" ]] && _btwaf_cache_lua_looks_valid "$stage/lib/cache.lua"; then
      log "已下载并校验 lib/cache.lua"
      if _btwaf_try_download_to "$b/body.lua" "$stage/body.lua" && [[ -s "$stage/body.lua" ]]; then
        log "已下载 body.lua"
      fi
      if _btwaf_try_download_to "$b/waf.lua" "$stage/waf.lua" && [[ -s "$stage/waf.lua" ]]; then
        log "已下载 waf.lua"
      fi
      _SHELLSTACK_BTWAF_HTTP_STAGE="$stage"
      return 0
    fi
    if [[ "$dlok" == "1" ]]; then
      _btwaf_cache_lua_debug_sample "$stage/lib/cache.lua"
      warn "URL 返回内容不是有效 cache.lua: $b/lib/cache.lua（可设 SHELLSTACK_BTWAF_HTTP_DEBUG=1 查看样本；若站点 location / 使用 charset utf-8,gbk，请为 ^~ /btwaf-ext/ 单独 charset off，见 nginx-config-example.conf）"
    fi
    rm -f "$stage/lib/cache.lua"
  done
  warn "HTTP 未成功拉取 lib/cache.lua。请确认：① 磁盘路径存在 \$root/btwaf-ext/btwaf/lib/cache.lua；② URL 200 且为 Lua；③ Nginx 未对 .lua 403；④ 静态站避免在 /btwaf-ext 上 charset 转码 body；⑤ 详见 nginx-config-example.conf / TROUBLESHOOTING.md"
  rm -rf "$stage"
  _SHELLSTACK_BTWAF_HTTP_STAGE=""
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
    if _btwaf_fetch_overlay_via_http; then
      tmp_stage="${_SHELLSTACK_BTWAF_HTTP_STAGE}"
      _SHELLSTACK_BTWAF_HTTP_STAGE=""
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
    if _btwaf_try_download_to "${SHELLSTACK_BTWAF_CACHE_LUA_URL}" "$dest/lib/cache.lua" && _btwaf_cache_lua_looks_valid "$dest/lib/cache.lua"; then
      log "已写入 $dest/lib/cache.lua（单文件 URL）"
    else
      rm -f "$dest/lib/cache.lua"
      warn "SHELLSTACK_BTWAF_CACHE_LUA_URL 下载失败或内容非有效 Lua"
    fi
  fi

  chmod 644 "$dest/body.lua" "$dest/lib/cache.lua" "$dest/waf.lua" 2>/dev/null || true
}

# 官方 waf.lua 仅在末尾 pcall(btwaf_run)。页缓存 try_access_cache_hit 必须在 btwaf_run 成功之后调用，
# 否则 Redis HIT 会 ngx.exit(200) 并跳过整段宝塔 WAF。注入位置：将「if not ok then ... end」改为带 else 分支。
_btwaf_ensure_waf_cache_hit_hook() {
  local waf="$BTWAF_INSTALL_DIR/waf.lua"
  [[ -f "$waf" ]] || return 0
  if grep -q 'shellstack_page_cache_after_btwaf' "$waf" 2>/dev/null; then
    log "waf.lua 已将页缓存置于 WAF 之后（shellstack_page_cache_after_btwaf），跳过注入"
    return 0
  fi
  _btwaf_chattr_unlock_path "$waf"
  if ! command -v perl >/dev/null 2>&1; then
    warn "未检测到 perl，无法自动注入 waf.lua；请复制仓库 btwaf-ext/btwaf/waf.lua 覆盖 $waf"
    return 0
  fi
  perl -0777 -i -pe '
  BEGIN {
    $else_blk = qq{\nelse\n    -- shellstack_page_cache_after_btwaf (auto: shellstack --extend-btwaf-cache)\n    do\n        local _ok, _c = pcall(require, "cache")\n        if not _ok then\n            ngx.log(ngx.ERR, "[shellstack-cache] require cache failed: ", tostring(_c))\n        elseif _c and type(_c.try_access_cache_hit) == "function" then\n            _c.try_access_cache_hit()\n        end\n    end};
  }
  # 去掉旧版「btwaf_run 之前」注入块，避免重复 try_access 且旁路 WAF
  s{\R-- shellstack_cache_access[^\R]*\Rdo\R    local _ok, _c = pcall\(require, "cache"\)[\s\S]*?\Rend\R}{}s;
  # 在「if not ok … btwaf_access … end」与文件末尾「end」之间插入 else 分支（兼容 180/360 等 TTL 与中间注释行）
  s{(if not ok then\s*\R(?:[^\R]*\R)*?\s*if not ngx\.shared\.spider:get\("btwaf_access"\) then\s*\R\s*Public\.logs\(error\)\s*\R\s*ngx\.shared\.spider:set\("btwaf_access",1,\d+\)\s*\R\s*end\s*\R)(end\s*\z)}{$1$else_blk\R$2}s
    or die "shellstack_waf_inject_no_match\n";
' "$waf" 2>>"$LOG_FILE" || {
    warn "无法在 $waf 自动注入页缓存（未识别宝塔 pcall 尾部或 perl 失败）。请用仓库 btwaf-ext/btwaf/waf.lua 覆盖后重试。"
    return 0
  }
  if grep -q 'shellstack_page_cache_after_btwaf' "$waf" 2>/dev/null; then
    log "已向 $waf 注入 shellstack_page_cache_after_btwaf（pcall 成功后，WAF 之后）"
    return 0
  fi
  warn "waf.lua 注入后未找到 shellstack_page_cache_after_btwaf 标记，请检查 $waf"
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
  _btwaf_ensure_body_lua_page_cache
  _btwaf_ensure_lib_resty_redis
  _btwaf_ensure_waf_cache_hit_hook
  _btwaf_ensure_init_requires_cache_module
  _btwaf_ensure_header_lua_shellstack_hook
  _btwaf_ensure_nginx_btwaf_conf_cache_shared

  if [[ ! -f "$BTWAF_INSTALL_DIR/lib/cache.lua" ]]; then
    local _bu="${SHELLSTACK_BASE_URL:-${BASE_URL:-https://shellstack.910918920801.xyz}}"
    _bu="${_bu%/}"
    warn "未找到 $BTWAF_INSTALL_DIR/lib/cache.lua。请保证可访问: ${_bu}/btwaf-ext/btwaf/lib/cache.lua（返回 200）。若 wget 为 403，多为 Nginx 拦截 .lua，需配置 location ^~ /btwaf-ext/。也可 SHELLSTACK_BTWAF_OVERLAY_SRC=/本机路径/btwaf 或 SHELLSTACK_BTWAF_CACHE_LUA_URL=直链。"
  fi

  log "BTwaf 扩展步骤完成（含 access 阶段 Redis 命中 + body 阶段写入）。升级官方 WAF 后若丢失扩展，请重新执行 --extend-btwaf-cache。"
}
