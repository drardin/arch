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

# MOUNTING TARGET FILESYSTEM
mount /dev/lvg0/rootvol /mnt
mkdir /mnt/home
mount /dev/lvg0/homevol /mnt/home

# GENERATE FSTAB FILE
mkdir /mnt/etc
genfstab -U -p /mnt >> /mnt/etc/fstab

# MAIN INSTALL
pacstrap /mnt
arch-chroot /mnt /bin/bash <<EOF
echo -e '1\n' | pacman -S linux linux-headers linux-lts linux-lts-headers
echo -e '1\n' | pacman -S base-devel openssh sudo nano vi networkmanager wpa_supplicant wireless_tools netctl dialog gzip which
systemctl enable NetworkManager
systemctl enable sshd
pacman -Sy lvm2
sed -i '/^HOOKS=/ s/^\(#*\)HOOKS=(.*$/HOOKS=\2 lvm2/' "/etc/mkinitcpio.conf"
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
read -s -p "Enter the root user's password: " root_password
echo
echo "root:$root_password" | chpasswd

# SET USER'S NAME AND PASSWORD
read -p "Enter the username for the admin user: " admin_username
read -s -p "Enter the password for the admin user: " admin_password
echo
useradd -m "$admin_username"
echo "$admin_username:$admin_password" | chpasswd

# SET USER'S GROUPS
useradd -m -g users -G wheel $admin_username

if grep -q "$admin_username" /etc/sudoers; then
    echo "User $admin_username is already in the sudoers file."
else
    # Add the user to the sudoers file
    echo "$admin_username ALL=(ALL) ALL" | tee -a /etc/sudoers
    echo "User $admin_username added to the sudoers file."
fi

# DISABLE ROOT USER
usermod -L root
EOF
