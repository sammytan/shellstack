# ShellStack

一个模块化的 Shell 脚本管理工具，支持远程调用和自动部署。

## 🚀 快速开始

### 远程使用（推荐）

```bash
# 列出所有可用模块
curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s --list

# 安装 modsecurity 模块
curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s modsecurity

# 安装模块并传递参数
curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s modsecurity --version=3.0.10 --enable-geoip
```

### 本地使用

```bash
# 克隆仓库
git clone https://github.com/yourusername/shellstack.git
cd shellstack

# 列出所有模块
./shellstack.sh --list

# 安装模块
./shellstack.sh modsecurity --version=3.0.10
```

## 📦 模块说明

### modsecurity

ModSecurity 核心库安装脚本，支持多系统、多版本的 ModSecurity 安装。

**功能特性：**
- 支持多系统（Ubuntu/Debian/CentOS/RHEL/Rocky Linux/Fedora/Arch/OpenSUSE）
- 支持多版本选择（ModSecurity 3.0.x）
- 可选功能：GeoIP、Fail2ban、OpenResty、内核优化等

**使用示例：**
```bash
# 基本安装
curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s modsecurity

# 完整安装（所有功能）
curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s modsecurity \
  --version=3.0.10 \
  --enable-geoip \
  --enable-security \
  --enable-openresty

# 查看帮助
curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s modsecurity --help
```

详细文档请查看 [modsecurity/README.md](./modsecurity/README.md)

## 📁 项目结构

```
shellstack/
├── shellstack.sh          # 主入口脚本
├── README.md              # 项目说明文档
├── modsecurity/           # ModSecurity 模块
│   ├── main.sh           # 模块入口脚本
│   ├── install.sh        # 安装脚本
│   ├── run.sh            # 运行包装脚本
│   ├── helper.sh         # 辅助脚本
│   ├── README.md         # 模块文档
│   └── includes/         # 模块子脚本
│       ├── shared.sh
│       ├── os_check.sh
│       ├── modsecurity.sh
│       └── ...
└── .github/
    └── workflows/
        └── deploy.yml    # GitHub Actions 部署配置
```

## 🔧 添加新模块

要添加新模块，只需在项目根目录创建一个新目录：

1. **创建模块目录**
   ```bash
   mkdir -p mymodule
   ```

2. **创建入口脚本**
   
   模块需要至少包含以下文件之一：
   - `main.sh` - 主入口脚本（推荐）
   - `run.sh` - 运行包装脚本
   - `install.sh` - 安装脚本

3. **添加 README.md**（可选）
   
   在模块目录中添加 README.md 说明模块功能和使用方法。

4. **测试模块**
   ```bash
   # 本地测试
   ./shellstack.sh mymodule
   
   # 远程测试（部署后）
   curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s mymodule
   ```

## 🔄 自动部署

项目使用 GitHub Actions 自动部署到远程服务器。

### 配置部署

1. **设置 GitHub Secrets**
   
   在仓库 Settings > Secrets and variables > Actions 中添加：
   - `SSH_HOST`: 服务器地址
   - `SSH_USER`: SSH 用户名
   - `SSH_PRIVATE_KEY`: SSH 私钥
   - `DEPLOY_PATH`: 部署路径

2. **配置 Web 服务器**
   
   确保 Web 服务器可以访问部署目录，并正确设置文件权限。

详细配置说明请查看 [.github/DEPLOYMENT.md](./.github/DEPLOYMENT.md)

### 部署流程

1. 推送代码到 `main` 分支
2. GitHub Actions 自动触发部署
3. 文件同步到远程服务器
4. 设置执行权限

## 📝 使用说明

### 主脚本命令

```bash
shellstack.sh [选项] [模块名] [模块参数...]
```

**选项：**
- `--list, -l` - 列出所有可用模块
- `--help, -h` - 显示帮助信息
- `--version, -v` - 显示版本信息

**示例：**
```bash
# 列出模块
./shellstack.sh --list

# 安装模块
./shellstack.sh modsecurity --version=3.0.10

# 远程使用
curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s --list
curl https://shellstack.910918920801.xyz/shellstack.sh | bash -s modsecurity
```

### 模块参数传递

所有传递给 `shellstack.sh` 的参数（模块名之后）都会传递给模块脚本：

```bash
# 这些参数会传递给 modsecurity 模块
./shellstack.sh modsecurity --version=3.0.10 --enable-geoip --prefix=/opt/modsecurity
```

## 🔒 安全注意事项

1. **远程执行脚本**
   
   使用 `curl | bash` 执行远程脚本存在安全风险，请确保：
   - 使用 HTTPS 连接
   - 信任脚本来源
   - 审查脚本内容

2. **服务器安全**
   
   - 使用 SSH 密钥认证
   - 限制 SSH 访问 IP
   - 定期更新服务器

3. **权限管理**
   
   - 模块脚本可能需要 root 权限
   - 谨慎授予执行权限
   - 审查模块脚本内容

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目遵循原模块的许可证。

## 📞 支持

如有问题，请：
- 查看模块的 README.md
- 提交 GitHub Issue
- 查看安装日志
