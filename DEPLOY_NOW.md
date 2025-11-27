# 🚀 立即部署指南

## 当前问题
你看到 404 错误，说明文件还没有部署到服务器。按照以下步骤快速解决：

## 方法 1: 使用 Git 克隆（最简单）

### 在服务器上执行：

```bash
# 1. 创建部署目录
mkdir -p /var/www/shellstack
cd /var/www/shellstack

# 2. 克隆仓库（替换为你的实际仓库地址）
git clone https://github.com/yourusername/shellstack.git .

# 如果仓库是私有的，使用 SSH:
# git clone git@github.com:yourusername/shellstack.git .

# 3. 设置权限
chmod +x shellstack.sh
find . -name '*.sh' -type f -exec chmod +x {} \;

# 4. 生成模块列表
chmod +x generate-modules-list.sh
./generate-modules-list.sh

# 5. 配置 Nginx（见下方）
```

## 方法 2: 使用部署脚本

### 步骤 1: 上传部署脚本到服务器

在本地执行：
```bash
scp deploy-on-server.sh root@shellstack.910918920801.xyz:/root/
scp setup-nginx.sh root@shellstack.910918920801.xyz:/root/
```

### 步骤 2: 在服务器上执行

```bash
# SSH 到服务器
ssh root@shellstack.910918920801.xyz

# 设置仓库 URL（替换为你的实际仓库）
export REPO_URL="https://github.com/yourusername/shellstack.git"

# 执行部署
sudo bash deploy-on-server.sh

# 配置 Nginx
sudo bash setup-nginx.sh
```

## 方法 3: 手动上传文件

### 步骤 1: 在本地打包文件

```bash
# 在项目根目录执行
tar czf shellstack.tar.gz \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='*.log' \
  --exclude='.DS_Store' \
  shellstack.sh \
  modules.txt \
  modsecurity/ \
  generate-modules-list.sh
```

### 步骤 2: 上传到服务器

```bash
scp shellstack.tar.gz root@shellstack.910918920801.xyz:/root/
```

### 步骤 3: 在服务器上解压

```bash
ssh root@shellstack.910918920801.xyz
mkdir -p /var/www/shellstack
cd /var/www/shellstack
tar xzf /root/shellstack.tar.gz
chmod +x shellstack.sh
find . -name '*.sh' -type f -exec chmod +x {} \;
```

## 配置 Nginx

### 自动配置（推荐）

```bash
sudo bash setup-nginx.sh
```

### 手动配置

```bash
# 创建配置文件
sudo nano /etc/nginx/sites-available/shellstack.conf
```

复制以下内容：

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

## 验证部署

部署完成后，测试：

```bash
# 测试主脚本
curl https://shellstack.910918920801.xyz/shellstack.sh | head -5

# 应该看到脚本内容，例如:
# #!/bin/bash
# set -e
# ...

# 测试列出模块
curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s --list

# 应该看到模块列表
```

## 如果仍然看到 404

### 检查清单：

1. **文件是否存在？**
   ```bash
   ls -la /var/www/shellstack/shellstack.sh
   ```

2. **Nginx 配置是否正确？**
   ```bash
   grep -r "root" /etc/nginx/sites-enabled/shellstack.conf
   # 应该显示: root /var/www/shellstack;
   ```

3. **Nginx 是否重载？**
   ```bash
   sudo systemctl reload nginx
   ```

4. **检查 Nginx 错误日志**
   ```bash
   sudo tail -f /var/log/nginx/error.log
   ```

5. **检查文件权限**
   ```bash
   ls -la /var/www/shellstack/
   sudo chmod -R 755 /var/www/shellstack
   sudo chown -R www-data:www-data /var/www/shellstack
   ```

## 快速命令总结

```bash
# 一键部署（如果已有 Git 仓库）
cd /var/www/shellstack && \
git pull && \
chmod +x shellstack.sh && \
find . -name '*.sh' -type f -exec chmod +x {} \; && \
sudo systemctl reload nginx

# 测试
curl https://shellstack.910918920801.xyz/shellstack.sh | head -5
```

## 需要帮助？

如果以上方法都不行，请提供：
1. `ls -la /var/www/shellstack/` 的输出
2. `cat /etc/nginx/sites-enabled/shellstack.conf` 的输出
3. `sudo nginx -t` 的输出
4. `sudo tail -20 /var/log/nginx/error.log` 的输出

