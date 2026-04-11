#!/bin/bash
# 从 GitHub / Gitee 等镜像拉取 ModSecurity（多镜像、重试、url.insteadOf），便于网络受限环境。
# 依赖已由调用方加载: log / warn / error、LOG_FILE、BUILD_DIR

MODSECURITY_GIT_URL="${MODSECURITY_GIT_URL:-}"
# 主仓库 Gitee 镜像（国内常用）
MODSECURITY_GITEE_URL="${MODSECURITY_GITEE_URL:-https://gitee.com/mirrors/ModSecurity.git}"
# 从 Gitee 拉主仓库时，子模块仍可能指向 GitHub；下列镜像可覆盖（可自行 export 修正）
MODSECURITY_GITEE_LIBINJECTION_URL="${MODSECURITY_GITEE_LIBINJECTION_URL:-https://gitee.com/mirrors/libinjection.git}"
MODSECURITY_GITEE_MBEDTLS_URL="${MODSECURITY_GITEE_MBEDTLS_URL:-https://gitee.com/mirrors/mbedtls.git}"
MODSECURITY_GITEE_SECRULES_URL="${MODSECURITY_GITEE_SECRULES_URL:-https://gitee.com/mirrors/secrules-language-tests.git}"
MODSECURITY_GITEE_PYTHON_BINDINGS_URL="${MODSECURITY_GITEE_PYTHON_BINDINGS_URL:-https://gitee.com/mirrors/ModSecurity-Python-bindings.git}"
# 设为 1 时即使主仓库来自 GitHub，也强制用下面 Gitee 地址拉子模块（主仓能通、子模块仍需翻墙时可用）
MODSECURITY_USE_GITEE_SUBMODULES="${MODSECURITY_USE_GITEE_SUBMODULES:-0}"
# 上游官方 URL（Gitee/ghproxy 失败时回退；一般无需改）
MODSECURITY_UPSTREAM_LIBINJECTION_URL="${MODSECURITY_UPSTREAM_LIBINJECTION_URL:-https://github.com/libinjection/libinjection.git}"
MODSECURITY_UPSTREAM_MBEDTLS_URL="${MODSECURITY_UPSTREAM_MBEDTLS_URL:-https://github.com/Mbed-TLS/mbedtls.git}"

_ms_try_git_clone() {
  local url="$1"
  local attempt
  for attempt in 1 2 3; do
    log "尝试克隆 ModSecurity ($attempt/3): $url"
    rm -rf ModSecurity
    if GIT_TERMINAL_PROMPT=0 git \
      -c "http.postBuffer=524288000" \
      -c "http.lowSpeedLimit=0" \
      -c "http.lowSpeedTime=999999" \
      clone --depth 1 "$url" ModSecurity >>"$LOG_FILE" 2>&1; then
      return 0
    fi
    sleep 10
  done
  return 1
}

# 克隆 SpiderLabs/ModSecurity 到当前目录下的 ModSecurity/
clone_modsecurity_source() {
  local repo
  local -a mirrors

  if [[ -n "$MODSECURITY_GIT_URL" ]]; then
    log "使用环境变量 MODSECURITY_GIT_URL 指定仓库"
    _ms_try_git_clone "$MODSECURITY_GIT_URL" && return 0
    warn "MODSECURITY_GIT_URL 克隆失败，尝试内置镜像列表..."
  fi

  # 默认优先 Gitee（国内访问 GitHub 常超时）；须先 GitHub 时请设 MODSECURITY_PREFER_GITHUB=1
  # 兼容旧变量：MODSECURITY_PREFER_GITEE=0 等价于先 GitHub
  if [[ "${MODSECURITY_PREFER_GITHUB:-}" == "1" ]] || [[ "${MODSECURITY_PREFER_GITEE:-}" == "0" ]]; then
    log "克隆顺序: GitHub 优先（MODSECURITY_PREFER_GITHUB=1）"
    mirrors=(
      "https://github.com/SpiderLabs/ModSecurity.git"
      "$MODSECURITY_GITEE_URL"
      "https://ghproxy.net/https://github.com/SpiderLabs/ModSecurity.git"
      "https://mirror.ghproxy.com/https://github.com/SpiderLabs/ModSecurity.git"
      "https://gitclone.com/github.com/SpiderLabs/ModSecurity.git"
    )
  else
    log "克隆顺序: Gitee 优先（$MODSECURITY_GITEE_URL）"
    mirrors=(
      "$MODSECURITY_GITEE_URL"
      "https://github.com/SpiderLabs/ModSecurity.git"
      "https://ghproxy.net/https://github.com/SpiderLabs/ModSecurity.git"
      "https://mirror.ghproxy.com/https://github.com/SpiderLabs/ModSecurity.git"
      "https://gitclone.com/github.com/SpiderLabs/ModSecurity.git"
    )
  fi

  for repo in "${mirrors[@]}"; do
    if _ms_try_git_clone "$repo"; then
      return 0
    fi
  done

  log "镜像直链均失败，尝试 url.insteadOf 经由 ghproxy 访问 github.com..."
  rm -rf ModSecurity
  if GIT_TERMINAL_PROMPT=0 git \
    -c "http.postBuffer=524288000" \
    -c "http.lowSpeedLimit=0" \
    -c "http.lowSpeedTime=999999" \
    -c "url.https://ghproxy.net/https://github.com/.insteadof=https://github.com/" \
    clone --depth 1 "https://github.com/SpiderLabs/ModSecurity.git" ModSecurity >>"$LOG_FILE" 2>&1; then
    return 0
  fi

  warn "git 克隆错误摘要（详见 $LOG_FILE）:"
  grep -iE 'error|failed|fatal|timed out|Connection|reset|403|SSL|GnuTLS' "$LOG_FILE" 2>/dev/null | tail -15 | while read -r line; do warn "  $line"; done || true

  error "无法克隆 ModSecurity 仓库。请检查网络/DNS/防火墙，或设置 MODSECURITY_GIT_URL / MODSECURITY_GITEE_URL 为可访问的镜像后再运行。完整日志: $LOG_FILE"
}

