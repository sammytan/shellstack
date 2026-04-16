#!/bin/bash
# CentOS 7 已 EOL：自动把仍指向 mirrorlist.centos.org / mirror.centos.org 的 yum 配置改为可用镜像（默认阿里云 centos-vault）。
# 解决: Could not resolve host: mirrorlist.centos.org / Cannot find a valid baseurl for repo: centos-sclo-sclo
#
# 用法:
#   sudo bash /path/to/modsecurity/includes/centos7_eol_yum_vault_fix.sh
#   sudo CENTOS7_YUM_MIRROR=vault bash .../centos7_eol_yum_vault_fix.sh
#
# 环境变量 CENTOS7_YUM_MIRROR（可选）:
#   aliyun | ali      — 默认。https://mirrors.aliyun.com/centos-vault/centos/...
#   vault | google    — 海外官方归档 https://vault.centos.org/centos/...（无 Google 公共 CentOS 源，google 即 vault）
#   tsinghua | tuna   — https://mirrors.tuna.tsinghua.edu.cn/centos-vault/centos/...
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

MIRROR="${CENTOS7_YUM_MIRROR:-aliyun}"
MIRROR_LC="$(echo "$MIRROR" | tr '[:upper:]' '[:lower:]')"
case "$MIRROR_LC" in
  aliyun|ali|alibaba)
    PREFIX="https://mirrors.aliyun.com/centos-vault/centos"
    MIRROR_LABEL="阿里云 centos-vault"
    ;;
  vault|google|intl|foreign)
    PREFIX="https://vault.centos.org/centos"
    MIRROR_LABEL="vault.centos.org（海外归档；google 选项等同此项）"
    ;;
  tsinghua|tuna)
    PREFIX="https://mirrors.tuna.tsinghua.edu.cn/centos-vault/centos"
    MIRROR_LABEL="清华 centos-vault"
    ;;
  *)
    echo "未知 CENTOS7_YUM_MIRROR=$MIRROR，改用 aliyun" >&2
    PREFIX="https://mirrors.aliyun.com/centos-vault/centos"
    MIRROR_LABEL="阿里云 centos-vault（回退）"
    ;;
esac

echo "使用镜像: $MIRROR_LABEL"
echo "baseurl 前缀: $PREFIX"

repod=/etc/yum.repos.d
bk="${repod}/.shellstack_repo_backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$bk"

# PREFIX 含 /，sed 用 | 作分隔符
fix_file() {
  local f="$1"
  sed -i \
    -e 's|^mirrorlist=http://mirrorlist.centos.org|#mirrorlist=http://mirrorlist.centos.org|g' \
    -e 's|^mirrorlist=https://mirrorlist.centos.org|#mirrorlist=https://mirrorlist.centos.org|g' \
    -e "s|http://mirror.centos.org/centos|${PREFIX}|g" \
    -e "s|https://mirror.centos.org/centos|${PREFIX}|g" \
    -e 's|^#baseurl=|baseurl=|g' \
    -e 's|^# baseurl=|baseurl=|g' \
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
  echo "[OK] 已切换镜像: $f"
  changed=$((changed + 1))
done

if [[ "$changed" -eq 0 ]]; then
  echo "未找到含 mirrorlist.centos.org / mirror.centos.org 的 repo 文件，跳过修改。"
else
  echo "备份目录: $bk"
fi

if command -v yum-config-manager >/dev/null 2>&1; then
  yum-config-manager --save --setopt=centos-sclo-sclo.skip_if_unavailable=true 2>/dev/null || true
  yum-config-manager --save --setopt=centos-sclo-rh.skip_if_unavailable=true 2>/dev/null || true
fi

echo "执行 yum clean all / makecache ..."
yum clean all || true
yum makecache fast || yum makecache || true

echo ""
echo "当前镜像: $MIRROR_LABEL"
echo "若 aliyun 不可用可重试: sudo CENTOS7_YUM_MIRROR=vault bash $0"
echo "请执行: yum install -y htop"
echo "再执行 ModSecurity 安装脚本。"
