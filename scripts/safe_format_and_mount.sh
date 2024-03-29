#! /bin/bash
# Copyright 2013 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# Mount a disk, formatting it if necessary.  If the disk looks like it may
# have been formatted before, we will not format it.
#
# This script uses blkid and file to search for magic "formatted" bytes
# at the beginning of the disk.  Furthermore, it attempts to use fsck to
# repair the filesystem before formatting it.
FSCK=fsck.ext4
MOUNT_OPTIONS="discard,defaults"
MKFS="mkfs.ext4 -E lazy_itable_init=0,lazy_journal_init=0 -F"
if [ -f /etc/redhat-release ]; then
  if grep -q '6\..' /etc/redhat-release; then
    # lazy_journal_init is not recognized in redhat 6
    MKFS="mkfs.ext4 -E lazy_itable_init=0 -F"
  elif grep -q '7\..' /etc/redhat-release; then
    FSCK=fsck.xfs
    MKFS=mkfs.xfs
  fi
fi
LOGTAG=safe_format_and_mount
LOGFACILITY=user
function log() {
  local readonly severity=$1; shift;
  logger -t ${LOGTAG} -p ${LOGFACILITY}.${severity} -s "$@"
}
function log_command() {
  local readonly log_file=$(mktemp)
  local readonly retcode
  log info "Running: $*"
  $* > ${log_file} 2>&1
  retcode=$?
  # only return the last 1000 lines of the logfile, just in case it's HUGE.
  tail -1000 ${log_file} | logger -t ${LOGTAG} -p ${LOGFACILITY}.info -s
  rm -f ${log_file}
  return ${retcode}
}
function help() {
  cat >&2 <<EOF
$0 [-f fsck_cmd] [-m mkfs_cmd] [-o mount_opts] <device> <mountpoint>
EOF
  exit 0
}
while getopts ":hf:o:m:" opt; do
  case $opt in
    h) help;;
    f) FSCK=$OPTARG;;
    o) MOUNT_OPTIONS=$OPTARG;;
    m) MKFS=$OPTARG;;
    -) break;;
    \?) log error "Invalid option: -${OPTARG}"; exit 1;;
    :) log "Option -${OPTARG} requires an argument."; exit 1;;
  esac
done

shift $(($OPTIND - 1))
readonly DISK=$1
readonly MOUNTPOINT=$2

[[ -z ${DISK} ]] && help
[[ -z ${MOUNTPOINT} ]] && help

function disk_looks_unformatted() {
  blkid ${DISK}
  if [[ $? == 0 ]]; then
    return 0
  fi

  local readonly file_type=$(file --special-files ${DISK})
  case ${file_type} in
    *filesystem*)
      return 0;;
  esac

  return 1
}

function format_disk() {
  log_command ${MKFS} ${DISK}
}

function try_repair_disk() {
  log_command ${FSCK} -a ${DISK}
  local readonly fsck_return=$?
  if [[ ${fsck_return} -ge 8 ]]; then
    log error "Fsck could not correct errors on ${DISK}"
    return 1
  fi
  if [[ ${fsck_return} -gt 0 ]]; then
    log warning "Fsck corrected errors on ${DISK}"
  fi
  return 0
}

function try_mount() {
  local mount_retcode
  try_repair_disk

  log_command mount -o ${MOUNT_OPTIONS} ${DISK} ${MOUNTPOINT}
  mount_retcode=$?
  if [[ ${mount_retcode} == 0 ]]; then
    return 0
  fi

  # Check to see if it looks like a filesystem before formatting it.
  disk_looks_unformatted ${DISK}
  if [[ $? == 0 ]]; then
    log error "Disk ${DISK} looks formatted but won't mount.  Giving up."
    return ${mount_retcode}
  fi

  # The disk looks like it's not been formatted before.
  format_disk
  if [[ $? != 0 ]]; then
    log error "Format of ${DISK} failed."
  fi

  log_command mount -o ${MOUNT_OPTIONS} ${DISK} ${MOUNTPOINT}
  mount_retcode=$?
  if [[ ${mount_retcode} == 0 ]]; then
    return 0
  fi
  log error "Tried everything we could, but could not mount ${DISK}."
  return ${mount_retcode}
}

log warn "====================================================================="
log warn "WARNING: safe_format_and_mount is deprecated."
log warn "See https://cloud.google.com/compute/docs/disks/persistent-disks"
log warn "for additional instructions."
log warn "====================================================================="
try_mount
exit $?