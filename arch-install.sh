#!/bin/bash

# List available devices
fdisk -l

# Prompt user to set variables
echo ""
read -p "Enter the target device (e.g., /dev/vda): " target_device
read -p "Enter the size of the root logical volume (e.g., +10G): " rootvol_size

# Create boot/EFI partition using sed
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

echo "Line 31: Press Enter to continue..."
read

# Set up LVM
pvcreate --dataalignment 1m "$target_device"2

# Create a logical volume group
vgcreate lvg0 "$target_device"2

# Create logical volumes
lvcreate -L "$rootvol_size" lvg0 -n rootvol
lvcreate -l 100%FREE lvg0 -n homevol

# Load the dm_mod kernel module
modprobe dm_mod

# Scan for volume groups
vgscan

# Activate volume group
vgchange -ay

# DISK FORMATTING
mkfs.fat -F32 "$target_device"1
mkfs.ext4 /dev/lvg0/rootvol
mkfs.ext4 /dev/lvg0/homevol

echo "Line 58: Press Enter to continue..."
read

# MOUNTING TARGET FILESYSTEM
mount /dev/lvg0/rootvol /mnt
mkdir /mnt/home
mount /dev/lvg0/homevol /mnt/home

echo "Line 66: Press Enter to continue..."
read

# GENERATE FSTAB FILE
mkdir /mnt/etc
genfstab -U -p /mnt >> /mnt/etc/fstab

echo "Line 73: Press Enter to continue..."
read

# MAIN INSTALL
pacstrap /mnt

echo "Line 79: Press Enter to continue..."
read

read -s -p "Enter a password to set for root user: " root_password
read -p "Enter the username for the admin user: " admin_username

while true; do
    read -s -p "Enter the password for the admin user: " admin_password
    echo
    read -s -p "Confirm the password: " confirm_password
    echo
    if [ "$admin_password" = "$confirm_password" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

read -p "Enter a hostname: " hostname

arch-chroot /mnt /bin/bash <<EOF
echo -e '1\n' | pacman -Sy linux linux-headers linux-lts linux-lts-headers
echo -e '1\n' | pacman -Sy base-devel openssh sudo nano vi networkmanager wpa_supplicant wireless_tools netctl dialog gzip which lvm2
systemctl enable NetworkManager
systemctl enable sshd
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


# DISABLE ROOT USER
usermod -L root

#BOOTLOADER CONFIGURATION
pacman -Sy grub dosfstools os-prober mtools efibootmgr
mkdir /boot/efi
mount "$target_device"1 /boot/efi
grub-install --target=x86_64-efi --bootloader-id=UEFI --recheck
cp /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo
grub-mkconfig -o /boot/grub/grub.cfg

#SETTING DATE AND TIME
timedatectl set-timezone America/Dallas
systemctl enable systemd-timesyncd
hostnamectl set-hostname $hostname
echo "127.0.0.1 localhost" | tee -a /etc/hosts
echo "::1 localhost ip6-localhost ip6-loopback" | tee -a /etc/hosts
echo "127.0.0.1 $hostname" | tee -a /etc/hosts

#INSTALLING MICROCODE AND DESKTOP ENVIRONMENT
pacman -Sy amd-ucode
pacman -Sy wayland
pacman -Sy virtualbox-guest-utils xf86-video-vmware systemctl enable vboxservice
pacman -Sy gnome gnome-tweaks
systemctl enable gdm
EOF
reboot now
