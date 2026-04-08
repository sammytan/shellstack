#!/bin/bash
# 宝塔面板环境：通过 nginx_configure.pl 注入 --add-module，执行 panel nginx.sh update 编译 OpenResty + ModSecurity-nginx
# 依赖: 已安装 libmodsecurity（pkg-config libmodsecurity）、/www/server/panel/install/nginx.sh

MODSECURITY_NGX_CONNECTOR_DIR="${MODSECURITY_NGX_CONNECTOR_DIR:-/www/server/modsecurity-nginx}"
BT_PANEL_NGINX_SH="${BT_PANEL_NGINX_SH:-/www/server/panel/install/nginx.sh}"
BT_OPENRESTY_VERSION="${BT_OPENRESTY_VERSION:-openresty127}"

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
  if [[ -f "$cfg_pl" ]] && grep -qF "$flag" "$cfg_pl" 2>/dev/null; then
    log "nginx_configure.pl 已包含 ModSecurity-nginx: $flag"
    return 0
  fi
  if [[ -f "$cfg_pl" ]] && [[ -s "$cfg_pl" ]]; then
    \cp -a "$cfg_pl" "${cfg_pl}.bak.shellstack.$(date +%Y%m%d%H%M%S)"
  fi
  echo "$flag" >> "$cfg_pl"
  log "已追加到 nginx_configure.pl: $flag"
}

# 检测宝塔并升级/重编译 OpenResty，静态链接 ModSecurity-nginx 连接器
baota_install_openresty_with_modsecurity_connector() {
  if ! _baota_panel_present; then
    warn "未检测到宝塔面板（缺少 $BT_PANEL_NGINX_SH），跳过 OpenResty + ModSecurity-nginx 编译。"
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
    error "宝塔 nginx.sh update 失败。请检查 $LOG_FILE 与 /tmp/nginx_config.pl / /tmp/nginx_make.pl"
  fi

  if nginx -V 2>&1 | grep -qi modsecurity; then
    log "验证: nginx -V 已包含 modsecurity"
  else
    warn "nginx -V 未看到 modsecurity 字样，请确认编译是否启用连接器（查看 /tmp/nginx_config.pl）"
  fi

  log "宝塔 OpenResty 更新与 ModSecurity-nginx 集成步骤完成。请执行: nginx -t && /etc/init.d/nginx restart"
}
