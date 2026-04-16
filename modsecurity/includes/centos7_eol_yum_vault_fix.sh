#!/bin/bash
# CentOS 7 已 EOL：mirrorlist.centos.org 不可解析时，把仍指向官方 mirror 的 yum 配置改为 vault.centos.org。
# 解决: Could not resolve host: mirrorlist.centos.org / Cannot find a valid baseurl for repo: centos-sclo-sclo
#
# 用法（在跑 main.sh / ModSecurity 安装前执行一次即可）:
#   sudo bash /path/to/modsecurity/includes/centos7_eol_yum_vault_fix.sh
#
# 会备份被修改的 .repo 到 /etc/yum.repos.d/.shellstack_repo_backup_<时间戳>/

set -eu

if [[ "${EUID:-0}" -ne 0 ]]; then
  echo "请使用 root 执行: sudo bash $0" >&2
  exit 1
fi

if [[ -f /etc/centos-release ]] && ! grep -qi 'release 7' /etc/centos-release 2>/dev/null; then
  echo "提示: 本机似乎不是 CentOS 7，若无需修复可 Ctrl+C 退出。" >&2
  sleep 2
fi

repod=/etc/yum.repos.d
bk="${repod}/.shellstack_repo_backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$bk"

fix_file() {
  local f="$1"
  sed -i \
    -e 's|^mirrorlist=http://mirrorlist.centos.org|#mirrorlist=http://mirrorlist.centos.org|g' \
    -e 's|^mirrorlist=https://mirrorlist.centos.org|#mirrorlist=https://mirrorlist.centos.org|g' \
    -e 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' \
    -e 's|^# baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' \
    -e 's|^baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' \
    -e 's|^#baseurl=https://mirror.centos.org|baseurl=https://vault.centos.org|g' \
    -e 's|^baseurl=https://mirror.centos.org|baseurl=https://vault.centos.org|g' \
    "$f"
}

changed=0
shopt -s nullglob
for f in "$repod"/*.repo; do
  [[ -f "$f" ]] || continue
  if ! grep -qE 'mirrorlist\.centos\.org|mirror\.centos\.org' "$f" 2>/dev/null; then
    continue
  fi
  cp -a "$f" "$bk/"
  fix_file "$f"
  echo "[OK] 已改为 vault: $f"
  changed=$((changed + 1))
done

if [[ "$changed" -eq 0 ]]; then
  echo "未找到含 mirrorlist.centos.org / mirror.centos.org 的 repo 文件，跳过修改。"
else
  echo "备份目录: $bk"
fi

# 降低因单个坏 repo 导致 yum 直接失败（可选）
if command -v yum-config-manager >/dev/null 2>&1; then
  yum-config-manager --save --setopt=centos-sclo-sclo.skip_if_unavailable=true 2>/dev/null || true
  yum-config-manager --save --setopt=centos-sclo-rh.skip_if_unavailable=true 2>/dev/null || true
fi

echo "执行 yum clean all / makecache ..."
yum clean all || true
yum makecache fast || yum makecache || true

echo ""
echo "请重试: yum install -y htop"
echo "再执行 ModSecurity 安装脚本。"
