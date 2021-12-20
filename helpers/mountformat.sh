#!/bin/bash
# Mount and format the extra disks
# UUID="2dca07e1-0cd4-4d0c-b109-bf0758603a79" /mnt/datastore      ext4 defaults,discard,nobarrier,nofail  0       0
# google_compute_instance.db (remote-exec): /usr/share/google/safe_format_and_mount [-f fsck_cmd] [-m mkfs_cmd] [-o mount_opts] <device> <mountpoint>
#google_compute_instance.db (remote-exec): Mount persists
#google_compute_instance.db (remote-exec): /usr/share/google/safe_format_and_mount [-f fsck_cmd] [-m mkfs_cmd] [-o mount_opts] <device> <mountpoint>
#google_compute_instance.db (remote-exec): Mount persists


# disk 1
echo "Setting up disks"

mkdir -p /datadisk1
/usr/local/bin/safe_format_and_mount -m "mkfs.ext4 -m 0 -F -E stripe-width=256,lazy_itable_init=0,lazy_journal_init=0,discard" /dev/sdb /datadisk1
umount /datadisk1
UUID=`sudo blkid -s UUID -o value /dev/sdb`
sh -c "echo \"UUID=${UUID}   /datadisk1   ext4   defaults,discard,nobarrier,nofail   0 2\" >> /etc/fstab"

# disk 2
mkdir -p /datadisk2
/usr/local/bin/safe_format_and_mount -m "mkfs.ext4 -m 0 -F -E stripe-width=256,lazy_itable_init=0,lazy_journal_init=0,discard" /dev/sdc /datadisk2
umount /datadisk2
UUID=`sudo blkid -s UUID -o value /dev/sdc`

sh -c "echo \"UUID=${UUID}   /datadisk2   ext4   defaults,discard,nobarrier,nofail   0 2\" >> /etc/fstab"

echo "mounting with UUID"
mount /datadisk1
mount /datadisk2
