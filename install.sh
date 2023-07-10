#!/bin/bash

# 如果有命令执行失败，立即停止脚本
# Update the system clock

timedatectl set-ntp true

# wipefs -a /dev/sda

# # Partition the disks
# echo -e "g\nn\n1\n\n+600M\nef00\nn\n2\n\n+10G\n8200\nn\n3\n\n\n\nw" | fdisk /dev/sda

# Format the partitions
mkfs.fat -F32 /dev/sda1
mkswap /dev/sda2
mkfs.ext5 /dev/sda3

# Mount the file systems
mount /dev/sda3 /mnt
swapon /dev/sda2
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot

# Install essential packages
pacstrap /mnt base linux linux-firmware vim net-tools wget curl

# Fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot
arch-chroot /mnt /bin/bash <<EOF

# Enable and start network service
systemctl enable dhcpcd
systemctl start dhcpcd

# Set the China mirror
echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist

# Update the system
pacman -Sy archlinux-keyring --noconfirm

# Time zone
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "myhostname" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 myhostname.localdomain myhostname" >> /etc/hosts

# Initramfs
mkinitcpio -P

# Root password
echo "root:password" | chpasswd

# Install bootloader
pacman -S grub efibootmgr --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=arch_grub --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# Install some common packages
pacman -S --noconfirm git base-devel

EOF

# Unmount
umount -R /mnt

# Reboot
reboot
