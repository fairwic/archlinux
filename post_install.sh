#!/bin/bash
# Arch Linux 安装后配置脚本
# 用于配置中文环境、输入法、蓝牙和其他常用软件

set -euo pipefail

# 彩色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
        error "请使用 root 权限运行此脚本，例如: sudo $0"
    fi
}

# 更新系统
update_system() {
    log "正在更新系统..."
    pacman -Syu --noconfirm || error "系统更新失败"
    log "系统更新完成"
}

# 安装中文字体
install_fonts() {
    log "正在安装中文字体..."
    pacman -S --noconfirm \
        noto-fonts \
        noto-fonts-cjk \
        noto-fonts-emoji \
        wqy-microhei \
        wqy-zenhei \
        ttf-dejavu \
        ttf-liberation \
        || error "字体安装失败"
    
    # 更新字体缓存
    fc-cache -fv
    log "中文字体安装完成"
}

# 配置中文环境
setup_locale() {
    log "正在配置中文环境..."
    
    # 检查并添加中文 locale
    if ! grep -q "zh_CN.UTF-8 UTF-8" /etc/locale.gen; then
        echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
        locale-gen || error "生成中文 locale 失败"
    fi
    
    # 配置系统环境变量
    cat > /etc/environment <<EOF
LANG=zh_CN.UTF-8
LC_CTYPE=zh_CN.UTF-8
EOF
    
    log "中文环境配置完成，重启后生效"
}

# 安装输入法
install_input_method() {
    log "正在安装中文输入法..."
    
    # 安装 Fcitx5
    pacman -S --noconfirm \
        fcitx5 \
        fcitx5-chinese-addons \
        fcitx5-qt \
        fcitx5-gtk \
        fcitx5-configtool \
        || error "输入法安装失败"
    
    # 配置输入法环境变量
    cat > /etc/environment.d/95-input-method.conf <<EOF
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=ibus
EOF
    
    # 设置开机自启
    mkdir -p /etc/xdg/autostart
    cat > /etc/xdg/autostart/fcitx5.desktop <<EOF
[Desktop Entry]
Name=Fcitx5
Comment=启动 Fcitx5 输入法
Exec=fcitx5
Type=Application
Categories=System;Utility;
EOF
    
    log "中文输入法安装完成，重启后可用"
}

# 安装和配置蓝牙
setup_bluetooth() {
    log "正在安装蓝牙支持..."
    
    pacman -S --noconfirm \
        bluez \
        bluez-utils \
        blueman \
        || error "蓝牙安装失败"
    
    # 启用蓝牙服务
    systemctl enable bluetooth.service
    systemctl start bluetooth.service
    
    log "蓝牙支持安装完成"
}

# 安装常用网络工具
install_network_tools() {
    log "正在安装网络工具..."
    
    pacman -S --noconfirm \
        networkmanager \
        network-manager-applet \
        nm-connection-editor \
        || error "网络工具安装失败"
    
    # 确保 NetworkManager 服务启用
    systemctl enable NetworkManager.service
    systemctl start NetworkManager.service
    
    log "网络工具安装完成"
}

# 安装常用系统工具
install_system_tools() {
    log "正在安装系统工具..."
    
    pacman -S --noconfirm \
        base-devel \
        git \
        vim \
        wget \
        curl \
        htop \
        unzip \
        usbutils \
        xdg-user-dirs \
        || error "系统工具安装失败"
    
    # 创建用户目录
    xdg-user-dirs-update
    
    log "系统工具安装完成"
}

# 安装桌面环境（如果需要）
install_desktop() {
    log "您想安装哪个桌面环境？"
    echo "1) GNOME 桌面"
    echo "2) KDE Plasma 桌面"
    echo "3) Xfce 桌面"
    echo "4) 不安装桌面环境"
    
    read -p "请输入选项 [1-4]: " desktop_choice
    
    case $desktop_choice in
        1)
            log "正在安装 GNOME 桌面环境..."
            pacman -S --noconfirm \
                gnome \
                gnome-tweaks \
                gdm \
                || error "GNOME 安装失败"
            
            # 启用显示管理器
            systemctl enable gdm.service
            ;;
        2)
            log "正在安装 KDE Plasma 桌面环境..."
            pacman -S --noconfirm \
                plasma \
                plasma-wayland-session \
                kde-applications \
                sddm \
                || error "KDE 安装失败"
            
            # 启用显示管理器
            systemctl enable sddm.service
            ;;
        3)
            log "正在安装 Xfce 桌面环境..."
            pacman -S --noconfirm \
                xfce4 \
                xfce4-goodies \
                lightdm \
                lightdm-gtk-greeter \
                || error "Xfce 安装失败"
            
            # 启用显示管理器
            systemctl enable lightdm.service
            ;;
        4)
            log "跳过桌面环境安装"
            ;;
        *)
            warn "无效选项，跳过桌面环境安装"
            ;;
    esac
}

# 安装AUR助手
install_aur_helper() {
    log "您想安装 AUR 助手吗？(y/n)"
    read -p "> " install_aur
    
    if [[ "$install_aur" =~ ^[Yy]$ ]]; then
        # 检查是否已安装 git
        if ! command -v git &> /dev/null; then
            pacman -S --noconfirm git || error "Git 安装失败"
        fi
        
        # 创建临时目录并克隆 yay
        log "正在安装 yay AUR 助手..."
        temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        git clone https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si --noconfirm
        
        # 清理
        cd ~
        rm -rf "$temp_dir"
        
        log "AUR 助手安装完成"
    else
        log "跳过 AUR 助手安装"
    fi
}

# 配置默认编辑器和终端行为
configure_defaults() {
    log "正在配置系统默认设置..."
    
    # 创建全局 aliases
    cat > /etc/profile.d/aliases.sh <<EOF
#!/bin/bash
alias ls='ls --color=auto'
alias ll='ls -la'
alias grep='grep --color=auto'
EOF
    
    chmod +x /etc/profile.d/aliases.sh
    
    log "默认设置配置完成"
}

# 主函数
main() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Arch Linux 安装后配置脚本         ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 检查权限
    check_root
    
    # 询问用户要执行的操作
    echo "请选择要执行的操作 (输入序号，多个序号用空格分隔):"
    echo "1) 更新系统"
    echo "2) 安装中文字体"
    echo "3) 配置中文环境"
    echo "4) 安装中文输入法"
    echo "5) 配置蓝牙"
    echo "6) 安装网络工具"
    echo "7) 安装常用系统工具"
    echo "8) 安装桌面环境"
    echo "9) 安装 AUR 助手"
    echo "10) 配置系统默认设置"
    echo "0) 执行所有操作"
    
    read -p "请输入您的选择: " -a choices
    
    # 默认执行所有操作
    if [[ "${choices[*]}" == "0" ]]; then
        choices=(1 2 3 4 5 6 7 8 9 10)
    fi
    
    # 根据选择执行操作
    for choice in "${choices[@]}"; do
        case "$choice" in
            1) update_system ;;
            2) install_fonts ;;
            3) setup_locale ;;
            4) install_input_method ;;
            5) setup_bluetooth ;;
            6) install_network_tools ;;
            7) install_system_tools ;;
            8) install_desktop ;;
            9) install_aur_helper ;;
            10) configure_defaults ;;
            *) warn "无效选项: $choice" ;;
        esac
    done
    
    log "配置完成！建议现在重启系统使所有更改生效。"
    read -p "是否立即重启系统？(y/n) " reboot_now
    if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
        log "系统将在 5 秒后重启..."
        sleep 5
        reboot
    fi
}

# 执行主函数
main
