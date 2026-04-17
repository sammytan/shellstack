#!/bin/bash
# 宝塔：部署 modsecurity.conf、OWASP CRS、modsec_includes.conf、custom_modsec_rules.conf、whitelist、nginx.conf 中的 modsecurity 指令
# 依赖 shared.sh: log warn error LOG_FILE

if [[ -z "${BT_NGINX_CONF_DIR:-}" ]]; then
  if [[ -d /www/server/nginx/conf ]]; then
    BT_NGINX_CONF_DIR="/www/server/nginx/conf"
  elif [[ -d /www/server/nginx/nginx/conf ]]; then
    BT_NGINX_CONF_DIR="/www/server/nginx/nginx/conf"
  else
    BT_NGINX_CONF_DIR="/www/server/nginx/conf"
  fi
fi
if [[ -z "${BT_NGINX_BIN:-}" ]]; then
  if [[ -x /www/server/nginx/sbin/nginx ]]; then
    BT_NGINX_BIN="/www/server/nginx/sbin/nginx"
  elif [[ -x /www/server/nginx/nginx/sbin/nginx ]]; then
    BT_NGINX_BIN="/www/server/nginx/nginx/sbin/nginx"
  else
    BT_NGINX_BIN="/www/server/nginx/sbin/nginx"
  fi
fi
# 为 0 时不写入 nginx.conf 的 fastcgi_cache 共享区，且不向 enable-php 注入 fastcgi_cache（仅 ModSecurity / real_ip 等）
SHELLSTACK_DEPLOY_FASTCGI_CACHE="${SHELLSTACK_DEPLOY_FASTCGI_CACHE:-1}"
# 为 1 时先删除 # shellstack-http-includes-begin … end 旧块再按当前环境重新注入（例如编译 modsecurity-nginx 后补全）
SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK="${SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK:-0}"
# nginx-module-vts：--deploy-conf 时写入 shellstack_vts.conf 并在 nginx.conf 中 include（需二进制已编入模块）
SHELLSTACK_DEPLOY_NGINX_MODULE_VTS="${SHELLSTACK_DEPLOY_NGINX_MODULE_VTS:-1}"
SHELLSTACK_VTS_LISTEN_PORT="${SHELLSTACK_VTS_LISTEN_PORT:-8898}"
BT_WHITELIST_FILE="${BT_WHITELIST_FILE:-/www/server/whitelist.txt}"
CRS_GIT_BRANCH="${CRS_GIT_BRANCH:-v3.3.5}"
CRS_GIT_URL="${CRS_GIT_URL:-https://github.com/coreruleset/coreruleset.git}"
CRS_GIT_URL_FALLBACK="${CRS_GIT_URL_FALLBACK:-https://github.com/SpiderLabs/owasp-modsecurity-crs.git}"
# 与 libmodsecurity 3.x 对齐的样例配置标签（用于 raw 回退下载）
MODSECURITY_CONF_SAMPLES_TAG="${MODSECURITY_CONF_SAMPLES_TAG:-v3.0.10}"

_baota_git_clone_shallow() {
  local url="$1"
  local dest="$2"
  local branch="$3"
  rm -rf "$dest"
  if [[ -n "$branch" ]]; then
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$branch" "$url" "$dest" >>"$LOG_FILE" 2>&1
  else
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$url" "$dest" >>"$LOG_FILE" 2>&1
  fi
}

_baota_deploy_clone_modsecurity_core_for_samples() {
  # 传入 $tmp_core（mktemp 根目录），克隆到 $tmp_core/ModSecurity/（勿再传 .../ModSecurity，否则会重复嵌套）
  local tmp_base="$1"
  local dest="$tmp_base/ModSecurity"
  local urls=(
    "https://github.com/SpiderLabs/ModSecurity.git"
    "https://github.com/owasp-modsecurity/ModSecurity.git"
    "https://gitee.com/mirrors/ModSecurity.git"
  )
  local u
  for u in "${urls[@]}"; do
    rm -rf "$dest"
    if _baota_git_clone_shallow "$u" "$dest" ""; then
      if [[ -f "$dest/modsecurity.conf-recommended" ]] && [[ -f "$dest/unicode.mapping" ]]; then
        return 0
      fi
      warn "克隆 $u 成功但缺少 modsecurity.conf-recommended 或 unicode.mapping，尝试下一源"
    fi
  done
  return 1
}

