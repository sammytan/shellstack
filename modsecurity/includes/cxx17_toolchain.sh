#!/bin/bash
# ModSecurity v3 的 configure 强制要求 C++17（AX_CXX_COMPILE_STDCXX 17）。
# RHEL/CentOS 7 默认 GCC 4.8 不支持，需在构建前启用 devtoolset（GCC 9+）。

# EL7：CentOS 7 已 EOL，默认 yum 源常缺 centos-release-scl；尝试 vault 直装 RPM，并依次尝试 devtoolset-11/10/9。
_cxx17_el7_try_install_scl_release() {
  local pkg_install="$1"
  if rpm -q centos-release-scl-rh >/dev/null 2>&1; then
    return 0
  fi
  if eval "$pkg_install centos-release-scl centos-release-scl-rh" >>"$LOG_FILE" 2>&1; then
    return 0
  fi
  warn "从当前 yum 源安装 centos-release-scl 失败（CentOS 7 EOL 后常见），尝试 vault.centos.org 的 extras RPM..."
  local vbase="https://vault.centos.org/centos/7/extras/x86_64/Packages"
  # 常见命名；若 404 可改版本号或手工下载后 yum localinstall
  local scl_rpm="${vbase}/centos-release-scl-2-3.el7.centos.noarch.rpm"
  local scl_rh_rpm="${vbase}/centos-release-scl-rh-2-3.el7.centos.noarch.rpm"
  eval "$pkg_install" "$scl_rpm" >>"$LOG_FILE" 2>&1 || true
  eval "$pkg_install" "$scl_rh_rpm" >>"$LOG_FILE" 2>&1 || true
  rpm -q centos-release-scl-rh >/dev/null 2>&1
}

_cxx17_el7_enable_devtoolset() {
  local n="$1"
  if [[ -f "/opt/rh/devtoolset-${n}/enable" ]]; then
    # shellcheck disable=SC1091
    source "/opt/rh/devtoolset-${n}/enable"
    export PATH="/opt/rh/devtoolset-${n}/root/usr/bin:$PATH"
    hash -r 2>/dev/null || true
    return 0
  fi
  return 1
}

_cxx17_el7_install_one_devtoolset() {
  local pkg_install="$1"
  local n="$2"
  if eval "$pkg_install devtoolset-${n}-gcc devtoolset-${n}-gcc-c++ devtoolset-${n}-binutils devtoolset-${n}-make" >>"$LOG_FILE" 2>&1; then
    if _cxx17_el7_enable_devtoolset "$n"; then
      log "已安装并启用 devtoolset-${n}（GCC 用于 ModSecurity C++17）"
      return 0
    fi
  fi
  return 1
}

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
    log "在 EL 7 上安装 Software Collections（devtoolset）以提供 C++17..."
    _cxx17_el7_try_install_scl_release "$pkg_install" || true
    if ! rpm -q centos-release-scl-rh >/dev/null 2>&1; then
      warn "仍未检测到 centos-release-scl-rh。若为 RHEL 7 请用订阅源启用 rh scl；若为其它 EL7 克隆请配置与 CentOS 7 vault 等价的 extras/SCL 仓库。"
    fi
    local ok_ds=0
    for n in 11 10 9; do
      if _cxx17_el7_install_one_devtoolset "$pkg_install" "$n"; then
        ok_ds=1
        break
      fi
    done
    if [[ "$ok_ds" -ne 1 ]]; then
      error "无法在 EL 7 上安装 devtoolset（已尝试 11/10/9）。CentOS 7 自带 GCC 4.8 不能编译 ModSecurity v3。请任选其一：(1) 按日志检查 yum 源，手工安装: yum install -y centos-release-scl centos-release-scl-rh && yum install -y devtoolset-11-gcc-c++，再执行 source /opt/rh/devtoolset-11/enable 后重跑；(2) 使用 vault.centos.org 替换/补充 7.x 仓库；(3) 升级到 Rocky Linux 8/9 等新发行版。"
    fi
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
