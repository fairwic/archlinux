#!/bin/bash

set -euo pipefail

# Default start step
START_STEP=1

# Print help message
show_help() {
    echo "Arch Linux Installation Script"
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -s, --step NUMBER    Start from specific step (default: 1)"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Available steps:"
    echo "  1. Check network connectivity"
    echo "  2. Synchronize system time"
    echo "  3. Update mirror list"
    echo "  4. Select installation disk"
    echo "  5. Clean up disk"
    echo "  6. Partition disk"
    echo "  7. Format partitions"
    echo "  8. Install base system"

    echo "  9. Generate fstab"
    echo "  10. Configure system"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--step)
            START_STEP="$2"
            if ! [[ "$START_STEP" =~ ^[0-9]+$ ]] || [ "$START_STEP" -lt 1 ] || [ "$START_STEP" -gt 10 ]; then
                echo "Error: Step must be a number between 1 and 10"
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help to see available options"
            exit 1
            ;;
    esac
done

# Network connection check function
check_network() {
    echo "Step 1: Checking network connection..."
    if ! ping -c 1 baidu.com &>/dev/null; then
        echo "Error: Cannot connect to baidu.com"
        echo "Please check your network connection and ensure:"
        echo "1. Network cable is connected or WiFi is connected"
        echo "2. Use 'ip link' to check network interface status"
        echo "3. Use 'ip addr' to check if IP address is obtained"
        echo "4. Check if DNS settings are correct"
        exit 1
    fi
    echo "Network connection is OK!"
}

# Update system time
update_system_time() {
    echo "Step 2: Synchronizing system time..."
    timedatectl set-ntp true
    sleep 2
}

# Update mirror list with error handling
update_mirrorlist() {
    log "INFO" "Step 3: Updating mirror list..."
    # Backup original mirror list
    if ! cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup; then
        error_handler ${LINENO} 1 "Failed to backup mirror list"
    fi
    
    # Update mirror database
    if ! pacman -Sy --noconfirm archlinux-keyring; then
        error_handler ${LINENO} 1 "Failed to update archlinux-keyring"
    fi
    
    # Use reflector to select fastest mirrors, but only add to the beginning of the file
    if command -v reflector &>/dev/null; then
        log "INFO" "Using reflector to update mirrors (timeout: 30s)..."
        
        # Create temporary file to store new mirrors
        TEMP_MIRROR_FILE=$(mktemp)
        
        if timeout 30 reflector --country China --age 12 --protocol https --sort rate > "$TEMP_MIRROR_FILE"; then
            log "INFO" "Retrieved fastest mirrors for China region"
            
            # Add comment to mark newly added mirrors
            echo "# Mirrors added by reflector for China region ($(date '+%Y-%m-%d %H:%M:%S'))" > /etc/pacman.d/mirrorlist.new
            cat "$TEMP_MIRROR_FILE" >> /etc/pacman.d/mirrorlist.new
            echo "" >> /etc/pacman.d/mirrorlist.new
            echo "# Original mirror list" >> /etc/pacman.d/mirrorlist.new
            cat /etc/pacman.d/mirrorlist >> /etc/pacman.d/mirrorlist.new
            
            # Replace original mirror file
            mv /etc/pacman.d/mirrorlist.new /etc/pacman.d/mirrorlist
            log "INFO" "Added new mirrors to the beginning of the file"
        else
            log "WARNING" "Reflector timed out or failed, using default mirrors"
        fi
        
        # Clean up temporary file
        rm -f "$TEMP_MIRROR_FILE"
    else
        log "WARNING" "Reflector not installed, using default mirrors"
    fi
}

# Log function
log() {
    local level="$1"
    local message="$2"
    echo "[$level] $message"
}

# Error handler function
error_handler() {
    local line="$1"
    local exit_code="$2"
    local message="$3"
    log "ERROR" "Error at line $line: $message (exit code: $exit_code)"
    exit "$exit_code"
}

