#!/bin/bash
# Mount and format the extra disks
# UUID="2dca07e1-0cd4-4d0c-b109-bf0758603a79" /mnt/datastore      ext4 defaults,discard,nobarrier,nofail  0       0
sudo mkdir -p /datadisk1
sudo /usr/share/google/safe_format_and_mount -m "mkfs.ext4 -m 0 -F -E stripe-width=256,lazy_itable_init=0,lazy_journal_init=0,discard" /dev/sdb
sudo echo "Mount persists"
sudo sh -c "echo \"/dev/sdb   /datadisk1   ext4   defaults,discard,nobarrier,nofail   0 2\" >> /etc/fstab"
sudo mkdir -p /datadisk2
sudo /usr/share/google/safe_format_and_mount -m "mkfs.ext4 -m 0 -F -E stripe-width=256,lazy_itable_init=0,lazy_journal_init=0,discard" /dev/sdc
sudo echo "Mount persists"
sudo sh -c "echo \"/dev/sdc   /datadisk2   ext4   defaults,discard,nobarrier,nofail   0 2\" >> /etc/fstab"
sudo echo "fstab done"
