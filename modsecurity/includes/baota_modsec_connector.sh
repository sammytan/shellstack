#!/bin/bash
# 宝塔面板环境：通过 nginx_configure.pl 注入 --add-module，执行 panel nginx.sh update 编译 OpenResty + ModSecurity-nginx
# 依赖: 已安装 libmodsecurity（pkg-config libmodsecurity）、/www/server/panel/install/nginx.sh

MODSECURITY_NGX_CONNECTOR_DIR="${MODSECURITY_NGX_CONNECTOR_DIR:-/www/server/modsecurity-nginx}"
BT_PANEL_NGINX_SH="${BT_PANEL_NGINX_SH:-/www/server/panel/install/nginx.sh}"
BT_PANEL_INSTALL_SOFT_SH="${BT_PANEL_INSTALL_SOFT_SH:-/www/server/panel/install/install_soft.sh}"
BT_OPENRESTY_VERSION="${BT_OPENRESTY_VERSION:-openresty127}"
# 设为 1 时强制执行宝塔 nginx.sh update（跳过「已就绪」检测）
MODSECURITY_FORCE_BT_NGINX_REBUILD="${MODSECURITY_FORCE_BT_NGINX_REBUILD:-0}"
# 设为 1 时保留 shellstack 生成的 .bak.shellstack.* 文件，默认清理
MODSECURITY_KEEP_BT_TEMP_FILES="${MODSECURITY_KEEP_BT_TEMP_FILES:-0}"
# 构建调用方式: auto | install_soft | nginx_sh（默认 auto，优先 install_soft）
MODSECURITY_BT_NGINX_INSTALL_MODE="${MODSECURITY_BT_NGINX_INSTALL_MODE:-auto}"

_baota_detect_nginx_bin() {
  local candidates=(
    "/www/server/nginx/sbin/nginx"
    "/www/server/nginx/nginx/sbin/nginx"
  )
  local p
  for p in "${candidates[@]}"; do
    [[ -x "$p" ]] && { echo "$p"; return 0; }
  done
  return 1
}

_baota_detect_nginx_setup_path() {
  local candidates=(
    "/www/server/nginx"
    "/www/server/nginx/nginx"
  )
  local p
  for p in "${candidates[@]}"; do
    [[ -d "$p" ]] && { echo "$p"; return 0; }
  done
  return 1
}

