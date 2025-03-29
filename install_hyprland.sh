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
    
    # 先安装基本驱动，避免无显示问题
    pacman -S --noconfirm mesa xf86-video-vesa

    # 检测显卡类型
    if lspci | grep -i "NVIDIA" &>/dev/null; then
        log "NVIDIA GPU detected, installing drivers..."
        
        # 提示用户选择驱动
        echo "NVIDIA GPU detected. Please select driver type:"
        echo "1) Proprietary NVIDIA drivers (best performance, may cause issues with Wayland)"
        echo "2) Open source Nouveau drivers (better compatibility, lower performance)"
        echo "3) Skip NVIDIA specific drivers (use generic drivers)"
        read -p "Enter your choice [1-3]: " nvidia_choice
        
        case "$nvidia_choice" in
            1)
                log "Installing proprietary NVIDIA drivers..."
                pacman -S --noconfirm nvidia nvidia-utils libva libva-nvidia-driver
                
                # 创建特殊的Hyprland配置，启用NVIDIA支持
                mkdir -p /etc/skel/.config/hypr
                cat > /etc/skel/.config/hypr/nvidia.conf <<EOF
# Nvidia特别配置，包含在hyprland.conf
env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = WLR_NO_HARDWARE_CURSORS,1
env = WLR_RENDERER,vulkan
EOF
                ;;
            2)
                log "Installing open source Nouveau drivers..."
                pacman -S --noconfirm xf86-video-nouveau mesa lib32-mesa
                ;;
            3)
                log "Skipping NVIDIA specific drivers..."
                ;;
        esac
    elif lspci | grep -i "AMD" &>/dev/null; then
        log "AMD GPU detected, installing drivers..."
        pacman -S --noconfirm mesa lib32-mesa xf86-video-amdgpu vulkan-radeon libva-mesa-driver
    elif lspci | grep -i "Intel" &>/dev/null; then
        log "Intel GPU detected, installing drivers..."
        pacman -S --noconfirm mesa lib32-mesa vulkan-intel intel-media-driver
    else
        log "No specific GPU detected, installing generic drivers..."
        pacman -S --noconfirm mesa xf86-video-fbdev
    fi
    
    # 安装硬件视频加速支持
    pacman -S --noconfirm libva-utils vulkan-tools
    
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

# 如果有NVIDIA特殊配置，引入它
source = ~/.config/hypr/nvidia.conf

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
    blur {
        enabled = true
        size = 3
        passes = 1
    }
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
    
    # 先安装基本的X11会话以备回退
    log "Installing fallback X11 session..."
    pacman -S --noconfirm xorg xorg-xinit i3 lightdm lightdm-gtk-greeter
    
    # 创建i3回退会话
    mkdir -p /usr/share/xsessions
    cat > /usr/share/xsessions/i3-fallback.desktop <<EOF
[Desktop Entry]
Name=i3 (Fallback)
Comment=Fallback window manager if Hyprland fails
Exec=/usr/bin/i3
Type=Application
EOF
    
    # 安装SDDM
    pacman -S --noconfirm sddm qt5-graphicaleffects qt5-quickcontrols2 || error "SDDM installation failed"
    
    # 创建SDDM配置目录
    mkdir -p /etc/sddm.conf.d
    
    # 创建SDDM配置文件，包含安全模式和传统X11回退
    cat > /etc/sddm.conf.d/00-general.conf <<EOF
[General]
# 使用X11以提高兼容性
DisplayServer=x11
# 添加调试输出，如果启动失败，这会显示错误信息
Debug=true
# 确保即使Wayland失败也能显示登录界面
GreeterEnvironment=QT_QPA_PLATFORM=xcb
EOF

    # 启用SDDM和LightDM服务，如果SDDM失败可回退到LightDM
    systemctl enable sddm.service
    
    # 创建回退方案 - 创建systemd单元，如果sddm失败则启动lightdm
    cat > /etc/systemd/system/display-manager-fallback.service <<EOF
[Unit]
Description=Display Manager Fallback
After=sddm.service
BindsTo=sddm.service
ConditionPathExists=!/run/sddm.pid

[Service]
Type=idle
ExecStart=/usr/bin/systemctl start lightdm.service

[Install]
WantedBy=graphical.target
EOF

    systemctl enable display-manager-fallback.service
    
    # 创建恢复脚本，让用户能从黑屏中恢复
    cat > /etc/skel/.local/bin/fix-display <<EOF
#!/bin/bash
echo "Display recovery tool"
echo "====================="
echo "1) Switch to LightDM (if SDDM is failing)"
echo "2) Force start X11 session"
echo "3) Reset graphics configuration"
echo "4) Generate debug information"

read -p "Enter choice [1-4]: " choice

case \$choice in
    1)
        sudo systemctl disable sddm
        sudo systemctl enable lightdm
        sudo systemctl restart lightdm
        ;;
    2)
        startx /usr/bin/i3
        ;;
    3)
        rm -rf ~/.config/hypr
        cp -r /etc/skel/.config/hypr ~/.config/
        echo "Graphics configuration reset to defaults"
        ;;
    4)
        echo "Generating debug information..."
        journalctl -b -p err > ~/display-errors.log
        dmesg > ~/dmesg.log
        echo "Logs saved to ~/display-errors.log and ~/dmesg.log"
        ;;
esac
EOF
    chmod +x /etc/skel/.local/bin/fix-display
    
    log "Login manager configuration completed with fallback options"
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

# 启动前检查显卡类型并设置额外变量
if lspci | grep -i "NVIDIA" &>/dev/null; then
    export LIBVA_DRIVER_NAME=nvidia
    export GBM_BACKEND=nvidia-drm
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export WLR_NO_HARDWARE_CURSORS=1
fi