# 当 git 不可用或克隆不完整时，从 GitHub raw 拉取官方样例
_baota_fetch_modsecurity_samples_fallback() {
  local out_dir="$1"
  local tag="${MODSECURITY_CONF_SAMPLES_TAG:-v3.0.10}"
  local base="https://raw.githubusercontent.com/owasp-modsecurity/ModSecurity/${tag}"
  mkdir -p "$out_dir"
  local ok=1
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 15 --max-time 120 "$base/modsecurity.conf-recommended" -o "$out_dir/modsecurity.conf-recommended.tmp" >>"$LOG_FILE" 2>&1 && [[ -s "$out_dir/modsecurity.conf-recommended.tmp" ]] || ok=0
    curl -fsSL --connect-timeout 15 --max-time 120 "$base/unicode.mapping" -o "$out_dir/unicode.mapping.tmp" >>"$LOG_FILE" 2>&1 && [[ -s "$out_dir/unicode.mapping.tmp" ]] || ok=0
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$out_dir/modsecurity.conf-recommended.tmp" --timeout=120 "$base/modsecurity.conf-recommended" >>"$LOG_FILE" 2>&1 && [[ -s "$out_dir/modsecurity.conf-recommended.tmp" ]] || ok=0
    wget -q -O "$out_dir/unicode.mapping.tmp" --timeout=120 "$base/unicode.mapping" >>"$LOG_FILE" 2>&1 && [[ -s "$out_dir/unicode.mapping.tmp" ]] || ok=0
  else
    return 1
  fi
  [[ "$ok" -eq 1 ]] || return 1
  mv -f "$out_dir/modsecurity.conf-recommended.tmp" "$out_dir/modsecurity.conf-recommended"
  mv -f "$out_dir/unicode.mapping.tmp" "$out_dir/unicode.mapping"
  [[ -f "$out_dir/modsecurity.conf-recommended" ]] && [[ -f "$out_dir/unicode.mapping" ]]
}

_baota_deploy_clone_crs() {
  local dest="$1"
  if [[ -d "$dest/.git" ]]; then
    log "CRS 目录已存在: $dest（保留现有克隆，请手动 git pull 如需更新）"
    return 0
  fi
  rm -rf "$dest"
  if _baota_git_clone_shallow "$CRS_GIT_URL" "$dest" "$CRS_GIT_BRANCH"; then
    return 0
  fi
  warn "CRS 主仓库失败，尝试: $CRS_GIT_URL_FALLBACK"
  rm -rf "$dest"
  _baota_git_clone_shallow "$CRS_GIT_URL_FALLBACK" "$dest" ""
}

_baota_nginx_has_modsecurity_module() {
  [[ -x "$BT_NGINX_BIN" ]] || return 1
  "$BT_NGINX_BIN" -V 2>&1 | grep -qi modsecurity
}

_baota_nginx_has_vts_module() {
  [[ -x "$BT_NGINX_BIN" ]] || return 1
  "$BT_NGINX_BIN" -V 2>&1 | grep -qiE 'vhost_traffic_status|ngx_http_vhost_traffic_status'
}

_baota_write_shellstack_vts_conf() {
  local out="$BT_NGINX_CONF_DIR/shellstack_vts.conf"
  local port="${SHELLSTACK_VTS_LISTEN_PORT:-8898}"
  local ms_line=""
  log "nginx-module-vts：正在生成独立片段文件（随后将 include 到 nginx.conf 的 http{}）"
  log "  → 输出: $out；监听: 127.0.0.1:${port}；URI 前缀: /nginx-vts-status"
  if _baota_nginx_has_modsecurity_module; then
    ms_line="    modsecurity off;"
    log "  → server 块内将写入 modsecurity off;（避免 WAF 拦截本机状态）"
  fi
  umask 022
  {
    echo "# shellstack: nginx-module-vts (https://github.com/vozlt/nginx-module-vts)"
    echo "# 本机 Prometheus: curl -sS http://127.0.0.1:${port}/nginx-vts-status/format/prometheus"
    echo "vhost_traffic_status_zone;"
    echo ""
    echo "server {"
    echo "    listen 127.0.0.1:${port};"
    echo "    server_name _;"
    if [[ -n "$ms_line" ]]; then
      echo "$ms_line"
    fi
    echo "    location /nginx-vts-status {"
    echo "        vhost_traffic_status_bypass_stats on;"
    echo "        vhost_traffic_status_bypass_limit on;"
    echo "        vhost_traffic_status_display;"
    echo "        vhost_traffic_status_display_format html;"
    echo "    }"
    echo "}"
  } > "$out"
  log "nginx-module-vts：片段文件已写入完成: $out"
}

