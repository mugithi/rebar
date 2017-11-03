#!/usr/bin/env bash
# Copyright 2015, RackN Inc

#
# We are deploying in google add this google instance as a provider
# and force the admin deploy to google
#
FORCE_PROVIDER=${PROVIDER:-google}
FORCE_DEPLOY_ADMIN=${DEPLOY_ADMIN:-google}

# Processes args, inits provider, and validates provider
. workloads/wl-lib.sh

PROVIDER_GOOGLE_ADMIN_INSTANCE_TYPE=${PROVIDER_GOOGLE_ADMIN_INSTANCE_TYPE:-n1-standard-2}
if [[ $PROVIDER_GOOGLE_ZONE ]] ; then
    ZONE_NAME="--zone $PROVIDER_GOOGLE_ZONE"
fi
if [[ $PROVIDER_GOOGLE_PROJECT ]] ; then
    PROJECT_ID="--project $PROVIDER_GOOGLE_PROJECT"
fi

# Check to see if device id exists.
if [ "$DEVICE_ID" != "" ] ; then
    STATE=`gcloud ${PROJECT_ID} compute instances describe ${ZONE_NAME} $DEVICE_ID --format=json | jq -r .status`

    if [[ $STATE == null ]] ; then
        echo "Instance ID doesn't exist in google: $DEVICE_ID"
        exit 1
    fi
    echo "GOOGLE reuse ${DEVICE_ID}"
else
    # Make name for unamed items
    NODENAME=$1
    if [ "$NODENAME" == "" ] ; then
        TSTAMP=`date +%H%M`
        NODENAME="${USER}1-${TSTAMP}"
    else
        shift
    fi
    echo "GOOGLE will create ${NODENAME}"
    DEVICE_ID=${NODENAME%%.*}

    if ! gcloud ${PROJECT_ID} compute instances create ${ZONE_NAME} --image ubuntu-14-04 --machine-type ${PROVIDER_GOOGLE_ADMIN_INSTANCE_TYPE} ${DEVICE_ID} ; then
        echo "Failed to create gcloud instance"
        exit 1
    fi
fi

# Wait for device to be up
STATE=`gcloud ${PROJECT_ID} compute instances describe $ZONE_NAME $DEVICE_ID --format=json | jq -r .status`
while [ "$STATE" != "RUNNING" ] ; do
  echo "STATE = $STATE"
  sleep 5
  STATE=`gcloud ${PROJECT_ID} compute instances describe $ZONE_NAME $DEVICE_ID --format=json | jq -r .status`
done
# HACK give a little extra settle time
sleep 10 

# Get Public IP - HACK - should look it up
IP=`gcloud ${PROJECT_ID} compute instances describe $ZONE_NAME $DEVICE_ID --format=json | jq -r .networkInterfaces[0].accessConfigs[0].natIP`
CIDR=32

ENV_VAR="\"google\": true,"

export ADMIN_IP="$IP/$CIDR"

# Make sure our key is in place.
gcloud ${PROJECT_ID} compute ssh $ZONE_NAME ubuntu@$DEVICE_ID --ssh-key-file $HOME/.ssh/id_rsa --command "sudo sed -i -e '/login as the user/d' /root/.ssh/authorized_keys"
gcloud ${PROJECT_ID} compute ssh $ZONE_NAME root@$DEVICE_ID --ssh-key-file $HOME/.ssh/id_rsa --command "date"
gcloud ${PROJECT_ID} compute ssh $ZONE_NAME ubuntu@$DEVICE_ID --ssh-key-file $HOME/.ssh/id_rsa --command "sudo sed -i -e '1d' /root/.ssh/authorized_keys"

. ./run-in-system.sh

echo "Google Device ID: $DEVICE_ID"
echo "repeat Google run: ./run-in-google.sh --device-id=${DEVICE_ID}"
echo "SSH access: ssh -X root@${IP}"
