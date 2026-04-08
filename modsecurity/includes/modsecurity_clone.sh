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

# 主仓库来自 Gitee（或显式要求）时，将所有子模块 URL 指到 Gitee mirrors。
# 若未全部重写，git submodule update --recursive 会先拉到 bindings/python 等仍指向 GitHub 的模块并超时，导致 libinjection/mbedtls 永远拉不下来。
_modsecurity_apply_gitee_submodule_mirrors() {
  local origin
  MODSECURITY_ORIGIN_IS_GITEE=0
  origin=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$origin" == *gitee.com* ]]; then
    MODSECURITY_ORIGIN_IS_GITEE=1
  fi
  if [[ "$MODSECURITY_ORIGIN_IS_GITEE" != "1" && "${MODSECURITY_USE_GITEE_SUBMODULES}" != "1" ]]; then
    return 0
  fi
  log "子模块统一改为 Gitee mirrors（含 Python 绑定与测试数据，避免仍访问 github.com）..."
  git config submodule.others/libinjection.url "$MODSECURITY_GITEE_LIBINJECTION_URL"
  git config submodule.others/mbedtls.url "$MODSECURITY_GITEE_MBEDTLS_URL"
  git config submodule.test/test-cases/secrules-language-tests.url "$MODSECURITY_GITEE_SECRULES_URL"
  git config submodule.bindings/python.url "$MODSECURITY_GITEE_PYTHON_BINDINGS_URL"
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

# 初始化子模块：必须先拉 others/libinjection、others/mbedtls（configure 硬性依赖），
# 再拉可选子模块；切勿一上来就对全仓库 recursive，否则 git 会先克隆 bindings/python 等并因 GitHub 超时而中断。
_modsecurity_git_submodules() {
  _modsecurity_apply_gitee_submodule_mirrors

  log "拉取构建必需子模块: others/libinjection、others/mbedtls..."
  if ! git submodule update --init --recursive others/libinjection others/mbedtls >>"$LOG_FILE" 2>&1; then
    log "必需子模块直连失败，尝试经 ghproxy 拉取 libinjection / mbedtls..."
    if ! GIT_TERMINAL_PROMPT=0 git \
      -c "http.postBuffer=524288000" \
      -c "url.https://ghproxy.net/https://github.com/.insteadof=https://github.com/" \
      submodule update --init --recursive others/libinjection others/mbedtls >>"$LOG_FILE" 2>&1; then
      error "无法拉取子模块 libinjection 或 mbedtls，configure 无法继续。请确认 Gitee 上 mirrors 齐全或网络可访问 GitHub。日志: $LOG_FILE"
    fi
  fi

  log "拉取可选子模块: bindings/python、test/test-cases/secrules-language-tests（失败一般不影响核心库编译）..."
  if ! git submodule update --init --recursive bindings/python test/test-cases/secrules-language-tests >>"$LOG_FILE" 2>&1; then
    GIT_TERMINAL_PROMPT=0 git \
      -c "http.postBuffer=524288000" \
      -c "url.https://ghproxy.net/https://github.com/.insteadof=https://github.com/" \
      submodule update --init --recursive bindings/python test/test-cases/secrules-language-tests >>"$LOG_FILE" 2>&1 \
      || warn "可选子模块未完全拉取（仅影响 Python 绑定或部分测试，可忽略）。"
  fi
}