_baota_ensure_nginx_conf_includes_vts() {
  local ngx="$BT_NGINX_CONF_DIR/nginx.conf"
  local line='        include /www/server/nginx/conf/shellstack_vts.conf;'
  if [[ ! -f "$ngx" ]]; then
    warn "nginx-module-vts：未找到主配置 $ngx，无法自动插入 include shellstack_vts.conf，请手工在 http{} 内加入: $line"
    return 0
  fi
  log "nginx-module-vts：正在合并到主配置: $ngx"
  if grep -qF 'shellstack_vts.conf' "$ngx" 2>/dev/null; then
    log "nginx-module-vts：$ngx 已存在 shellstack_vts.conf 引用，跳过重复插入"
    return 0
  fi
  local snip
  snip="$(mktemp)"
  printf '%s\n' "$line" > "$snip"
  if grep -q 'include proxy.conf;' "$ngx"; then
    sed -i '/include proxy.conf;/r '"$snip" "$ngx"
    log "nginx-module-vts：已在 $ngx 的 include proxy.conf; 之后插入一行: $line"
  elif grep -q 'default_type' "$ngx"; then
    sed -i '/default_type[[:space:]]/r '"$snip" "$ngx"
    log "nginx-module-vts：已在 $ngx 的 default_type 行之后插入一行: $line"
  else
    warn "nginx-module-vts：无法在 $ngx 中定位 include proxy.conf 或 default_type，请手工在 http{} 内加入: $line"
  fi
  rm -f "$snip"
}

# 在 http{} 内注入：real_ip 始终写入；modsecurity 仅当 nginx 已编进 modsecurity-nginx；fastcgi 共享区仅当开启 SHELLSTACK_DEPLOY_FASTCGI_CACHE 且尚未存在 keys_zone
_baota_inject_shellstack_http_block_in_nginx_conf() {
  local ngx="$BT_NGINX_CONF_DIR/nginx.conf"
  [[ -f "$ngx" ]] || return 0

  local begin='# shellstack-http-includes-begin'
  local ending='# shellstack-http-includes-end'

  if grep -qF "$begin" "$ngx" 2>/dev/null && [[ "${SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK:-0}" != "1" ]]; then
    log "nginx.conf 已包含 shellstack http 块（$begin），跳过。若已新编译 modsecurity-nginx 需补全指令，请设置 SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK=1 后重跑 --deploy-conf"
    return 0
  fi

  if grep -qF "$begin" "$ngx" 2>/dev/null && [[ "${SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK:-0}" == "1" ]]; then
    sed -i '/# shellstack-http-includes-begin/,/# shellstack-http-includes-end/d' "$ngx"
    log "已按 SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK=1 移除旧 shellstack http 块"
  fi

  mkdir -p /www/wwwlogs/fastcgi_cache

  local has_ms=0
  if _baota_nginx_has_modsecurity_module; then
    has_ms=1
  else
    warn "当前 $BT_NGINX_BIN 未包含 modsecurity 模块，将不写入 modsecurity on / modsecurity_rules_file（仅 real_ip 等）。请先完成 ModSecurity-nginx 编译后再设置 SHELLSTACK_REFRESH_NGINX_HTTP_BLOCK=1 并重跑 --deploy-conf。"
  fi

  local want_fc_zone=0
  if [[ "${SHELLSTACK_DEPLOY_FASTCGI_CACHE:-1}" == "1" ]] && ! grep -q 'fastcgi_cache_path' "$ngx" 2>/dev/null; then
    want_fc_zone=1
  elif [[ "${SHELLSTACK_DEPLOY_FASTCGI_CACHE:-1}" != "1" ]]; then
    log "SHELLSTACK_DEPLOY_FASTCGI_CACHE=0，跳过 nginx.conf 中的 fastcgi_cache_path / fastcgi_cache_key"
  fi

  local snip
  snip="$(mktemp)"
  {
    echo "        $begin"
    echo '        # shellstack-real-ip'
    echo '        set_real_ip_from  0.0.0.0/0;'
    echo '        real_ip_header    X-Forwarded-For;'
    echo '        real_ip_recursive on;'
    if [[ "$has_ms" -eq 1 ]]; then
      echo '        # shellstack-modsecurity'
      echo '        # 只有当安装了 modsecurity-nginx 才能启用以下配置;'
      echo '        modsecurity on;'
      echo '        modsecurity_rules_file /www/server/nginx/conf/modsec_includes.conf;'
    fi
    if [[ "$want_fc_zone" -eq 1 ]]; then
      echo '        # shellstack-fastcgi-cache-zone'
      echo '        # 只有开启了 fastcgi 缓存才能启用这些配置;'
      echo '        fastcgi_cache_path /www/wwwlogs/fastcgi_cache levels=1:2 keys_zone=fastcgi_cache:10m max_size=10g inactive=60m use_temp_path=off;'
      echo '        #fastcgi_cache_key "$scheme$request_method$host$request_uri";'
    fi
    echo "        $ending"
  } > "$snip"

  if grep -q 'include proxy.conf;' "$ngx"; then
    sed -i '/include proxy.conf;/r '"$snip" "$ngx"
    log "已向 nginx.conf 注入 shellstack http 块（锚点: include proxy.conf）"
  elif grep -q 'default_type' "$ngx"; then
    sed -i '/default_type[[:space:]]/r '"$snip" "$ngx"
    log "已向 nginx.conf 注入 shellstack http 块（锚点: default_type）"
  else
    warn "无法在 nginx.conf 中找到 include proxy.conf 或 default_type，请手工在 http{} 内加入相关配置"
  fi
  rm -f "$snip"
}

