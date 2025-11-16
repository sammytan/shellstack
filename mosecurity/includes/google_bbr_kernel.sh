#!/bin/bash

# =====================================================================
# Google BBR 内核优化（默认安装）
# 包括 BBR 支持和内核参数优化
# =====================================================================

# 安装和配置 Google BBR 内核优化
install_google_bbr_kernel() {
  log "开始安装和配置 Google BBR 内核优化..."

  # 创建内核优化文档目录
  mkdir -p /usr/local/share/doc/modsecurity

  # 备份当前内核参数
  log "备份当前内核参数..."
  sysctl -a > /usr/local/share/doc/modsecurity/sysctl.conf.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || warn "备份内核参数失败"

  # 检查是否已经支持 BBR
  if grep -q "tcp_bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    log "当前内核已支持 BBR，无需安装新内核"
  else
    log "检查并安装 BBR 支持的内核..."

    case "$SYSTEM_TYPE" in
      debian)
        eval "$PKG_UPDATE" >> "$LOG_FILE" 2>&1
        CURRENT_KERNEL=$(uname -r)
        log "当前内核版本: $CURRENT_KERNEL"
        
        eval "$PKG_INSTALL linux-image-amd64" >> "$LOG_FILE" 2>&1 || warn "内核安装失败"
        ;;
      redhat)
        if check_command dnf; then
          eval "$PKG_INSTALL kernel-ml" >> "$LOG_FILE" 2>&1 || warn "内核安装失败"
        else
          # 添加 ELRepo 仓库
          log "添加 ELRepo 仓库..."
          rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org 2>/dev/null || warn "导入 GPG 密钥失败"
          
          if [ -f /etc/redhat-release ] && grep -q "release 7" /etc/redhat-release; then
            rpm -Uvh https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm >> "$LOG_FILE" 2>&1 || warn "添加仓库失败"
          elif [ -f /etc/redhat-release ] && grep -q "release 8" /etc/redhat-release; then
            rpm -Uvh https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm >> "$LOG_FILE" 2>&1 || warn "添加仓库失败"
          fi
          
          eval "$PKG_INSTALL kernel-ml" >> "$LOG_FILE" 2>&1 || warn "内核安装失败"
        fi
        ;;
      *)
        warn "不支持的系统类型，跳过内核安装"
        ;;
    esac
  fi

  # 确保 sysctl.d 目录存在
  mkdir -p /etc/sysctl.d

  # 配置内核参数
  log "配置内核参数..."
  cat > /etc/sysctl.d/99-sysctl.conf << 'EOF'
# 网络优化
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# 文件系统优化
fs.file-max = 2097152
fs.nr_open = 2097152
fs.inotify.max_user_watches = 524288

# 内存优化
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2
vm.vfs_cache_pressure = 50

# 系统限制
kernel.pid_max = 65535
kernel.threads-max = 2097152
kernel.sysrq = 1
EOF

  # 应用内核参数
  sysctl -p /etc/sysctl.d/99-sysctl.conf >> "$LOG_FILE" 2>&1 || warn "应用内核参数失败"

  # 设置默认启动内核
  case "$SYSTEM_TYPE" in
    debian)
      if command -v grub-set-default >/dev/null 2>&1; then
        NEW_KERNEL=$(dpkg -l | grep linux-image | grep -v linux-image-extra | awk '{print $2}' | sort -V | tail -n1)
        if [ -n "$NEW_KERNEL" ]; then
          log "设置默认启动内核: $NEW_KERNEL"
          grub-set-default "$NEW_KERNEL" >> "$LOG_FILE" 2>&1 || warn "设置默认内核失败"
          update-grub >> "$LOG_FILE" 2>&1 || warn "更新 grub 失败"
        fi
      fi
      ;;
    redhat)
      if command -v grub2-set-default >/dev/null 2>&1; then
        NEW_KERNEL=$(rpm -q kernel-ml 2>/dev/null | sort -V | tail -n1)
        if [ -n "$NEW_KERNEL" ]; then
          log "设置默认启动内核: $NEW_KERNEL"
          grub2-set-default "$NEW_KERNEL" >> "$LOG_FILE" 2>&1 || warn "设置默认内核失败"
          grub2-mkconfig -o /boot/grub2/grub.cfg >> "$LOG_FILE" 2>&1 || warn "更新 grub 失败"
        fi
      fi
      ;;
  esac

  # 创建使用说明文档
  cat > /usr/local/share/doc/modsecurity/google-bbr-kernel.txt << 'EOF'
Google BBR 内核优化说明
====================

1. 已安装的优化
-------------
- Google BBR 拥塞控制算法
- TCP 优化参数
- 文件系统优化
- 内存管理优化
- 系统限制优化

2. 配置文件位置
-------------
- 内核参数配置: /etc/sysctl.d/99-sysctl.conf
- 原始参数备份: /usr/local/share/doc/modsecurity/sysctl.conf.bak.*

3. 验证 BBR 是否启用
------------------
运行以下命令检查 BBR 是否启用:
sysctl net.ipv4.tcp_congestion_control

如果输出包含 "bbr"，则表示 BBR 已成功启用。

4. 系统兼容性
-----------
支持的系统:
- Debian 10/11/12
- CentOS/RHEL 7/8
- Rocky Linux/AlmaLinux

5. 故障排除
---------
如果遇到网络问题:
1. 检查当前内核参数: sysctl -a
2. 检查 BBR 状态: sysctl net.ipv4.tcp_congestion_control
3. 查看系统日志: journalctl -xe

6. 恢复默认设置
------------
如果需要恢复默认设置:
1. 使用备份文件: cp /usr/local/share/doc/modsecurity/sysctl.conf.bak.* /etc/sysctl.d/99-sysctl.conf
2. 应用更改: sysctl -p /etc/sysctl.d/99-sysctl.conf

7. 注意事项
---------
1. 修改内核参数后需要重启系统才能完全生效
2. 建议在修改前备份重要数据
3. 如果系统出现异常，可以使用备份文件恢复
EOF

  chmod 644 /usr/local/share/doc/modsecurity/google-bbr-kernel.txt

  log "Google BBR 内核优化完成"
  log "详细说明已保存到: /usr/local/share/doc/modsecurity/google-bbr-kernel.txt"
  log "请重启系统以使所有更改生效"
  log "重启后，请运行 'sysctl net.ipv4.tcp_congestion_control' 确认 BBR 已启用"
}