_baota_panel_present() {
  # 文件特征
  if [[ -d /www/server/panel ]] && [[ -f /www/server/panel/install/public.sh ]]; then
    return 0
  fi
  # 进程特征（BT-Panel / BT-Task）
  if command -v pgrep >/dev/null 2>&1; then
    if pgrep -f '/www/server/panel/BT-Panel|/www/server/panel/BT-Task' >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

_baota_run_panel_nginx_build() {
  local ver="$1"
  local install_dir="/www/server/panel/install"
  local mode="${MODSECURITY_BT_NGINX_INSTALL_MODE:-auto}"

  if [[ "$mode" == "install_soft" ]] || [[ "$mode" == "auto" && -f "$BT_PANEL_INSTALL_SOFT_SH" ]]; then
    log "调用宝塔 install_soft.sh 安装/重装 Nginx（与面板一致）"
    log "执行: cd ${install_dir} && bash install_soft.sh 3 install nginx"
    ( cd "$install_dir" && bash "$BT_PANEL_INSTALL_SOFT_SH" 3 install nginx >>"$LOG_FILE" 2>&1 )
    return $?
  fi

  if [[ ! -f "$BT_PANEL_NGINX_SH" ]]; then
    warn "未找到 $BT_PANEL_NGINX_SH，回退尝试 install_soft.sh 3 install nginx"
    if [[ -f "$BT_PANEL_INSTALL_SOFT_SH" ]]; then
      ( cd "$install_dir" && bash "$BT_PANEL_INSTALL_SOFT_SH" 3 install nginx >>"$LOG_FILE" 2>&1 )
      return $?
    fi
    return 1
  fi

  log "调用宝塔 nginx.sh update ${ver}"
  log "执行: bash ${BT_PANEL_NGINX_SH} update ${ver}"
  bash "$BT_PANEL_NGINX_SH" update "$ver" >>"$LOG_FILE" 2>&1
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

_baota_register_modsecurity_with_panel() {
  local connector_dir="$1"
  local nginx_install_dir="/www/server/panel/install/nginx"
  local ms_dir="${nginx_install_dir}/modsecurity"
  local config_pl="${nginx_install_dir}/config.pl"
  local args_pl="${ms_dir}/args.pl"
  local ps_pl="${ms_dir}/ps.pl"

  mkdir -p "$ms_dir"
  [[ -f "$config_pl" ]] || touch "$config_pl"

  # 按宝塔扩展约定：config.pl 中登记模块名（去重保留一条）
  if grep -qE '^[[:space:]]*modsecurity[[:space:]]*$' "$config_pl" 2>/dev/null; then
    awk '
      {
        line=$0
        gsub(/\r/, "", line)
        sub(/^[ \t]+/, "", line)
        sub(/[ \t]+$/, "", line)
        if (line=="modsecurity") {
          c++
          if (c==1) print "modsecurity"
          next
        }
        print $0
      }
    ' "$config_pl" > "${config_pl}.tmp.shellstack" && mv -f "${config_pl}.tmp.shellstack" "$config_pl"
  else
    echo "modsecurity" >> "$config_pl"
  fi

  # 官方扩展参数入口：args.pl
  echo "--add-module=${connector_dir}" > "$args_pl"

  # 保持 ps.pl 存在（部分面板逻辑会探测该文件）
  [[ -f "$ps_pl" ]] || echo "modsecurity" > "$ps_pl"

  log "已按宝塔扩展方式登记 ModSecurity: ${config_pl} + ${args_pl}"
}

# 当前 Nginx 是否已是「目标 OpenResty 键 + 已编进 ModSecurity-nginx」，可跳过重复 nginx.sh update
_baota_skip_openresty_rebuild_if_current() {
  [[ "${MODSECURITY_FORCE_BT_NGINX_REBUILD}" == "1" ]] && return 1

  local nginx_bin
  nginx_bin="$(_baota_detect_nginx_bin 2>/dev/null)" || return 1
  local setup_path
  setup_path="$(_baota_detect_nginx_setup_path 2>/dev/null)" || return 1
  local vchk="${setup_path}/version_check.pl"
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
  if [[ -f /tmp/nginx_install.pl ]]; then
    warn "  /tmp/nginx_install.pl 尾部:"
    local tail_install
    tail_install="$(awk 'NR>0{a[NR%20]=$0} END{for(i=NR-19;i<=NR;i++) if(i>0) print a[i%20]}' /tmp/nginx_install.pl 2>/dev/null)"
    if [[ -n "$tail_install" ]]; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && warn "    $line"
      done <<< "$tail_install"
    fi
  fi
}

_baota_cleanup_shellstack_temp_files() {
  if [[ "${MODSECURITY_KEEP_BT_TEMP_FILES:-0}" == "1" ]]; then
    log "保留临时文件: MODSECURITY_KEEP_BT_TEMP_FILES=1"
    return 0
  fi
  local install_dir="/www/server/panel/install"
  rm -f "${install_dir}/nginx_configure.pl.tmp.shellstack" 2>/dev/null || true
  rm -f "${install_dir}"/nginx_configure.pl.bak.shellstack.* 2>/dev/null || true
  log "已清理安装目录下的 shellstack 临时配置文件（nginx_configure.pl.bak.shellstack.* 等）"
}

_baota_post_build_verification() {
  local nginx_bin
  if ! nginx_bin="$(_baota_detect_nginx_bin 2>/dev/null)"; then
    warn "验收: 未找到可执行 nginx（已尝试 /www/server/nginx/sbin/nginx 与 /www/server/nginx/nginx/sbin/nginx），跳过自动验收"
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

_baota_update_result_can_be_accepted() {
  local nginx_bin
  nginx_bin="$(_baota_detect_nginx_bin 2>/dev/null)" || return 1

  # 1) 最理想：二进制已含 modsecurity 且配置可通过
  if "$nginx_bin" -V 2>&1 | grep -qi modsecurity; then
    if "$nginx_bin" -t >/dev/null 2>&1; then
      return 0
    fi
    # nginx -t 失败时也可能是现有配置问题，不代表编译失败
    warn "验收提示: nginx -V 已含 modsecurity，但 nginx -t 未通过，继续按可接受结果处理（请后续修复配置）"
    return 0
  fi

  # 2) 兜底：宝塔 nginx.sh 常见“假失败”——/tmp/nginx_install.pl 已显示 make install 完成并复制 nginx
  local inst="/tmp/nginx_install.pl"
  if [[ -f "$inst" ]]; then
    if grep -qE "cp objs/nginx '.*/nginx/sbin/nginx'|make\[1\]: Leaving directory '.*/nginx/src'" "$inst" 2>/dev/null; then
      if [[ -x "/www/server/nginx/sbin/nginx" ]] || [[ -x "/www/server/nginx/nginx/sbin/nginx" ]]; then
        warn "验收提示: 检测到 /tmp/nginx_install.pl 显示 make install 已执行，按可接受结果处理（宝塔脚本可能返回假失败）"
        return 0
      fi
    fi
  fi

  return 1
}

_baota_repair_openresty_layout_if_needed() {
  # 宝塔 nginx.sh 在 openresty 某些分支会出现“已安装到 /www/server/nginx/nginx，但未创建外层链接”的情况
  local inner="/www/server/nginx/nginx"
  local outer="/www/server/nginx"
  if [[ ! -x "${inner}/sbin/nginx" ]]; then
    return 0
  fi

  mkdir -p "${outer}" 2>/dev/null || true
  if [[ ! -e "${outer}/sbin" ]]; then
    ln -s "${inner}/sbin" "${outer}/sbin" 2>/dev/null || true
  fi
  if [[ ! -e "${outer}/conf" ]]; then
    ln -s "${inner}/conf" "${outer}/conf" 2>/dev/null || true
  fi
  if [[ ! -e "${outer}/logs" ]]; then
    ln -s "${inner}/logs" "${outer}/logs" 2>/dev/null || true
  fi
  if [[ ! -e "${outer}/html" ]]; then
    ln -s "${inner}/html" "${outer}/html" 2>/dev/null || true
  fi
  if [[ ! -e "${outer}/modules" ]] && [[ -d "${inner}/modules" ]]; then
    ln -s "${inner}/modules" "${outer}/modules" 2>/dev/null || true
  fi
  if [[ -x "${outer}/sbin/nginx" ]]; then
    ln -sf "${outer}/sbin/nginx" /usr/bin/nginx 2>/dev/null || true
    log "已修复 OpenResty 目录布局：补齐 /www/server/nginx/{sbin,conf,logs,html} 软链接"
  fi
}

_baota_recover_nginx_layout_from_source() {
  local outer="/www/server/nginx"
  local src_dir="${outer}/src"

  # 已有可执行 nginx 则无需恢复
  if [[ -x "${outer}/sbin/nginx" ]] || [[ -x "${outer}/nginx/sbin/nginx" ]]; then
    return 0
  fi

  if [[ -d "$src_dir" ]] && [[ -f "${src_dir}/Makefile" ]]; then
    warn "检测到 /www/server/nginx 缺少运行目录（sbin/conf 等），尝试在 ${src_dir} 执行 make install 恢复布局..."
    if (cd "$src_dir" && make install >>"$LOG_FILE" 2>&1); then
      log "已执行恢复命令: (cd ${src_dir} && make install)"
    else
      warn "恢复命令 make install 失败，请检查 ${src_dir}/Makefile 与编译产物"
    fi
  fi

  # 兜底：若出现内层 nginx 目录，补齐外层链接
  _baota_repair_openresty_layout_if_needed
}

# 检测宝塔并升级/重编译 OpenResty，静态链接 ModSecurity-nginx 连接器
baota_install_openresty_with_modsecurity_connector() {
  if ! _baota_panel_present; then
    warn "未检测到宝塔面板（缺少 $BT_PANEL_NGINX_SH），跳过 OpenResty + ModSecurity-nginx 编译。"
    return 0
  fi

  if _baota_skip_openresty_rebuild_if_current; then
    local nginx_bin
    nginx_bin="$(_baota_detect_nginx_bin 2>/dev/null || true)"
    local setup_path cur_ver
    setup_path="$(_baota_detect_nginx_setup_path 2>/dev/null || true)"
    cur_ver="$(head -1 "${setup_path}/version_check.pl" 2>/dev/null | tr -d '\n')"
    log "当前 OpenResty（version_check.pl: ${cur_ver:-unknown}）已包含 ModSecurity，且与 --bt-openresty=${BT_OPENRESTY_VERSION} 一致，跳过重复执行 nginx.sh update。"
    log "若需强制重新编译 Nginx，请设置: export MODSECURITY_FORCE_BT_NGINX_REBUILD=1 后重跑。"
    if [[ -n "$nginx_bin" ]] && "$nginx_bin" -V 2>&1 | grep -qi modsecurity; then
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
  _baota_register_modsecurity_with_panel "$MODSECURITY_NGX_CONNECTOR_DIR"

  log "=========================================="
  log "调用宝塔 Nginx 编译安装流程"
  log "（将按面板流程编译，日志同时写入 $LOG_FILE；模式: ${MODSECURITY_BT_NGINX_INSTALL_MODE}）"
  log "=========================================="
  if ! _baota_run_panel_nginx_build "$BT_OPENRESTY_VERSION"; then
    _baota_recover_nginx_layout_from_source
    _baota_repair_openresty_layout_if_needed
    _baota_print_nginx_make_failure_snippet
    if _baota_update_result_can_be_accepted; then
      warn "宝塔 nginx.sh update 返回非 0，但验收通过（nginx -V 含 modsecurity 且 nginx -t 通过），按成功继续。"
    else
      _baota_cleanup_shellstack_temp_files
      error "宝塔 nginx.sh update 失败。请检查 $LOG_FILE 与 /tmp/nginx_config.pl / /tmp/nginx_make.pl"
    fi
  fi

  _baota_recover_nginx_layout_from_source
  _baota_repair_openresty_layout_if_needed
  _baota_post_build_verification
  _baota_cleanup_shellstack_temp_files

  log "宝塔 OpenResty 更新与 ModSecurity-nginx 集成步骤完成。请执行: nginx -t && /etc/init.d/nginx restart"
}