# 在 enable-php-*.conf 的 PHP location 内开启 FastCGI 缓存（默认宝塔未写这些指令）
_baota_inject_fastcgi_cache_into_enable_php_confs() {
  local snip
  snip="$(mktemp)"
  cat > "$snip" <<'SNIP'

        # FastCGI 缓存（shellstack / --deploy-conf 注入）
        fastcgi_cache fastcgi_cache;
        fastcgi_cache_valid 200 301 302 3m;
        fastcgi_cache_valid 404 1m;
        fastcgi_cache_use_stale error timeout invalid_header updating http_500 http_503;
        fastcgi_cache_min_uses 1;
        fastcgi_cache_lock on;
        fastcgi_cache_bypass $skip_cache;
        fastcgi_no_cache $skip_cache;
        set $skip_cache 0;
        if ($request_method = POST) {
            set $skip_cache 1;
        }
        if ($query_string != "") {
            set $skip_cache 1;
        }
        if ($http_cookie ~* "wordpress_logged_in_|wp-postpass_|wordpress_no_cache|comment_author") {
            set $skip_cache 1;
        }
SNIP

  local f
  for f in "$BT_NGINX_CONF_DIR"/enable-php-*.conf; do
    [[ -f "$f" ]] || continue
    case "$(basename "$f")" in
      enable-php-00.conf) continue ;;
    esac
    grep -q 'fastcgi_pass' "$f" 2>/dev/null || continue
    grep -q 'fastcgi_cache fastcgi_cache' "$f" 2>/dev/null && continue
    if grep -q 'include pathinfo.conf;' "$f"; then
      sed -i "/include pathinfo.conf;/r $snip" "$f"
      log "已为 $(basename "$f") 开启 FastCGI 缓存（after pathinfo.conf）"
    elif grep -q 'include fastcgi.conf;' "$f"; then
      sed -i "/include fastcgi.conf;/r $snip" "$f"
      log "已为 $(basename "$f") 开启 FastCGI 缓存（after fastcgi.conf）"
    else
      warn "未找到 pathinfo.conf / fastcgi.conf 引用，跳过: $(basename "$f")"
    fi
  done
  rm -f "$snip"
}

