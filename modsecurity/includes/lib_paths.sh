#!/bin/bash
# 共享库 / pkg-config 路径：动态扫描本机目录，不绑定 x86_64、arm64 等固定 triplet 名。
# Debian/Ubuntu 多架构：/usr/lib/<triplet>/；RHEL 等多为 /usr/lib64（无 triplet 子目录）。

# 每行一个目录，供 check_lib 等遍历
shellstack_standard_library_dirs() {
  local p
  for p in /usr/lib /usr/lib64 /usr/local/lib /lib /lib64; do
    [[ -d "$p" ]] && printf '%s\n' "$p"
  done
  local d
  shopt -s nullglob
  for d in /usr/lib/*-linux-*/; do
    [[ -d "$d" ]] && printf '%s\n' "${d%/}"
  done
  shopt -u nullglob
}

# ModSecurity ./configure：让 pkg-config 找到 libpcre2-8 等（多架构下 .pc 在 triplet 子目录）
modsecurity_export_configure_build_env() {
  export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:+$PKG_CONFIG_PATH:}/usr/lib/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig"
  export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}/usr/lib64:/usr/lib:/usr/local/lib"
  export LDFLAGS="-L/usr/local/lib -L/usr/lib64 -L/usr/lib"
  export CPPFLAGS="-I/usr/local/include -I/usr/include"

  local pcbase libdir _ms_multi=0
  shopt -s nullglob
  for pcbase in /usr/lib/*-linux-*/pkgconfig; do
    [[ -d "$pcbase" ]] || continue
    ((_ms_multi++))
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$pcbase"
    libdir="${pcbase%/pkgconfig}"
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$libdir"
    export LDFLAGS="$LDFLAGS -L$libdir"
  done
  shopt -u nullglob

  if [[ "$_ms_multi" -gt 0 ]] && declare -F log >/dev/null 2>&1; then
    log "configure 构建环境: 已动态加入 $_ms_multi 组多架构路径（/usr/lib/*-linux-*/pkgconfig）"
  fi
}