# 当前检出版本的 .gitmodules 中，others/ 下需要拉取的子模块路径（v3.0.x 可能仅有 libinjection，无 mbedtls）
_modsecurity_others_submodule_paths() {
  local -n _ms_paths_out="$1"
  _ms_paths_out=()
  [[ -f .gitmodules ]] || return 0
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] && _ms_paths_out+=("$p")
  done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '$2 ~ /^others\// {print $2}')
}

# 从 .gitmodules 读取子模块 URL；失败时用内置上游默认（仅 others/libinjection、others/mbedtls）
_modsecurity_submodule_url_for_path() {
  local path="$1"
  local key="submodule.${path}.url"
  local u
  u=$(git config -f .gitmodules --get "$key" 2>/dev/null) || u=""
  if [[ -n "$u" ]]; then
    echo "$u"
    return 0
  fi
  case "$path" in
    others/libinjection) echo "$MODSECURITY_UPSTREAM_LIBINJECTION_URL" ;;
    others/mbedtls) echo "$MODSECURITY_UPSTREAM_MBEDTLS_URL" ;;
    *) echo "" ;;
  esac
}

# 是否「先」用 Gitee 拉 others/libinjection、others/mbedtls（默认 0：与旧版一致，先 GitHub+代理，失败再 Gitee）
MODSECURITY_OTHERS_SUBMODULES_GITEE_FIRST="${MODSECURITY_OTHERS_SUBMODULES_GITEE_FIRST:-0}"

_modsecurity_origin_is_gitee_or_force_submodules() {
  MODSECURITY_ORIGIN_IS_GITEE=0
  local origin
  origin=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$origin" == *gitee.com* ]]; then
    MODSECURITY_ORIGIN_IS_GITEE=1
  fi
  [[ "$MODSECURITY_ORIGIN_IS_GITEE" == "1" || "${MODSECURITY_USE_GITEE_SUBMODULES}" == "1" ]]
}

# 将 others/* 指到环境变量中的 Gitee 镜像（无 origin 判断；由调用方决定何时使用）
_modsecurity_set_gitee_urls_for_others_submodules() {
  if git config -f .gitmodules --get 'submodule.others/libinjection.url' &>/dev/null; then
    git config submodule.others/libinjection.url "$MODSECURITY_GITEE_LIBINJECTION_URL"
  fi
  if git config -f .gitmodules --get 'submodule.others/mbedtls.url' &>/dev/null; then
    git config submodule.others/mbedtls.url "$MODSECURITY_GITEE_MBEDTLS_URL"
  fi
}