_baota_crs_rule_files() {
  # 与 CRS 3.3.x rules/ 下文件名一致（不存在则稍后在写入 includes 时跳过）
  echo "REQUEST-901-INITIALIZATION.conf"
  echo "REQUEST-903.9002-WORDPRESS-EXCLUSION-RULES.conf"
  echo "REQUEST-905-COMMON-EXCEPTIONS.conf"
  echo "REQUEST-910-IP-REPUTATION.conf"
  echo "REQUEST-911-METHOD-ENFORCEMENT.conf"
  echo "REQUEST-912-DOS-PROTECTION.conf"
  echo "REQUEST-913-SCANNER-DETECTION.conf"
  echo "REQUEST-920-PROTOCOL-ENFORCEMENT.conf"
  echo "REQUEST-921-PROTOCOL-ATTACK.conf"
  echo "REQUEST-930-APPLICATION-ATTACK-LFI.conf"
  echo "REQUEST-931-APPLICATION-ATTACK-RFI.conf"
  echo "REQUEST-932-APPLICATION-ATTACK-RCE.conf"
  echo "REQUEST-933-APPLICATION-ATTACK-PHP.conf"
  echo "REQUEST-941-APPLICATION-ATTACK-XSS.conf"
  echo "REQUEST-942-APPLICATION-ATTACK-SQLI.conf"
  echo "REQUEST-943-APPLICATION-ATTACK-SESSION-FIXATION.conf"
  echo "REQUEST-949-BLOCKING-EVALUATION.conf"
  echo "RESPONSE-950-DATA-LEAKAGES.conf"
  echo "RESPONSE-951-DATA-LEAKAGES-SQL.conf"
  echo "RESPONSE-952-DATA-LEAKAGES-JAVA.conf"
  echo "RESPONSE-953-DATA-LEAKAGES-PHP.conf"
  echo "RESPONSE-954-DATA-LEAKAGES-IIS.conf"
  echo "RESPONSE-959-BLOCKING-EVALUATION.conf"
  echo "RESPONSE-980-CORRELATION.conf"
}

_baota_detect_geoip_db_for_modsec() {
  local candidates=(
    "/usr/local/share/GeoIP/dbip-country-lite.mmdb"
    "/usr/local/share/GeoIP/GeoLite2-Country.mmdb"
    "/var/lib/GeoIP/dbip-country-lite.mmdb"
    "/var/lib/GeoIP/GeoLite2-Country.mmdb"
  )
  local p
  for p in "${candidates[@]}"; do
    [[ -f "$p" ]] && { echo "$p"; return 0; }
  done
  return 1
}

