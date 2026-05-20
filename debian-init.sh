#!/usr/bin/env bash

set -euo pipefail

NEW_USER="xy"
SSH_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSH_DROPIN_FILE="${SSH_DROPIN_DIR}/99-user-login-policy.conf"
SSH_MAIN_CONFIG="/etc/ssh/sshd_config"
PROFILE_SCRIPT="/etc/profile.d/99-custom-shell.sh"
VIM_LOCAL_CONFIG="/etc/vim/vimrc.local"
FAIL2BAN_LOCAL="/etc/fail2ban/jail.local"
SYSCTL_FILE="/etc/sysctl.d/99-custom.conf"
JOURNALD_DROPIN_DIR="/etc/systemd/journald.conf.d"
JOURNALD_DROPIN_FILE="${JOURNALD_DROPIN_DIR}/99-custom.conf"
LIMITS_FILE="/etc/security/limits.d/99-custom.conf"
SYSTEMD_SYSTEM_CONF_DIR="/etc/systemd/system.conf.d"
SYSTEMD_SYSTEM_CONF_FILE="${SYSTEMD_SYSTEM_CONF_DIR}/99-limits.conf"
SYSTEMD_USER_CONF_DIR="/etc/systemd/user.conf.d"
SYSTEMD_USER_CONF_FILE="${SYSTEMD_USER_CONF_DIR}/99-limits.conf"
AUTO_UPGRADES_FILE="/etc/apt/apt.conf.d/20auto-upgrades"
TIMEZONE="Asia/Hong_Kong"
SWAP_FILE="/swapfile"
UFW_PORTS=(22 80 443 8443)
COMMON_PACKAGES=(
  sudo
  vim
  curl
  wget
  git
  rsync
  unzip
  zip
  tar
  jq
  lsof
  htop
  tree
  tmux
  screen
  less
  bash-completion
  ca-certificates
  dnsutils
  net-tools
  ufw
  fail2ban
  tzdata
  unattended-upgrades
  logrotate
)

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "请用 root 运行此脚本。"
    exit 1
  fi
}

ensure_debian_like() {
  if [[ ! -r /etc/os-release ]]; then
    echo "无法识别系统版本，缺少 /etc/os-release。"
    exit 1
  fi

  # 这份脚本先按 Debian / Ubuntu 系来写，避免在别的发行版上误操作 ssh 配置。
  if ! grep -Eq '^(ID|ID_LIKE)=.*(debian|ubuntu)' /etc/os-release; then
    echo "当前系统不是 Debian / Ubuntu 系，已停止。"
    exit 1
  fi
}

ensure_common_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y "${COMMON_PACKAGES[@]}"
}

configure_timezone() {
  if [[ ! -e "/usr/share/zoneinfo/${TIMEZONE}" ]]; then
    echo "时区 ${TIMEZONE} 不存在，已停止。"
    exit 1
  fi

  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-timezone "${TIMEZONE}" || true
  fi

  ln -snf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
  printf '%s\n' "${TIMEZONE}" > /etc/timezone
  echo "已设置时区为 ${TIMEZONE}。"
}

ensure_user_exists() {
  if id "${NEW_USER}" >/dev/null 2>&1; then
    echo "用户 ${NEW_USER} 已存在，跳过创建。"
  else
    adduser --gecos "" "${NEW_USER}"
  fi
}

ensure_user_in_sudo_group() {
  usermod -aG sudo "${NEW_USER}"
}

set_sshd_option() {
  local key="$1"
  local value="$2"

  if grep -Eq "^\s*#?\s*${key}\s+" "${SSH_MAIN_CONFIG}"; then
    sed -i "s/^\s*#\?\s*${key}\s\+.*/${key} ${value}/" "${SSH_MAIN_CONFIG}"
  else
    printf '\n%s %s\n' "${key}" "${value}" >> "${SSH_MAIN_CONFIG}"
  fi
}

configure_ssh_login_policy() {
  if [[ -d "${SSH_DROPIN_DIR}" ]]; then
    cat > "${SSH_DROPIN_FILE}" <<'EOF'
AllowUsers xy
PermitEmptyPasswords no
PermitRootLogin no
PasswordAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    echo "已写入 ${SSH_DROPIN_FILE}。"
    return
  fi

  cp "${SSH_MAIN_CONFIG}" "${SSH_MAIN_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
  set_sshd_option "AllowUsers" "${NEW_USER}"
  set_sshd_option "PermitEmptyPasswords" "no"
  set_sshd_option "PermitRootLogin" "no"
  set_sshd_option "PasswordAuthentication" "yes"
  set_sshd_option "MaxAuthTries" "3"
  set_sshd_option "LoginGraceTime" "30"
  set_sshd_option "X11Forwarding" "no"
  set_sshd_option "ClientAliveInterval" "300"
  set_sshd_option "ClientAliveCountMax" "2"

  echo "已更新 ${SSH_MAIN_CONFIG}。"
}

