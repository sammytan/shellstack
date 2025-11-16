#!/bin/bash

# =====================================================================
# 终端颜色和别名配置（默认安装）
# =====================================================================

# 设置终端颜色和别名
setup_terminal() {
  log "设置终端颜色和别名..."

  # 设置 root 用户的配置
  for shell_config in /root/.bashrc /root/.zshrc; do
    if [ -f "$shell_config" ]; then
      cp "$shell_config" "${shell_config}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
      
      if [[ "$shell_config" == *".bashrc" ]]; then
        cat >> "$shell_config" << 'EOF'

# ===== 终端颜色设置 (Mocano风格) =====
# 颜色定义
export TERM=xterm-256color
export CLICOLOR=1
export LSCOLORS=ExGxBxDxCxEgEdxbxgxcxd

# 提示符颜色
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# 目录颜色
export LS_COLORS='di=1;34:ln=1;36:so=1;32:pi=1;33:ex=1;31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'

# 常用别名
alias ll='ls -l --color=auto'
alias la='ls -la --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# 设置 less 的颜色
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

# 设置 man 页面的颜色
export MANPAGER="less -R --use-color -Dd+r -Du+b"
EOF
      elif [[ "$shell_config" == *".zshrc" ]]; then
        cat >> "$shell_config" << 'EOF'

# ===== 终端颜色设置 (Mocano风格) =====
# 颜色定义
export TERM=xterm-256color
export CLICOLOR=1
export LSCOLORS=ExGxBxDxCxEgEdxbxgxcxd

# 提示符颜色
PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '

# 目录颜色
export LS_COLORS='di=1;34:ln=1;36:so=1;32:pi=1;33:ex=1;31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'

# 常用别名
alias ll='ls -l --color=auto'
alias la='ls -la --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# 设置 less 的颜色
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

# 设置 man 页面的颜色
export MANPAGER="less -R --use-color -Dd+r -Du+b"
EOF
      fi
    fi
  done

  # 为当前非 root 用户设置配置
  if [ "$(id -u)" != "0" ]; then
    USER_HOME=$(eval echo ~$(whoami))
    
    for shell_config in "$USER_HOME/.bashrc" "$USER_HOME/.zshrc"; do
      if [ -f "$shell_config" ]; then
        cp "$shell_config" "${shell_config}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        
        if [[ "$shell_config" == *".bashrc" ]]; then
          cat >> "$shell_config" << 'EOF'

# ===== 终端颜色设置 (Mocano风格) =====
# 颜色定义
export TERM=xterm-256color
export CLICOLOR=1
export LSCOLORS=ExGxBxDxCxEgEdxbxgxcxd

# 提示符颜色
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# 目录颜色
export LS_COLORS='di=1;34:ln=1;36:so=1;32:pi=1;33:ex=1;31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'

# 常用别名
alias ll='ls -l --color=auto'
alias la='ls -la --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# 设置 less 的颜色
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

# 设置 man 页面的颜色
export MANPAGER="less -R --use-color -Dd+r -Du+b"
EOF
        elif [[ "$shell_config" == *".zshrc" ]]; then
          cat >> "$shell_config" << 'EOF'

# ===== 终端颜色设置 (Mocano风格) =====
# 颜色定义
export TERM=xterm-256color
export CLICOLOR=1
export LSCOLORS=ExGxBxDxCxEgEdxbxgxcxd

# 提示符颜色
PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '

# 目录颜色
export LS_COLORS='di=1;34:ln=1;36:so=1;32:pi=1;33:ex=1;31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'

# 常用别名
alias ll='ls -l --color=auto'
alias la='ls -la --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# 设置 less 的颜色
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

# 设置 man 页面的颜色
export MANPAGER="less -R --use-color -Dd+r -Du+b"
EOF
        fi
      fi
    done
  fi

  # 创建全局配置文件
  mkdir -p /etc/profile.d
  cat > /etc/profile.d/terminal-colors.sh << 'EOF'
# ===== 终端颜色设置 (Mocano风格) =====
# 颜色定义
export TERM=xterm-256color
export CLICOLOR=1
export LSCOLORS=ExGxBxDxCxEgEdxbxgxcxd

# 目录颜色
export LS_COLORS='di=1;34:ln=1;36:so=1;32:pi=1;33:ex=1;31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'

# 设置 less 的颜色
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

# 设置 man 页面的颜色
export MANPAGER="less -R --use-color -Dd+r -Du+b"
EOF

  chmod +x /etc/profile.d/terminal-colors.sh

  log "终端颜色和别名设置完成"
  log "请重新登录或运行 'source /etc/profile.d/terminal-colors.sh' 使设置生效"
}

