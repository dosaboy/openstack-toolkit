#!/bin/bash -u
#
# Scans all Octavia loadbalancers, checks that all member ports' have a security
# group rule containing a rule that opens the port being loadbalanced.
#
SCRATCH_AREA=`mktemp -d`
cleanup ()
{
    rm -rf $SCRATCH_AREA
}

trap cleanup KILL INT EXIT

LOADBALANCER=${1:-}

. `dirname $0`/common/openstack_client

fetch_security_group_rules ()
{
    # get sg rules if they are not already cached
    local sg=$1
    local sg_path=$SCRATCH_AREA/security_groups/$sg/rules/
    local rule=

    ! [ -d $sg_path ] || return
    mkdir -p $sg_path
    for rule in `openstack_security_group_rule_list $sg| jq -r '.security_group_rules[].id'`; do
        openstack_security_group_rule_show $rule > $sg_path/$rule
    done
}

get_subnet_cidr ()
{
    local subnet=$1
    local path=$SCRATCH_AREA/subnets/$subnet
    if ! [ -r "$path/cidr" ]; then
        mkdir -p $path
        openstack_subnet_show $subnet| jq -r '.subnet.cidr' > $path/cidr
    fi
    cat $path/cidr
    return
}

get_member_port_uuid ()
{
    local m_subnet_id=$1
    local m_address=$2

    # should only ever return one port
    jq -r ".ports[]| select(.fixed_ips[]| .subnet_id==\"$m_subnet_id\")| select(.fixed_ips[]| .ip_address==\"$m_address\")| .id" \
        $SCRATCH_AREA/ports.json
}

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
openstack_loadbalancer_listener_list ${LOADBALANCER:-} > $SCRATCH_AREA/listeners.json &

echo -n "[pools]"
openstack_loadbalancer_pool_list ${LOADBALANCER:-} > $SCRATCH_AREA/pools.json &
wait

if ! [ -e "$SCRATCH_AREA/loadbalancer_list" ]; then
    jq -r '.loadbalancers[].id' $SCRATCH_AREA/loadbalancers.json > $SCRATCH_AREA/loadbalancer_list
fi

# Get members and per-lb listeners
echo -n "[members]"
while read -r lb; do
    mkdir -p $SCRATCH_AREA/loadbalancers/$lb/pools
    for pool in `jq -r ".pools[]| select(.loadbalancers[]| select(.id==\"$lb\"))| .id" $SCRATCH_AREA/pools.json`; do
        mkdir -p $SCRATCH_AREA/loadbalancers/$lb/pools/$pool
        mkdir -p $SCRATCH_AREA/loadbalancers/$lb/listeners
        for id in `jq -r ".listeners[]| select(.loadbalancers[]| select(.id==\"$lb\"))| \
                                        select(.default_pool_id==\"$pool\")| .id" $SCRATCH_AREA/listeners.json`; do
            mkdir -p $SCRATCH_AREA/loadbalancers/$lb/listeners/$id
            listener="`jq -r \".listeners[]| select(.id==\\\"$id\\\")\" $SCRATCH_AREA/listeners.json`"
            echo $listener| jq -r '.protocol' > $SCRATCH_AREA/loadbalancers/$lb/listeners/$id/protocol
            echo $listener| jq -r '.protocol_port' > $SCRATCH_AREA/loadbalancers/$lb/listeners/$id/port
        done

        mkdir -p $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members
        openstack_loadbalancer_member_list $pool > $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members.json
        for id in `jq -r '.members[].id' $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members.json`; do
            mkdir -p $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$id
            member="`jq -r \".members[]| select(.id==\\\"$id\\\")\" $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members.json`"
            echo $member| jq -r '.address' > $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$id/address
            echo $member| jq -r '.subnet_id' > $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$id/subnet_id
        done
    done
done < $SCRATCH_AREA/loadbalancer_list
wait

echo ""