# Function to select installation disk
select_disk() {
    echo "Step 4: Selecting installation disk..."
    echo "Available disks:"
    echo "----------------"
    lsblk -d -e 7,11 -o NAME,SIZE,MODEL
    echo "----------------"
    
    # Get available disks
    mapfile -t disks < <(lsblk -d -e 7,11 -o NAME | tail -n +2)
    
    if [ ${#disks[@]} -eq 0 ]; then
        echo "Error: No available disks found"
        exit 1
    fi
    
    PS3="Please select the disk for installation (enter number): "
    select disk in "${disks[@]}"; do
        if [ -n "$disk" ]; then
            echo "You selected: /dev/$disk"
            echo "WARNING: All data on /dev/$disk will be erased!"
            read -p "Are you sure you want to continue? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                DISK="/dev/$disk"
                break
            else
                echo "Installation aborted by user"
                exit 1
            fi
        else
            echo "Invalid selection. Please try again."
        fi
    done
}

# 清理磁盘函数 - 确保所选磁盘上的所有分区都已卸载
cleanup_disk() {
    log "INFO" "Step 5: Cleaning up disk partitions on $DISK..."
    
    # 关闭所有 swap 分区
    log "INFO" "Turning off all swap partitions..."
    swapoff -a || true
    
    # 获取所选磁盘上的所有挂载点
    local mount_points=$(mount | grep "^$DISK" | awk '{print $3}' | sort -r)
    
    if [ -n "$mount_points" ]; then
        log "INFO" "Unmounting all mount points..."
        for mp in $mount_points; do
            log "INFO" "Unmounting $mp"
            umount -f "$mp" || true
        done
    fi
    
    # 如果 /mnt 下有任何挂载点，也需要卸载它们
    local mnt_mounts=$(mount | grep " /mnt" | sort -r)
    if [ -n "$mnt_mounts" ]; then
        log "INFO" "Unmounting mount points under /mnt..."
        umount -R /mnt || true
    fi
    
    # 确保没有进程在使用磁盘
    log "INFO" "Ensuring no processes are using the disk..."
    sync
    
    # 尝试释放设备
    log "INFO" "Attempting to release device..."
    blockdev --flushbufs "$DISK" || true
    
    log "INFO" "Disk cleanup completed"
}

# Set user-defined variables
set_variables() {
    # Default values (used when starting from later steps)
    # These will be overridden if user selects a disk
    DISK=${DISK:-"/dev/sda"}  # Default disk if not set
    HOSTNAME="fwc-arch"         # Hostname
    TIMEZONE="Asia/Shanghai"    # Timezone
    LANG="en_US.UTF-8"          # System language
    KEYMAP="us"                 # Keyboard layout
    ROOT_PASSWORD="onions"      # Root password (change immediately after installation)
    
    # Detect UEFI mode
    if [ -d "/sys/firmware/efi/efivars" ]; then
        BOOT_MODE="UEFI"
    else
        BOOT_MODE="BIOS"
    fi
    
    # Print selected configuration
    log "INFO" "Installation configuration:"
    log "INFO" "- Disk: $DISK"
    log "INFO" "- Boot mode: $BOOT_MODE"
    log "INFO" "- Hostname: $HOSTNAME"
    log "INFO" "- Timezone: $TIMEZONE"
    log "INFO" "- Language: $LANG"
    
    # Confirm if starting from a later step
    if [ "$START_STEP" -gt 4 ]; then
        read -p "You are starting from step $START_STEP with disk $DISK. Continue? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "INFO" "Installation aborted by user"
            exit 0
        fi
    fi
}

# Partition function
partition_disk() {
    log "INFO" "Step 6: Partitioning disk $DISK..."
    
    # Clear partition table
    parted -s $DISK mklabel gpt

    if [ "$BOOT_MODE" = "UEFI" ]; then
        # Create EFI partition (512MB)
        parted -s $DISK mkpart primary fat32 1MiB 513MiB
        parted -s $DISK set 1 esp on
        
        # Create swap partition (4GB)
        parted -s $DISK mkpart primary linux-swap 513MiB 4609MiB
        
        # Create root partition (remaining space)
        parted -s $DISK mkpart primary ext4 4609MiB 100%
    else
        # BIOS partition scheme
        # Create BIOS boot partition (1MB) for GRUB
        parted -s $DISK mkpart primary 1MiB 2MiB
        parted -s $DISK set 1 bios_grub on
        
        # Create swap partition (4GB)
        parted -s $DISK mkpart primary linux-swap 2MiB 4098MiB
        
        # Create root partition (remaining space)
        parted -s $DISK mkpart primary ext4 4098MiB 100%
        parted -s $DISK set 3 boot on
    fi
    
    # Wait a moment after partitioning to ensure the system recognizes new partitions
    log "INFO" "Waiting for system to recognize new partition layout..."
    sleep 3
}

# Format partitions
format_partitions() {
    log "INFO" "Step 7: Formatting partitions..."
    
    if [ "$BOOT_MODE" = "UEFI" ]; then
        mkfs.fat -F32 ${DISK}1
        mkswap ${DISK}2
        swapon ${DISK}2
        mkfs.ext4 ${DISK}3
        mount ${DISK}3 /mnt
        mkdir -p /mnt/boot
        mount ${DISK}1 /mnt/boot
    else
        # BIOS模式
        mkswap ${DISK}2
        swapon ${DISK}2
        mkfs.ext4 ${DISK}3
        mount ${DISK}3 /mnt
    fi
}

# Install base system
install_base() {
    log "INFO" "Step 8: Installing base system..."
    
    pacman -Sy --noconfirm archlinux-keyring
    # Add essential packages for hardware support and filesystem
    pacstrap /mnt base base-devel linux linux-firmware linux-headers vim networkmanager sudo \
        mkinitcpio udev lvm2 mdadm xfsprogs dosfstools e2fsprogs ntfs-3g efibootmgr grub
}

# Generate fstab
generate_fstab() {
    log "INFO" "Step 9: Generating fstab..."
    
    genfstab -U /mnt >> /mnt/etc/fstab
}

# Configure system
configure_system() {
    log "INFO" "Step 10: Configuring system..."
    
    arch-chroot /mnt /bin/bash <<EOF
    # Timezone setup
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc
    
    # Localization
    sed -i "s/#$LANG/$LANG/" /etc/locale.gen
    locale-gen
    echo "LANG=$LANG" > /etc/locale.conf
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
    
    # Network configuration
    echo $HOSTNAME > /etc/hostname
    cat > /etc/hosts <<EOL
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
EOL
    systemctl enable NetworkManager
    
    # Configure mkinitcpio - 增加更多必要的钩子
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard keymap consolefont filesystems fsck)/' /etc/mkinitcpio.conf
    
    # 确保MODULES中包含必要的硬盘控制器模块
    sed -i 's/^MODULES=.*/MODULES=(ahci sd_mod)/' /etc/mkinitcpio.conf
    
    # Regenerate initramfs
    mkinitcpio -P
    
    # Root password
    echo "root:$ROOT_PASSWORD" | chpasswd
    
    # Bootloader
    if [ "$BOOT_MODE" = "UEFI" ]; then
        # 安装并配置GRUB (UEFI模式)
        pacman -S --noconfirm efibootmgr grub
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
        
        # 更新GRUB配置
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3"/' /etc/default/grub
        grub-mkconfig -o /boot/grub/grub.cfg
    else
        # 安装并配置GRUB (BIOS模式)
        pacman -S --noconfirm grub
        grub-install --target=i386-pc $DISK
        
        # 更新GRUB配置
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3"/' /etc/default/grub
        grub-mkconfig -o /boot/grub/grub.cfg
    fi

    # Add user and sudo configuration
    useradd -m -G wheel -s /bin/bash fangweicong
    echo "fangweicong:$ROOT_PASSWORD" | chpasswd
    echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
    
    # Enable essential services
    systemctl enable systemd-modules-load
    systemctl enable systemd-udevd
EOF
}

# Cleanup after installation
cleanup_after_install() {
    log "INFO" "Cleaning up and unmounting..."
    umount -R /mnt || true
    swapoff -a || true
    log "INFO" "Installation complete! Please enter 'reboot' to restart the system"
}

# Main function to execute all steps
main() {
    log "INFO" "=== Arch Linux Installation Script ==="
    log "INFO" "Starting from step $START_STEP"
    
    # Step 1: Check network
    if [ "$START_STEP" -le 1 ]; then
        check_network
    else
        log "INFO" "Skipping step 1 (Check network)"
    fi
    
    # Step 2: Update system time
    if [ "$START_STEP" -le 2 ]; then
        update_system_time
    else
        log "INFO" "Skipping step 2 (Update system time)"
    fi
    
    # Step 3: Update mirror list
    if [ "$START_STEP" -le 3 ]; then
        update_mirrorlist
    else
        log "INFO" "Skipping step 3 (Update mirror list)"
    fi
    
    # Step 4: Select installation disk
    if [ "$START_STEP" -le 4 ]; then
        select_disk
    else
        log "INFO" "Skipping step 4 (Select installation disk)"
    fi
    
    # Set variables based on previous steps or defaults
    set_variables
    
    # Step 5: Clean up disk
    if [ "$START_STEP" -le 5 ]; then
        cleanup_disk
    else
        log "INFO" "Skipping step 5 (Clean up disk)"
    fi
    
    # Step 6: Partition disk
    if [ "$START_STEP" -le 6 ]; then
        partition_disk
    else
        log "INFO" "Skipping step 6 (Partition disk)"
    fi
    
    # Step 7: Format partitions
    if [ "$START_STEP" -le 7 ]; then
        format_partitions
    else
        log "INFO" "Skipping step 7 (Format partitions)"
    fi
    
    # Step 8: Install base system
    if [ "$START_STEP" -le 8 ]; then
        install_base
    else
        log "INFO" "Skipping step 8 (Install base system)"
    fi
    
    # Step 9: Generate fstab
    if [ "$START_STEP" -le 9 ]; then
        generate_fstab
    else
        log "INFO" "Skipping step 9 (Generate fstab)"
    fi
    
    # Step 10: Configure system
    if [ "$START_STEP" -le 10 ]; then
        configure_system
    else
        log "INFO" "Skipping step 10 (Configure system)"
    fi
    
    # Cleanup after installation
    cleanup_after_install
}

# Run the main function
main