# 仅将可选子模块指到 Gitee（避免 bindings/python 等仍走 GitHub 导致超时）
_modsecurity_apply_gitee_submodule_mirrors_optional() {
  if ! _modsecurity_origin_is_gitee_or_force_submodules; then
    return 0
  fi
  log "可选子模块使用 Gitee 镜像（Python 绑定、secrules 测试数据）..."
  if git config -f .gitmodules --get 'submodule.test/test-cases/secrules-language-tests.url' &>/dev/null; then
    git config submodule.test/test-cases/secrules-language-tests.url "$MODSECURITY_GITEE_SECRULES_URL"
  fi
  if git config -f .gitmodules --get 'submodule.bindings/python.url' &>/dev/null; then
    git config submodule.bindings/python.url "$MODSECURITY_GITEE_PYTHON_BINDINGS_URL"
  fi
}

# 兼容旧逻辑：others + 可选 均改为 Gitee URL（不执行 submodule update）
_modsecurity_apply_gitee_submodule_mirrors() {
  _modsecurity_set_gitee_urls_for_others_submodules
  _modsecurity_apply_gitee_submodule_mirrors_optional
}

# 将 others/* 子模块 URL 设为「前缀 + 上游 GitHub URL」（前缀可为 ghproxy 等镜像根）
_modsecurity_set_others_submodule_urls_prefixed() {
  local prefix="${1:-}"
  local path raw prefixed
  local -a ms_paths=()
  _modsecurity_others_submodule_paths ms_paths
  for path in "${ms_paths[@]}"; do
    raw=$(_modsecurity_submodule_url_for_path "$path") || raw=""
    [[ -z "$raw" ]] && continue
    if [[ "$raw" != https://github.com/* ]]; then
      git config "submodule.${path}.url" "$raw"
      continue
    fi
    prefixed="${prefix}${raw}"
    git config "submodule.${path}.url" "$prefixed"
  done
}

# 将 others/* 子模块恢复为 .gitmodules 中的官方 GitHub URL（供 insteadOf 或直连使用）
_modsecurity_reset_others_submodule_urls_to_upstream() {
  local path raw
  local -a ms_paths=()
  _modsecurity_others_submodule_paths ms_paths
  for path in "${ms_paths[@]}"; do
    raw=$(_modsecurity_submodule_url_for_path "$path") || raw=""
    [[ -n "$raw" ]] && git config "submodule.${path}.url" "$raw"
  done
}

# 拉取标签（失败时用 ghproxy 重写再试）
_modsecurity_git_fetch_tags() {
  if git fetch --tags >>"$LOG_FILE" 2>&1; then
    return 0
  fi
  log "git fetch --tags 失败，尝试经 ghproxy 重写 github.com..."
  GIT_TERMINAL_PROMPT=0 git \
    -c "http.postBuffer=524288000" \
    -c "url.https://ghproxy.net/https://github.com/.insteadof=https://github.com/" \
    fetch --tags >>"$LOG_FILE" 2>&1
}

# 运行 git submodule update；参数为子模块路径列表
_modsecurity_submodule_update_paths() {
  git submodule update --init --recursive "$@" >>"$LOG_FILE" 2>&1
}

# 假定 others/* 已恢复为 .gitmodules 中的 GitHub URL；依次尝试直连、ghproxy、gitclone 等
_modsecurity_fetch_others_with_github_mirror_ladder() {
  local -a ms_paths=("$@")
  if _modsecurity_submodule_update_paths "${ms_paths[@]}"; then
    return 0
  fi
  if GIT_TERMINAL_PROMPT=0 git \
    -c "http.postBuffer=524288000" \
    -c "url.https://ghproxy.net/https://github.com/.insteadof=https://github.com/" \
    submodule update --init --recursive "${ms_paths[@]}" >>"$LOG_FILE" 2>&1; then
    return 0
  fi
  if GIT_TERMINAL_PROMPT=0 git \
    -c "http.postBuffer=524288000" \
    -c "url.https://mirror.ghproxy.com/https://github.com/.insteadof=https://github.com/" \
    submodule update --init --recursive "${ms_paths[@]}" >>"$LOG_FILE" 2>&1; then
    return 0
  fi
  log "insteadOf 仍失败，尝试将子模块 URL 设为 ghproxy 完整路径..."
  _modsecurity_set_others_submodule_urls_prefixed "https://ghproxy.net/"
  if _modsecurity_submodule_update_paths "${ms_paths[@]}"; then
    return 0
  fi
  _modsecurity_set_others_submodule_urls_prefixed "https://mirror.ghproxy.com/"
  if _modsecurity_submodule_update_paths "${ms_paths[@]}"; then
    return 0
  fi
  _modsecurity_reset_others_submodule_urls_to_upstream
  log "尝试经 gitclone.com 访问 GitHub..."
  if GIT_TERMINAL_PROMPT=0 git \
    -c "http.postBuffer=524288000" \
    -c "url.https://gitclone.com/github.com/.insteadof=https://github.com/" \
    submodule update --init --recursive "${ms_paths[@]}" >>"$LOG_FILE" 2>&1; then
    return 0
  fi
  _modsecurity_reset_others_submodule_urls_to_upstream
  if _modsecurity_submodule_update_paths "${ms_paths[@]}"; then
    return 0
  fi
  return 1
}

# 初始化子模块：必须先拉 others/*（configure 硬性依赖），再拉可选子模块。
#
# 主仓库用 Gitee 只解决「主仓克隆」；others/libinjection 默认仍用 .gitmodules 里的 GitHub URL + 代理（与直接克隆 GitHub 主仓时一致）。
# 若先改写成 Gitee 子模块镜像，Gitee 上 libinjection 常不可用，会白白失败一轮。最后才回退到 Gitee 上的 others 镜像。
_modsecurity_git_submodules() {
  local -a ms_paths=()
  local paths_label

  _modsecurity_others_submodule_paths ms_paths
  if [[ ${#ms_paths[@]} -eq 0 ]] && [[ -f .gitmodules ]] && grep -q 'others/libinjection' .gitmodules; then
    ms_paths=(others/libinjection)
  fi
  if [[ ${#ms_paths[@]} -eq 0 ]]; then
    error "未在 .gitmodules 中发现 others/* 子模块，无法构建 ModSecurity。日志: $LOG_FILE"
  fi
  paths_label="${ms_paths[*]}"
  paths_label="${paths_label// /、}"

  if [[ "${MODSECURITY_OTHERS_SUBMODULES_GITEE_FIRST}" == "1" ]] || [[ "${MODSECURITY_USE_GITEE_SUBMODULES}" == "1" ]]; then
    log "拉取构建必需子模块（先试 Gitee：MODSECURITY_OTHERS_SUBMODULES_GITEE_FIRST=1 或 MODSECURITY_USE_GITEE_SUBMODULES=1）: $paths_label..."
    _modsecurity_set_gitee_urls_for_others_submodules
    if _modsecurity_submodule_update_paths "${ms_paths[@]}"; then
      :
    else
      log "Gitee 拉取 others 失败，恢复为 GitHub 官方 URL 并重试..."
      _modsecurity_reset_others_submodule_urls_to_upstream
      if ! _modsecurity_fetch_others_with_github_mirror_ladder "${ms_paths[@]}"; then
        log "GitHub/代理仍失败，最后再次尝试 Gitee 上的 others 镜像..."
        _modsecurity_set_gitee_urls_for_others_submodules
        _modsecurity_submodule_update_paths "${ms_paths[@]}" \
          || error "无法拉取必需子模块（$paths_label）。请检查网络或设置 MODSECURITY_GITEE_LIBINJECTION_URL / MODSECURITY_UPSTREAM_*。日志: $LOG_FILE"
      fi
    fi
  else
    _modsecurity_reset_others_submodule_urls_to_upstream
    log "拉取构建必需子模块（优先 GitHub / 代理；主仓来自 Gitee 时亦如此）: $paths_label..."
    if ! _modsecurity_fetch_others_with_github_mirror_ladder "${ms_paths[@]}"; then
      log "GitHub 与常用代理均失败，最后尝试 Gitee 上的 libinjection/mbedtls 镜像..."
      _modsecurity_set_gitee_urls_for_others_submodules
      if ! _modsecurity_submodule_update_paths "${ms_paths[@]}"; then
        error "无法拉取必需子模块（$paths_label）。请检查网络，或设置 MODSECURITY_PREFER_GITHUB=1 克隆主仓、或配置可访问的 MODSECURITY_GITEE_LIBINJECTION_URL / MODSECURITY_UPSTREAM_*。日志: $LOG_FILE"
      fi
    fi
  fi

  log "拉取可选子模块: bindings/python、test/test-cases/secrules-language-tests（失败一般不影响核心库编译）..."
  _modsecurity_apply_gitee_submodule_mirrors_optional
  if ! git submodule update --init --recursive bindings/python test/test-cases/secrules-language-tests >>"$LOG_FILE" 2>&1; then
    GIT_TERMINAL_PROMPT=0 git \
      -c "http.postBuffer=524288000" \
      -c "url.https://ghproxy.net/https://github.com/.insteadof=https://github.com/" \
      submodule update --init --recursive bindings/python test/test-cases/secrules-language-tests >>"$LOG_FILE" 2>&1 \
      || warn "可选子模块未完全拉取（仅影响 Python 绑定或部分测试，可忽略）。"
  fi
}
