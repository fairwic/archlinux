#!/bin/bash
# Arch Linux 系统备份恢复脚本 (使用 Timeshift)
# 此脚本用于设置和管理 Arch Linux 的系统备份与恢复

set -euo pipefail

# 彩色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 日志函数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[错误] $1${NC}" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[警告] $1${NC}"
}

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "请使用 root 权限运行此脚本，例如: sudo $0"
    fi
}

# 安装 Timeshift
install_timeshift() {
    log "正在安装 Timeshift..."
    
    # 检查是否已安装 yay
    if ! command -v yay &> /dev/null; then
        log "正在安装 AUR 助手 yay..."
        # 安装构建工具
        pacman -S --needed --noconfirm base-devel git
        
        # 创建临时目录并克隆 yay
        temp_dir=$(mktemp -d)
        git clone https://aur.archlinux.org/yay.git "$temp_dir/yay"
        cd "$temp_dir/yay"
        makepkg -si --noconfirm
        cd - > /dev/null
        rm -rf "$temp_dir"
        
        if ! command -v yay &> /dev/null; then
            error "yay 安装失败，请手动安装后重试"
        fi
    fi
    
    # 使用 yay 安装 timeshift
    sudo -u nobody yay -S --noconfirm timeshift || error "Timeshift 安装失败"
    
    log "Timeshift 安装完成"
}

# 配置 Timeshift 的 RSYNC 模式
configure_timeshift_rsync() {
    log "正在配置 Timeshift RSYNC 模式..."
    
    # 创建配置目录
    mkdir -p /etc/timeshift
    
    # 设置基本配置
    cat > /etc/timeshift/timeshift.json <<EOF
{
  "backup_device_uuid" : "",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "false",
  "include_btrfs_home" : "false",
  "include_app_data" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "true",
  "schedule_weekly" : "true",
  "schedule_daily" : "true",
  "schedule_hourly" : "false",
  "schedule_boot" : "false",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "5",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "exclude" : [
    "/home/**",
    "/opt/**",
    "/var/cache/**",
    "/var/log/**",
    "/var/tmp/**",
    "/tmp/**",
    "/root/**",
    "/lost+found",
    "/media/**",
    "/mnt/**",
    "/proc/**",
    "/sys/**",
    "/dev/**",
    "/run/**"
  ],
  "exclude-apps" : []
}
EOF
    
    # 获取根分区的 UUID 并设置为备份分区
    ROOT_UUID=$(findmnt -no UUID /)
    sed -i "s/\"backup_device_uuid\" : \"\"/\"backup_device_uuid\" : \"$ROOT_UUID\"/" /etc/timeshift/timeshift.json
    sed -i "s/\"parent_device_uuid\" : \"\"/\"parent_device_uuid\" : \"$ROOT_UUID\"/" /etc/timeshift/timeshift.json
    
    log "Timeshift RSYNC 模式配置完成"
}

# 配置 Timeshift 的 BTRFS 模式
configure_timeshift_btrfs() {
    log "正在检查是否可以使用 BTRFS 模式..."
    
    # 检查根文件系统是否为 BTRFS
    if [ "$(findmnt -no FSTYPE /)" = "btrfs" ]; then
        log "检测到 BTRFS 文件系统，配置 Timeshift BTRFS 模式..."
        
        # 创建配置目录
        mkdir -p /etc/timeshift
        
        # 设置基本配置
        cat > /etc/timeshift/timeshift.json <<EOF
{
  "backup_device_uuid" : "",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "true",
  "include_btrfs_home" : "false",
  "include_app_data" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "true",
  "schedule_weekly" : "true",
  "schedule_daily" : "true",
  "schedule_hourly" : "false",
  "schedule_boot" : "false",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "5",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "exclude" : [],
  "exclude-apps" : []
}
EOF
        
        # 获取根分区的 UUID 并设置为备份分区
        ROOT_UUID=$(findmnt -no UUID /)
        sed -i "s/\"backup_device_uuid\" : \"\"/\"backup_device_uuid\" : \"$ROOT_UUID\"/" /etc/timeshift/timeshift.json
        sed -i "s/\"parent_device_uuid\" : \"\"/\"parent_device_uuid\" : \"$ROOT_UUID\"/" /etc/timeshift/timeshift.json
        
        log "Timeshift BTRFS 模式配置完成"
        return 0
    else
        log "未检测到 BTRFS 文件系统，将使用 RSYNC 模式"
        return 1
    fi
}