# Run checks
echo "INFO: checking loadbalancers '`cat $SCRATCH_AREA/loadbalancer_list| tr -s '\n' ' '| sed -r 's/\s+$//g'`'"
while read -r lb; do
    mkdir -p $SCRATCH_AREA/results/$lb
    mkdir -p $SCRATCH_AREA/security_groups
    error_idx=0
    for pool in `ls $SCRATCH_AREA/loadbalancers/$lb/pools`; do
        for member_uuid in `ls $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members`; do
            m_address=`cat $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$member_uuid/address`
            m_subnet_id=`cat $SCRATCH_AREA/loadbalancers/$lb/pools/$pool/members/$member_uuid/subnet_id`
            subnet_cidr=`get_subnet_cidr $m_subnet_id`

            # find port with this address and subnet_id
            port_uuid=`get_member_port_uuid $m_subnet_id $m_address`
            if [[ -z "$port_uuid" ]]; then
                echo "WARNING: unable to identify member port with address=$m_address on subnet=$m_subnet_id - skipping member $member_uuid"
                continue
            fi

            for listener in `ls $SCRATCH_AREA/loadbalancers/$lb/listeners`; do
                listener_port=`cat $SCRATCH_AREA/loadbalancers/$lb/listeners/$listener/port`
                declare -a security_groups_checked=()

                found=false
                for sg in `jq -r ".ports[]| select(.id==\"$port_uuid\")| .security_groups[]" $SCRATCH_AREA/ports.json`; do
                    security_groups_checked+=( $sg )
                    fetch_security_group_rules $sg
                    for rule in `find $SCRATCH_AREA/security_groups/$sg/rules/ -type f`; do

                        # THESE ARE THE ACTUAL CHECKS - ADD MORE AS NEEDED #

                        # Look for a rule that contains a match for all of the following
                        port_range_max=`jq -r '.security_group_rule.port_range_max' $rule`
                        port_range_min=`jq -r '.security_group_rule.port_range_min' $rule`
                        remote_ip_prefix=`jq -r '.security_group_rule.remote_ip_prefix' $rule`
                        direction=`jq -r '.security_group_rule.direction' $rule`

                        # ensure port range
                        port_open=false
                        if [[ "$port_range_min" != "null" ]] && [[ "$port_range_max" != "null" ]]; then
                            if ((listener_port>=port_range_min)) && ((listener_port<=port_range_max)); then
                                port_open=true
                            fi
                        fi

                        # following checks only apply iff the port is open i.e. they must all be within the same rule
                        if ! $port_open; then
                            continue
                        fi

                        # ensure ingress
                        if [[ "$direction" != "ingress" ]]; then
                            continue
                        fi

                        # ensure correct network range
                        valid_subnet_range=false
                        if [[ "$remote_ip_prefix" == "$subnet_cidr" ]] || \
                               [[ "$remote_ip_prefix" == "0.0.0.0/0" ]]; then
                            valid_subnet_range=true
                        fi

                        # Have we got a match for all items in this rule?
                        if $port_open && $valid_subnet_range; then
                            found=true
                            break
                        fi
                    done
                    ! $found || break
                done
                if ((${#security_groups_checked[@]})) && ! $found; then
                    # Save the information to display later
                    error_path=$SCRATCH_AREA/results/$lb/errors/$error_idx
                    mkdir -p $error_path/{security_group,loadbalancer}
                    echo "$pool" > $error_path/loadbalancer/pool
                    echo "$listener_port" > $error_path/loadbalancer/protocol_port
                    echo "$listener" > $error_path/loadbalancer/listener
                    echo "$member_uuid" > $error_path/loadbalancer/member
                    echo "$port_uuid" > $error_path/loadbalancer/member_vm_port
                    echo "$subnet_cidr" > $error_path/loadbalancer/member_vm_subnet_cidr

                    comma=false
                    for sg in ${security_groups_checked[@]}; do
                        $comma && echo -n ", " >> $error_path/security_group/ids
                        echo -n "$sg" >> $error_path/security_group/ids
                        comma=true
                    done

                    for section in `ls $error_path`; do
                        [[ "$section" != "details" ]] || continue
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
done < $SCRATCH_AREA/loadbalancer_list

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
