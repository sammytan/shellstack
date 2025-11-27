# 快速开始指南

## 问题：404 Not Found

如果你看到 404 错误，说明文件还没有部署到服务器。按照以下步骤快速解决：

## 方法 1: 手动部署（推荐）

### 步骤 1: 准备部署脚本

在本地项目目录中，确保你有 SSH 访问权限：

```bash
# 设置环境变量（根据实际情况修改）
export SSH_HOST="shellstack.910918920801.xyz"
export SSH_USER="root"
export DEPLOY_PATH="/var/www/shellstack"
```

### 步骤 2: 执行部署

```bash
# 使用提供的部署脚本
chmod +x deploy-manual.sh
./deploy-manual.sh
```

### 步骤 3: 配置 Web 服务器

**Nginx 配置示例**:

```bash
# 创建 Nginx 配置文件
sudo nano /etc/nginx/sites-available/shellstack.conf
```

将以下内容复制到文件中（根据实际路径修改）：

```nginx
server {
    listen 80;
    server_name shellstack.910918920801.xyz;
    root /var/www/shellstack;
    index shellstack.sh;

    location / {
        try_files $uri $uri/ =404;
        add_header Content-Type text/plain;
        add_header Content-Disposition "inline";
    }

    location ~ \.sh$ {
        add_header Content-Type text/plain;
        add_header Content-Disposition "inline";
    }
}
```

启用配置：

```bash
# 创建符号链接
sudo ln -s /etc/nginx/sites-available/shellstack.conf /etc/nginx/sites-enabled/

# 测试配置
sudo nginx -t

# 重载 Nginx
sudo systemctl reload nginx
```

### 步骤 4: 测试

```bash
# 测试访问
curl https://shellstack.910918920801.xyz/shellstack.sh | head -5

# 应该看到脚本内容，而不是 404
```

## 方法 2: 直接上传文件

如果无法使用 SSH，可以直接在服务器上操作：

### 步骤 1: 在服务器上创建目录

```bash
ssh root@shellstack.910918920801.xyz
mkdir -p /var/www/shellstack
cd /var/www/shellstack
```

### 步骤 2: 上传文件

使用 `scp` 或 `rsync` 从本地上传：

```bash
# 在本地执行
rsync -avz --exclude='.git' --exclude='.github' \
  ./ root@shellstack.910918920801.xyz:/var/www/shellstack/
```

或使用 Git：

```bash
# 在服务器上执行
cd /var/www/shellstack
git clone https://github.com/yourusername/shellstack.git .
chmod +x shellstack.sh
find . -name '*.sh' -type f -exec chmod +x {} \;
```

### 步骤 3: 配置 Web 服务器

参考方法 1 的步骤 3

## 方法 3: 使用 GitHub Actions（自动化）

### 步骤 1: 配置 GitHub Secrets

在 GitHub 仓库中：
1. 进入 Settings > Secrets and variables > Actions
2. 添加以下 secrets:
   - `SSH_HOST`: `shellstack.910918920801.xyz`
   - `SSH_USER`: `root`
   - `SSH_PRIVATE_KEY`: 你的 SSH 私钥（完整内容）
   - `DEPLOY_PATH`: `/var/www/shellstack`

### 步骤 2: 推送代码

```bash
git add .
git commit -m "Initial deployment"
git push origin main
```

GitHub Actions 会自动部署。

## 验证部署

部署完成后，运行诊断脚本：

```bash
# 在本地运行
./diagnose.sh

# 或直接在服务器上测试
curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s --list
```

## 常见问题

### 1. SSH 连接失败

```bash
# 测试 SSH 连接
ssh root@shellstack.910918920801.xyz

# 如果失败，检查：
# - SSH 密钥是否正确配置
# - 服务器防火墙是否允许 SSH
# - 服务器地址是否正确
```

### 2. 文件权限问题

```bash
# 在服务器上执行
chmod +x /var/www/shellstack/shellstack.sh
chmod -R 755 /var/www/shellstack
chown -R www-data:www-data /var/www/shellstack  # Nginx
# 或
chown -R apache:apache /var/www/shellstack  # Apache
```

### 3. Nginx 403 Forbidden

```bash
# 检查目录权限
ls -ld /var/www/shellstack

# 检查 Nginx 错误日志
sudo tail -f /var/log/nginx/error.log

# 确保目录有执行权限
chmod 755 /var/www/shellstack
```

### 4. 文件存在但无法访问

检查 Nginx 配置中的 `root` 路径是否正确：

```bash
# 检查实际文件位置
ls -la /var/www/shellstack/shellstack.sh

# 检查 Nginx 配置中的 root 路径
grep -r "root" /etc/nginx/sites-enabled/shellstack.conf
```

## 下一步

部署成功后：

1. **测试基本功能**:
   ```bash
   curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s --list
   ```

2. **安装模块**:
   ```bash
   curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s modsecurity
   ```

3. **查看帮助**:
   ```bash
   curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s --help
   ```

## 需要帮助？

如果以上方法都无法解决问题，请：
1. 运行 `./diagnose.sh` 获取详细诊断信息
2. 查看 [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
3. 提交 GitHub Issue 并提供错误信息

