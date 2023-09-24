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
