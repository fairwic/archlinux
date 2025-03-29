#!/bin/bash
# Arch Linux Hyprland安装脚本
# 用于安装和配置Hyprland窗口管理器及其相关组件
# 参考JaKooLit/Arch-Hyprland项目改进

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

# 安装必要工具
install_tools() {
    log "Installing essential tools..."
    pacman -S --noconfirm --needed \
        git \
        wget \
        unzip \
        base-devel \
        xdg-utils \
        xdg-user-dirs \
        || error "Failed to install essential tools"
    log "Essential tools installation completed"
}

# 安装基础依赖
install_dependencies() {
    log "Installing base dependencies..."
    pacman -S --noconfirm --needed \
        wayland \
        xorg-xwayland \
        qt5-wayland \
        qt6-wayland \
        qt5-svg \
        qt5-quickcontrols2 \
        qt5-graphicaleffects \
        pipewire \
        pipewire-alsa \
        pipewire-pulse \
        pipewire-jack \
        wireplumber \
        polkit-kde-agent \
        xdg-desktop-portal-hyprland \
        xdg-desktop-portal-gtk \
        xdg-desktop-portal \
        grim \
        slurp \
        || error "Failed to install dependencies"
    
    # 安装最基本的显卡支持，这是必需的
    log "Installing basic graphics support (mesa)..."
    pacman -S --noconfirm --needed mesa xf86-video-vesa || warn "Basic graphics driver installation failed, continuing anyway"
    
    log "Base dependencies installation completed"
}

# 安装显卡驱动（可选）
install_gpu_drivers() {
    echo "Graphics driver installation:"
    echo "1) Install only basic/generic drivers (recommended)"
    echo "2) Detect and install specific GPU drivers"
    echo "3) Skip all graphics drivers (not recommended)"
    read -p "Enter your choice [1-3] (default: 1): " gpu_choice
    
    case "$gpu_choice" in
        2)
            log "Detecting GPU type for driver installation..."
            
            # 检测显卡类型
            if lspci | grep -i "NVIDIA" &>/dev/null; then
                log "NVIDIA GPU detected, installing drivers..."
                
                echo "NVIDIA GPU detected. Please select driver type:"
                echo "1) Proprietary NVIDIA drivers (best performance)"
                echo "2) Open source Nouveau drivers (better compatibility)"
                echo "3) Skip NVIDIA specific drivers (use generic drivers)"
                read -p "Enter your choice [1-3]: " nvidia_choice
                
                case "$nvidia_choice" in
                    1)
                        log "Installing proprietary NVIDIA drivers..."
                        # 安装NVIDIA驱动和必要组件
                        pacman -S --noconfirm --needed \
                            nvidia-dkms \
                            nvidia-utils \
                            lib32-nvidia-utils \
                            libva \
                            libva-nvidia-driver \
                            nvidia-settings
                        
                        # 创建Hyprland的NVIDIA配置
                        mkdir -p /etc/hypr
                        cat > /etc/hypr/nvidia.conf <<EOF
# 为Hyprland创建的NVIDIA配置
env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = WLR_NO_HARDWARE_CURSORS,1
EOF

                        # 创建模块加载配置
                        mkdir -p /etc/modprobe.d
                        cat > /etc/modprobe.d/nvidia.conf <<EOF
options nvidia-drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
                        ;;
                    2)
                        log "Installing open source Nouveau drivers..."
                        pacman -S --noconfirm --needed mesa lib32-mesa xf86-video-nouveau
                        ;;
                    3)
                        log "Skipping NVIDIA specific drivers..."
                        ;;
                esac
            elif lspci | grep -i "AMD" &>/dev/null; then
                log "AMD GPU detected, installing drivers..."
                pacman -S --noconfirm --needed \
                    mesa \
                    lib32-mesa \
                    xf86-video-amdgpu \
                    vulkan-radeon \
                    lib32-vulkan-radeon \
                    libva-mesa-driver \
                    lib32-libva-mesa-driver
            elif lspci | grep -i "Intel" &>/dev/null; then
                log "Intel GPU detected, installing drivers..."
                pacman -S --noconfirm --needed \
                    mesa \
                    lib32-mesa \
                    vulkan-intel \
                    intel-media-driver
            else
                log "No specific GPU detected, installing generic drivers..."
                pacman -S --noconfirm --needed mesa xf86-video-fbdev
            fi
            ;;
        3)
            warn "Skipping all graphics drivers. Hyprland may not work correctly without basic graphics support."
            ;;
        *)
            # 默认情况: 只安装基本驱动
            log "Installing only basic/generic graphics drivers..."
            pacman -S --noconfirm --needed mesa xf86-video-fbdev
            ;;
    esac
    
    log "Graphics driver setup completed"
}

