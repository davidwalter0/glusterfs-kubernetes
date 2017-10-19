#!/usr/bin/dumb-init /bin/sh
systemctl stop glusterd
systemctl stop glustereventsd
systemctl stop rpcbind
systemctl disable glusterd
systemctl disable glustereventsd
systemctl disable rpcbind

mkdir -p ${GLUSTER_MOUNTPOINT}
mount -t glusterfs ${GLUSTER_VOLUME_SERVER}:/${GLUSTER_VOLUMEID} ${GLUSTER_MOUNTPOINT}
sleep 5

MOUNTS=`mount | grep glusterfs`

exec /lib/systemd/systemd

MOUNTS=`mount | grep glusterfs`
if [ -z "${MOUNTS}" ]; then
    exit;
fi
tail -f /dev/null
