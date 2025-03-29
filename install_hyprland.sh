#!/bin/bash
# Arch Linux Hyprland安装脚本
# 用于安装和配置Hyprland窗口管理器及其相关组件

set -e

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

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "请使用root权限运行此脚本，例如: sudo $0"
    fi
}

# 更新系统
update_system() {
    log "正在更新系统..."
    pacman -Syu --noconfirm || error "系统更新失败"
    log "系统更新完成"
}

# 安装基础依赖
install_dependencies() {
    log "正在安装基础依赖..."
    pacman -S --noconfirm \
        wayland \
        xorg-xwayland \
        qt5-wayland \
        qt6-wayland \
        pipewire \
        pipewire-pulse \
        wireplumber \
        polkit-kde-agent \
        || error "安装依赖失败"
    log "基础依赖安装完成"
}

# 安装Hyprland
install_hyprland() {
    log "正在安装Hyprland窗口管理器..."
    pacman -S --noconfirm hyprland || error "Hyprland安装失败"
    log "Hyprland安装完成"
}

# 安装配套应用程序
install_apps() {
    log "正在安装配套应用程序..."
    pacman -S --noconfirm \
        kitty \
        wofi \
        waybar \
        grim \
        slurp \
        mako \
        thunar \
        swaylock \
        swayidle \
        wl-clipboard \
        || error "配套应用程序安装失败"
    log "配套应用程序安装完成"
}

# 创建基础配置
create_configs() {
    log "正在创建基础配置..."
    
    # 创建配置目录
    mkdir -p /etc/skel/.config/hypr
    
    # 创建Hyprland配置文件
    cat > /etc/skel/.config/hypr/hyprland.conf <<EOF
# Hyprland基础配置文件

# 显示器配置
monitor=,preferred,auto,1

# 自动启动
exec-once = waybar
exec-once = mako
exec-once = /usr/lib/polkit-kde-authentication-agent-1

# 输入设置
input {
    kb_layout = us
    follow_mouse = 1
    sensitivity = 0
}

# 界面美化
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee)
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

# 窗口装饰
decoration {
    rounding = 10
    blur = yes
    blur_size = 3
    blur_passes = 1
    drop_shadow = yes
    shadow_range = 4
    shadow_render_power = 3
}

# 动画
animations {
    enabled = yes
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

# 窗口规则
dwindle {
    pseudotile = yes
    preserve_split = yes
}

# 按键绑定
$mainMod = SUPER

bind = $mainMod, Return, exec, kitty
bind = $mainMod, Q, killactive, 
bind = $mainMod, M, exit, 
bind = $mainMod, E, exec, thunar
bind = $mainMod, V, togglefloating, 
bind = $mainMod, D, exec, wofi --show drun
bind = $mainMod, P, pseudo,
bind = $mainMod, J, togglesplit,

# 移动焦点
bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

# 切换工作区
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

# 移动窗口到工作区
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9
bind = $mainMod SHIFT, 0, movetoworkspace, 10

# 截图
bind = $mainMod, S, exec, grim -g "$(slurp)" - | wl-copy
EOF

    log "已创建基础配置文件"
}

# 配置登录管理器
setup_login() {
    log "正在配置登录管理器..."
    
    # 安装SDDM
    pacman -S --noconfirm sddm || error "SDDM安装失败"
    
    # 启用SDDM服务
    systemctl enable sddm.service
    
    log "登录管理器配置完成"
}

# 创建用户脚本
create_user_script() {
    log "正在创建用户配置脚本..."
    
    mkdir -p /etc/skel/.local/bin
    
    # 创建Hyprland会话启动脚本
    cat > /etc/skel/.local/bin/start-hypr <<EOF
#!/bin/bash

# 环境变量设置
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=Hyprland
export QT_QPA_PLATFORM=wayland
export QT_QPA_PLATFORMTHEME=qt5ct
export MOZ_ENABLE_WAYLAND=1

exec Hyprland
EOF
    
    chmod +x /etc/skel/.local/bin/start-hypr
    
    log "用户配置脚本创建完成"
}

# 主函数
main() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Arch Linux Hyprland 安装脚本        ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 检查权限
    check_root
    
    # 开始安装
    update_system
    install_dependencies
    install_hyprland
    install_apps
    create_configs
    setup_login
    create_user_script
    
    log "Hyprland安装完成！"
    log "重启后使用SDDM登录到Hyprland会话"
    log "如果你正在为新用户安装，配置文件将自动复制到新用户目录"
    log "如果你需要为现有用户安装，请复制配置文件："
    log "sudo cp -r /etc/skel/.config/hypr ~/.config/"
    log "sudo cp -r /etc/skel/.local/bin ~/.local/"
    
    # 询问是否重启
    read -p "是否立即重启系统？(y/n) " reboot_now
    if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
        log "系统将在 5 秒后重启..."
        sleep 5
        reboot
    fi
}

# 执行主函数
main 