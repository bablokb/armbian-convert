#!/bin/bash
# --------------------------------------------------------------------------
# Convert Armbian-image from a single-filesystem image to a two-filesystem image.
#
# This script installs all necessary files.
#
# Author: Bernhard Bablok
# License: GPL3
#
# Website: https://github.com/bablokb/armbian-convert
#
# --------------------------------------------------------------------------

# usage message   -------------------------------------------------------------

usage() {
  local pgm=`basename $0`
  echo -e "\n$pgm: rewrite Armbian image to a two-partition system
  \nusage: `basename $0` [options] source-image\n\
  Possible options:\n\
    -o image    target-image (defaults to source.new.img)\n\
    -n dev-nr   configure system to use /dev/mmcblk<dev-nr>\n\
                (default: use heuristic)\n\
    -U          use UUIDs instead of partition-names\n\
    -k          keep extracted image\n\
    -h          show this help\n\
"
  exit 3
}

# set defaults   --------------------------------------------------------------

setDefaults() {
  removeImg=0
  useUUID=0
  targetImage=""
  devNr=""
}

# parse arguments and set variables -------------------------------------------

parseArguments() {
  while getopts ":o:n:Ukh" opt; do
    case $opt in
      o) targetImage="$OPTARG";;
      n) devNr="$OPTARG";;
      U) useUUID=1;;
      k) removeImg=2;;
      h) usage;;
      ?) echo "error: illegal option: $OPTARG"
           usage;;
    esac
  done

  shift $((OPTIND-1))
  srcImage="$1"
  if [ -z "$srcImage" ]; then
    echo -e "no image specified" >&2
    exit 3
  fi
}

# --- extract source image   -----------------------------------------

extractSourceImage() {
  if [ "${srcImage##*.}" = "7z" ]; then
    if ! type -p "7z" > /dev/null; then
      echo "error: you need to install program 7z to run this script!" >&2
      exit 3
    fi
    7z e '-i!*.img' -o${srcImage%/*} "$srcImage"
    srcImage="${srcImage%.*}.img"
    [ $removeImg -eq 0 ] && removeImg=1
  fi
  [ -z "$targetImage" ] && targetImage="${srcImage%.*}.new.img"
}

# --- query size of target-image   -----------------------------------

getSize() {
  # we just take the current size and add 100MB
  local currentSize
  currentSize=`stat -c "%s" "$srcImage"`
  let targetSize=currentSize+104857600

  # start of first partition
  firstSector=$(sfdisk -ql -o Start "srcImage" | sed -n 2p)
  firstSector=$(echo $firstSector)          # remove leading blanks
}

# --- create target image   ------------------------------------------

createTargetImage() {
  # take the first xxx sectors from source-image to pick up
  # the boot-loader
  dd if="$srcImage" of="$targetImage" bs=512 count=$firstSector
  
  # extend image to target-size
  dd if=/dev/zero of="$targetImage" bs=1 count=0 seek="$targetSize"
}

# --- partition target-image   ---------------------------------------

partitionTargetImage() {
  # create loop-device
  modprobe loop
  targetDevice=`losetup --show -f -P "$targetImage"`
  # delete existing partition, create two new ones
  let startSecond=$firstSector+204800
  echo -e "d\nn\np\n1\n$firstSector\n+204799\nn\np\n2\n$startSecond\n\nw\n" | fdisk "$targetDevice"
  sleep 3
  partprobe
  losetup -D "$targetDevice"
  
  # now format partitions
  targetDevice=`losetup --show -f -P "$targetImage"`
  mkfs.ext4  "${targetDevice}p1"
  mkfs.ext4 "${targetDevice}p2"

  if [ "$useUUID" -eq 1 ]; then
    targetUUIDp1=$(blkid -o export -s UUID "${targetDevice}p1" | \
                                        sed -ne "/UUID/s/UUID=//p")
    targetUUIDp2=$(blkid -o export -s UUID "${targetDevice}p2" | \
                                        sed -ne "/UUID/s/UUID=//p")
  fi
}

# --- mount source and target partitions   ---------------------------

mountPartitions() {
  # source
  srcDevice=`losetup --show -f -P "$srcImage"`
  srcMnt=`mktemp -d /tmp/armbian.XXXXX`
  mount "${srcDevice}p1" "$srcMnt"

  # target
  targetMnt=`mktemp -d /tmp/armbian.XXXXX`
  mount "${targetDevice}p2" "$targetMnt"
  mkdir -p  "$targetMnt/boot"
  mount "${targetDevice}p1" "$targetMnt/boot"
}

# --- copy files   ---------------------------------------------------

copyFiles() {
  rsync -aHAXS "$srcMnt/" "$targetMnt"
}

# --- fix values in boot-environment   -------------------------------

fixFiles() {
  if [ "$useUUID" -eq 1 ]; then
    rootdev="UUID=$targetUUIDp2"
  else
    # we need to set rootdev to mmcblk0p2 or mmcblk1p2
    if [ -z "$devNr" ]; then
      # use heuristics
      if grep -qi "odroid" <<< "$srcImage"; then
        rootdev="/dev/mmcblk1p2"                   # at least on HC1
      else
        rootdev="/dev/mmcblk0p2"
      fi
    else
      rootdev="/dev/mmcblk${devNr}p2"
    fi
  fi

  if [ -f "$targetMnt/boot/armbianEnv.txt" ]; then
    sed -i -e "/rootdev=/s,=.*,=$rootdev," "$targetMnt/boot/armbianEnv.txt"
  else
    echo "rootdev=$rootdev" > "$targetMnt/boot/armbianEnv.txt"
  fi

  # fix fstab
  sed -i  -e "/\W\/\W/s,^[^ \t]*,$rootdev," "$targetMnt/etc/fstab"
  if [ "$useUUID" -eq 1 ]; then
    cat >> "$targetMnt/etc/fstab" <<EOF
$targetUUIDp1 /boot   ext4 defaults,acl,user_xattr,noatime,nodiratime   1 2
EOF
  else
    cat >> "$targetMnt/etc/fstab" <<EOF
${rootdev:0:-1}1 /boot   ext4 defaults,acl,user_xattr,noatime,nodiratime   1 2
EOF
  fi
}

# --- umount partitions   --------------------------------------------

umountPartitions() {
  umount "${targetDevice}p1"
  umount "${targetDevice}p2" && rm -fr "$targetMnt"
  umount "$srcMnt" && rm -fr "$srcMnt"
}

# --- cleanup   ------------------------------------------------------

cleanup() {
  # remove loop-devices
  losetup -D "$srcDevice"
  losetup -D "$targetDevice"
  
  # remove temporary image
  if [ $removeImg -eq 1 ]; then
    # image-name not passed in as argument
    rm -f "$srcImage"
  fi
}

# --- main program   -------------------------------------------------

setDefaults
parseArguments "$@"
extractSourceImage
getSize
createTargetImage
partitionTargetImage
mountPartitions
copyFiles
fixFiles
umountPartitions
cleanup