# 添加错误处理
if ! command -v Hyprland &>/dev/null; then
    echo "ERROR: Hyprland not found! Falling back to i3..."
    exec i3
fi

# 尝试启动Hyprland，如果失败则启动回退会话
if ! Hyprland; then
    echo "Hyprland failed to start. Falling back to i3..."
    exec i3
fi
EOF
    
    chmod +x /etc/skel/.local/bin/start-hypr
    
    # 创建一个可以在TTY使用的恢复模式脚本
    cat > /etc/skel/.local/bin/recovery-mode <<EOF
#!/bin/bash
echo "Hyprland Recovery Mode"
echo "======================"
echo "This script will help you recover from black screen or boot issues."
echo ""
echo "1) Start minimal X session (i3)"
echo "2) Reinstall video drivers"
echo "3) Reset Hyprland configuration"
echo "4) Reset display manager to LightDM"
echo "5) Show system logs"
echo "0) Exit"

read -p "Enter your choice: " choice

case \$choice in
    1)
        echo "Starting minimal X session..."
        startx /usr/bin/i3
        ;;
    2)
        echo "Choose GPU type to reinstall drivers:"
        echo "a) NVIDIA"
        echo "b) AMD"
        echo "c) Intel"
        echo "d) Generic/Fallback"
        read -p "GPU type [a-d]: " gpu
        
        sudo pacman -Syy
        
        case \$gpu in
            a) sudo pacman -S --noconfirm mesa xf86-video-vesa nvidia-open nvidia-utils ;;
            b) sudo pacman -S --noconfirm mesa xf86-video-amdgpu ;;
            c) sudo pacman -S --noconfirm mesa xf86-video-intel ;;
            *) sudo pacman -S --noconfirm mesa xf86-video-vesa ;;
        esac
        echo "Drivers reinstalled. Please reboot."
        ;;
    3)
        rm -rf ~/.config/hypr
        mkdir -p ~/.config/hypr
        cp /etc/skel/.config/hypr/* ~/.config/hypr/
        echo "Hyprland configuration has been reset to defaults."
        ;;
    4)
        sudo systemctl disable sddm
        sudo systemctl enable lightdm
        echo "Display manager set to LightDM. Please reboot."
        ;;
    5)
        echo "Last boot errors:"
        journalctl -b -1 -p err
        echo ""
        echo "Press Enter to continue..."
        read
        ;;
    0)
        exit 0
        ;;
    *)
        echo "Invalid option."
        ;;
esac
EOF
    chmod +x /etc/skel/.local/bin/recovery-mode
    
    log "User configuration scripts created with recovery options"
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
    
    # 创建一个更全面的检查脚本，帮助诊断可能的问题
    cat > /etc/skel/.local/bin/hyprland-troubleshoot <<EOF
#!/bin/bash
echo "Hyprland Troubleshooting Tool"
echo "=============================="

# 收集系统信息
echo "System information:"
echo "-------------------"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo "CPU: $(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^[ \t]*//')"

echo "Checking if Hyprland is installed..."
if command -v Hyprland &>/dev/null; then
  echo "[OK] Hyprland is installed ($(which Hyprland))"
else
  echo "[ERROR] Hyprland is not installed"
fi

echo "Checking GPU information..."
echo "--------------------------"
lspci -k | grep -A 2 -E "(VGA|3D|Display)"

echo "Checking if any GPU drivers are loaded..."
lsmod | grep -E 'nvidia|amdgpu|i915|nouveau|radeon'

echo "Checking Wayland sessions..."
ls -la /usr/share/wayland-sessions/

echo "Checking X11 sessions (fallback)..."
ls -la /usr/share/xsessions/

echo "Checking display manager status..."
systemctl status sddm lightdm gdm | grep "Active:"

echo "Checking XDG portal status..."
systemctl --user status xdg-desktop-portal xdg-desktop-portal-hyprland 2>/dev/null || echo "XDG portal services not running"

echo "Checking environment variables..."
env | grep -E 'WAYLAND|XDG|QT|WLR|DISPLAY'

echo "Boot errors (last boot):"
journalctl -b -1 -p err | tail -20

echo ""
echo "If screen is black after login:"
echo "1. Press Ctrl+Alt+F2 to switch to TTY2"
echo "2. Login with your username and password"
echo "3. Run recovery-mode to fix the issue"
echo "4. Or try running: startx /usr/bin/i3"
EOF
    chmod +x /etc/skel/.local/bin/hyprland-troubleshoot
    
    # 为现有用户也创建恢复脚本
    for userdir in /home/*; do
        if [ -d "$userdir" ]; then
            username=$(basename "$userdir")
            if id "$username" &>/dev/null; then
                mkdir -p "$userdir/.local/bin"
                cp /etc/skel/.local/bin/recovery-mode "$userdir/.local/bin/"
                cp /etc/skel/.local/bin/fix-display "$userdir/.local/bin/"
                cp /etc/skel/.local/bin/hyprland-troubleshoot "$userdir/.local/bin/"
                chown -R "$username:$username" "$userdir/.local"
                chmod +x "$userdir/.local/bin/"*
            fi
        fi
    done
    
    log "Hyprland installation completed!"
    log "IMPORTANT: If you encounter a black screen or just a cursor after login:"
    log "1. Press Ctrl+Alt+F2 to switch to TTY"
    log "2. Login with your username and password"
    log "3. Run 'recovery-mode' and choose an option to fix the issue"
    log ""
    log "After reboot, select 'Hyprland' from the session menu in SDDM"
    log "If you can't see SDDM, the system will automatically try LightDM instead"
    log "For existing users, recovery tools are installed in ~/.local/bin/"
    
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