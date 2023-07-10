#!/bin/bash

# 如果有命令执行失败，立即停止脚本
set -e

# 当脚本退出时，打印错误消息
trap 'echo "脚本执行出错，请检查！"; exit 1' ERR


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
