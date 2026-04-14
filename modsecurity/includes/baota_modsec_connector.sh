#!/bin/bash
# 宝塔面板环境：通过 nginx_configure.pl 注入 --add-module，执行 panel nginx.sh update 编译 OpenResty + ModSecurity-nginx
# 依赖: 已安装 libmodsecurity（pkg-config libmodsecurity）、/www/server/panel/install/nginx.sh

MODSECURITY_NGX_CONNECTOR_DIR="${MODSECURITY_NGX_CONNECTOR_DIR:-/www/server/modsecurity-nginx}"
BT_PANEL_NGINX_SH="${BT_PANEL_NGINX_SH:-/www/server/panel/install/nginx.sh}"
BT_OPENRESTY_VERSION="${BT_OPENRESTY_VERSION:-openresty127}"
# 设为 1 时强制执行宝塔 nginx.sh update（跳过「已就绪」检测）
MODSECURITY_FORCE_BT_NGINX_REBUILD="${MODSECURITY_FORCE_BT_NGINX_REBUILD:-0}"

_baota_panel_present() {
  [[ -f "$BT_PANEL_NGINX_SH" ]] && [[ -f /www/server/panel/install/public.sh ]]
}

_clone_modsecurity_nginx_connector() {
  local dest="$1"
  if [[ -d "$dest/.git" ]]; then
    log "ModSecurity-nginx 连接器已存在: $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  local urls=(
    "https://github.com/SpiderLabs/ModSecurity-nginx.git"
    "https://gitee.com/mirrors/ModSecurity-nginx.git"
  )
  local u
  for u in "${urls[@]}"; do
    log "尝试克隆 ModSecurity-nginx: $u"
    if GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$u" "$dest" >>"$LOG_FILE" 2>&1; then
      return 0
    fi
  done
  return 1
}

_baota_merge_nginx_prepare_modsec() {
  local modsec_prefix="$1"
  local np="/www/server/panel/install/nginx_prepare.sh"
  local mark="# shellstack-modsec-PKG_CONFIG_PATH"
  if [[ -f "$np" ]] && grep -qF "$mark" "$np" 2>/dev/null; then
    return 0
  fi
  if [[ ! -f "$np" ]]; then
    echo "#!/bin/bash" > "$np"
    chmod +x "$np" 2>/dev/null || true
  fi
  cat >> "$np" << EOF

$mark
export PKG_CONFIG_PATH="${modsec_prefix}/lib/pkgconfig:\${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="${modsec_prefix}/lib:\${LD_LIBRARY_PATH:-}"
EOF
  log "已写入 $mark 到 nginx_prepare.sh（libmodsecurity 编译期可见性）"
}

_baota_ensure_nginx_config_pl() {
  local d="/www/server/panel/install/nginx"
  mkdir -p "$d"
  if [[ ! -f "$d/config.pl" ]]; then
    touch "$d/config.pl"
  fi
}

_baota_append_nginx_configure_modsecurity() {
  local connector_dir="$1"
  local cfg_pl="/www/server/panel/install/nginx_configure.pl"
  local flag="--add-module=${connector_dir}"
  # 每次都做一次稳健去重：兼容 CRLF、前后空白、历史重复行
  if [[ -f "$cfg_pl" ]] && [[ -s "$cfg_pl" ]]; then
    \cp -a "$cfg_pl" "${cfg_pl}.bak.shellstack.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    awk -v f="$flag" '
      {
        line=$0
        gsub(/\r/, "", line)
        sub(/^[ \t]+/, "", line)
        sub(/[ \t]+$/, "", line)
        if (line==f) {
          dup++
          next
        }
        print $0
      }
      END {
        # no-op
      }
    ' "$cfg_pl" > "${cfg_pl}.tmp.shellstack" && mv -f "${cfg_pl}.tmp.shellstack" "$cfg_pl"
  fi

  if grep -qF "$flag" "$cfg_pl" 2>/dev/null; then
    log "nginx_configure.pl 已存在 ModSecurity-nginx 标记（重复项已清理）: $flag"
  else
    echo "$flag" >> "$cfg_pl"
    log "已追加到 nginx_configure.pl: $flag"
  fi
}

