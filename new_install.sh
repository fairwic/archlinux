#!/bin/bash
set -euo pipefail

# Global variables for cleanup tracking
declare -A MOUNT_POINTS
declare -A ENABLED_SERVICES

# Cleanup function
cleanup() {
    log "INFO" "Starting cleanup process..."
    
    # Unmount all tracked mount points in reverse order
    for mount_point in "${!MOUNT_POINTS[@]}"; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            log "INFO" "Unmounting $mount_point"
            umount -R "$mount_point" || log "WARNING" "Failed to unmount $mount_point"
        fi
    done
    
    # Disable swap if it was enabled
    if [ -n "${DISK:-}" ] && swapon --show | grep -q "${DISK}2" 2>/dev/null; then
        log "INFO" "Disabling swap"
        swapoff "${DISK}2" || log "WARNING" "Failed to disable swap"
    fi
    
    # Remove temporary files
    if [ -f /mnt/configure_chroot.sh ]; then
        log "INFO" "Removing temporary files"
        rm -f /mnt/configure_chroot.sh
    fi
    
    log "INFO" "Cleanup completed"
}

# Error handling function with improved cleanup
error_handler() {
    local line_number=$1
    local error_code=$2
    local error_message=$3
    
    echo "----------------------------------------"
    echo "ERROR DETECTED - STOPPING INSTALLATION"
    echo "----------------------------------------"
    echo "Error occurred in script at line $line_number"
    echo "Error code: $error_code"
    echo "Error message: $error_message"
    echo
    echo "Stack trace:"
    local frame=0
    while caller $frame; do
        ((frame++))
    done
    echo "----------------------------------------"
    
    # Perform cleanup
    cleanup
    
    # Save error log
    if [ -d "/mnt" ]; then
        local error_log="/mnt/install_error.log"
        {
            echo "Installation failed at $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Error line: $line_number"
            echo "Error code: $error_code"
            echo "Error message: $error_message"
            echo
            echo "System information:"
            uname -a
            echo
            echo "Memory status:"
            free -h
            echo
            echo "Disk status:"
            lsblk
            echo
            echo "Mount points:"
            mount
            echo
            echo "Last 50 lines of pacman log:"
            tail -n 50 /var/log/pacman.log 2>/dev/null || echo "No pacman log available"
        } > "$error_log"
        echo "Error details have been saved to $error_log"
    fi
    
    echo
    echo "Installation failed. Please check the error message above."
    echo "You may need to:"
    echo "1. Check the error log for details"
    echo "2. Fix the reported issue"
    echo "3. Restart the installation process"
    echo
    
    exit $error_code
}

# Set error trap
trap 'error_handler ${LINENO} $? "Command failed"' ERR

# Enhanced log function with timestamps
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

# Function to verify a step completed successfully
verify_step() {
    local step_name=$1
    local check_command=$2
    local error_message=$3
    
    log "INFO" "Verifying step: $step_name"
    if ! eval "$check_command"; then
        error_handler ${LINENO} 1 "$error_message"
    fi
    log "INFO" "Step verified successfully: $step_name"
}

# Check system requirements
check_system_requirements() {
    log "INFO" "Checking system requirements..."
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        error_handler ${LINENO} 1 "This script must be run as root"
    fi
    
    # Check minimum memory requirements (2GB)
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 2048 ]; then
        log "WARNING" "System has less than 2GB of RAM (${total_mem}MB). Installation might be slow."
    fi
    
    # Check minimum disk space (20GB)
    local disk_size=$(lsblk -b -n -d -o SIZE $(findmnt -n -o SOURCE /) | numfmt --to=iec)
    if [ "$disk_size" -lt 20000000000 ]; then
        error_handler ${LINENO} 1 "Insufficient disk space. Minimum 20GB required."
    fi
}

# Network connection check function
check_network() {
    log "INFO" "Checking network connection..."
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if ping -c 1 archlinux.org &>/dev/null; then
            log "INFO" "Network connection is OK!"
            return 0
        fi
        retry_count=$((retry_count + 1))
        log "WARNING" "Network check failed, attempt $retry_count of $max_retries"
        sleep 2
    done
    
    error_handler ${LINENO} 1 "Network connection failed after $max_retries attempts"
}

