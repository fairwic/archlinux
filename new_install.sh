timedatectl set-ntp true

fdisk /dev/sda <<EOF
n
p
1

+600M
n
p
2

+10G
n
p
3

+50G
n
p

+30G
w
EOF

mkfs.vfat -F32 /dev/sda1
mkswap /dev/sda2
swapon /dev/sda2
mkfs.ext4 /dev/sda3
mkfs.ext4 /dev/sda4

mount /dev/sda3 /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot
mkdir /mnt/home
mount /dev/sda4 /mnt/home

pacman -Syy

pacstrap /mnt base linux linux-firmware vim git

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

pacman -S --noconfirm dhcp wpa_supplicant dialog networkmanager zsh sudo
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