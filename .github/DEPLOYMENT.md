# 部署配置说明

## GitHub Actions 部署配置

本项目使用 GitHub Actions 自动部署到远程服务器。需要配置以下 Secrets：

### 必需的 Secrets

在 GitHub 仓库的 Settings > Secrets and variables > Actions 中添加以下 secrets：

1. **SSH_HOST**: 服务器 IP 地址或域名
   - 例如: `shellstack.910918920801.xyz`

2. **SSH_USER**: SSH 用户名
   - 例如: `root` 或 `deploy`

3. **SSH_PRIVATE_KEY**: SSH 私钥
   - 完整的 SSH 私钥内容（包括 `-----BEGIN` 和 `-----END` 行）

4. **DEPLOY_PATH**: 服务器上的部署路径
   - 例如: `/var/www/shellstack` 或 `/data/wwwroot/shellstack`

### 服务器配置

1. **Web 服务器配置** (Nginx 示例):

```nginx
server {
    listen 80;
    server_name shellstack.910918920801.xyz;
    root /var/www/shellstack;
    index shellstack.sh;

    location / {
        try_files $uri $uri/ =404;
    }

    # 确保 shell 脚本可以被下载
    location ~ \.sh$ {
        add_header Content-Type text/plain;
        add_header Content-Disposition "inline";
    }
}
```

2. **文件权限**:

确保部署目录有正确的权限：
```bash
chmod +x /var/www/shellstack/shellstack.sh
find /var/www/shellstack -name '*.sh' -type f -exec chmod +x {} \;
```

3. **SSH 密钥设置**:

在服务器上添加部署公钥到 `~/.ssh/authorized_keys`

### 测试部署

部署完成后，可以通过以下命令测试：

```bash
# 列出模块
curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s --list

# 安装模块
curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s modsecurity
```

