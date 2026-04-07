#!/bin/bash
# ModSecurity v3 的 configure 强制要求 C++17（AX_CXX_COMPILE_STDCXX 17）。
# RHEL/CentOS 7 默认 GCC 4.8 不支持，需在构建前启用 devtoolset（GCC 9）。

# 可被 main.sh 流程（已设置 PKG_INSTALL / SYSTEM_TYPE）或独立 install.sh 调用；
# 未设置 PKG_INSTALL 时回退为 yum/dnf。
ensure_modsecurity_cxx17_toolchain() {
  log "检查 C++17 编译器 (ModSecurity v3 必需)..."

  if ! command -v g++ >/dev/null 2>&1; then
    error "未找到 g++。请先安装 gcc-c++（RedHat）或 build-essential（Debian）。"
  fi

  mkdir -p "$BUILD_DIR"

  local test_cpp="$BUILD_DIR/.ms_cxx17_probe_$$.cpp"
  local test_bin="$BUILD_DIR/.ms_cxx17_probe_$$"

  cat > "$test_cpp" <<'EOF'
#include <optional>
int main() { std::optional<int> o; return o.has_value() ? 1 : 0; }
EOF

  if g++ -std=c++17 -o "$test_bin" "$test_cpp" 2>>"$LOG_FILE"; then
    rm -f "$test_cpp" "$test_bin"
    log "当前 g++ 满足 C++17: $(command -v g++) ($(g++ -dumpfullversion 2>/dev/null || g++ -dumpversion))"
    return 0
  fi
  rm -f "$test_cpp" "$test_bin" 2>/dev/null || true

  warn "系统默认 g++ 无法满足 ModSecurity 所需的 C++17"

  local pkg_install="${PKG_INSTALL:-}"
  if [[ -z "$pkg_install" ]]; then
    if command -v dnf >/dev/null 2>&1; then
      pkg_install="dnf install -y"
    else
      pkg_install="yum install -y"
    fi
  fi

  local sys_type="${SYSTEM_TYPE:-}"
  if [[ -z "$sys_type" ]] && [[ -f /etc/redhat-release ]]; then
    sys_type="redhat"
  fi

  local dv="${DISTRO_VERSION%%.*}"
  if [[ -z "$dv" ]] && [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    dv="${VERSION_ID%%.*}"
  fi

  local is_el7=0
  if [[ "$dv" == "7" ]]; then
    is_el7=1
  elif [[ -f /etc/redhat-release ]] && grep -qi 'release 7' /etc/redhat-release; then
    is_el7=1
  fi

  if [[ "$sys_type" == "redhat" && "$is_el7" -eq 1 ]]; then
    log "在 EL 7 上安装 devtoolset-9（GCC 9）以提供 C++17..."
    # yum 解析到仅 IPv6 的镜像且本机无 IPv6 时会失败；强制 IPv4
    local yum4=""
    if [[ "$pkg_install" == yum\ install\ -y ]]; then
      yum4="--setopt=ip_resolve=4"
    fi
    eval "$pkg_install $yum4 centos-release-scl" >> "$LOG_FILE" 2>&1 || true
    if ! eval "$pkg_install $yum4 devtoolset-9-gcc devtoolset-9-gcc-c++ devtoolset-9-binutils devtoolset-9-make" >> "$LOG_FILE" 2>&1; then
      error "无法安装 devtoolset-9。CentOS/RHEL 7 自带的 GCC 4.8 无法编译 ModSecurity v3。请确保已启用 Software Collections 仓库后手动安装: yum install -y devtoolset-9-gcc-c++，执行 source /opt/rh/devtoolset-9/enable 后重试本脚本。"
    fi
    if [[ -f /opt/rh/devtoolset-9/enable ]]; then
      # shellcheck disable=SC1091
      source /opt/rh/devtoolset-9/enable
    fi
    export PATH="/opt/rh/devtoolset-9/root/usr/bin:$PATH"
    hash -r 2>/dev/null || true
  elif [[ "$sys_type" == "debian" ]]; then
    error "g++ 版本过旧，不支持 C++17。安装较新的 g++（例如 g++-9 或更高）或升级发行版后再运行本脚本。"
  else
    error "g++ 不支持 C++17，无法构建 ModSecurity v3。需要 GCC 7 或更高版本的 g++。当前: $(g++ --version 2>&1 | head -1)"
  fi

  cat > "$test_cpp" <<'EOF'
#include <optional>
int main() { std::optional<int> o; return o.has_value() ? 1 : 0; }
EOF
  if ! g++ -std=c++17 -o "$test_bin" "$test_cpp" 2>>"$LOG_FILE"; then
    rm -f "$test_cpp" "$test_bin" 2>/dev/null || true
    error "启用新工具链后 C++17 检测仍失败。请查看日志: $LOG_FILE"
  fi
  rm -f "$test_cpp" "$test_bin"
  log "已启用 C++17 工具链: $(command -v g++) ($(g++ -dumpfullversion 2>/dev/null || g++ -dumpversion))"
}
