#!/bin/bash

# =====================================================================
# Fail2ban 安装和配置（默认不启用）
# 包括 fail2ban 和 SSH 安全配置
# =====================================================================

# 安装和配置 fail2ban
install_fail2ban() {
  log "开始安装和配置 fail2ban..."

  # 确定日志路径
  case "$SYSTEM_TYPE" in
    debian)
      LOG_PATH="/var/log/auth.log"
      ;;
    redhat)
      LOG_PATH="/var/log/secure"
      ;;
    *)
      LOG_PATH="/var/log/auth.log"
      warn "未知的系统类型，使用默认日志路径"
      ;;
  esac

  # 创建文档目录
  mkdir -p /usr/local/share/doc/modsecurity

  # 安装 fail2ban
  if ! command -v fail2ban-server >/dev/null 2>&1; then
    log "安装 fail2ban..."
    case "$SYSTEM_TYPE" in
      debian)
        eval "$PKG_UPDATE" >> "$LOG_FILE" 2>&1
        eval "$PKG_INSTALL fail2ban" >> "$LOG_FILE" 2>&1 || error "fail2ban 安装失败"
        ;;
      redhat)
        # 确保 EPEL 仓库已安装
        if ! rpm -q epel-release >/dev/null 2>&1; then
          eval "$PKG_INSTALL epel-release" >> "$LOG_FILE" 2>&1 || warn "EPEL 仓库安装失败"
        fi
        eval "$PKG_INSTALL fail2ban" >> "$LOG_FILE" 2>&1 || error "fail2ban 安装失败"
        ;;
      *)
        warn "无法自动安装 fail2ban，请手动安装后继续"
        return 1
        ;;
    esac
  else
    log "fail2ban 已安装"
  fi

  # 配置 fail2ban
  mkdir -p /etc/fail2ban
  
  if [ -f /etc/fail2ban/jail.local ]; then
    mv /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak.$(date +%Y%m%d%H%M%S)
  fi

  cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sender = fail2ban@localhost
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = ${LOG_PATH}
maxretry = 3
findtime = 300
bantime = 3600

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
findtime = 300
bantime = 3600

[nginx-botsearch]
enabled = true
filter = nginx-botsearch
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2
findtime = 300
bantime = 3600
EOF

  # 启动 fail2ban
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable fail2ban >> "$LOG_FILE" 2>&1 || warn "启用 fail2ban 失败"
    systemctl restart fail2ban >> "$LOG_FILE" 2>&1 || warn "启动 fail2ban 失败"
  elif command -v service >/dev/null 2>&1; then
    chkconfig fail2ban on 2>/dev/null || service fail2ban enable 2>/dev/null || warn "启用 fail2ban 失败"
    service fail2ban restart >> "$LOG_FILE" 2>&1 || warn "启动 fail2ban 失败"
  fi

  log "fail2ban 安装和配置完成"
  
  # 配置 SSH（可选，需要用户确认）
  if [ -f /etc/ssh/sshd_config ]; then
    log "检测到 SSH 配置文件，是否要应用安全配置？"
    log "警告: 这可能会禁用密码登录和限制 root 登录"
    read -p "继续配置 SSH？[y/N] " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      # 备份原配置
      cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)
      
      # 修改 SSH 配置
      sed -i 's/#PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config 2>/dev/null || true
      sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config 2>/dev/null || true
      sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config 2>/dev/null || true
      
      # 重启 SSH 服务
      if command -v systemctl >/dev/null 2>&1; then
        systemctl restart sshd >> "$LOG_FILE" 2>&1 || warn "重启 SSH 服务失败"
      elif command -v service >/dev/null 2>&1; then
        service sshd restart >> "$LOG_FILE" 2>&1 || warn "重启 SSH 服务失败"
      fi
      
      log "SSH 安全配置已应用"
    else
      log "跳过 SSH 安全配置"
    fi
  fi

  # 创建使用说明文件
  cat > /usr/local/share/doc/modsecurity/fail2ban-setup.txt << 'EOF'
Fail2ban 安装和配置说明
=====================

1. Fail2ban 配置
---------------
- 配置文件位置: /etc/fail2ban/jail.local
- 日志文件位置: /var/log/fail2ban.log
- 已配置的防护:
  * SSH 登录保护
  * Nginx HTTP 认证保护
  * Nginx 机器人扫描保护

常用命令:
- 查看状态: fail2ban-client status
- 查看特定 jail 状态: fail2ban-client status sshd
- 解封 IP: fail2ban-client set sshd unbanip <IP地址>
- 封禁 IP: fail2ban-client set sshd banip <IP地址>
- 查看日志: tail -f /var/log/fail2ban.log

2. SSH 安全配置
--------------
- 配置文件位置: /etc/ssh/sshd_config
- 备份文件位置: /etc/ssh/sshd_config.bak.*

3. 系统兼容性
------------
支持的系统:
- Debian/Ubuntu
- CentOS/RHEL/Fedora
- Rocky Linux/AlmaLinux

4. 故障排除
----------
如果遇到 SSH 登录问题:
1. 检查 fail2ban 状态: systemctl status fail2ban
2. 检查 SSH 服务状态: systemctl status sshd
3. 查看系统日志: journalctl -xe
4. 检查 fail2ban 日志: tail -f /var/log/fail2ban.log

5. 紧急恢复
---------
如果需要恢复 SSH 配置:
1. 使用备份文件: cp /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config
2. 重启 SSH 服务: systemctl restart sshd

如果需要解封被误封的 IP:
1. fail2ban-client set sshd unbanip <IP地址>
2. 如果 fail2ban 服务异常，可以临时停止: systemctl stop fail2ban
EOF

  chmod 644 /usr/local/share/doc/modsecurity/fail2ban-setup.txt

  log "fail2ban 配置完成"
  log "详细使用说明已保存到: /usr/local/share/doc/modsecurity/fail2ban-setup.txt"
  log "请仔细阅读使用说明，特别是故障排除和紧急恢复部分"
}

