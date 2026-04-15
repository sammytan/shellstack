# 故障排除指南

## 常见问题

### 1. 404 Not Found 错误

**问题**: 访问 `https://shellstack.910918920801.xyz/shellstack.sh` 返回 404

**可能原因**:
- 文件尚未部署到服务器
- Web 服务器配置不正确
- 文件路径不匹配

**解决步骤**:

1. **检查文件是否存在**:
```bash
ssh root@shellstack.910918920801.xyz "ls -la /var/www/shellstack/shellstack.sh"
```

2. **手动部署文件**:
```bash
# 使用提供的部署脚本
chmod +x deploy-manual.sh
./deploy-manual.sh

# 或手动部署
rsync -avz ./ root@shellstack.910918920801.xyz:/var/www/shellstack/
```

3. **检查 Web 服务器配置**:
```bash
# 检查 Nginx 配置
ssh root@shellstack.910918920801.xyz "nginx -t"

# 查看 Nginx 配置
ssh root@shellstack.910918920801.xyz "cat /etc/nginx/sites-available/shellstack.conf"
```

4. **检查文件权限**:
```bash
ssh root@shellstack.910918920801.xyz "chmod +x /var/www/shellstack/shellstack.sh"
```

### 2. 权限被拒绝错误

**问题**: `Permission denied` 或无法执行脚本

**解决方法**:
```bash
# 设置执行权限
ssh root@shellstack.910918920801.xyz "chmod +x /var/www/shellstack/shellstack.sh"
ssh root@shellstack.910918920801.xyz "find /var/www/shellstack -name '*.sh' -type f -exec chmod +x {} \;"

# 检查文件所有者
ssh root@shellstack.910918920801.xyz "ls -la /var/www/shellstack/shellstack.sh"
```

### 3a. `wget .../btwaf-ext/btwaf/lib/cache.lua` 返回 403 Forbidden

**原因**: Nginx 使用了类似 `location ~ \.(php|lua|pl|cgi)$ { return 403; }` 的规则，所有 `.lua` 请求都会被拒绝；`--extend-btwaf-cache` 用 curl/wget 拉取扩展 Lua 时同样会 403。

**解决**: 为静态仓库目录增加 **`^~` 前缀 location**，使其优先于上述正则（官方文档：带 `^~` 的最长前缀匹配成功后不再尝试正则）：

```nginx
# 写在「禁止 .lua」的 location 之前或同一 server 内；root 与站点一致即可继承
location ^~ /btwaf-ext/ {
    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime on;
    charset utf-8,gbk;
}
```

然后 `nginx -t && nginx -s reload`，再验证：

```bash
curl -fsSL -o /dev/null -w '%{http_code}\n' https://你的域名/btwaf-ext/btwaf/lib/cache.lua
# 应输出 200
```

### 3b. 脚本提示「不是有效 cache.lua」但浏览器能打开同一 URL

**常见原因**：服务端对静态文件启用了 **gzip**，旧版脚本用 curl 落盘的是**压缩二进制**，本地 `grep` 匹配不到 `resty.redis`。当前 `btwaf_extend.sh` 已改为 `curl --compressed`（并带固定 UA），请更新脚本后重试。

自检（应看到明文 `--` 或 `local` 开头，且含 `resty.redis`）：

```bash
curl -fsSL --compressed -A 'ShellStack-test/1' 'https://你的域名/btwaf-ext/btwaf/lib/cache.lua' | head -n 5
```

### 3. Web 服务器无法访问文件

**问题**: Nginx/Apache 返回 403 Forbidden

**解决方法**:
```bash
# 检查目录权限
ssh root@shellstack.910918920801.xyz "ls -ld /var/www/shellstack"

# 设置正确的权限（Nginx 通常以 www-data 用户运行）
ssh root@shellstack.910918920801.xyz "chown -R www-data:www-data /var/www/shellstack"
ssh root@shellstack.910918920801.xyz "chmod -R 755 /var/www/shellstack"
```

### 4. GitHub Actions 部署失败

**问题**: GitHub Actions 工作流执行失败

**检查清单**:
- [ ] SSH_HOST secret 是否正确设置
- [ ] SSH_USER secret 是否正确设置
- [ ] SSH_PRIVATE_KEY secret 是否完整（包括 BEGIN/END 行）
- [ ] DEPLOY_PATH secret 是否正确
- [ ] 服务器 SSH 密钥是否已添加到 authorized_keys

**调试步骤**:
1. 查看 GitHub Actions 日志
2. 手动测试 SSH 连接:
```bash
ssh -i ~/.ssh/id_rsa ${SSH_USER}@${SSH_HOST}
```

### 5. 模块下载失败

**问题**: 执行模块时无法下载子脚本

**解决方法**:
1. 检查模块目录是否存在:
```bash
ssh root@shellstack.910918920801.xyz "ls -la /var/www/shellstack/modsecurity/"
```

2. 检查模块入口文件:
```bash
ssh root@shellstack.910918920801.xyz "test -f /var/www/shellstack/modsecurity/main.sh && echo 'OK' || echo 'Missing'"
```

3. 检查 Web 服务器是否可以访问模块目录

### 6. 脚本执行错误

**问题**: 脚本下载成功但执行时报错

**调试方法**:
```bash
# 下载脚本到本地查看
curl https://shellstack.910918920801.xyz/shellstack.sh > /tmp/test.sh
cat /tmp/test.sh

# 检查脚本语法
bash -n /tmp/test.sh

# 手动执行查看详细错误
bash -x /tmp/test.sh --list
```

## 快速诊断命令

运行以下命令进行完整诊断:

```bash
#!/bin/bash
BASE_URL="https://shellstack.910918920801.xyz"
DEPLOY_PATH="/var/www/shellstack"

echo "=== 诊断开始 ==="
echo ""

echo "1. 检查主脚本是否存在..."
curl -I "${BASE_URL}/shellstack.sh" 2>&1 | head -1

echo ""
echo "2. 检查模块列表文件..."
curl -I "${BASE_URL}/modules.txt" 2>&1 | head -1

echo ""
echo "3. 检查 modsecurity 模块..."
curl -I "${BASE_URL}/modsecurity/main.sh" 2>&1 | head -1

echo ""
echo "4. 测试脚本下载..."
curl -s "${BASE_URL}/shellstack.sh" | head -5

echo ""
echo "=== 诊断完成 ==="
```

## 联系支持

如果以上方法都无法解决问题，请提供以下信息:

1. 错误消息的完整输出
2. Web 服务器类型和版本 (Nginx/Apache)
3. 服务器操作系统版本
4. 部署路径
5. Web 服务器配置文件的片段

