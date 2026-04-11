#!/bin/bash
# ModSecurity 主仓库克隆：多镜像、进度输出（镜像顺序由 modsecurity_ipinfo.sh）
# 依赖: modsecurity_clone_env.sh、modsecurity_ipinfo.sh、log/warn/error、LOG_FILE、BUILD_DIR

_ms_git_clone_modsecurity_repo() {
  local url="$1"
  local mode="${2:-normal}"
  rm -rf ModSecurity
  local -a gargs=(
    -c "http.postBuffer=524288000"
    -c "http.lowSpeedLimit=0"
    -c "http.lowSpeedTime=999999"
  )
  if [[ "$mode" == "ghproxy" ]]; then
    gargs+=(-c "url.https://ghproxy.net/https://github.com/.insteadof=https://github.com/")
  fi
  if [[ "${MODSECURITY_GIT_CLONE_QUIET}" == "1" ]] || ! command -v tee >/dev/null 2>&1; then
    GIT_TERMINAL_PROMPT=0 git "${gargs[@]}" clone --progress --depth 1 "$url" ModSecurity >>"$LOG_FILE" 2>&1
    return $?
  fi
  GIT_TERMINAL_PROMPT=0 git "${gargs[@]}" clone --progress --depth 1 "$url" ModSecurity 2>&1 | tee -a "$LOG_FILE"
  return "${PIPESTATUS[0]}"
}

_ms_try_git_clone() {
  local url="$1"
  local attempt
  for attempt in 1 2 3; do
    log "尝试克隆 ModSecurity ($attempt/3): $url"
    if [[ "${MODSECURITY_GIT_CLONE_QUIET}" != "1" ]]; then
      log "克隆进度（同时写入日志 $LOG_FILE）:"
    fi
    if _ms_git_clone_modsecurity_repo "$url" normal; then
      return 0
    fi
    sleep 10
  done
  return 1
}

clone_modsecurity_source() {
  local repo
  local -a mirrors

  if [[ -n "$MODSECURITY_GIT_URL" ]]; then
    log "使用环境变量 MODSECURITY_GIT_URL 指定仓库"
    _ms_try_git_clone "$MODSECURITY_GIT_URL" && return 0
    warn "MODSECURITY_GIT_URL 克隆失败，尝试内置镜像列表..."
  fi

  local _ms_github_first=0
  local _ms_reason=""
  _modsecurity_clone_mirror_decision _ms_github_first _ms_reason

  if [[ "$_ms_github_first" == "1" ]]; then
    log "克隆顺序: GitHub 优先 — $_ms_reason"
    mirrors=(
      "https://github.com/SpiderLabs/ModSecurity.git"
      "$MODSECURITY_GITEE_URL"
      "https://ghproxy.net/https://github.com/SpiderLabs/ModSecurity.git"
      "https://mirror.ghproxy.com/https://github.com/SpiderLabs/ModSecurity.git"
      "https://gitclone.com/github.com/SpiderLabs/ModSecurity.git"
    )
  else
    log "克隆顺序: Gitee 优先 — $_ms_reason"
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
  if [[ "${MODSECURITY_GIT_CLONE_QUIET}" != "1" ]]; then
    log "克隆进度（同时写入日志 $LOG_FILE）:"
  fi
  if _ms_git_clone_modsecurity_repo "https://github.com/SpiderLabs/ModSecurity.git" ghproxy; then
    return 0
  fi

  warn "git 克隆错误摘要（详见 $LOG_FILE）:"
  grep -iE 'error|failed|fatal|timed out|Connection|reset|403|SSL|GnuTLS' "$LOG_FILE" 2>/dev/null | tail -15 | while read -r line; do warn "  $line"; done || true

  error "无法克隆 ModSecurity 仓库。请检查网络/DNS/防火墙，或设置 MODSECURITY_GIT_URL / MODSECURITY_GITEE_URL 为可访问的镜像后再运行。完整日志: $LOG_FILE"
}
