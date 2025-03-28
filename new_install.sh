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

# Update mirror list
update_mirrorlist() {
    echo "Updating mirror list..."
    # Backup original mirror list
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
    
    # Update mirror database
    if ! pacman -Sy --noconfirm archlinux-keyring; then
        echo "Error: Cannot update mirror list"
        exit 1
    fi
    
    # Use reflector to select fastest mirrors (if installed)
    if command -v reflector &>/dev/null; then
        reflector --country China --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    fi
}

# Execute network check and updates
check_network
update_system_time
update_mirrorlist

# User-defined variables
DISK="/dev/sda"              # Installation disk (modify according to actual situation)
HOSTNAME="archlinux"         # Hostname
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
    parted -s $DISK mkpart primary ext4 1MiB 100%
    parted -s $DISK set 1 boot on
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
    mkfs.ext4 ${DISK}1
    mount ${DISK}1 /mnt
  fi
}

# Install base system
install_base() {
  pacman -Sy --noconfirm archlinux-keyring
  pacstrap /mnt base base-devel linux linux-firmware linux-headers vim networkmanager sudo
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
  systemctl enable NetworkManager
  
  # Root password
  echo "root:$ROOT_PASSWORD" | chpasswd
  
  # Bootloader
  if [ "$BOOT_MODE" = "UEFI" ]; then
    bootctl install
    echo "default arch" > /boot/loader/loader.conf
    echo "timeout 3" >> /boot/loader/loader.conf
    echo "title Arch Linux" > /boot/loader/entries/arch.conf
    echo "linux /vmlinuz-linux" >> /boot/loader/entries/arch.conf
    echo "initrd /initramfs-linux.img" >> /boot/loader/entries/arch.conf
    echo "options root=$(blkid -s UUID -o value ${DISK}3) rw" >> /boot/loader/entries/arch.conf
  else
    pacman -S --noconfirm grub
    grub-install $DISK
    grub-mkconfig -o /boot/grub/grub.cfg
  fi

  # Add user
  useradd -m -G wheel -s /bin/bash fangweicong
  echo "fangweicong:$ROOT_PASSWORD" | chpasswd
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
