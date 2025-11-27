#!/bin/bash
# 自动配置 Nginx 的脚本
# 在服务器上执行: sudo bash setup-nginx.sh

set -e

BASE_URL="https://shellstack.910918920801.xyz"
DOMAIN="${BASE_URL#https://}"
DEPLOY_PATH="/var/www/shellstack"
NGINX_CONF="/etc/nginx/sites-available/shellstack.conf"

echo "=========================================="
echo "Nginx 自动配置脚本"
echo "=========================================="
echo ""
echo "域名: ${DOMAIN}"
echo "部署路径: ${DEPLOY_PATH}"
echo "配置文件: ${NGINX_CONF}"
echo ""

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
   echo "错误: 此脚本需要 root 权限运行"
   echo "请使用: sudo bash setup-nginx.sh"
   exit 1
fi

# 检查 Nginx 是否安装
if ! command -v nginx &> /dev/null; then
    echo "错误: Nginx 未安装"
    echo "请先安装 Nginx:"
    echo "  Ubuntu/Debian: apt-get install nginx"
    echo "  CentOS/RHEL: yum install nginx"
    exit 1
fi

# 检查部署目录是否存在
if [[ ! -d "${DEPLOY_PATH}" ]]; then
    echo "错误: 部署目录不存在: ${DEPLOY_PATH}"
    echo "请先运行部署脚本或创建目录"
    exit 1
fi

# 创建 Nginx 配置文件
echo "1. 创建 Nginx 配置文件..."
cat > "${NGINX_CONF}" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    root ${DEPLOY_PATH};
    index shellstack.sh index.html;

    access_log /var/log/nginx/shellstack_access.log;
    error_log /var/log/nginx/shellstack_error.log;

    location / {
        try_files \$uri \$uri/ =404;
        add_header Content-Type text/plain;
        add_header Content-Disposition "inline";
    }

    location ~ \.sh$ {
        add_header Content-Type text/plain;
        add_header Content-Disposition "inline";
        add_header X-Content-Type-Options "nosniff";
    }

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~ /\.git {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF

echo "   ✓ 配置文件已创建"

# 启用站点
echo "2. 启用站点..."
if [[ -f "/etc/nginx/sites-enabled/shellstack.conf" ]]; then
    echo "   ⚠ 站点已启用，跳过"
else
    ln -sf "${NGINX_CONF}" /etc/nginx/sites-enabled/shellstack.conf
    echo "   ✓ 站点已启用"
fi

# 测试配置
echo "3. 测试 Nginx 配置..."
if nginx -t; then
    echo "   ✓ 配置测试通过"
else
    echo "   ✗ 配置测试失败"
    exit 1
fi

# 重载 Nginx
echo "4. 重载 Nginx..."
if systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null; then
    echo "   ✓ Nginx 已重载"
else
    echo "   ⚠ 无法自动重载，请手动执行: systemctl reload nginx"
fi

echo ""
echo "=========================================="
echo "配置完成！"
echo "=========================================="
echo ""
echo "测试访问:"
echo "  curl ${BASE_URL}/shellstack.sh | head -5"
echo ""
echo "如果看到脚本内容而不是 404，说明配置成功！"

