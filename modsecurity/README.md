# ModSecurity 核心库安装脚本

一个模块化的 ModSecurity 核心库安装脚本，支持多系统、多版本的 ModSecurity 安装。

## 📁 目录结构

```
mosecurity/
├── main.sh                    # 主入口文件
├── install.sh                 # 原始安装脚本（已重构）
├── README.md                  # 本文档
└── includes/                  # 模块目录
    ├── shared.sh              # 共享配置和工具函数
    ├── os_check.sh            # 系统检测和版本检查
    ├── require_packages.sh    # 依赖包安装
    ├── modsecurity.sh         # ModSecurity 核心安装（默认安装）
    ├── geoip.sh               # GeoIP 选装功能
    ├── google_bbr_kernel.sh   # Google BBR 内核优化（默认安装）
    ├── terminal.sh            # 终端配置（默认安装）
    ├── fail2ban.sh            # Fail2ban 安装和配置（默认不启用）
    ├── openresty.sh           # OpenResty 选装
    └── help.sh                # 帮助和信息查看
```

## 🚀 快速开始

### 基本安装

```bash
sudo ./main.sh
```

### 指定版本和路径

```bash
sudo ./main.sh --version=3.0.9 --prefix=/opt/modsecurity
```

### 启用所有可选功能

```bash
sudo ./main.sh --enable-geoip --enable-security --enable-openresty
```

## 📋 功能模块说明

### 默认安装模块

1. **modsecurity.sh** - ModSecurity 核心库（必需）
   - 支持多版本选择
   - 自动检测和安装依赖
   - 支持多种编译选项

2. **google_bbr_kernel.sh** - Google BBR 内核优化（默认启用）
   - BBR 拥塞控制算法
   - TCP 参数优化
   - 文件系统和内存优化

3. **terminal.sh** - 终端配置（默认启用）
   - 终端颜色配置
   - 常用别名设置
   - 支持 bash 和 zsh

### 可选安装模块

4. **geoip.sh** - GeoIP 支持（选装）
   - 安装 libmaxminddb
   - 配置 GeoIP 数据库更新
   - 支持自动更新定时任务
   - 使用 `--enable-geoip` 启用

5. **fail2ban.sh** - Fail2ban 安装和配置（默认不启用）
   - fail2ban 安装和配置
   - SSH 安全加固
   - 使用 `--enable-security` 启用

6. **openresty.sh** - OpenResty 安装（选装）
   - 完整的 OpenResty 安装
   - 可选的 ModSecurity 集成
   - 使用 `--enable-openresty` 启用

## 🔧 命令行选项

### 基本选项

- `--prefix=PATH` - 设置 ModSecurity 安装路径（默认: `/usr/local/modsecurity`）
- `--version=VERSION` - 设置 ModSecurity 版本（默认: `3.0.10`）
- `--help` / `-h` - 显示帮助信息

### 功能开关

- `--enable-geoip` - 启用 GeoIP 支持
- `--enable-security` - 启用安全配置
- `--enable-openresty` - 安装 OpenResty
- `--enable-kernel-opt` - 启用内核优化（默认启用）
- `--enable-terminal` - 启用终端配置（默认启用）
- `--disable-kernel-opt` - 禁用内核优化
- `--disable-terminal` - 禁用终端配置

### 信息命令

- `--verify` - 验证已安装的 ModSecurity
- `--info` - 显示安装信息
- `--cleanup` - 清理临时文件

## 📦 支持的系统

- **Ubuntu/Debian** - 支持 10/11/12 版本
- **CentOS/RHEL** - 支持 7/8 版本
- **Rocky Linux/AlmaLinux** - 支持 8/9 版本
- **Fedora** - 最新版本
- **Arch Linux/Manjaro** - 最新版本
- **OpenSUSE/SUSE** - 最新版本

## 🔄 ModSecurity 版本支持

支持所有 ModSecurity 3.0.x 版本：
- `3.0.0` - `3.0.10`（推荐）
- `latest` / `master` - 最新版本
- 任何有效的 git 标签版本

## 📝 使用示例

### 示例 1: 默认安装

```bash
sudo ./main.sh
```

### 示例 2: 安装特定版本并启用 GeoIP

```bash
sudo ./main.sh --version=3.0.9 --enable-geoip
```

### 示例 3: 完整安装（所有功能）

```bash
sudo ./main.sh \
  --version=3.0.10 \
  --prefix=/usr/local/modsecurity \
  --enable-geoip \
  --enable-security \
  --enable-openresty
```

### 示例 4: 验证安装

```bash
sudo ./main.sh --verify
```

### 示例 5: 查看安装信息

```bash
sudo ./main.sh --info
```

## 📂 安装后的文件位置

- **库文件**: `/usr/local/modsecurity/lib/libmodsecurity.so`
- **头文件**: `/usr/local/modsecurity/include/modsecurity/`
- **配置文件**: `/usr/local/etc/GeoIP.conf`（如果启用 GeoIP）
- **日志文件**: `/tmp/modsecurity_install.log`

## 🔍 验证安装

安装完成后，可以使用以下命令验证：

```bash
# 验证库文件
ls -lh /usr/local/modsecurity/lib/libmodsecurity.so*

# 验证头文件
ls -la /usr/local/modsecurity/include/modsecurity/

# 使用 pkg-config
pkg-config --modversion libmodsecurity
pkg-config --cflags --libs libmodsecurity
```

## 🛠️ 编译使用示例

安装后，可以在代码中使用 ModSecurity：

```c
// 编译时链接库
gcc your_code.c \
  -L/usr/local/modsecurity/lib \
  -lmodsecurity \
  -I/usr/local/modsecurity/include

// 使用 pkg-config
gcc $(pkg-config --cflags --libs libmodsecurity) your_code.c
```

## 📚 模块说明

### shared.sh
- 全局变量和配置
- 颜色定义和日志函数
- 通用工具函数

### os_check.sh
- 系统发行版检测
- 架构检测
- 包管理器识别

### require_packages.sh
- 系统依赖包安装
- 编译依赖库安装（YAJL, Lua, LMDB, SSDEEP, libmaxminddb）

### modsecurity.sh
- ModSecurity 源码下载
- 版本选择和编译
- 安装和验证

### geoip.sh
- GeoIP/MaxMindDB 支持
- geoipupdate 工具安装
- 自动更新配置

### google_bbr_kernel.sh
- BBR 内核安装
- 内核参数优化
- 系统性能调优

### terminal.sh
- 终端颜色配置
- Shell 别名设置
- 全局配置文件

### fail2ban.sh
- fail2ban 安装和配置
- SSH 安全加固
- 安全策略设置

### openresty.sh
- OpenResty 编译安装
- ModSecurity 集成
- 系统服务配置

### help.sh
- 安装验证
- 信息显示
- 清理功能

## 🐛 故障排除

### 问题 1: 编译失败

**解决方案**: 检查日志文件 `/tmp/modsecurity_install.log`，确保所有依赖已正确安装。

### 问题 2: 找不到库文件

**解决方案**: 运行 `ldconfig` 更新库缓存，或检查 `LD_LIBRARY_PATH` 环境变量。

### 问题 3: GeoIP 更新失败

**解决方案**: 检查网络连接和 MaxMind 账户配置 `/usr/local/etc/GeoIP.conf`。

## 📄 许可证

本脚本遵循原 ModSecurity 项目的许可证。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📞 支持

如有问题，请查看：
- 安装日志: `/tmp/modsecurity_install.log`
- ModSecurity 官方文档: https://github.com/SpiderLabs/ModSecurity

