#!/bin/bash -eu
#
# Scans all Octavia loadbalancers, checks that all member ports' have a security
# group rule containing a rule that opens the port being loadbalanced.
#
SCRATCH_AREA=`mktemp -d`
LOADBALANCER=${1:-}

. `dirname $0`/openstack_client

echo "INFO: fetching token"
TOKEN=`openstack token issue| awk '$2=="id" {print $4}'`
AUTH_URL=`echo $OS_AUTH_URL| sed 's/5000/35357/g'`
neutron_ep=`get_endpoint neutron`
nova_ep=`get_endpoint nova`
octavia_ep=`get_endpoint octavia`


cleanup ()
{
    rm -rf $SCRATCH_AREA
}

trap cleanup KILL INT EXIT

if [ -z "${OS_AUTH_URL:-}" ]; then
    read -p "Path to credentials file: " openrc_path
    source $openrc_path
fi

mkdir -p $SCRATCH_AREA/{results,ports,loadbalancers,pools,listeners}

echo -n "INFO: pre-fetching information..."

# Get all ports
echo -n "[ports]"
openstack_port_list > $SCRATCH_AREA/ports.json &

# Get all LBs and allow single loadbalancer override
echo -n "[loadbalancers]"
if [ -n "$LOADBALANCER" ]; then
    echo "$LOADBALANCER" > $SCRATCH_AREA/loadbalancer_list
else
    openstack_loadbalancer_list > $SCRATCH_AREA/loadbalancers.json &
fi

echo -n "[listeners]"
openstack_loadbalancer_listener_list > $SCRATCH_AREA/listeners.json &

echo -n "[pools]"
openstack_loadbalancer_pool_list > $SCRATCH_AREA/pools.json &
wait
# Extract port info
for uuid in `jq -r '.ports[].id' $SCRATCH_AREA/ports.json`; do
    mkdir -p $SCRATCH_AREA/ports/$uuid
    {
    port="`jq -r \".ports[]| select(.id==\\\"$uuid\\\")\" $SCRATCH_AREA/ports.json`"
    # note: format of this field changes across releases so this may need updating
    ip_address=`echo $port| jq -r '.fixed_ips[].ip_address'`
    subnet_id=`echo $port| jq -r '.fixed_ips[].subnet_id'`
    #[ -n "$ip_address" ] && [ -n "$subnet_id" ] || echo "WARNING: incomplete information for port $uuid"
    echo $ip_address > $SCRATCH_AREA/ports/$uuid/ip_address
    echo $subnet_id > $SCRATCH_AREA/ports/$uuid/subnet_id
    } &
done
wait
if ! [ -e "$SCRATCH_AREA/loadbalancer_list" ]; then
    jq -r '.loadbalancers[].id' $SCRATCH_AREA/loadbalancers.json > $SCRATCH_AREA/loadbalancer_list
fi

# Get listeners and members
echo -n "[members+listeners]"
while read -r lb; do
    for id in `jq -r ".pools[]| select(.loadbalancers[]| select(.id==\"$lb\"))| .id" $SCRATCH_AREA/pools.json`; do
        mkdir -p $SCRATCH_AREA/loadbalancers/$lb/pools/$id
    done

    for pool in `jq -r '.pools[].id' $SCRATCH_AREA/pools.json`; do
        mkdir -p $SCRATCH_AREA/loadbalancers/$lb/listeners
        for id in `jq -r ".listeners[]| select(.loadbalancers[]| select(.id==\"$lb\"))| .id" $SCRATCH_AREA/listeners.json`; do
            mkdir -p $SCRATCH_AREA/loadbalancers/$lb/listeners/$id
            listener="`jq -r \".listeners[]| select(.id==\\\"$id\\\")\" $SCRATCH_AREA/listeners.json`"
            echo $listener| jq -r '.protocol' > $SCRATCH_AREA/loadbalancers/$lb/listeners/$id/protocol
            echo $listener| jq -r '.protocol_port' > $SCRATCH_AREA/loadbalancers/$lb/listeners/$id/port
        done &

        mkdir -p $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members
        openstack_loadbalancer_member_list $pool > $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members.json
        for id in `jq -r '.members[].id' $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members.json`; do
            mkdir -p $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$id
            member="`jq -r \".members[]| select(.id==\\\"$id\\\")\" $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members.json`"
            echo $member| jq -r '.address' > $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$id/address
            echo $member| jq -r '.subnet_id' > $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$id/subnet_id

        done &
        wait
    done &
done < $SCRATCH_AREA/loadbalancer_list
wait

echo ""

fetch_security_group_rules ()
{
    # get sg rules if they are not already cached
    local sg=$1
    local sg_path=$SCRATCH_AREA/security_groups/$sg/rules/

    ! [ -d $sg_path ] || return
    mkdir -p $sg_path
    for rule in `openstack_security_group_rule_list $sg| jq '.security_group_rules[].id'`; do
        openstack_security_group_rule_show $rule > $sg_path/$rule &
    done
    wait
}

