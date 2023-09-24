#!/bin/bash

# Prompt user to set variables
read -p "Enter the target device (e.g., /dev/vda): " target_device
read -p "Enter the size of the primary partition (e.g., +200G): " partition_size
read -p "Enter the size of the root logical volume (e.g., +10G): " rootvol_size

# Create boot/EFI partition using sed
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk "$target_device"
  n  # Create a new partition
  p  # Primary partition
  1  # Partition number 1
     # Accept the default first sector
  +512M  # Set the partition size to 512MB
  t  # Change partition type
  1  # Select partition 1
  1  # Set it as EFI System (EF00)
  w  # Write changes and exit
EOF

# Create primary partition for LVM using sed
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk "$target_device"
  n  # Create a new partition
  p  # Primary partition
  2  # Partition number 2
     # Accept the default first sector
  $partition_size  # Set the partition size
  t  # Change partition type
  2  # Select partition 2
  20  # Set it as Linux LVM (8e00)
  w  # Write changes and exit
EOF

# Display partition table info
fdisk -l "$target_device"

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