# 安装Hyprland
install_hyprland() {
    log "Installing Hyprland window manager..."
    
    # 安装Hyprland和必要组件
    pacman -S --noconfirm --needed \
        hyprland \
        hyprpaper \
        hyprpicker \
        xdg-desktop-portal-hyprland \
        || error "Hyprland installation failed"
    
    log "Hyprland installation completed"
}

# 安装配套应用程序
install_apps() {
    log "Installing companion applications..."
    
    # 安装终端和工具
    pacman -S --noconfirm --needed \
        kitty \
        alacritty \
        wofi \
        waybar \
        mako \
        swappy \
        grim \
        slurp \
        thunar \
        thunar-archive-plugin \
        file-roller \
        swaylock \
        swayidle \
        wl-clipboard \
        xfce4-settings \
        pavucontrol \
        brightnessctl \
        || error "Companion applications installation failed"
    
    log "Companion applications installation completed"
}

# 创建基础配置
create_configs() {
    log "Creating base configuration..."
    
    # 创建配置目录
    mkdir -p /etc/skel/.config/hypr
    
    # 注意：Hyprland配置语法可能随版本变化，以下配置适用于最新版
    # 如果遇到配置错误，请参考Hyprland最新文档：https://wiki.hyprland.org/
    
    # 创建Hyprland配置文件
    cat > /etc/skel/.config/hypr/keybinds.conf <<EOF
# 防止单个字符触发命令
# 确保所有快捷键都要求修饰键
general {
    # 禁用单字符输入作为快捷键
    allow_single_letter_shortcuts = false
}

# 更精确地设置键绑定
\$mainMod = SUPER

# 应用程序快捷键
bind = \$mainMod, RETURN, exec, kitty
bind = \$mainMod, Q, killactive, 
bind = \$mainMod, M, exit, 
bind = \$mainMod, E, exec, thunar
bind = \$mainMod, V, togglefloating, 
bind = \$mainMod, D, exec, wofi --show drun
bind = \$mainMod, P, pseudo,
bind = \$mainMod, J, togglesplit,

# 紧急热键
bind = CTRL ALT, DELETE, exec, hyprctl dispatch exit
bind = CTRL ALT, T, exec, kitty

# 移动焦点
bind = \$mainMod, left, movefocus, l
bind = \$mainMod, right, movefocus, r
bind = \$mainMod, up, movefocus, u
bind = \$mainMod, down, movefocus, d

# 切换工作区
bind = \$mainMod, 1, workspace, 1
bind = \$mainMod, 2, workspace, 2
bind = \$mainMod, 3, workspace, 3
bind = \$mainMod, 4, workspace, 4
bind = \$mainMod, 5, workspace, 5
bind = \$mainMod, 6, workspace, 6
bind = \$mainMod, 7, workspace, 7
bind = \$mainMod, 8, workspace, 8
bind = \$mainMod, 9, workspace, 9
bind = \$mainMod, 0, workspace, 10

# 移动窗口到工作区
bind = \$mainMod SHIFT, 1, movetoworkspace, 1
bind = \$mainMod SHIFT, 2, movetoworkspace, 2
bind = \$mainMod SHIFT, 3, movetoworkspace, 3
bind = \$mainMod SHIFT, 4, movetoworkspace, 4
bind = \$mainMod SHIFT, 5, movetoworkspace, 5
bind = \$mainMod SHIFT, 6, movetoworkspace, 6
bind = \$mainMod SHIFT, 7, movetoworkspace, 7
bind = \$mainMod SHIFT, 8, movetoworkspace, 8
bind = \$mainMod SHIFT, 9, movetoworkspace, 9
bind = \$mainMod SHIFT, 0, movetoworkspace, 10

# 截图
bind = \$mainMod, S, exec, grim -g "\$(slurp)" - | wl-copy
bind = \$mainMod SHIFT, S, exec, grim -g "\$(slurp)" ~/Pictures/Screenshots/\$(date +'%Y%m%d%H%M%S').png

# 调整亮度和音量
bind = , XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+
bind = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bind = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bind = , XF86MonBrightnessUp, exec, brightnessctl set +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%-
EOF

    # 为NVIDIA用户创建一个空的配置文件
    # 如果没有安装NVIDIA驱动，这个文件仍然存在但为空，避免出错
    cat > /etc/skel/.config/hypr/nvidia.conf <<EOF
# 如果您有NVIDIA GPU并安装了驱动，请取消注释以下行
# env = LIBVA_DRIVER_NAME,nvidia
# env = XDG_SESSION_TYPE,wayland
# env = GBM_BACKEND,nvidia-drm
# env = __GLX_VENDOR_LIBRARY_NAME,nvidia
# env = WLR_NO_HARDWARE_CURSORS,1
EOF

    # 创建环境变量配置
    cat > /etc/skel/.config/hypr/hyprland_env.conf <<EOF
# Hyprland环境变量配置
env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,qt5ct
env = QT_QPA_PLATFORM,wayland
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = GDK_BACKEND,wayland,x11
EOF

    # 在hyprland.conf中引入keybinds.conf
    cat > /etc/skel/.config/hypr/hyprland.conf <<EOF
# Hyprland基础配置文件

# 源文件引入
source = ~/.config/hypr/nvidia.conf
source = ~/.config/hypr/keybinds.conf

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
    touchpad {
        natural_scroll = true
        tap-to-click = true
    }
    # 添加键盘设置，防止误触发
    kb_options = terminate:ctrl_alt_bksp
    # 防止单字符快捷键
    repeat_rate = 25
    repeat_delay = 600
}

