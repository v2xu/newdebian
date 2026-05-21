# newdebian

这是一个用于 Debian 服务器初始化的本地仓库，当前包含通用初始化脚本：

- `debian-init.sh`

脚本会处理这些基础项：

- 设置主机名并同步 `/etc/hosts`
- 创建你指定的管理用户
- 禁止 `root` 通过 SSH 登录
- 启用 SSH 密码登录
- 安装常用软件
- 配置彩色终端、alias、shell 历史记录
- 写入常用 `vim` 配置
- 配置 `ufw`
- 配置 `fail2ban`
- 设置香港时区
- 创建 `swap`
- 写入温和型 `sysctl`
- 启用自动安全更新
- 配置时间同步
- 限制 `journald` 日志占用
- 提升文件句柄上限
- 输出执行后的自检信息

## 服务器使用方法

### 1. 登录服务器

先用 `root` 登录到 Debian 服务器。

### 2. 下载脚本

推荐直接执行下面这组命令：

```bash
cd /root
apt-get update
apt-get install -y ca-certificates wget
wget https://raw.githubusercontent.com/v2xu/newdebian/main/debian-init.sh
```

这样更适合新机器首装，不依赖预先安装 `git`。

### 3. 执行初始化脚本

```bash
chmod +x debian-init.sh
bash debian-init.sh
```

如果你想一次性带上主机名和管理员用户名，也可以这样执行：

```bash
bash debian-init.sh hk-node-01 adminuser
```

脚本运行过程中会：

- 一开始就先要求输入主机名，或使用你传入的主机名参数
- 一开始就先要求输入管理员用户名，或使用你传入的管理员用户名参数
- 自动同步 `/etc/hostname` 和 `/etc/hosts`
- 创建你指定的管理员用户
- 提示设置该管理员用户的登录密码
- 然后才开始安装软件和配置系统安全项
- 输出自检结果

### 4. 执行完成后验证

建议你不要直接关闭当前 `root` 会话，先新开一个终端窗口测试：

```bash
ssh 你设置的管理员用户名@你的服务器IP
```

登录后再确认：

```bash
sudo -i
ufw status verbose
fail2ban-client status sshd
swapon --show
timedatectl
ss -tulpn
```

确认无误后，再放弃继续使用 `root` 远程登录。

## 注意事项

- 当前脚本默认只允许你创建的管理员用户通过 SSH 登录
- 如果以后还要增加别的运维用户，需要同步修改 SSH 的 `AllowUsers`
- 当前脚本是通用初始化脚本，不包含节点专用的 `BBR` 或 SSPANEL 节点部署逻辑
- 节点相关脚本建议单独维护
