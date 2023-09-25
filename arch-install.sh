#!/bin/bash
# This script sets up Arch Linux with support for Logical Volume Groups on UEFI-based systems
# It only creates two partitions, an EFI System partition and a primary LVM partition
# The LVM partition uses Logical Volume Groups for the root and home volumes
# These volumes are auto mounted on startup and this is set up automatically
# Adapt this script to add additional functionality, like creating additional Logical Volume Groups
# This script works as-is for QEMU/KVM installs, assuming a VirtIO disk type

echo "!!!WARNING!!! - This script can be destructive to connected drives"
echo
echo "########## USER SETUP ##########"
# SET ROOT USER AND ADMIN USER
#ROOT USER
while true; do
    read -s -p "Set password for root user: " root_password
    echo
    read -s -p "Confirm the password: " root_confirm_password
    echo
    if [ "$root_password" = "$root_confirm_password" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done
#ADMIN USER
read -p "Enter the username for the admin user: " admin_username
while true; do
    read -s -p "Enter the password for the $admin_username: " admin_password
    echo
    read -s -p "Confirm the password: " admin_confirm_password
    echo
    if [ "$admin_password" = "$admin_confirm_password" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

echo "########## TARGET HOST SETUP ##########"
#SET HOSTNAME VARIABLE
read -p "Specify a hostname: " hostname

#SET TIMEZONE VARIABLE
read -p "Specify a timezone (e.g., America/Dallas): " timezone

#SET CPU_MICROCODE VARIABLE
read -p "Specify which CPU Microcode to install (Intel/AMD): " cpu_microcode
cpu_microcode="${cpu_microcode,,}"  # Convert input to lowercase
selected_cpu_microcode=""
case "$cpu_microcode" in
    "intel")
        selected_cpu_microcode="intel"
        ;;
    "amd")
        selected_cpu_microcode="amd"
        ;;
    *)
        echo "Invalid selection. Please choose 'Intel' or 'AMD'."
esac

#SET DISPLAY SERVER VARIABLE
read -p "Select a display server (X11/Wayland): " display_server
display_server="${display_server,,}"  # Convert input to lowercase
selected_display_server=""
case "$display_server" in
    "x11")
        selected_display_server="x11"
        ;;
    "wayland")
        selected_display_server="wayland"
        ;;
    *)
        echo "Invalid selection. Please choose 'X11' or 'Wayland'."
        ;;
esac

#SET VIDEO DRIVER VARIABLE
read -p "Select a video driver (AMD/NVIDIA/Intel/Virtual): " video_driver
video_driver="${video_driver,,}"  # Convert input to lowercase
selected_video_driver=""
case "$video_driver" in
    "amd")
        selected_video_driver="amd"
        ;;
    "nvidia")
        selected_video_driver="nvidia"
        ;;
    "intel")
        selected_video_driver="intel"
        ;;
    "virtual")
        selected_video_driver="virtual"
        ;;
    *)
        echo "Invalid selection. Please choose 'AMD', 'NVIDIA', 'Intel', or 'Virtual'."
        ;;
esac

read -p "Select a desktop environment (Gnome/KDE/XFCE/Mate): " desktop_environment
desktop_environment="${desktop_environment,,}"  # Convert input to lowercase
selected_desktop_environment=""
case "$desktop_environment" in
    "gnome")
        selected_desktop_environment="gnome"
        ;;
    "kde")
        selected_desktop_environment="kde"
        ;;
    "xfce")
        selected_desktop_environment="xfce"
        ;;
    "mate")
        selected_desktop_environment="mate"
        ;;
    *)
        echo "Invalid selection. Please choose 'Gnome', 'KDE', 'XFCE', or 'Mate'."
        ;;
esac

# List available devices
fdisk -l

# SET DISK VARIABLES
echo
read -p "Enter the target disk to install to (e.g., /dev/vda): " target_device
read -p "Enter the size of the root logical volume (e.g., +10G): " rootvol_size

# Create boot/EFI partition
# These selections are hardcoded and lack logic that may be necessary for other disk types
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk "$target_device"
  g  # Create a GPT partition table
  n  # Create a new partition
  1  # Partition number 1
     # Accept the default first sector
  +512M  # Set the partition size to 512MB
  t  # Change partition type
  uefi  # Set it as EFI System
  n  # Create a new partition
  2  # Partition number 2
     # Accept the default first sector
     # Accept the default first sector
  t  # Change partition type
  2  # Select partition 2
  lvm  # Set it as Linux LVM
  p  # Display partition table
  w  # Write changes and exit
EOF

# Set up LVM
pvcreate --dataalignment 1m "$target_device"2
vgcreate lvg0 "$target_device"2
lvcreate -L "$rootvol_size" lvg0 -n rootvol
lvcreate -l 100%FREE lvg0 -n homevol
modprobe dm_mod
vgscan
vgchange -ay

