#!/bin/bash
# Arch Linux Post-Installation Configuration Script
# For configuring Chinese environment, input methods, Bluetooth and other common software
# 安装字体等

set -euo pipefail

# Colored output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Check root privileges
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "Please run this script with root privileges, e.g.: sudo $0"
    fi
}

# Update system
update_system() {
    log "Updating system..."
    pacman -Syu --noconfirm || error "System update failed"
    log "System update completed"
}

# Install Chinese fonts
install_fonts() {
    log "Installing Chinese fonts..."
    pacman -S --noconfirm \
        noto-fonts \
        noto-fonts-cjk \
        noto-fonts-emoji \
        wqy-microhei \
        wqy-zenhei \
        ttf-dejavu \
        ttf-liberation \
        adobe-source-han-sans-cn-fonts \
        adobe-source-han-serif-cn-fonts \
        || error "Font installation failed"
    
    # Create better font configuration
    log "Creating optimized font configuration..."
    mkdir -p /etc/fonts/conf.d/
    
    # Create custom font configuration
    cat > /etc/fonts/local.conf <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Set default fonts for Chinese -->
  <match target="pattern">
    <test name="lang" compare="contains">
      <string>zh</string>
    </test>
    <test name="family">
      <string>sans-serif</string>
    </test>
    <edit name="family" mode="prepend" binding="strong">
      <string>Noto Sans CJK SC</string>
      <string>WenQuanYi Micro Hei</string>
      <string>Source Han Sans CN</string>
    </edit>
  </match>
  
  <match target="pattern">
    <test name="lang" compare="contains">
      <string>zh</string>
    </test>
    <test name="family">
      <string>serif</string>
    </test>
    <edit name="family" mode="prepend" binding="strong">
      <string>Noto Serif CJK SC</string>
      <string>WenQuanYi Zen Hei</string>
      <string>Source Han Serif CN</string>
    </edit>
  </match>
  
  <match target="pattern">
    <test name="lang" compare="contains">
      <string>zh</string>
    </test>
    <test name="family">
      <string>monospace</string>
    </test>
    <edit name="family" mode="prepend" binding="strong">
      <string>Noto Sans Mono CJK SC</string>
      <string>WenQuanYi Micro Hei Mono</string>
    </edit>
  </match>
</fontconfig>
EOF
    
    # Update font cache thoroughly
    fc-cache -fv
    
    # Test if Chinese fonts are available
    log "Testing Chinese font availability..."
    if fc-list :lang=zh | grep -q .; then
        log "Chinese fonts are available in the system"
    else
        warn "Chinese fonts might not be properly installed, please check font configuration manually"
    fi
    
    log "Chinese fonts installation completed"
}

# Configure Chinese locale
setup_locale() {
    log "Configuring Chinese locale..."
    
    # Ensure all required locales are in locale.gen
    sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
    
    # If entries don't exist, add them
    if ! grep -q "zh_CN.UTF-8 UTF-8" /etc/locale.gen; then
        echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
    fi
    if ! grep -q "en_US.UTF-8 UTF-8" /etc/locale.gen; then
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    fi
    
    # Generate locales
    locale-gen || error "Failed to generate locales"
    
    # Configure system environment variables
    cat > /etc/locale.conf <<EOF
LANG=zh_CN.UTF-8
LC_CTYPE=zh_CN.UTF-8
EOF
    
    # Also add to environment file for compatibility
    cat > /etc/environment <<EOF
LANG=zh_CN.UTF-8
LC_CTYPE=zh_CN.UTF-8
LANGUAGE=zh_CN:en_US
EOF
    
    # Set system locale immediately (might not work in all environments)
    if command -v localectl &>/dev/null; then
        localectl set-locale LANG=zh_CN.UTF-8
    fi
    
    log "Chinese locale configuration completed, will take effect after reboot"
    log "You can check current locale with 'locale' command after reboot"
}

# Install input method
install_input_method() {
    log "Installing Chinese input method..."
    
    # Install Fcitx5
    pacman -S --noconfirm \
        fcitx5 \
        fcitx5-chinese-addons \
        fcitx5-qt \
        fcitx5-gtk \
        fcitx5-configtool \
        || error "Input method installation failed"
    
    # Configure input method environment variables
    cat > /etc/environment.d/95-input-method.conf <<EOF
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=ibus
EOF
    
    # Set autostart
    mkdir -p /etc/xdg/autostart
    cat > /etc/xdg/autostart/fcitx5.desktop <<EOF
[Desktop Entry]
Name=Fcitx5
Comment=Start Fcitx5 Input Method
Exec=fcitx5
Type=Application
Categories=System;Utility;
EOF
    
    log "Chinese input method installation completed, will be available after reboot"
}

