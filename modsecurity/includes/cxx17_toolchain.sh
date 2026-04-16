#!/bin/bash
# ModSecurity v3 的 configure 强制要求 C++17（AX_CXX_COMPILE_STDCXX 17）。
# RHEL/CentOS 7 默认 GCC 4.8 不支持，需在构建前启用 devtoolset（GCC 8+）。

# EL7：CentOS 7 已 EOL，mirror.centos.org 常不可用；依次尝试官方 yum → extras RPM → 写入 vault SCLo 仓库后再装 devtoolset。

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
  local scl_rpm="${vbase}/centos-release-scl-2-3.el7.centos.noarch.rpm"
  local scl_rh_rpm="${vbase}/centos-release-scl-rh-2-3.el7.centos.noarch.rpm"
  # 须整段 eval，否则 URL 不会传给 yum
  eval "$pkg_install $scl_rpm" >>"$LOG_FILE" 2>&1 || true
  eval "$pkg_install $scl_rh_rpm" >>"$LOG_FILE" 2>&1 || true
  rpm -q centos-release-scl-rh >/dev/null 2>&1
}

# 不依赖 centos-release-scl-rh 是否安装成功：直接指向 vault 上仍保留的 SCLo rh 包目录
_cxx17_el7_write_vault_sclo_rh_repo() {
  local f=/etc/yum.repos.d/shellstack-vault-centos7-sclo-rh.repo
  if [[ -f "$f" ]] && grep -q 'vault.centos.org/centos/7/sclo' "$f" 2>/dev/null; then
    return 0
  fi
  warn "写入 fallback 仓库（vault SCLo rh），用于 EOL 后仍安装 devtoolset: $f"
  cat > "$f" <<'EOF'
[shellstack-vault-centos7-sclo-rh]
name=ShellStack fallback — CentOS 7 SCLo rh (vault.centos.org)
baseurl=https://vault.centos.org/centos/7/sclo/$basearch/rh/
enabled=1
gpgcheck=0
repo_gpgcheck=0
# gpg 在 EOL/最小化系统上常缺失 SIG key；仅用于本机编译工具链
EOF
  if command -v yum >/dev/null 2>&1; then
    yum clean all >>"$LOG_FILE" 2>&1 || true
  fi
  return 0
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

_cxx17_el7_try_devtoolset_versions() {
  local pkg_install="$1"
  local ok=0
  for n in 11 10 9 8; do
    if _cxx17_el7_install_one_devtoolset "$pkg_install" "$n"; then
      ok=1
      break
    fi
  done
  [[ "$ok" -eq 1 ]]
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
      warn "仍未检测到 centos-release-scl-rh，将尝试 vault 直链仓库（不依赖该包）。"
    fi

    local ok_ds=0
    if _cxx17_el7_try_devtoolset_versions "$pkg_install"; then
      ok_ds=1
    else
      _cxx17_el7_write_vault_sclo_rh_repo
      if _cxx17_el7_try_devtoolset_versions "$pkg_install"; then
        ok_ds=1
      fi
    fi

    if [[ "$ok_ds" -ne 1 ]]; then
      {
        echo "---- yum repolist (诊断) ----"
        yum repolist all 2>&1 || true
        echo "---- 尝试列出 devtoolset（诊断） ----"
        yum list available 'devtoolset-*-gcc-c++' 2>&1 | head -40 || true
      } >>"$LOG_FILE" 2>&1 || true
      error "无法在 EL 7 上安装 devtoolset（已尝试 11/10/9/8，且已尝试 vault SCLo 仓库）。请查看: $LOG_FILE 末尾诊断。可手工执行: (1) cat /etc/yum.repos.d/*.repo | grep -E baseurl|mirrorlist (2) curl -I https://vault.centos.org/centos/7/sclo/x86_64/rh/repodata/repomd.xml (3) 或升级到 Rocky Linux 8/9。"
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