# DISK FORMATTING
mkfs.fat -F32 "$target_device"1
mkfs.ext4 /dev/lvg0/rootvol
mkfs.ext4 /dev/lvg0/homevol

# MOUNTING TARGET FILESYSTEM
mount /dev/lvg0/rootvol /mnt
mkdir /mnt/home
mount /dev/lvg0/homevol /mnt/home

# GENERATE FSTAB FILE
mkdir /mnt/etc
genfstab -U -p /mnt >> /mnt/etc/fstab

# MAIN INSTALL
pacstrap /mnt

# SETUP INSTALL ENVIRONMENT
arch-chroot /mnt /bin/bash <<EOF
echo -e '1\n' | pacman -S --noconfirm linux linux-headers linux-lts linux-lts-headers
echo -e '1\n' | pacman -S --noconfirm base-devel openssh sudo nano vi networkmanager wpa_supplicant wireless_tools netctl dialog gzip which lvm2
sed -i '/^HOOKS=/ s/\(.*\))/\1 lvm2)/' /etc/mkinitcpio.conf
mkinitcpio -p linux
mkinitcpio -p linux-lts

locale_to_allow="en_US.UTF-8 UTF-8"
if grep -q "^# *$locale_to_allow" "/etc/locale.gen"; then
    sed -i "s/^# *$locale_to_allow/$locale_to_uncomment/" "/etc/locale.gen"
    echo "Uncommented $locale_to_allow in /etc/locale.gen"
else
    echo "The locale $locale_to_allow is already uncommented or not found in /etc/locale.gen"
fi
locale-gen

# SET ROOT USER PASSWORD
echo "root:$root_password" | chpasswd

# SET USER'S NAME AND PASSWORD
useradd -m "$admin_username"
echo "$admin_username:$admin_password" | chpasswd

# SET USER'S GROUPS AND ADD TO SUDOERS FILE
useradd -m -g users -G wheel $admin_username
echo "$admin_username ALL=(ALL) ALL" | tee -a /etc/sudoers

#BOOTLOADER CONFIGURATION
pacman -S --noconfirm grub dosfstools os-prober mtools efibootmgr
mkdir /boot/efi
mount "$target_device"1 /boot/efi
grub-install --target=x86_64-efi --bootloader-id=UEFI --recheck
cp /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo
grub-mkconfig -o /boot/grub/grub.cfg

#SETTING DATE AND TIME
timedatectl set-timezone $timezone
hostnamectl set-hostname $hostname
echo "127.0.0.1 localhost" | tee -a /etc/hosts
echo "::1 localhost ip6-localhost ip6-loopback" | tee -a /etc/hosts
echo "127.0.0.1 $hostname" | tee -a /etc/hosts

#INSTALLING MICROCODE AND DESKTOP ENVIRONMENT
if [ "$selected_cpu_microcode" = "intel" ]; then
    pacman -S --noconfirm intel-ucode
elif [ "$selected_cpu_microcode" = "amd" ]; then
    pacman -S --noconfirm amd-ucode
fi

if [ "$selected_display_server" = "x11" ]; then
    pacman -S --noconfirm xorg-server
elif [ "$selected_display_server" = "wayland" ]; then
    pacman -S --noconfirm wayland
fi

if [ "$selected_video_driver" = "amd" ]; then
    pacman -S --noconfirm mesa xf86-video-amdgpu
elif [ "$selected_video_driver" = "nvidia" ]; then
    pacman -S --noconfirm nvidia nvidia-lts
elif [ "$selected_video_driver" = "intel" ]; then
    pacman -S --noconfirm mesa xf86-video-intel
elif [ "$selected_video_driver" = "virtual" ]; then
    pacman -S --noconfirm virtualbox-guest-utils xf86-video-vmware
fi

if [ "$selected_desktop_environment" = "gnome" ]; then
    pacman -S --noconfirm gnome gnome-tweaks
    systemctl enable gdm
elif [ "$selected_desktop_environment" = "kde" ]; then
    pacman -S --noconfirm plasma-meta kde-applications
    pacman -S --noconfirm sddm
    systemctl enable sddm
elif [ "$selected_desktop_environment" = "xfce" ]; then
    pacman -S --noconfirm xfce4 xfce4-goodies
    pacman -S --noconfirm lightdm
    systemctl enable lightdm
elif [ "$selected_desktop_environment" = "mate" ]; then
    pacman -S --noconfirm mate mate-extra
    pacman -S --noconfirm lightdm
    systemctl enable lightdm
fi

#ENABLE SERVICES
systemctl enable systemd-timesyncd
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable vboxservice

# DISABLE ROOT USER
usermod -L root
EOF

#REBOOT SYSTEM
reboot now