# Install and configure Bluetooth
setup_bluetooth() {
    log "Installing Bluetooth support..."
    
    pacman -S --noconfirm \
        bluez \
        bluez-utils \
        blueman \
        || error "Bluetooth installation failed"
    
    # Enable Bluetooth service
    systemctl enable bluetooth.service
    systemctl start bluetooth.service
    
    log "Bluetooth support installation completed"
}

# Install common network tools
install_network_tools() {
    log "Installing network tools..."
    
    pacman -S --noconfirm \
        networkmanager \
        network-manager-applet \
        nm-connection-editor \
        || error "Network tools installation failed"
    
    # Ensure NetworkManager service is enabled
    systemctl enable NetworkManager.service
    systemctl start NetworkManager.service
    
    log "Network tools installation completed"
}

# Install common system tools
install_system_tools() {
    log "Installing system tools..."
    
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
        || error "System tools installation failed"
    
    # Create user directories
    xdg-user-dirs-update
    
    log "System tools installation completed"
}

# Install desktop environment (if needed)
install_desktop() {
    log "Which desktop environment would you like to install?"
    echo "1) GNOME Desktop"
    echo "2) KDE Plasma Desktop"
    echo "3) Xfce Desktop"
    echo "4) Don't install desktop environment"
    
    read -p "Please enter your choice [1-4]: " desktop_choice
    
    case $desktop_choice in
        1)
            log "Installing GNOME desktop environment..."
            pacman -S --noconfirm \
                gnome \
                gnome-tweaks \
                gdm \
                || error "GNOME installation failed"
            
            # Enable display manager
            systemctl enable gdm.service
            ;;
        2)
            log "Installing KDE Plasma desktop environment..."
            pacman -S --noconfirm \
                plasma \
                plasma-wayland-session \
                kde-applications \
                sddm \
                || error "KDE installation failed"
            
            # Enable display manager
            systemctl enable sddm.service
            ;;
        3)
            log "Installing Xfce desktop environment..."
            pacman -S --noconfirm \
                xfce4 \
                xfce4-goodies \
                lightdm \
                lightdm-gtk-greeter \
                || error "Xfce installation failed"
            
            # Enable display manager
            systemctl enable lightdm.service
            ;;
        4)
            log "Skipping desktop environment installation"
            ;;
        *)
            warn "Invalid option, skipping desktop environment installation"
            ;;
    esac
}

# Install AUR helper
install_aur_helper() {
    log "Would you like to install an AUR helper? (y/n)"
    read -p "> " install_aur
    
    if [[ "$install_aur" =~ ^[Yy]$ ]]; then
        # Check if git is already installed
        if ! command -v git &> /dev/null; then
            pacman -S --noconfirm git || error "Git installation failed"
        fi
        
        # Create temporary directory and clone yay
        log "Installing yay AUR helper..."
        temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        git clone https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si --noconfirm
        
        # Cleanup
        cd ~
        rm -rf "$temp_dir"
        
        log "AUR helper installation completed"
    else
        log "Skipping AUR helper installation"
    fi
}

# Configure default editor and terminal behavior
configure_defaults() {
    log "Configuring system default settings..."
    
    # Create global aliases
    cat > /etc/profile.d/aliases.sh <<EOF
#!/bin/bash
alias ls='ls --color=auto'
alias ll='ls -la'
alias grep='grep --color=auto'
EOF
    
    chmod +x /etc/profile.d/aliases.sh
    
    log "Default settings configuration completed"
}

# Main function
main() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Arch Linux Post-Installation Script ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Check permissions
    check_root
    
    # Ask user which operations to execute
    echo "Please select operations to perform (enter numbers, separate multiple choices with spaces):"
    echo "1) Update system"
    echo "2) Install Chinese fonts"
    echo "3) Configure Chinese locale"
    echo "4) Install Chinese input method"
    echo "5) Configure Bluetooth"
    echo "6) Install network tools"
    echo "7) Install common system tools"
    echo "8) Install desktop environment"
    echo "9) Install AUR helper"
    echo "10) Configure system defaults"
    echo "0) Perform all operations"
    
    read -p "Please enter your choice: " -a choices
    
    # Default to all operations
    if [[ "${choices[*]}" == "0" ]]; then
        choices=(1 2 3 4 5 6 7 8 9 10)
    fi
    
    # Execute operations based on choices
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
            *) warn "Invalid option: $choice" ;;
        esac
    done
    
    log "Configuration completed! It's recommended to reboot your system now for all changes to take effect."
    read -p "Would you like to reboot now? (y/n) " reboot_now
    if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
        log "System will reboot in 5 seconds..."
        sleep 5
        reboot
    fi
}

# Execute main function
main