# 界面美化
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee)
    col.inactive_border = rgba(595959aa)
    layout = dwindle
    # 禁用单字符快捷键，要求修饰键
    allow_tearing = false
}

# 窗口装饰
decoration {
    rounding = 10
    blur = true
    blur_size = 3
    blur_passes = 1
    blur_new_optimizations = true
    
    drop_shadow = true
    shadow_range = 4
    shadow_render_power = 3
    col.shadow = rgba(1a1a1aee)
}

# 动画
animations {
    enabled = true
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

# 窗口规则
dwindle {
    pseudotile = true
    preserve_split = true
}

# 杂项设置
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
    mouse_move_enables_dpms = true
    key_press_enables_dpms = true
    # 防止单字符快捷键
    allow_chording = false
}
EOF

    log "Base configuration files created"

    # 为现有用户也复制配置文件
    for userdir in /home/*; do
        if [ -d "$userdir" ]; then
            username=$(basename "$userdir")
            if id "$username" &>/dev/null; then
                mkdir -p "$userdir/.config/hypr"
                cp -r /etc/skel/.config/hypr/* "$userdir/.config/hypr/"
                chown -R "$username:$username" "$userdir/.config"
            fi
        fi
    done
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
    
    # 创建备用桌面会话(X11)
    mkdir -p /usr/share/xsessions
    
    # 安装备用窗口管理器
    pacman -S --noconfirm --needed i3 || log "Failed to install backup window manager, continuing..."
    
    cat > /usr/share/xsessions/i3-fallback.desktop <<EOF
[Desktop Entry]
Name=i3 (Fallback)
Comment=Fallback window manager if Hyprland fails
Exec=/usr/bin/i3
Type=Application
EOF
    
    log "Fallback session created"
}

# 配置登录管理器
setup_login() {
    log "Configuring login manager..."

    # 安装SDDM和LightDM作为备用
    pacman -S --noconfirm --needed \
        sddm \
        lightdm \
        lightdm-gtk-greeter \
        qt5-graphicaleffects \
        qt5-quickcontrols2 \
        || error "Display manager installation failed"
    
    # 创建SDDM配置目录
    mkdir -p /etc/sddm.conf.d
    
    # 创建更安全的SDDM配置
    cat > /etc/sddm.conf.d/10-wayland.conf <<EOF
[General]
# 建议使用X11作为备份，Wayland更不稳定
DisplayServer=x11
GreeterEnvironment=QT_QPA_PLATFORM=xcb
EOF
    
    # 默认启用SDDM
    systemctl enable sddm
    
    # 创建TTY自动启动Hyprland的配置
    mkdir -p /etc/systemd/system/getty@tty1.service.d/
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin username - \$TERM
EOF
    
    log "Login manager configuration completed"
}

# 创建自动恢复脚本
create_recovery_script() {
    log "Creating recovery script..."
    
    mkdir -p /etc/skel/.local/bin
    
    cat > /etc/skel/.local/bin/hyprland-recovery <<EOF
#!/bin/bash
# Hyprland紧急恢复脚本

echo "================================================"
echo "  Hyprland 紧急恢复工具 "
echo "================================================"
echo "1. 启动紧急X11会话 (i3)"
echo "2. 重置Hyprland配置"
echo "3. 重装显卡驱动"
echo "4. 切换至LightDM"
echo "5. 显示系统日志"
echo "================================================"

read -p "请选择选项 [1-5]: " choice

case \$choice in
    1)
        echo "启动i3备用会话..."
        startx /usr/bin/i3
        ;;
    2)
        echo "重置Hyprland配置..."
        rm -rf ~/.config/hypr
        cp -r /etc/skel/.config/hypr ~/.config/
        echo "配置已重置。重启后生效。"
        ;;
    3)
        echo "重装显卡驱动..."
        echo "1) 只安装基本驱动 (mesa)"
        echo "2) 安装NVIDIA驱动"
        echo "3) 安装AMD驱动"
        echo "4) 安装Intel驱动"
        read -p "选择驱动类型 [1-4]: " driver_type
        case \$driver_type in
            1) sudo pacman -S --noconfirm mesa xf86-video-vesa ;;
            2) sudo pacman -S --noconfirm nvidia-dkms nvidia-utils ;;
            3) sudo pacman -S --noconfirm mesa xf86-video-amdgpu ;;
            4) sudo pacman -S --noconfirm mesa xf86-video-intel ;;
            *) sudo pacman -S --noconfirm mesa xf86-video-vesa ;;
        esac
        echo "显卡驱动已重装。请重启系统。"
        ;;
    4)
        echo "切换到LightDM..."
        sudo systemctl disable sddm
        sudo systemctl enable lightdm
        echo "已切换到LightDM。请重启系统。"
        ;;
    5)
        echo "系统日志:"
        journalctl -b -p err
        echo ""
        read -p "按Enter继续..."
        ;;
    *)
        echo "无效选项"
        ;;
esac
EOF
    
    chmod +x /etc/skel/.local/bin/hyprland-recovery
    
    # 创建.zprofile或.bash_profile以便在TTY登录后自动启动Hyprland
    cat > /etc/skel/.bash_profile <<EOF
# 自动启动Hyprland (如果在tty1且未运行X或Wayland)
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
    exec Hyprland
fi
EOF
    
    log "Recovery script created"
}

# 创建TTY紧急恢复指南
create_tty_guide() {
    log "Creating TTY rescue guide..."
    
    mkdir -p /etc/skel/Documents
    
    cat > /etc/skel/Documents/tty-rescue-guide.txt <<EOF
======================================================
               Hyprland 紧急恢复指南
======================================================

如果您的系统只显示光标闪烁或黑屏，请按照以下步骤操作:

1. 按 Ctrl+Alt+F2 切换到TTY2
   (如果无效，尝试 Ctrl+Alt+F3, F4, F5...)

2. 使用您的用户名和密码登录

3. 运行以下命令修复系统:
   
   hyprland-recovery

4. 选择适当的选项修复您的系统

常见问题:

- 如果未安装显卡驱动，选择选项3安装基本驱动(mesa)
- 如果无法访问TTY，使用安装U盘启动系统进行修复
- 登录管理器问题: 尝试切换到LightDM

紧急命令:
- startx /usr/bin/i3    (启动备用桌面)
- sudo systemctl restart sddm    (重启登录管理器)
- sudo pacman -S --needed xf86-video-vesa    (安装通用显卡驱动)

======================================================
EOF
    
    # 为所有现有用户复制恢复脚本
    for userdir in /home/*; do
        if [ -d "$userdir" ]; then
            username=$(basename "$userdir")
            if id "$username" &>/dev/null; then
                mkdir -p "$userdir/.local/bin" "$userdir/Documents"
                cp /etc/skel/.local/bin/hyprland-recovery "$userdir/.local/bin/"
                cp /etc/skel/Documents/tty-rescue-guide.txt "$userdir/Documents/"
                chown -R "$username:$username" "$userdir/.local" "$userdir/Documents"
                chmod +x "$userdir/.local/bin/hyprland-recovery"
            fi
        fi
    done
    
    log "TTY rescue guide created"
}

# 主函数
main() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Arch Linux Hyprland Installer       ${NC}"
    echo -e "${BLUE}      (Enhanced Recovery Edition)       ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 检查权限
    check_root
    
    # 开始安装
    update_system
    install_tools
    install_dependencies
    
    # 询问是否安装显卡驱动
    echo ""
    echo "Hyprland needs basic graphics support, but specialized drivers are optional."
    read -p "Do you want to install graphics drivers? (y/n) [default: n]: " install_drivers
    
    if [[ "$install_drivers" =~ ^[Yy]$ ]]; then
        install_gpu_drivers
    else
        log "Skipping dedicated GPU driver installation (using only basic Mesa support)"
    fi
    
    install_hyprland
    install_apps
    create_configs
    create_desktop_entry
    setup_login
    create_recovery_script
    create_tty_guide
    
    log "Hyprland installation completed!"
    log "IMPORTANT: Read carefully for black screen/cursor issues:"
    log ""
    log "1. If you see only a cursor after login:"
    log "   - Press Ctrl+Alt+F2 to access TTY"
    log "   - Login with your username and password"
    log "   - Run 'hyprland-recovery' and select an option"
    log ""
    log "2. A rescue guide is available in ~/Documents/tty-rescue-guide.txt"
    log ""
    log "3. After reboot, select 'Hyprland' from the login screen"
    log ""
    
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