# Update system time with error handling
update_system_time() {
    log "INFO" "Synchronizing system time..."
    if ! timedatectl set-ntp true; then
        error_handler ${LINENO} 1 "Failed to synchronize system time"
    fi
    sleep 2
}

# Update mirror list with error handling
update_mirrorlist() {
    log "INFO" "Updating mirror list..."
    # Backup original mirror list
    if ! cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup; then
        error_handler ${LINENO} 1 "Failed to backup mirror list"
    fi
    
    # Update mirror database
    if ! pacman -Sy --noconfirm archlinux-keyring; then
        error_handler ${LINENO} 1 "Failed to update archlinux-keyring"
    fi
    
    # Use reflector to select fastest mirrors
    if command -v reflector &>/dev/null; then
        log "INFO" "Using reflector to update mirrors..."
        if ! reflector --country China --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist; then
            log "WARNING" "Reflector failed, using default mirrors"
        fi
    else
        log "WARNING" "Reflector not installed, using default mirrors"
    fi
}

# Function to select installation disk with validation
select_disk() {
    log "INFO" "Scanning available disks..."
    echo "Available disks:"
    echo "----------------"
    lsblk -d -e 7,11 -o NAME,SIZE,MODEL,TRAN,TYPE
    echo "----------------"
    
    # Get available disks
    mapfile -t disks < <(lsblk -d -e 7,11 -o NAME | tail -n +2)
    
    if [ ${#disks[@]} -eq 0 ]; then
        error_handler ${LINENO} 1 "No available disks found"
    fi
    
    # Check if disks are mounted
    for disk in "${disks[@]}"; do
        if grep -q "/dev/$disk" /proc/mounts; then
            log "WARNING" "Disk /dev/$disk is currently mounted"
        fi
    done
    
    PS3="Please select the disk for installation (enter number): "
    select disk in "${disks[@]}"; do
        if [ -n "$disk" ]; then
            # Check disk size
            local disk_size=$(lsblk -b -n -d -o SIZE "/dev/$disk")
            if [ "$disk_size" -lt 20000000000 ]; then
                log "WARNING" "Selected disk is smaller than recommended size (20GB)"
                read -p "Continue anyway? (y/N): " small_disk_confirm
                [[ "$small_disk_confirm" =~ ^[Yy]$ ]] || continue
            fi
            
            echo "You selected: /dev/$disk"
            echo "WARNING: All data on /dev/$disk will be erased!"
            read -p "Are you sure you want to continue? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                DISK="/dev/$disk"
                break
            else
                log "INFO" "Installation aborted by user"
                exit 0
            fi
        else
            log "ERROR" "Invalid selection. Please try again."
        fi
    done
}

# User-defined variables
# DISK is now set by select_disk function
HOSTNAME="fwc-arch"         # Hostname
TIMEZONE="Asia/Shanghai"     # Timezone
LANG="en_US.UTF-8"          # System language
KEYMAP="us"                 # Keyboard layout

# Detect UEFI mode
if [ -d "/sys/firmware/efi/efivars" ]; then
  BOOT_MODE="UEFI"
  PARTITION_SCRIPT="efi_partition"
else
  BOOT_MODE="BIOS"
  PARTITION_SCRIPT="bios_partition"
fi

# Partition function with error handling
partition_disk() {
    log "INFO" "Starting disk partitioning..."
    
    # Check if disk exists
    if [ ! -b "$DISK" ]; then
        error_handler ${LINENO} 1 "Selected disk $DISK does not exist"
    fi
    
    # Check if disk is mounted
    if grep -q "$DISK" /proc/mounts; then
        error_handler ${LINENO} 1 "Disk $DISK is currently mounted. Please unmount first."
    fi
    
    # Clear partition table
    log "INFO" "Clearing partition table..."
    if ! parted -s $DISK mklabel gpt; then
        error_handler ${LINENO} 1 "Failed to create GPT partition table"
    fi

    if [ "$BOOT_MODE" = "UEFI" ]; then
        log "INFO" "Creating UEFI partitions..."
        # Create partitions with error checking
        if ! parted -s $DISK mkpart primary fat32 1MiB 513MiB; then
            error_handler ${LINENO} 1 "Failed to create EFI partition"
        fi
        if ! parted -s $DISK set 1 esp on; then
            error_handler ${LINENO} 1 "Failed to set ESP flag"
        fi
        if ! parted -s $DISK mkpart primary linux-swap 513MiB 4609MiB; then
            error_handler ${LINENO} 1 "Failed to create swap partition"
        fi
        if ! parted -s $DISK mkpart primary ext4 4609MiB 100%; then
            error_handler ${LINENO} 1 "Failed to create root partition"
        fi
    else
        log "INFO" "Creating BIOS partitions..."
        if ! parted -s $DISK mkpart primary ext4 1MiB 100%; then
            error_handler ${LINENO} 1 "Failed to create root partition"
        fi
        if ! parted -s $DISK set 1 boot on; then
            error_handler ${LINENO} 1 "Failed to set boot flag"
        fi
    fi
    
    # Wait for partition changes to be recognized
    sleep 2
    
    # Verify partitions were created
    if ! lsblk "$DISK" | grep -q "part"; then
        error_handler ${LINENO} 1 "Partition creation failed"
    fi
}

# Format partitions with verification
format_partitions() {
    log "INFO" "Starting partition formatting..."
    
    if [ "$BOOT_MODE" = "UEFI" ]; then
        # Format EFI partition
        log "INFO" "Formatting EFI partition..."
        if ! mkfs.fat -F32 ${DISK}1; then
            error_handler ${LINENO} 1 "Failed to format EFI partition"
        fi
        verify_step "EFI partition format" "blkid ${DISK}1 | grep -q 'vfat'" "EFI partition format verification failed"
        
        # Create and enable swap
        log "INFO" "Creating swap partition..."
        if ! mkswap ${DISK}2; then
            error_handler ${LINENO} 1 "Failed to create swap partition"
        fi
        if ! swapon ${DISK}2; then
            error_handler ${LINENO} 1 "Failed to enable swap"
        fi
        verify_step "Swap partition" "swapon --show | grep -q ${DISK}2" "Swap partition verification failed"
        
        # Format root partition
        log "INFO" "Formatting root partition..."
        if ! mkfs.ext4 ${DISK}3; then
            error_handler ${LINENO} 1 "Failed to format root partition"
        fi
        verify_step "Root partition format" "blkid ${DISK}3 | grep -q 'ext4'" "Root partition format verification failed"
        
        # Mount partitions
        log "INFO" "Mounting partitions..."
        if ! mount ${DISK}3 /mnt; then
            error_handler ${LINENO} 1 "Failed to mount root partition"
        fi
        MOUNT_POINTS["/mnt"]=1
        
        if ! mkdir -p /mnt/boot; then
            error_handler ${LINENO} 1 "Failed to create boot directory"
        fi
        if ! mount ${DISK}1 /mnt/boot; then
            error_handler ${LINENO} 1 "Failed to mount boot partition"
        fi
        MOUNT_POINTS["/mnt/boot"]=1
    else
        # Format root partition
        log "INFO" "Formatting root partition..."
        if ! mkfs.ext4 ${DISK}1; then
            error_handler ${LINENO} 1 "Failed to format root partition"
        fi
        verify_step "Root partition format" "blkid ${DISK}1 | grep -q 'ext4'" "Root partition format verification failed"
        
        # Mount root partition
        if ! mount ${DISK}1 /mnt; then
            error_handler ${LINENO} 1 "Failed to mount root partition"
        fi
        MOUNT_POINTS["/mnt"]=1
    fi
    
    log "INFO" "Partition formatting completed successfully"
}

# Install base system with verification
install_base() {
    log "INFO" "Starting base system installation..."
    
    # Update keyring first
    if ! pacman -Sy --noconfirm archlinux-keyring; then
        error_handler ${LINENO} 1 "Failed to update archlinux-keyring"
    fi
    
    # Install base packages
    local base_packages="base base-devel linux linux-firmware linux-headers vim networkmanager sudo mkinitcpio udev lvm2 mdadm xfsprogs dosfstools e2fsprogs ntfs-3g"
    
    log "INFO" "Installing base packages..."
    if ! pacstrap /mnt $base_packages; then
        error_handler ${LINENO} 1 "Failed to install base packages"
    fi
    
    # Verify installation
    for pkg in $base_packages; do
        if ! arch-chroot /mnt pacman -Q $pkg >/dev/null 2>&1; then
            error_handler ${LINENO} 1 "Package $pkg was not installed correctly"
        fi
    done
    
    log "INFO" "Base system installation completed successfully"
}

# Generate fstab
generate_fstab() {
  genfstab -U /mnt >> /mnt/etc/fstab
}

# Configure system
configure_system() {
    log "INFO" "Starting system configuration..."
    
    # Create a temporary script for chroot operations
    cat > /mnt/configure_chroot.sh <<EOFINNER
#!/bin/bash
set -e

# 将主脚本的变量传递给 chroot 环境
TIMEZONE="$TIMEZONE"
LANG="$LANG"
KEYMAP="$KEYMAP"
HOSTNAME="$HOSTNAME"
BOOT_MODE="$BOOT_MODE"
DISK="$DISK"
ROOT_PASSWORD="$ROOT_PASSWORD"

# Error handling function for chroot environment
chroot_error() {
    echo "[ERROR] Configuration failed at step: $1"
    echo "[ERROR] Error message: $2"
    exit 1
}

# Function to check command status
check_step() {
    if [ $? -ne 0 ]; then
        chroot_error "$1" "$2"
    fi
}

echo "[INFO] Setting up timezone..."
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
check_step "timezone" "Failed to set timezone"
hwclock --systohc
check_step "hwclock" "Failed to set hardware clock"

echo "[INFO] Configuring localization..."
sed -i "s/#$LANG/$LANG/" /etc/locale.gen
check_step "locale.gen" "Failed to configure locale.gen"
locale-gen
check_step "locale-gen" "Failed to generate locales"
echo "LANG=$LANG" > /etc/locale.conf
check_step "locale.conf" "Failed to set language"
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
check_step "vconsole.conf" "Failed to set keyboard layout"

echo "[INFO] Configuring network..."
echo "$HOSTNAME" > /etc/hostname
check_step "hostname" "Failed to set hostname"
systemctl enable NetworkManager
check_step "networkmanager" "Failed to enable NetworkManager"

echo "[INFO] Configuring mkinitcpio..."
cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.backup
check_step "mkinitcpio-backup" "Failed to backup mkinitcpio.conf"
sed -i 's/^HOOKS=.*/HOOKS=(base udev block autodetect modconf keyboard keymap consolefont filesystems fsck)/' /etc/mkinitcpio.conf
check_step "mkinitcpio-config" "Failed to configure mkinitcpio"

echo "[INFO] Generating initramfs..."
mkinitcpio -P
check_step "mkinitcpio" "Failed to generate initramfs"

echo "[INFO] Setting root password..."
echo "root:$ROOT_PASSWORD" | chpasswd
check_step "root-password" "Failed to set root password"

echo "[INFO] Installing and configuring bootloader..."
if [ "$BOOT_MODE" = "UEFI" ]; then
    bootctl install
    check_step "bootctl-install" "Failed to install systemd-boot"
    
    # Create bootloader configuration
    mkdir -p /boot/loader/entries
    check_step "bootloader-dirs" "Failed to create bootloader directories"
    
    echo "default arch" > /boot/loader/loader.conf
    echo "timeout 3" >> /boot/loader/loader.conf
    check_step "loader-conf" "Failed to create loader.conf"
    
    echo "title Arch Linux" > /boot/loader/entries/arch.conf
    echo "linux /vmlinuz-linux" >> /boot/loader/entries/arch.conf
    echo "initrd /initramfs-linux.img" >> /boot/loader/entries/arch.conf
    root_uuid=$(blkid -s UUID -o value ${DISK}3)
    echo "options root=UUID=$root_uuid rw rootfstype=ext4 add_efi_memmap" >> /boot/loader/entries/arch.conf
    check_step "bootloader-entry" "Failed to create bootloader entry"
else
    pacman -S --noconfirm grub
    check_step "grub-install" "Failed to install GRUB"
    
    grub-install $DISK
    check_step "grub-install" "Failed to install GRUB to disk"
    
    cp /etc/default/grub /etc/default/grub.backup
    check_step "grub-backup" "Failed to backup GRUB configuration"
    
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="rootfstype=ext4"/' /etc/default/grub
    check_step "grub-config" "Failed to configure GRUB"
    
    grub-mkconfig -o /boot/grub/grub.cfg
    check_step "grub-mkconfig" "Failed to generate GRUB configuration"
fi

echo "[INFO] Creating user account..."
useradd -m -G wheel -s /bin/bash fangweicong
check_step "user-create" "Failed to create user account"
echo "fangweicong:$ROOT_PASSWORD" | chpasswd
check_step "user-password" "Failed to set user password"

echo "[INFO] Configuring sudo..."
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
check_step "sudo-config" "Failed to configure sudo"
chmod 440 /etc/sudoers.d/wheel
check_step "sudo-permissions" "Failed to set sudo file permissions"

echo "[INFO] Enabling essential services..."
systemctl enable systemd-modules-load
check_step "systemd-modules" "Failed to enable systemd-modules-load"
systemctl enable systemd-udevd
check_step "systemd-udev" "Failed to enable systemd-udevd"

echo "[INFO] Configuration completed successfully"
EOFINNER

    # Make the script executable
    chmod +x /mnt/configure_chroot.sh
    
    # Execute the script in chroot
    log "INFO" "Entering chroot environment for system configuration..."
    if ! arch-chroot /mnt /configure_chroot.sh; then
        log "ERROR" "Configuration failed in chroot environment"
        log "INFO" "Attempting to save logs..."
        if [ -f /mnt/var/log/pacman.log ]; then
            cp /mnt/var/log/pacman.log /mnt/var/log/pacman.log.failed
        fi
        error_handler ${LINENO} 1 "System configuration failed. Check /var/log/pacman.log.failed for details"
    fi
    
    # Cleanup
    log "INFO" "Cleaning up configuration files..."
    rm -f /mnt/configure_chroot.sh
    
    log "INFO" "System configuration completed successfully"
}

# Main execution flow with enhanced error checking
main() {
    local total_steps=7
    local current_step=0
    
    log "INFO" "Starting Arch Linux installation..."
    log "INFO" "Installation started at $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Create error log directory
    mkdir -p /var/log/arch_install
    
    # Execute each step with verification
    for step in check_system_requirements \
                check_network \
                update_system_time \
                update_mirrorlist \
                select_disk \
                partition_disk \
                format_partitions \
                install_base \
                generate_fstab \
                configure_system; do
        ((current_step++))
        log "INFO" "[$current_step/$total_steps] Executing: $step"
        if ! $step; then
            error_handler ${LINENO} 1 "Step $step failed"
        fi
        log "INFO" "Step completed successfully: $step"
    done
    
    # Final verification
    verify_installation
    
    log "INFO" "Installation completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
    log "INFO" "Please remove installation media and reboot the system"
    log "INFO" "After reboot, login as root and change the root password"
}

# Start installation with error handling
main || error_handler ${LINENO} $? "Installation failed in main function"

# 交互式输入密码
read_password() {
    local prompt=$1
    local password=""
    local confirm=""
    
    while true; do
        read -s -p "$prompt: " password
        echo
        read -s -p "确认密码: " confirm
        echo
        
        if [ "$password" = "$confirm" ]; then
            echo "$password"
            return 0
        else
            echo "密码不匹配，请重试"
        fi
    done
}

# 在执行前获取密码
ROOT_PASSWORD=$(read_password "请输入root密码")

# 验证安装
verify_installation() {
    log "INFO" "Verifying installation..."
    
    # 检查必要文件是否存在
    for file in /mnt/etc/fstab /mnt/etc/hostname; do
        if [ ! -f "$file" ]; then
            error_handler ${LINENO} 1 "Required file $file not found"
        fi
    done
    
    # 验证引导加载程序配置
    if [ "$BOOT_MODE" = "UEFI" ]; then
        if [ ! -d "/mnt/boot/loader" ]; then
            error_handler ${LINENO} 1 "UEFI bootloader installation failed"
        fi
    else
        if [ ! -f "/mnt/boot/grub/grub.cfg" ]; then
            error_handler ${LINENO} 1 "GRUB configuration file not found"
        fi
    fi
    
    log "INFO" "Installation verification completed"
}