baota_deploy_modsecurity_conf() {
  if [[ ! -d "$BT_NGINX_CONF_DIR" ]]; then
    error "配置目录不存在: $BT_NGINX_CONF_DIR"
  fi

  log "=========================================="
  log "部署 ModSecurity / CRS 配置到 $BT_NGINX_CONF_DIR"
  log "=========================================="

  local tmp_core
  tmp_core="$(mktemp -d /tmp/shellstack-modsec-core.XXXXXX)"
  local ms_src="$tmp_core/ModSecurity"
  if ! _baota_deploy_clone_modsecurity_core_for_samples "$tmp_core"; then
    warn "ModSecurity 仓库克隆失败或不完整，尝试从 raw.githubusercontent.com 下载样例（标签 ${MODSECURITY_CONF_SAMPLES_TAG:-v3.0.10}）"
    if ! _baota_fetch_modsecurity_samples_fallback "$ms_src"; then
      rm -rf "$tmp_core"
      error "无法获取 modsecurity.conf-recommended / unicode.mapping（请检查网络与 git/curl）"
    fi
  fi
  if [[ ! -f "$ms_src/modsecurity.conf-recommended" ]] || [[ ! -f "$ms_src/unicode.mapping" ]]; then
    warn "克隆目录仍缺少样例文件，尝试 raw 回退"
    if ! _baota_fetch_modsecurity_samples_fallback "$ms_src"; then
      rm -rf "$tmp_core"
      error "无法获取 modsecurity.conf-recommended / unicode.mapping"
    fi
  fi
  \cp -a "$ms_src/modsecurity.conf-recommended" "$BT_NGINX_CONF_DIR/modsecurity.conf"
  \cp -a "$ms_src/unicode.mapping" "$BT_NGINX_CONF_DIR/"
  rm -rf "$tmp_core"

  sed -i 's/^SecRuleEngine DetectionOnly/SecRuleEngine On/' "$BT_NGINX_CONF_DIR/modsecurity.conf"
  sed -i 's/^SecStatusEngine Off/SecStatusEngine On/' "$BT_NGINX_CONF_DIR/modsecurity.conf"
  sed -i 's@#SecDebugLog /opt/modsecurity/var/log/debug.log@SecDebugLog /var/log/modsec_debug.log@' "$BT_NGINX_CONF_DIR/modsecurity.conf"
  sed -i 's/^#SecDebugLogLevel 3/SecDebugLogLevel 3/' "$BT_NGINX_CONF_DIR/modsecurity.conf"

  local crs_dir="$BT_NGINX_CONF_DIR/owasp-modsecurity-crs"
  if ! _baota_deploy_clone_crs "$crs_dir"; then
    error "无法克隆 OWASP CRS（coreruleset）到 $crs_dir"
  fi

  if [[ -f "$crs_dir/crs-setup.conf.example" ]]; then
    \cp -a "$crs_dir/crs-setup.conf.example" "$crs_dir/crs-setup.conf"
  elif [[ -f "$crs_dir/crs-setup.conf" ]]; then
    log "crs-setup.conf 已存在"
  else
    warn "未找到 crs-setup.conf.example，请检查 CRS 版本"
  fi

  if [[ -f "$crs_dir/crs-setup.conf" ]]; then
    sed -i 's/^SecDefaultAction "phase:1,log,auditlog,pass"/#SecDefaultAction "phase:1,log,auditlog,pass"/' "$crs_dir/crs-setup.conf"
    sed -i 's/^SecDefaultAction "phase:2,log,auditlog,pass"/#SecDefaultAction "phase:2,log,auditlog,pass"/' "$crs_dir/crs-setup.conf"
    sed -i 's/^#.*SecDefaultAction "phase:1,log,auditlog,deny,status:403"/SecDefaultAction "phase:1,log,auditlog,deny,status:403"/' "$crs_dir/crs-setup.conf"
    sed -i 's/^# SecDefaultAction "phase:2,log,auditlog,deny,status:403"/SecDefaultAction "phase:2,log,auditlog,deny,status:403"/' "$crs_dir/crs-setup.conf"
  fi

  local crs_rel="owasp-modsecurity-crs"
  local inc="$BT_NGINX_CONF_DIR/modsec_includes.conf"
  {
    echo "include modsecurity.conf"
    echo "include custom_modsec_rules.conf"
    echo "include ${crs_rel}/crs-setup.conf"
    local rf
    while IFS= read -r rf; do
      [[ -z "$rf" ]] && continue
      if [[ -f "$BT_NGINX_CONF_DIR/${crs_rel}/rules/$rf" ]]; then
        echo "include ${crs_rel}/rules/${rf}"
      else
        warn "跳过不存在的 CRS 规则文件: ${crs_rel}/rules/$rf"
      fi
    done < <(_baota_crs_rule_files)
  } > "$inc"
  log "已写入 $inc"

  touch "$BT_WHITELIST_FILE"

  local geoip_db=""
  geoip_db="$(_baota_detect_geoip_db_for_modsec 2>/dev/null || true)"
  if [[ -n "$geoip_db" ]]; then
    log "GeoIP 数据库检测: 使用 $geoip_db（优先 DB-IP Lite）"
  else
    warn "未检测到可用 GeoIP 数据库（dbip/GeoLite2），将不写入 SecGeoLookupDB，避免 nginx -t 失败。"
  fi

  {
    if [[ -n "$geoip_db" ]]; then
      echo "SecGeoLookupDB $geoip_db"
    else
      echo "# SecGeoLookupDB /usr/local/share/GeoIP/dbip-country-lite.mmdb"
      echo "# 未检测到 GeoIP 库，已注释以避免 nginx 启动失败"
    fi
    cat <<'RULES'
SecRule REMOTE_ADDR "@geoLookup" "id:10001,phase:1,pass,log"
SecRule REQUEST_URI "@beginsWith /vts_status" "id:10002,phase:1,nolog,pass,ctl:ruleEngine=Off"
SecRule REQUEST_URI "@beginsWith /nginx-vts-status" "id:10006,phase:1,nolog,pass,ctl:ruleEngine=Off"
SecRule REQUEST_URI "@beginsWith /e/e_DliR28KktG1dpud/" "id:10003,phase:1,nolog,pass,ctl:ruleEngine=Off"

SecRule REMOTE_ADDR "@ipMatchFromFile /www/server/whitelist.txt" \
    "id:999,phase:1,allow,msg:'Allow access from whitelist IP'"

SecRule REQUEST_URI "@rx ^/e/member/" \
    "id:11000,phase:1,deny,status:403,msg:'Access to /e/member/ is denied'"

SecRule REQUEST_URI "@rx ^//e/ShopSys/" \
    "id:11001,phase:1,deny,status:403,msg:'Access to //e/ShopSys/ is denied'"

SecRule ARGS "^([A-Za-z0-9+/]{64,}=*)$" \
    "phase:2,deny,id:10004,log,msg:'参数值疑似Base64编码且长度超过64'"

SecRule ARGS "^[A-Fa-f0-9]{64,}$" \
    "phase:2,deny,id:10005,log,msg:'参数值疑似十六进制编码且长度超过64'"

SecAction "id:1001,phase:1,nolog,pass,setvar:tx.html_rate_limit=2"
SecRule REQUEST_URI "@endsWith .html" "id:1002,phase:2,t:none,pass,nolog,setvar:ip.html_request_counter=+1,expirevar:ip.html_request_counter=2"
SecRule IP:html_request_counter "@gt 2" "id:1003,phase:2,log,deny,status:429,msg:'Too many requests for .html files from this IP',setvar:ip.html_exceed_counter=+1,expirevar:ip.html_exceed_counter=3600"

SecRule IP:html_exceed_counter "@ge 3" "id:1004,phase:2,log,deny,status:403,msg:'IP temporarily banned for excessive requests to .html files',setvar:ip.block_time=+1,expirevar:ip.block_time=300,setvar:ip.html_exceed_counter=0"
SecRule IP:block_time "@ge 2" "id:1005,phase:1,log,deny,status:403,msg:'IP is banned for 5 minutes'"

SecRule RESPONSE_STATUS "@in 400,403,404,405,429,503" \
    "id:2001,phase:3,pass,nolog,setvar:ip.error_request_counter=+1,expirevar:ip.error_request_counter=180"

SecRule IP:error_request_counter "@gt 15" \
    "id:2002,phase:3,log,deny,status:403,msg:'Too many error requests in 3 minutes , IP temporarily banned',setvar:ip.block_time=+1,expirevar:ip.block_time=3600,setvar:ip.error_request_counter=0"

SecRule IP:block_time "@ge 1" \
    "id:2003,phase:1,log,deny,status:403,msg:'IP is banned for 1 hour due to excessive error requests'"
RULES
  } > "$BT_NGINX_CONF_DIR/custom_modsec_rules.conf"
  log "已写入 $BT_NGINX_CONF_DIR/custom_modsec_rules.conf"

  _baota_inject_shellstack_http_block_in_nginx_conf
  if [[ "${SHELLSTACK_DEPLOY_FASTCGI_CACHE:-1}" == "1" ]]; then
    _baota_inject_fastcgi_cache_into_enable_php_confs
  else
    log "SHELLSTACK_DEPLOY_FASTCGI_CACHE=0，跳过 enable-php 中的 FastCGI 缓存片段"
  fi

  if [[ "${SHELLSTACK_DEPLOY_NGINX_MODULE_VTS:-1}" == "1" ]]; then
    log "=========================================="
    log "--deploy-conf：nginx-module-vts（shellstack_vts.conf + nginx.conf include）"
    log "=========================================="
    if _baota_nginx_has_vts_module; then
      log "检测: $BT_NGINX_BIN 已编入 vhost_traffic_status，继续写入片段并注入 nginx.conf"
      _baota_write_shellstack_vts_conf
      _baota_ensure_nginx_conf_includes_vts
      log "nginx-module-vts：注入步骤结束；请执行: $BT_NGINX_BIN -t && /etc/init.d/nginx reload（或 systemctl reload nginx）"
    else
      log "检测: $BT_NGINX_BIN 的 nginx -V 未含 nginx-module-vts，跳过 shellstack_vts.conf 与 nginx.conf include"
      log "（请重编 OpenResty；若故意不编 VTS 可 export SHELLSTACK_WITH_NGINX_MODULE_VTS=0）"
    fi
  else
    log "SHELLSTACK_DEPLOY_NGINX_MODULE_VTS=0，跳过 nginx-module-vts 片段与 nginx.conf include"
  fi

  log "配置部署完成。请确认 GeoIP 数据库路径、执行 nginx -t 后重载 Nginx。"
}
