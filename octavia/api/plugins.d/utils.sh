#!/bin/bash -u
SCRATCH_AREA=`mktemp -d`
master_cleanup ()
{
#    rm -rf $SCRATCH_AREA
    :
}

trap master_cleanup KILL INT EXIT

LOADBALANCER=${1:-""}
declare -A LISTENER_PROTOCOL_SG_MAP=(
    [HTTP]=tcp
    [HTTPS]=tcp
    [SCTP]=sctp
    [UDP]=udp
)

.  $LIB_PATH/openstack_client

mkdir -p $SCRATCH_AREA/{results,loadbalancers,pools,listeners,healthmonitors}

echo -n "INFO: pre-fetching information..."

# Get all ports
echo -n "[ports]"
openstack_port_list > $SCRATCH_AREA/ports.json &

# Get all LBs and allow single loadbalancer override
echo -n "[loadbalancers]"
if [ -n "$LOADBALANCER" ]; then
    # check that it exists
    openstack_loadbalancer_show $LOADBALANCER > $SCRATCH_AREA/loadbalancer_show
    if [[ `jq .faultcode $SCRATCH_AREA/loadbalancer_show` != null ]]; then
        message="`jq .faultstring $SCRATCH_AREA/loadbalancer_show`"
        wait
        echo -e "\nERROR: $message"
        exit 1
    fi
    echo "$LOADBALANCER" > $SCRATCH_AREA/loadbalancer_list
else
    openstack_loadbalancer_list > $SCRATCH_AREA/loadbalancers.json &
fi

echo -n "[listeners]"
openstack_loadbalancer_listener_list ${LOADBALANCER:-} > $SCRATCH_AREA/listeners.json &

echo -n "[pools]"
openstack_loadbalancer_pool_list ${LOADBALANCER:-} > $SCRATCH_AREA/pools.json &

echo -n "[healthmonitors]"
openstack_loadbalancer_healthmonitor_list > $SCRATCH_AREA/healthmonitors.json &

wait

# if no user-provided LB, include all
if ! [ -e "$SCRATCH_AREA/loadbalancer_list" ]; then
    jq -r '.loadbalancers[].id' $SCRATCH_AREA/loadbalancers.json > $SCRATCH_AREA/loadbalancer_list
fi

# Get members and per-lb listeners
echo -n "[members]"
while read -r lb; do
    mkdir -p $SCRATCH_AREA/loadbalancers/$lb/pools
    mkdir -p $SCRATCH_AREA/loadbalancers/$lb/listeners
    for pool in `jq -r ".pools[]| select(.loadbalancers[]| select(.id==\"$lb\"))| .id" $SCRATCH_AREA/pools.json`; do
        mkdir -p $SCRATCH_AREA/loadbalancers/$lb/pools/$pool
        for id in `jq -r ".listeners[]| select(.loadbalancers[]| select(.id==\"$lb\"))| \
                                        select(.default_pool_id==\"$pool\")| .id" $SCRATCH_AREA/listeners.json`; do
            mkdir -p $SCRATCH_AREA/loadbalancers/$lb/listeners/$id
            listener="`jq -r \".listeners[]| select(.id==\\\"$id\\\")\" $SCRATCH_AREA/listeners.json`"
            echo $listener| jq -r '.protocol' > $SCRATCH_AREA/loadbalancers/$lb/listeners/$id/protocol
            echo $listener| jq -r '.protocol_port' > $SCRATCH_AREA/loadbalancers/$lb/listeners/$id/port
            echo $listener| jq -r '.operating_status' > $SCRATCH_AREA/loadbalancers/$lb/listeners/$id/operating_status
        done

        mkdir -p $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members
        openstack_loadbalancer_member_list $pool > $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members.json
        for id in `jq -r '.members[].id' $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members.json`; do
            mkdir -p $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$id
            member="`jq -r \".members[]| select(.id==\\\"$id\\\")\" $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members.json`"
            echo $member| jq -r '.address' > $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$id/address
            echo $member| jq -r '.subnet_id' > $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$id/subnet_id
            echo $member| jq -r '.project_id' > $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$id/project_id
            echo $member| jq -r '.protocol_port' > $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$id/protocol_port
        done
    done
done < $SCRATCH_AREA/loadbalancer_list
wait

echo ""
