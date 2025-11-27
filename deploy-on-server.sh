#!/bin/bash
# 在服务器上直接执行的部署脚本
# 使用方法: 将此脚本上传到服务器，然后执行 bash deploy-on-server.sh

set -e

BASE_URL="https://shellstack.910918920801.xyz"
DEPLOY_PATH="/var/www/shellstack"
REPO_URL="${REPO_URL:-https://github.com/yourusername/shellstack.git}"

echo "=========================================="
echo "ShellStack 服务器端部署脚本"
echo "=========================================="
echo ""
echo "部署路径: ${DEPLOY_PATH}"
echo ""

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
   echo "错误: 此脚本需要 root 权限运行"
   echo "请使用: sudo bash deploy-on-server.sh"
   exit 1
fi

# 创建部署目录
echo "1. 创建部署目录..."
mkdir -p "${DEPLOY_PATH}"
cd "${DEPLOY_PATH}"

# 检查是否已有 Git 仓库
if [[ -d ".git" ]]; then
    echo "2. 检测到现有 Git 仓库，更新代码..."
    git pull origin main || git pull origin master
else
    echo "2. 克隆仓库..."
    if [[ -n "$REPO_URL" ]] && [[ "$REPO_URL" != "https://github.com/yourusername/shellstack.git" ]]; then
        git clone "${REPO_URL}" .
    else
        echo "错误: 请设置 REPO_URL 环境变量"
        echo "例如: REPO_URL=https://github.com/yourusername/shellstack.git bash deploy-on-server.sh"
        echo ""
        echo "或者手动克隆:"
        echo "  cd ${DEPLOY_PATH}"
        echo "  git clone <your-repo-url> ."
        exit 1
    fi
fi

# 生成模块列表
echo "3. 生成模块列表..."
if [[ -f "generate-modules-list.sh" ]]; then
    chmod +x generate-modules-list.sh
    ./generate-modules-list.sh
fi

# 设置文件权限
echo "4. 设置文件权限..."
chmod +x shellstack.sh 2>/dev/null || true
find . -name '*.sh' -type f -exec chmod +x {} \; 2>/dev/null || true

# 设置目录权限（Web 服务器需要读取权限）
echo "5. 设置目录权限..."
chmod -R 755 "${DEPLOY_PATH}"
chown -R www-data:www-data "${DEPLOY_PATH}" 2>/dev/null || \
chown -R nginx:nginx "${DEPLOY_PATH}" 2>/dev/null || \
chown -R apache:apache "${DEPLOY_PATH}" 2>/dev/null || true

# 验证部署
echo "6. 验证部署..."
if [[ -f "shellstack.sh" ]]; then
    echo "   ✓ shellstack.sh 存在"
else
    echo "   ✗ shellstack.sh 不存在"
    exit 1
fi

if [[ -f "modules.txt" ]]; then
    echo "   ✓ modules.txt 存在"
    echo "   模块列表:"
    grep -v "^#" modules.txt | grep -v "^$" | sed 's/^/     - /'
else
    echo "   ⚠ modules.txt 不存在（可选）"
fi

echo ""
echo "=========================================="
echo "部署完成！"
echo "=========================================="
echo ""
echo "下一步：配置 Web 服务器"
echo ""
echo "Nginx 配置示例:"
echo "  server {"
echo "      listen 80;"
echo "      server_name ${BASE_URL#https://};"
echo "      root ${DEPLOY_PATH};"
echo "      index shellstack.sh;"
echo ""
echo "      location / {"
echo "          try_files \$uri \$uri/ =404;"
echo "          add_header Content-Type text/plain;"
echo "      }"
echo "  }"
echo ""
echo "测试命令:"
echo "  curl ${BASE_URL}/shellstack.sh | head -5"

