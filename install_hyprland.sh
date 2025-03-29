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
    echo -e "${RED}[ERROR] $1${NC}" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "Please run this script with root privileges, e.g.: sudo $0"
    fi
}

# 更新系统
update_system() {
    log "Updating system..."
    pacman -Syu --noconfirm || error "System update failed"
    log "System update completed"
}

# 安装基础依赖
install_dependencies() {
    log "Installing base dependencies..."
    pacman -S --noconfirm \
        wayland \
        xorg-xwayland \
        qt5-wayland \
        qt6-wayland \
        pipewire \
        pipewire-pulse \
        wireplumber \
        polkit-kde-agent \
        xdg-desktop-portal-hyprland \
        xdg-desktop-portal \
        xdg-desktop-portal-wlr \
        || error "Failed to install dependencies"
    log "Base dependencies installation completed"
}

# 安装显卡驱动
install_gpu_drivers() {
    log "Detecting and installing GPU drivers..."
    
    # 检测显卡类型
    if lspci | grep -i "NVIDIA" &>/dev/null; then
        log "NVIDIA GPU detected, installing drivers..."
        pacman -S --noconfirm nvidia nvidia-utils libva libva-nvidia-driver
    elif lspci | grep -i "AMD" &>/dev/null; then
        log "AMD GPU detected, installing drivers..."
        pacman -S --noconfirm mesa lib32-mesa xf86-video-amdgpu libva-mesa-driver
    elif lspci | grep -i "Intel" &>/dev/null; then
        log "Intel GPU detected, installing drivers..."
        pacman -S --noconfirm mesa lib32-mesa vulkan-intel intel-media-driver
    else
        log "No specific GPU detected, installing generic drivers..."
        pacman -S --noconfirm mesa
    fi
    
    # 安装硬件视频加速支持
    pacman -S --noconfirm libva-utils
    
    log "GPU drivers installation completed"
}

# 安装Hyprland
install_hyprland() {
    log "Installing Hyprland window manager..."
    pacman -S --noconfirm hyprland || error "Hyprland installation failed"
    log "Hyprland installation completed"
}

# 安装配套应用程序
install_apps() {
    log "Installing companion applications..."
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
        || error "Companion applications installation failed"
    log "Companion applications installation completed"
}

# 创建基础配置
create_configs() {
    log "Creating base configuration..."
    
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

    log "Base configuration files created"
}

# 创建桌面入口文件
create_desktop_entry() {
    log "Creating Hyprland desktop entry file..."
    
    # 创建目录
    mkdir -p /usr/share/wayland-sessions
    
    # 创建桌面入口文件
    cat > /usr/share/wayland-sessions/hyprland.desktop <<EOF
[Desktop Entry]
Name=Hyprland
Comment=A dynamic tiling Wayland compositor
Exec=/usr/bin/Hyprland
Type=Application
EOF
    
    log "Desktop entry file created"
}

# 配置登录管理器
setup_login() {
    log "Configuring login manager..."
    
    # 安装SDDM
    pacman -S --noconfirm sddm qt5-graphicaleffects qt5-quickcontrols2 || error "SDDM installation failed"
    
    # 创建SDDM配置目录
    mkdir -p /etc/sddm.conf.d
    
    # 创建SDDM配置文件
    cat > /etc/sddm.conf.d/10-wayland.conf <<EOF
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
EnableHiDPI=true
SessionDir=/usr/share/wayland-sessions
EOF

    # 启用SDDM服务
    systemctl enable sddm.service
    
    log "Login manager configuration completed"
}

# 创建用户脚本
create_user_script() {
    log "Creating user configuration scripts..."
    
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
    
    log "User configuration scripts created"
}

# 主函数
main() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Arch Linux Hyprland Installer       ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 检查权限
    check_root
    
    # 开始安装
    update_system
    install_dependencies
    install_gpu_drivers
    install_hyprland
    install_apps
    create_configs
    create_desktop_entry
    setup_login
    create_user_script
    
    # 创建一个检查脚本，帮助诊断可能的问题
    cat > /etc/skel/.local/bin/hyprland-troubleshoot <<EOF
#!/bin/bash
echo "Hyprland Troubleshooting Tool"
echo "=============================="
echo "Checking if Hyprland is installed..."
if command -v Hyprland &>/dev/null; then
  echo "[OK] Hyprland is installed"
else
  echo "[ERROR] Hyprland is not installed"
fi

echo "Checking GPU drivers..."
lspci -k | grep -A 2 -E "(VGA|3D)"

echo "Checking Wayland sessions..."
ls -la /usr/share/wayland-sessions/

echo "Checking XDG portal status..."
systemctl --user status xdg-desktop-portal xdg-desktop-portal-hyprland --no-pager

echo "Checking environment variables..."
env | grep -E 'WAYLAND|XDG|QT|WLR'

echo "You can run 'Hyprland' in a TTY to see if there are any error messages"
EOF
    chmod +x /etc/skel/.local/bin/hyprland-troubleshoot
    
    log "Hyprland installation completed!"
    log "After reboot, use SDDM to log into Hyprland session"
    log "If you're installing for new users, configuration files will be automatically copied to new user directories"
    log "If you need to install for existing users, please copy the configuration files:"
    log "sudo cp -r /etc/skel/.config/hypr ~/.config/"
    log "sudo cp -r /etc/skel/.local/bin ~/.local/"
    log "If you encounter issues, run the troubleshooting script: ~/.local/bin/hyprland-troubleshoot"
    
    # 询问是否重启
    read -p "Would you like to reboot now? (y/n) " reboot_now
    if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
        log "System will reboot in 5 seconds..."
        sleep 5
        reboot
    fi
}

# 执行主函数
main 