#!/bin/bash

[[ -x /etc/init.d/rebar_join.sh || \
    -x /etc/init.d/rebar_join || \
    -x /etc/init.d/rebar || \
    -x /usr/sbin/rebar ]] && exit 0

set -x
set +e

. /etc/profile.d/rebar-key.sh
if ! [[ -f /etc/rebar-uuid ]]; then
    echo "Must be run on a Sledgehammer that knows about node UUIDs"
    exit 1
fi

REBAR_UUID="$(cat /etc/rebar-uuid)"

# Nuke it all.
declare vg pv maj min blocks name
# Make sure that the kernel knows about all the partitions
for bd in /sys/block/sd*; do
    [[ -b /dev/${bd##*/} ]] || continue
    partprobe "/dev/${bd##*/}" || :
done
# Zap any volume groups that may be lying around.
vgscan --ignorelockingfailure -P
while read vg; do
    vgremove -f "$vg"
done < <(vgs --noheadings -o vg_name)
# Wipe out any LVM metadata that the kernel may have detected.
pvscan --ignorelockingfailure
while read pv; do
    pvremove -f -y "$pv"
done < <(pvs --noheadings -o pv_name)
# Now zap any partitions along with any RAID metadata that may exist.
while read maj min blocks name; do
    [[ -b /dev/$name && -w /dev/$name && $name != name ]] || continue
    [[ $name = loop* ]] && continue
    [[ $name = dm* ]] && continue
    mdadm --misc --zero-superblock --force /dev/$name
    if (( blocks >= 2048)); then
        dd "if=/dev/zero" "of=/dev/$name" "bs=512" "count=2048"
        dd "if=/dev/zero" "of=/dev/$name" "bs=512" "count=2048" "seek=$(($blocks - 2048))"
    else
        dd "if=/dev/zero" "of=/dev/$name" "bs=512" "count=$blocks"
    fi
done < <(tac /proc/partitions)

while ! rebar nodes get $REBAR_UUID attrib provisioner-active-bootstate |grep -q -- '-install'; do
    sleep 1
done

need_reboot