configure_color_prompt() {
  cat > "${PROFILE_SCRIPT}" <<'EOF'
case "$-" in
  *i*) ;;
  *) return ;;
esac

if command -v dircolors >/dev/null 2>&1; then
  eval "$(dircolors -b)"
fi

alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias vi='vim'
alias cls='clear'

if [ -n "${BASH_VERSION:-}" ]; then
  export HISTSIZE=5000
  export HISTFILESIZE=10000
  export HISTCONTROL=ignoreboth:erasedups
  export HISTTIMEFORMAT='%F %T '
  shopt -s histappend 2>/dev/null || true
  PROMPT_COMMAND='history -a; history -c; history -r'
fi

if [ -z "${BASH_VERSION:-}" ]; then
  return
fi

if command -v tput >/dev/null 2>&1; then
  if [ "$(tput colors 2>/dev/null || echo 0)" -lt 8 ]; then
    return
  fi
fi

PS1='\[\e[1;32m\]\u\[\e[0m\]@\[\e[1;32m\]\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\] \[\e[1;31m\]\A\[\e[0m\] \$ '
EOF

  chmod 644 "${PROFILE_SCRIPT}"
  echo "已写入 ${PROFILE_SCRIPT}。"
}

configure_vim() {
  cat > "${VIM_LOCAL_CONFIG}" <<'EOF'
set autoindent
set enc=utf-8
set history=1000
set hlsearch
set incsearch
set iskeyword+=_,$,@,%,#,-
set linebreak
set mouse=c
set number
set ruler
set softtabstop=2
set shiftwidth=2
set showcmd
set showmatch
set showmode
set tabstop=2
set t_Co=256
set paste
syntax on
EOF

  echo "已写入 ${VIM_LOCAL_CONFIG}。"
}

configure_ufw() {
  ufw default deny incoming
  ufw default allow outgoing

  for port in "${UFW_PORTS[@]}"; do
    ufw allow "${port}/tcp"
  done

  ufw limit 22/tcp

  ufw --force enable
  systemctl enable ufw >/dev/null 2>&1 || true
  echo "已配置 UFW 允许端口: ${UFW_PORTS[*]}。"
}

configure_fail2ban() {
  cat > "${FAIL2BAN_LOCAL}" <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
banaction = ufw
backend = systemd

[sshd]
enabled = true
EOF

  systemctl enable fail2ban
  systemctl restart fail2ban
  echo "已写入 ${FAIL2BAN_LOCAL}。"
}

calculate_swap_size_mb() {
  local mem_kb
  local mem_mb

  mem_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
  mem_mb="$(((mem_kb + 1023) / 1024))"

  if (( mem_mb <= 2048 )); then
    printf '%s\n' "${mem_mb}"
  else
    printf '4096\n'
  fi
}

ensure_swap_fstab_entry() {
  if ! grep -qE "^${SWAP_FILE//\//\\/}[[:space:]]+none[[:space:]]+swap[[:space:]]+sw[[:space:]]+0[[:space:]]+0$" /etc/fstab; then
    printf '%s none swap sw 0 0\n' "${SWAP_FILE}" >> /etc/fstab
  fi
}

configure_swap() {
  local swap_size_mb

  if swapon --noheadings --show=NAME | grep -q .; then
    echo "检测到系统已有启用中的 swap，跳过创建。"
    return
  fi

  swap_size_mb="$(calculate_swap_size_mb)"

  if [[ -f "${SWAP_FILE}" ]]; then
    chmod 600 "${SWAP_FILE}"
  else
    if command -v fallocate >/dev/null 2>&1; then
      if ! fallocate -l "${swap_size_mb}M" "${SWAP_FILE}"; then
        dd if=/dev/zero of="${SWAP_FILE}" bs=1M count="${swap_size_mb}" status=progress
      fi
    else
      dd if=/dev/zero of="${SWAP_FILE}" bs=1M count="${swap_size_mb}" status=progress
    fi

    chmod 600 "${SWAP_FILE}"
  fi

  mkswap "${SWAP_FILE}" >/dev/null
  swapon "${SWAP_FILE}"
  ensure_swap_fstab_entry
  echo "已配置 swap，大小 ${swap_size_mb}M。"
}

configure_sysctl() {
  cat > "${SYSCTL_FILE}" <<'EOF'
# 温和型内核参数，适合大多数 Debian 通用服务器
fs.file-max = 1048576
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF

  sysctl --system >/dev/null
  echo "已写入 ${SYSCTL_FILE}。"
}

