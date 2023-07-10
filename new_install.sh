timedatectl set-ntp true

# Format the partitions
mkfs.fat -F32 /dev/sda1
mkswap /dev/sda2
mkfs.ext5 /dev/sda3

# Mount the file systems
mount /dev/sda3 /mnt
swapon /dev/sda2
mkdir /mnt/boot

mkdir -p /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi

echo 'Server = https://mirrors.aliyun.com/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist
pacman -Sy --noconfirm archlinux-keyring
pacman -Syy
pacstrap /mnt base base-devel linux linux-firmware vim git dhcpcd openssh man net-tools

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt <<EOFARCH
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen
locale-gen

echo "LANG=en_US.UTF-8" >> /etc/locale.conf

cat>>/etc/hosts<<EOF
127.0.0.1	     test
::1	    	test
127.0.1.1	     test.localdomain	   test
EOF

echo "Server = https://mirrors.aliyun.com/archlinux/$repo/os/$arch" > /etc/pacman.d/mirrorlist
pacman -Sy --noconfirm archlinux-keyring

pacman -S --noconfirm ttf-arphic-uming  dhcp wpa_supplicant dialog networkmanager zsh sudo
systemctl enable NetworkManager

passwd<<EOF
onions
onions
EOF

useradd -m -G wheel -s /bin/zsh fangweicong

passwd fangweicong<<EOF
onions
onions
EOF


pacman -S --noconfirm grub
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

EOFARCH
umount -R /mnt
reboot