#!/bin/bash
# ModSecurity git 子模块：others/*、可选模块、Gitee/代理回退
# 依赖: modsecurity_clone_env.sh、log/warn/error、LOG_FILE

_modsecurity_others_submodule_paths() {
  local -n _ms_paths_out="$1"
  _ms_paths_out=()
  [[ -f .gitmodules ]] || return 0
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] && _ms_paths_out+=("$p")
  done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '$2 ~ /^others\// {print $2}')
}

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

_modsecurity_origin_is_gitee_or_force_submodules() {
  MODSECURITY_ORIGIN_IS_GITEE=0
  local origin
  origin=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$origin" == *gitee.com* ]]; then
    MODSECURITY_ORIGIN_IS_GITEE=1
  fi
  [[ "$MODSECURITY_ORIGIN_IS_GITEE" == "1" || "${MODSECURITY_USE_GITEE_SUBMODULES}" == "1" ]]
}

_modsecurity_set_gitee_urls_for_others_submodules() {
  if git config -f .gitmodules --get 'submodule.others/libinjection.url' &>/dev/null; then
    git config submodule.others/libinjection.url "$MODSECURITY_GITEE_LIBINJECTION_URL"
  fi
  if git config -f .gitmodules --get 'submodule.others/mbedtls.url' &>/dev/null; then
    git config submodule.others/mbedtls.url "$MODSECURITY_GITEE_MBEDTLS_URL"
  fi
}

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

_modsecurity_apply_gitee_submodule_mirrors() {
  _modsecurity_set_gitee_urls_for_others_submodules
  _modsecurity_apply_gitee_submodule_mirrors_optional
}

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

_modsecurity_reset_others_submodule_urls_to_upstream() {
  local path raw
  local -a ms_paths=()
  _modsecurity_others_submodule_paths ms_paths
  for path in "${ms_paths[@]}"; do
    raw=$(_modsecurity_submodule_url_for_path "$path") || raw=""
    [[ -n "$raw" ]] && git config "submodule.${path}.url" "$raw"
  done
}

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

_modsecurity_submodule_update_paths() {
  GIT_TERMINAL_PROMPT=0 git submodule update --init --recursive "$@" >>"$LOG_FILE" 2>&1
}

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
  GIT_TERMINAL_PROMPT=0 git submodule sync bindings/python test/test-cases/secrules-language-tests >>"$LOG_FILE" 2>&1 || true
  if GIT_TERMINAL_PROMPT=0 git submodule update --init --recursive bindings/python test/test-cases/secrules-language-tests >>"$LOG_FILE" 2>&1; then
    :
  elif GIT_TERMINAL_PROMPT=0 git \
    -c "http.postBuffer=524288000" \
    -c "url.https://ghproxy.net/https://github.com/.insteadof=https://github.com/" \
    submodule update --init --recursive bindings/python test/test-cases/secrules-language-tests >>"$LOG_FILE" 2>&1; then
    :
  elif GIT_TERMINAL_PROMPT=0 git \
    -c "http.postBuffer=524288000" \
    -c "url.https://mirror.ghproxy.com/https://github.com/.insteadof=https://github.com/" \
    submodule update --init --recursive bindings/python test/test-cases/secrules-language-tests >>"$LOG_FILE" 2>&1; then
    :
  else
    log "可选子模块经 GitHub/代理失败，尝试 Gitee 镜像（失败可忽略）..."
    _modsecurity_apply_gitee_submodule_mirrors_optional
    GIT_TERMINAL_PROMPT=0 git submodule update --init --recursive bindings/python test/test-cases/secrules-language-tests >>"$LOG_FILE" 2>&1 \
      || warn "可选子模块未完全拉取（仅影响 Python 绑定或部分测试，可忽略）。"
  fi
}
