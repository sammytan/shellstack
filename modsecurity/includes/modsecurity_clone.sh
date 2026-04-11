#!/bin/bash
# ModSecurity 源码获取入口：加载环境变量后依次 include 克隆与子模块逻辑。
# 依赖已由调用方加载: log / warn / error、LOG_FILE、BUILD_DIR

_MS_CLONE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=modsecurity_clone_env.sh
source "$_MS_CLONE_DIR/modsecurity_clone_env.sh"
# shellcheck source=modsecurity_ipinfo.sh
source "$_MS_CLONE_DIR/modsecurity_ipinfo.sh"
# shellcheck source=modsecurity_git_clone.sh
source "$_MS_CLONE_DIR/modsecurity_git_clone.sh"
# shellcheck source=modsecurity_git_submodules.sh
source "$_MS_CLONE_DIR/modsecurity_git_submodules.sh"
unset _MS_CLONE_DIR
