#!/bin/bash
set -euo pipefail

# 检查网络连接函数
check_network() {
    echo "正在检查网络连接..."
    if ! ping -c 1 archlinux.org &>/dev/null; then
        echo "错误：无法连接到 archlinux.org"
        echo "请检查您的网络连接并确保："
        echo "1. 网线已正确连接或WiFi已连接"
        echo "2. 使用 ip link 检查网络接口状态"
        echo "3. 使用 ip addr 检查是否获取到IP地址"
        echo "4. 检查DNS设置是否正确"
        exit 1
    fi
    echo "网络连接正常！"
}

# 更新系统时间
update_system_time() {
    echo "正在同步系统时间..."
    timedatectl set-ntp true
    sleep 2
}

# 更新镜像源
update_mirrorlist() {
    echo "正在更新镜像源..."
    # 备份原有镜像源
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
    
    # 更新镜像源数据库
    if ! pacman -Sy --noconfirm archlinux-keyring; then
        echo "错误：无法更新镜像源"
        exit 1
    fi
    
    # 使用reflector选择最快的镜像源（如果已安装）
    if command -v reflector &>/dev/null; then
        reflector --country China --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    fi
}

# 执行网络检查和更新
check_network
update_system_time
update_mirrorlist

# 需要用户自定义的变量
DISK="/dev/sda"              # 安装磁盘（根据实际情况修改）
HOSTNAME="archlinux"         # 主机名
TIMEZONE="Asia/Shanghai"     # 时区
LANG="en_US.UTF-8"           # 系统语言
KEYMAP="us"                  # 键盘布局
ROOT_PASSWORD="onions"       # root密码（安装后请立即修改）

# 检测UEFI模式
if [ -d "/sys/firmware/efi/efivars" ]; then
  BOOT_MODE="UEFI"
  PARTITION_SCRIPT="efi_partition"
else
  BOOT_MODE="BIOS"
  PARTITION_SCRIPT="bios_partition"
fi

# 分区函数
partition_disk() {
  # 清除分区表
  parted -s $DISK mklabel gpt

  if [ "$BOOT_MODE" = "UEFI" ]; then
    # 创建EFI分区 (512MB)
    parted -s $DISK mkpart primary fat32 1MiB 513MiB
    parted -s $DISK set 1 esp on
    
    # 创建交换分区 (4GB)
    parted -s $DISK mkpart primary linux-swap 513MiB 4609MiB
    
    # 创建根分区 (剩余空间)
    parted -s $DISK mkpart primary ext4 4609MiB 100%
  else
    # BIOS模式分区方案
    parted -s $DISK mkpart primary ext4 1MiB 100%
    parted -s $DISK set 1 boot on
  fi
}

# 格式化分区
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

# 安装基本系统
install_base() {
  pacman -Sy --noconfirm archlinux-keyring
  pacstrap /mnt base base-devel linux linux-firmware linux-headers vim networkmanager sudo
}

# 生成fstab
generate_fstab() {
  genfstab -U /mnt >> /mnt/etc/fstab
}

# chroot配置
configure_system() {
  arch-chroot /mnt /bin/bash <<EOF
  # 时区设置
  ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
  hwclock --systohc
  
  # 本地化配置
  sed -i "s/#$LANG/$LANG/" /etc/locale.gen
  locale-gen
  echo "LANG=$LANG" > /etc/locale.conf
  echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
  
  # 网络配置
  echo $HOSTNAME > /etc/hostname
  systemctl enable NetworkManager
  
  # root密码
  echo "root:$ROOT_PASSWORD" | chpasswd
  
  # 引导程序
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

  # 添加用户
  useradd -m -G wheel -s /bin/bash fangweicong
  echo "fangweicong:$ROOT_PASSWORD" | chpasswd
EOF
}

# 执行安装流程
echo "开始分区..."
partition_disk
echo "格式化分区..."
format_partitions
echo "安装基本系统..."
install_base
echo "生成fstab..."
generate_fstab
echo "系统配置..."
configure_system

# 清理卸载
umount -R /mnt
swapoff -a

echo "安装完成！请输入 reboot 重启系统"
