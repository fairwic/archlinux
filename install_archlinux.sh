#!/bin/bash
set -euo pipefail

# Network connection check function
check_network() {
    echo "Checking network connection..."
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
    echo "Synchronizing system time..."
    timedatectl set-ntp true
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
    
    # Use reflector to select fastest mirrors with timeout
    if command -v reflector &>/dev/null; then
        log "INFO" "Using reflector to update mirrors (timeout: 30s)..."
        if ! timeout 3 reflector --country China --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist; then
            log "WARNING" "Reflector timed out or failed, using default mirrors"
        fi
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

# Execute network check and updates
check_network
update_system_time
update_mirrorlist

# Select installation disk
select_disk

# User-defined variables
# DISK is now set by select_disk function
HOSTNAME="fwc-arch"         # Hostname
TIMEZONE="Asia/Shanghai"     # Timezone
LANG="en_US.UTF-8"          # System language
KEYMAP="us"                 # Keyboard layout
ROOT_PASSWORD="onions"      # Root password (change immediately after installation)

# Detect UEFI mode
if [ -d "/sys/firmware/efi/efivars" ]; then
  BOOT_MODE="UEFI"
  PARTITION_SCRIPT="efi_partition"
else
  BOOT_MODE="BIOS"
  PARTITION_SCRIPT="bios_partition"
fi

# Partition function
partition_disk() {
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
}

# Format partitions
format_partitions() {
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
  pacman -Sy --noconfirm archlinux-keyring
  # Add essential packages for hardware support and filesystem
  pacstrap /mnt base base-devel linux linux-firmware linux-headers vim networkmanager sudo \
    mkinitcpio udev lvm2 mdadm xfsprogs dosfstools e2fsprogs ntfs-3g efibootmgr grub
}

# Generate fstab
generate_fstab() {
  genfstab -U /mnt >> /mnt/etc/fstab
}

# Configure system
configure_system() {
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

# Execute installation process
echo "Starting partitioning..."
partition_disk
echo "Formatting partitions..."
format_partitions
echo "Installing base system..."
install_base
echo "Generating fstab..."
generate_fstab
echo "Configuring system..."
configure_system

# Cleanup and unmount
umount -R /mnt
swapoff -a

echo "Installation complete! Please enter 'reboot' to restart the system"
