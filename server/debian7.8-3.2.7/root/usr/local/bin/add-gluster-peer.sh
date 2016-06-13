#!/bin/bash

# Exit status = 0 means the peer was successfully joined
# Exit status = 1 means there was an error while joining the peer to the cluster

set -e

PEER=$1

if [ -z "${PEER}" ]; then
   echo "=> ERROR: I was supposed to add a new gluster peer to the cluster but no IP was specified, doing nothing ..."
   exit 1
fi

GLUSTER_CONF_FLAG=/etc/gluster.env
SEMAPHORE_FILE=/tmp/adding-gluster-node.${PEER}
SEMAPHORE_TIMEOUT=120
source ${GLUSTER_CONF_FLAG}

function echo() {
   builtin echo $(basename $0): [From container ${MY_IP}] $1
}

function detach() {
   echo "=> Some error ocurred while trying to add peer ${PEER} to the cluster - detaching it ..."
   gluster peer detach ${PEER} force
   rm -f ${SEMAPHORE_FILE}
   exit 1
}

[ "$DEBUG" == "1" ] && set -x && set +e

echo "=> Checking if I can reach gluster container ${PEER} ..."
HOSTNAME=`sshpass -p ${ROOT_PASSWORD} ssh ${SSH_OPTS} ${SSH_USER}@${PEER} "hostname" 3>&1`
if [ ${HOSTNAME} != hostname ]; then
   echo "=> Gluster container ${PEER} is alive"
else
   echo "*** Could not reach gluster master container ${PEER} - exiting ..."
   exit 1
fi

# Gluster does not like to add two nodes at once
for ((SEMAPHORE_RETRY=0; SEMAPHORE_RETRY<SEMAPHORE_TIMEOUT; SEMAPHORE_RETRY++)); do
   if [ ! -e ${SEMAPHORE_FILE} ]; then
      break
   fi
   echo "*** There is another container joining the cluster, waiting $((SEMAPHORE_TIMEOUT-SEMAPHORE_RETRY)) seconds ..."
   sleep 1     
done

if [ -e ${SEMAPHORE_FILE} ]; then
   echo "*** Error: another container is joining the cluster"
   echo "and after waiting ${SEMAPHORE_TIMEOUT} seconds I could not join peer ${PEER}, giving it up ..."
   exit 1
fi
touch ${SEMAPHORE_FILE}

for i in `seq 1 $MAX_VOLUMES`; do
 
	# Check how many peers are already joined in the cluster - needed to add a replica
	NUMBER_OF_REPLICAS=`gluster volume info ${GLUSTER_VOL}${i} | grep "Number of Bricks:" | awk '{print $6}'`

	# Check if peer container is already part of the cluster
	PEER_STATUS=`gluster peer status | grep -A2 "Hostname: ${PEER}$" | grep State: | awk -F: '{print $2}'`
	if echo "${PEER_STATUS}" | grep "Peer Rejected"; then
	   if gluster volume info ${GLUSTER_VOL}${i} | grep ": ${PEER}:${GLUSTER_BRICK_PATH}/${i}$" >/dev/null; then
	      echo "=> Peer container ${PEER} was part of this cluster but must be dropped now ..."
	      gluster --mode=script volume remove-brick ${GLUSTER_VOL}${i} replica $((NUMBER_OF_REPLICAS-1)) ${PEER}:${GLUSTER_BRICK_PATH}/${i} force
	      sleep 5
	   fi
	   gluster peer detach ${PEER} force
	   sleep 5
	fi

	# Probe the peer
	if ! echo "${PEER_STATUS}" | grep "Peer in Cluster" >/dev/null; then
	    # Peer probe
	    echo "=> Probing peer ${PEER} ..."
	    gluster peer probe ${PEER}
	    sleep 5
	fi

	# Check how many peers are already joined in the cluster - needed to add a replica
	NUMBER_OF_REPLICAS=`gluster volume info ${GLUSTER_VOL}${i} | grep "Number of Bricks:" | awk '{print $6}'`
	# Create the volume
	if ! gluster volume list | grep "^${GLUSTER_VOL}${i}$" >/dev/null; then
	   echo "=> Creating GlusterFS volume ${GLUSTER_VOL}${i}..."
	   gluster volume create ${GLUSTER_VOL}${i} replica 2 transport tcp ${MY_IP}:${GLUSTER_BRICK_PATH}/${i} ${PEER}:${GLUSTER_BRICK_PATH}/${i} force || detach
	   sleep 1
	fi

	# Start the volume
	if ! gluster volume status ${GLUSTER_VOL}${i} >/dev/null; then
	   echo "=> Starting GlusterFS volume ${GLUSTER_VOL}${i}..."
	   gluster volume start ${GLUSTER_VOL}${i}
	   sleep 1
	fi

	if ! gluster volume info ${GLUSTER_VOL}${i} | grep ": ${PEER}:${GLUSTER_BRICK_PATH}/${i}$" >/dev/null; then
	   echo "=> Adding brick ${PEER}:${GLUSTER_BRICK_PATH}/${i} to the cluster (replica=$((NUMBER_OF_REPLICAS+1)))..."
	   gluster volume add-brick ${GLUSTER_VOL}${i} replica $((NUMBER_OF_REPLICAS+1)) ${PEER}:${GLUSTER_BRICK_PATH}/${i} force || detach
	fi

done

rm -f ${SEMAPHORE_FILE}
exit 0