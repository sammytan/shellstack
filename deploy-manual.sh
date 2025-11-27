#!/bin/bash
# 手动部署脚本 - 用于快速部署到服务器

set -e

# 配置变量（请根据实际情况修改）
SSH_HOST="${SSH_HOST:-shellstack.910918920801.xyz}"
SSH_USER="${SSH_USER:-root}"
DEPLOY_PATH="${DEPLOY_PATH:-/var/www/shellstack}"

echo "=========================================="
echo "ShellStack 手动部署脚本"
echo "=========================================="
echo ""
echo "配置信息:"
echo "  服务器: ${SSH_USER}@${SSH_HOST}"
echo "  部署路径: ${DEPLOY_PATH}"
echo ""

# 检查 SSH 连接
echo "检查 SSH 连接..."
if ! ssh -o ConnectTimeout=5 ${SSH_USER}@${SSH_HOST} "echo 'SSH 连接成功'" 2>/dev/null; then
    echo "错误: 无法连接到服务器，请检查："
    echo "  1. SSH 密钥是否已配置"
    echo "  2. 服务器地址是否正确"
    echo "  3. 网络连接是否正常"
    exit 1
fi

# 生成模块列表
echo "生成模块列表..."
chmod +x generate-modules-list.sh
./generate-modules-list.sh

# 创建部署目录
echo "创建部署目录..."
ssh ${SSH_USER}@${SSH_HOST} "mkdir -p ${DEPLOY_PATH}"

# 同步文件
echo "同步文件到服务器..."
rsync -avz --delete \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='.DS_Store' \
  --exclude='*.log' \
  --exclude='deploy-manual.sh' \
  ./ ${SSH_USER}@${SSH_HOST}:${DEPLOY_PATH}/

# 设置执行权限
echo "设置文件权限..."
ssh ${SSH_USER}@${SSH_HOST} "chmod +x ${DEPLOY_PATH}/shellstack.sh"
ssh ${SSH_USER}@${SSH_HOST} "find ${DEPLOY_PATH} -name '*.sh' -type f -exec chmod +x {} \;"

# 验证部署
echo "验证部署..."
if ssh ${SSH_USER}@${SSH_HOST} "test -f ${DEPLOY_PATH}/shellstack.sh"; then
    echo ""
    echo "=========================================="
    echo "部署成功！"
    echo "=========================================="
    echo ""
    echo "文件位置: ${DEPLOY_PATH}/shellstack.sh"
    echo ""
    echo "下一步："
    echo "  1. 配置 Web 服务器（Nginx/Apache）"
    echo "  2. 确保 Web 服务器可以访问 ${DEPLOY_PATH}"
    echo "  3. 测试访问: curl https://shellstack.910918920801.xyz/shellstack.sh"
    echo ""
else
    echo "错误: 部署验证失败"
    exit 1
fi