get_subnet_cidr ()
{
    local subnet=$1
    if ! [ -r "$SCRATCH_AREA/subnets/$subnet/cidr" ]; then
        mkdir -p $SCRATCH_AREA/subnets/$subnet/
        openstack_subnet_show $subnet| jq -r '.subnet.cidr' > $SCRATCH_AREA/subnets/$subnet/cidr
    fi
    cat $SCRATCH_AREA/subnets/$subnet/cidr
    return
}

get_member_port_uuid ()
{
    local m_subnet_id=$1
    local m_address=$2
    local port=
    local port_ip_address=

    readarray -t ports<<<`find $SCRATCH_AREA/ports -name subnet_id| xargs -l egrep -l "$m_subnet_id$"`
    for path in ${ports[@]}; do
        [ -n "$path" ] || continue
        port=`dirname $path`
        port_ip_address=`cat $port/ip_address`
        [[ "$port_ip_address" == "$m_address" ]] || continue
        basename $port
        return 0
    done
}

# Run checks
echo "INFO: checking loadbalancers '`cat $SCRATCH_AREA/loadbalancer_list| tr -s '\n' ' '| sed -r 's/\s+$//g'`'"
while read -r lb; do
    (
    mkdir -p $SCRATCH_AREA/results/$lb
    mkdir -p $SCRATCH_AREA/security_groups
    for pool in `ls $SCRATCH_AREA/loadbalancers/$lb/pools`; do
        for listener in `ls $SCRATCH_AREA/loadbalancers/$lb/listeners`; do
            listener_port=`cat $SCRATCH_AREA/loadbalancers/$lb/listeners/$listener/port`
            error_idx=0
            for member_uuid in `ls $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members`; do
                m_address=`cat $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$member_uuid/address`
                m_subnet_id=`cat $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$member_uuid/subnet_id`

                # find port with this address and subnet_id
                port_uuid=`get_member_port_uuid $m_subnet_id $m_address`
                if [[ -z "$port_uuid" ]]; then
                    echo "WARNING: unable to identify member port for address=$m_address, subnet=$m_subnet_id - skipping member $member_uuid"
                    continue
                fi

                for sg in `jq -r ".ports[]| select(.id==\"$port_uuid\")| .security_groups[]" $SCRATCH_AREA/ports.json`; do
                    fetch_security_group_rules $sg
                    found=false
                    for rule in `find $SCRATCH_AREA/security_groups/$sg/rules/ -type f`; do
                        # THIS IS THE ACTUAL CHECK - ADD MORE AS NEEDED #
                        port_range_max=`awk "\\$2==\"port_range_max\" {print \\$4}" $rule`
                        port_range_min=`awk "\\$2==\"port_range_min\" {print \\$4}" $rule`
                        remote_ip_prefix=`awk "\\$2==\"remote_ip_prefix\" {print \\$4}" $rule`
                        direction=`awk "\\$2==\"direction\" {print \\$4}" $rule`
                        subnet_cidr=`get_subnet_cidr $m_subnet_id`

                        # ensure port range
                        [[ "$port_range_min" == "None" ]] || [[ "$port_range_max" == "None" ]] && continue
                        ((listener_port>=port_range_min)) && ((listener_port<=port_range_max)) || continue
                        # ensure ingress
                        [[ "$direction" == "ingress" ]] || continue
                        # ensure correct network range
                        [[ "$remote_ip_prefix" == "$subnet_cidr" ]] || continue

                        found=true
                        break
                    done
                    if ! $found; then
                        error_path=$SCRATCH_AREA/results/$lb/errors/$error_idx
                        mkdir -p $error_path/{security_group,loadbalancer}
                        echo "$sg" > $error_path/security_group/id
                        echo "$listener_port" > $error_path/loadbalancer/protocol_port
                        echo "$member_uuid" > $error_path/loadbalancer/member_id
                        echo "$port_uuid" > $error_path/loadbalancer/member_vm_port
                        echo "$subnet_cidr" > $error_path/loadbalancer/member_vm_subnet_cidr

                        for section in `ls $error_path`; do
                            echo "$section:" >> $error_path/details
                            for entry in `ls $error_path/$section`; do
                                echo " - $entry: `cat $error_path/$section/$entry`" >> $error_path/details
                            done
                        done
                        ((error_idx+=1))
                    fi
                done
            done
        done
    done > $SCRATCH_AREA/results/$lb/all
    ) &
done < $SCRATCH_AREA/loadbalancer_list
wait

for errors in `find $SCRATCH_AREA/results -name errors`; do
    lb=$(basename `dirname $errors`)
    for error in `ls $errors`; do
        port=`cat $errors/$error/loadbalancer/protocol_port`
        echo -e "\nWARNING: loadbalancer $lb has member(s) with security group(s) with insufficient rules:"
        cat $errors/$error/details
    done
done
if `ls $SCRATCH_AREA/results/*/errors &>/dev/null`; then
    echo ""
else
    echo "INFO: no issues found."
fi

echo "Done."