# 当前 Nginx 是否已是「目标 OpenResty 键 + 已编进 ModSecurity-nginx」，可跳过重复 nginx.sh update
_baota_skip_openresty_rebuild_if_current() {
  [[ "${MODSECURITY_FORCE_BT_NGINX_REBUILD}" == "1" ]] && return 1

  local nginx_bin="/www/server/nginx/sbin/nginx"
  local vchk="/www/server/nginx/version_check.pl"
  local want="${BT_OPENRESTY_VERSION:-openresty127}"

  [[ -x "$nginx_bin" ]] || return 1
  if ! "$nginx_bin" -V 2>&1 | grep -qi modsecurity; then
    return 1
  fi
  [[ -f "$vchk" ]] || return 1

  local line
  line=$(head -1 "$vchk" | tr -d '[:space:]')

  case "$want" in
    openresty127)
      [[ "$line" == *openresty-1.27* ]] || [[ "$line" == *openresty-1.28* ]] || [[ "$line" == *openresty-1.29* ]] || return 1
      ;;
    openresty)
      [[ "$line" == *openresty-1.25* ]] || [[ "$line" == *openresty-1.24* ]] || [[ "$line" == *openresty-1.23* ]] || [[ "$line" == *openresty-1.26* ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac

  return 0
}

_baota_print_nginx_make_failure_snippet() {
  local mk="/tmp/nginx_make.pl"
  local cfg="/tmp/nginx_config.pl"
  warn "宝塔编译失败关键日志（自动摘录）:"
  if [[ -f "$mk" ]]; then
    local snip
    snip="$(rg -n -i '(^|[[:space:]])(error|undefined reference|fatal):|No such file|cannot find' "$mk" 2>/dev/null | head -n 40)"
    if [[ -n "$snip" ]]; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && warn "  $line"
      done <<< "$snip"
    else
      warn "  /tmp/nginx_make.pl 未匹配到明确 error 关键词，请手工查看完整文件"
    fi
  else
    warn "  未找到 /tmp/nginx_make.pl"
  fi
  if [[ -f "$cfg" ]]; then
    warn "  参考配置文件: $cfg"
  fi
}

_baota_post_build_verification() {
  local nginx_bin="/www/server/nginx/sbin/nginx"
  if [[ ! -x "$nginx_bin" ]]; then
    warn "验收: 未找到 $nginx_bin，跳过自动验收"
    return 0
  fi

  local vout
  vout="$("$nginx_bin" -V 2>&1)"
  log "验收: nginx -V 关键摘要"
  local ver_line cfg_line
  ver_line="$(echo "$vout" | awk 'NR==1{print; exit}')"
  cfg_line="$(echo "$vout" | awk 'NR==2{print; exit}')"
  [[ -n "$ver_line" ]] && log "  $ver_line"
  if echo "$cfg_line" | grep -q -- '--add-module='; then
    # 只保留与模块相关的参数，避免输出过长
    local mod_args
    mod_args="$(echo "$cfg_line" | tr ' ' '\n' | grep -- '--add-module=' | tr '\n' ' ')"
    [[ -n "$mod_args" ]] && log "  configure modules: $mod_args"
  fi

  if echo "$vout" | grep -qi modsecurity; then
    log "验收: nginx -V 已包含 modsecurity"
  else
    warn "验收: nginx -V 未包含 modsecurity，请检查 /tmp/nginx_config.pl 与 /tmp/nginx_make.pl"
  fi

  if "$nginx_bin" -t >/tmp/shellstack-nginx-test.log 2>&1; then
    log "验收: nginx -t 通过"
  else
    warn "验收: nginx -t 失败（摘要如下）"
    while IFS= read -r line; do
      [[ -n "$line" ]] && warn "  $line"
    done < /tmp/shellstack-nginx-test.log
  fi
}

# 检测宝塔并升级/重编译 OpenResty，静态链接 ModSecurity-nginx 连接器
baota_install_openresty_with_modsecurity_connector() {
  if ! _baota_panel_present; then
    warn "未检测到宝塔面板（缺少 $BT_PANEL_NGINX_SH），跳过 OpenResty + ModSecurity-nginx 编译。"
    return 0
  fi

  if _baota_skip_openresty_rebuild_if_current; then
    log "当前 OpenResty（version_check.pl: $(head -1 /www/server/nginx/version_check.pl 2>/dev/null | tr -d '\n')）已包含 ModSecurity，且与 --bt-openresty=${BT_OPENRESTY_VERSION} 一致，跳过重复执行 nginx.sh update。"
    log "若需强制重新编译 Nginx，请设置: export MODSECURITY_FORCE_BT_NGINX_REBUILD=1 后重跑。"
    if nginx -V 2>&1 | grep -qi modsecurity; then
      log "验证: nginx -V 已包含 modsecurity"
    fi
    log "宝塔 OpenResty 与 ModSecurity-nginx 无需变更。请按需: nginx -t && /etc/init.d/nginx restart"
    return 0
  fi

  local modsec_prefix="${MODSECURITY_PREFIX:-/usr/local/modsecurity}"
  if ! pkg-config --exists libmodsecurity 2>/dev/null && [[ ! -f "$modsec_prefix/lib/libmodsecurity.so" ]] && [[ ! -f "$modsec_prefix/lib/libmodsecurity.so.3" ]]; then
    error "宝塔环境需要 libmodsecurity（$modsec_prefix）。请先完整安装核心库，或恢复 .so 与 pkg-config 后再执行。"
  fi

  if ! _clone_modsecurity_nginx_connector "$MODSECURITY_NGX_CONNECTOR_DIR"; then
    error "无法克隆 ModSecurity-nginx，请检查网络或设置 MODSECURITY_NGX_CONNECTOR_DIR 指向已有源码。"
  fi

  _baota_merge_nginx_prepare_modsec "$modsec_prefix"
  _baota_ensure_nginx_config_pl
  _baota_append_nginx_configure_modsecurity "$MODSECURITY_NGX_CONNECTOR_DIR"

  log "=========================================="
  log "调用宝塔 nginx.sh update ${BT_OPENRESTY_VERSION}"
  log "（将按面板流程编译，日志同时写入 $LOG_FILE）"
  log "=========================================="
  if ! bash "$BT_PANEL_NGINX_SH" update "$BT_OPENRESTY_VERSION" >>"$LOG_FILE" 2>&1; then
    _baota_print_nginx_make_failure_snippet
    error "宝塔 nginx.sh update 失败。请检查 $LOG_FILE 与 /tmp/nginx_config.pl / /tmp/nginx_make.pl"
  fi

  _baota_post_build_verification

  log "宝塔 OpenResty 更新与 ModSecurity-nginx 集成步骤完成。请执行: nginx -t && /etc/init.d/nginx restart"
}