configure_auto_updates() {
  cat > "${AUTO_UPGRADES_FILE}" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

  systemctl enable unattended-upgrades >/dev/null 2>&1 || true
  systemctl restart unattended-upgrades >/dev/null 2>&1 || true
  echo "已启用 unattended-upgrades。"
}

configure_time_sync() {
  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-ntp true || true
  fi

  if systemctl list-unit-files | grep -q '^systemd-timesyncd\.service'; then
    systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || true
    echo "已启用 systemd-timesyncd。"
    return
  fi

  echo "未发现 systemd-timesyncd，跳过时间同步服务配置。"
}

configure_log_limits() {
  install -d -m 755 "${JOURNALD_DROPIN_DIR}"
  cat > "${JOURNALD_DROPIN_FILE}" <<'EOF'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=50M
MaxRetentionSec=14day
EOF

  systemctl restart systemd-journald
  systemctl enable logrotate.timer >/dev/null 2>&1 || true
  echo "已写入 ${JOURNALD_DROPIN_FILE}。"
}

configure_file_limits() {
  cat > "${LIMITS_FILE}" <<'EOF'
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF

  install -d -m 755 "${SYSTEMD_SYSTEM_CONF_DIR}" "${SYSTEMD_USER_CONF_DIR}"

  cat > "${SYSTEMD_SYSTEM_CONF_FILE}" <<'EOF'
[Manager]
DefaultLimitNOFILE=65535
EOF

  cat > "${SYSTEMD_USER_CONF_FILE}" <<'EOF'
[Manager]
DefaultLimitNOFILE=65535
EOF

  systemctl daemon-reexec >/dev/null 2>&1 || true
  echo "已写入文件句柄限制配置。"
}

reload_sshd() {
  if command -v sshd >/dev/null 2>&1; then
    sshd -t
  else
    echo "未找到 sshd 命令，无法校验 SSH 配置。"
    exit 1
  fi

  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    systemctl restart ssh
    return
  fi

  if systemctl list-unit-files | grep -q '^sshd\.service'; then
    systemctl restart sshd
    return
  fi

  echo "未找到 ssh/sshd systemd 服务，请手动重启 SSH。"
  exit 1
}

print_post_checks() {
  echo
  echo "========== 自检信息 =========="
  echo
  echo "[当前时间]"
  timedatectl 2>/dev/null || date
  echo
  echo "[UFW 状态]"
  ufw status verbose || true
  echo
  echo "[fail2ban 状态]"
  fail2ban-client status 2>/dev/null || true
  echo
  echo "[fail2ban sshd 状态]"
  fail2ban-client status sshd 2>/dev/null || true
  echo
  echo "[swap 状态]"
  swapon --show || true
  echo
  echo "[文件句柄限制]"
  ulimit -n || true
  echo
  echo "[监听端口]"
  ss -tulpn || true
}

main() {
  require_root
  ensure_debian_like
  ensure_common_packages
  ensure_user_exists
  ensure_user_in_sudo_group
  configure_timezone
  configure_ssh_login_policy
  configure_swap
  configure_sysctl
  configure_auto_updates
  configure_time_sync
  configure_log_limits
  configure_file_limits
  configure_color_prompt
  configure_vim
  configure_ufw
  configure_fail2ban
  reload_sshd

  echo
  echo "完成："
  echo "1. 用户 ${NEW_USER} 已创建或已存在"
  echo "2. 用户 ${NEW_USER} 已加入 sudo 组"
  echo "3. 时区已设置为 ${TIMEZONE}"
  echo "4. root SSH 登录已禁用"
  echo "5. SSH 已限制为用户 ${NEW_USER} 登录，并收紧认证参数"
  echo "6. SSH 密码登录已明确启用"
  echo "7. swap 已按规则配置"
  echo "8. sysctl 温和优化已写入"
  echo "9. 自动安全更新和时间同步已启用"
  echo "10. journald 日志占用已限制，logrotate 已确保安装"
  echo "11. 文件句柄限制已提升到 65535"
  echo "12. 彩色终端提示符、alias、历史记录已配置"
  echo "13. Vim 常用配置已写入"
  echo "14. UFW 已启用并放行端口: ${UFW_PORTS[*]}，并对 22 端口做基础限速"
  echo "15. fail2ban 已启用: 10 分钟内失败 3 次封禁 1 小时"
  echo "16. 常用软件已安装: ${COMMON_PACKAGES[*]}"
  echo
  echo "建议你现在新开一个终端，验证 ${NEW_USER} 登录、彩色提示符和 vim 配置是否符合习惯。"

  print_post_checks
}

main "$@"