# 创建备份
create_backup() {
    log "正在创建系统备份..."
    
    # 创建标签名
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    COMMENT="自动备份_$TIMESTAMP"
    
    # 使用 timeshift 创建快照
    if ! timeshift --create --comments "$COMMENT" --verbose; then
        error "创建备份失败"
    fi
    
    log "系统备份创建完成，标签: $COMMENT"
}

# 列出可用备份
list_backups() {
    log "可用的系统备份:"
    
    # 列出所有快照
    timeshift --list
    
    echo ""
    log "使用 '恢复备份' 选项并输入快照名称以恢复系统"
}

# 恢复备份
restore_backup() {
    log "请从以下备份中选择要恢复的快照:"
    
    # 获取可用的快照列表
    SNAPSHOTS=$(timeshift --list | grep "^[0-9]" | awk '{print $3}')
    
    if [ -z "$SNAPSHOTS" ]; then
        error "没有找到可用的备份快照"
    fi
    
    # 显示可用的快照
    echo "$SNAPSHOTS" | nl
    
    # 读取用户选择
    read -p "请输入要恢复的快照编号: " choice
    
    # 获取所选快照的名称
    SELECTED_SNAPSHOT=$(echo "$SNAPSHOTS" | sed -n "${choice}p")
    
    if [ -z "$SELECTED_SNAPSHOT" ]; then
        error "无效的选择"
    fi
    
    log "您选择了恢复快照: $SELECTED_SNAPSHOT"
    read -p "确定要恢复此快照吗？这将覆盖当前系统。(y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log "正在恢复系统到快照: $SELECTED_SNAPSHOT"
        log "警告: 系统将在恢复后自动重启..."
        
        # 确认是否需要立即重启
        read -p "准备好后按回车继续..." nothing
        
        # 执行恢复
        if ! timeshift --restore --snapshot "$SELECTED_SNAPSHOT" --verbose --yes; then
            error "系统恢复失败"
        fi
    else
        log "已取消恢复操作"
    fi
}

# 设置定时备份
setup_scheduled_backups() {
    log "正在设置定时备份..."
    
    # 启用并启动 timeshift-autosnap 服务
    systemctl enable cronie.service
    systemctl start cronie.service
    
    # 创建每日备份的 cron 任务
    echo "0 4 * * * /usr/bin/timeshift --create --comments \"每日自动备份\" --skip-grub > /dev/null 2>&1" > /tmp/timeshift-cron
    crontab /tmp/timeshift-cron
    rm /tmp/timeshift-cron
    
    log "已设置每天凌晨 4 点执行自动备份"
    log "系统最多保留: 2个月度备份, 3个周度备份, 5个每日备份"
}

# 设置 Timeshift 开机启动时自动创建快照
setup_boot_snapshot() {
    log "正在设置开机自动备份..."
    
    # 修改 Timeshift 配置
    sed -i 's/"schedule_boot" : "false"/"schedule_boot" : "true"/' /etc/timeshift/timeshift.json
    
    log "已启用开机自动创建快照功能"
}

# 清理旧备份
cleanup_old_backups() {
    log "正在清理旧备份..."
    
    # 使用 timeshift 的自动清理功能
    if ! timeshift --delete-all; then
        warn "清理旧备份时出现问题，可能没有过期的备份需要清理"
    fi
    
    log "旧备份清理完成"
}

# 主函数
main() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Arch Linux 系统备份与恢复工具      ${NC}"
    echo -e "${BLUE}    (基于 Timeshift)                   ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 检查权限
    check_root
    
    # 主菜单
    while true; do
        echo ""
        echo "请选择操作:"
        echo "1) 安装并配置 Timeshift"
        echo "2) 创建系统备份"
        echo "3) 列出可用备份"
        echo "4) 恢复系统备份"
        echo "5) 设置定时自动备份"
        echo "6) 清理旧备份"
        echo "0) 退出"
        
        read -p "请输入选项 [0-6]: " choice
        
        case "$choice" in
            1)
                install_timeshift
                if ! configure_timeshift_btrfs; then
                    configure_timeshift_rsync
                fi
                ;;
            2)
                create_backup
                ;;
            3)
                list_backups
                ;;
            4)
                restore_backup
                ;;
            5)
                setup_scheduled_backups
                setup_boot_snapshot
                ;;
            6)
                cleanup_old_backups
                ;;
            0)
                log "退出程序"
                exit 0
                ;;
            *)
                warn "无效选项: $choice"
                ;;
        esac
    done
}

# 运行主函数
main 