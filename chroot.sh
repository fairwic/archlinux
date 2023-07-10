
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

# Root 密码
echo "root:password" | chpasswd

# Install bootloader
pacman -S grub efibootmgr --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=arch_grub --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# Install some common packages
pacman -S --noconfirm git base-devel

exit
