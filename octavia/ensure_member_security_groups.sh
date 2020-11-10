#!/bin/bash -eu
#
# Scans all Octavia loadbalancers, checks that all member ports' have a security
# group rule containing a rule that opens the port being loadbalanced.
#
SCRATCH_AREA=`mktemp -d`
LOADBALANCER=${1:-}

cleanup ()
{
    rm -rf $SCRATCH_AREA
}

trap cleanup KILL INT EXIT

if [ -z "${OS_AUTH_URL:-}" ]; then
    read -p "Path to credentials file: " openrc_path
    source $openrc_path
fi

mkdir -p $SCRATCH_AREA/results

echo -n "INFO: pre-fetching information..."

# Get all ports
echo -n "[ports]"
openstack port list -c ID -c fixed_ips -f value > $SCRATCH_AREA/port_list &

# Get all LBs and allow single loadbalancer override
echo -n "[loadbalancers]"
if [ -n "$LOADBALANCER" ]; then
    echo "$LOADBALANCER" > $SCRATCH_AREA/loadbalancer_list
else
    openstack loadbalancer list -c id -f value > $SCRATCH_AREA/loadbalancer_list &
fi
wait

# Extract port info
while read -r port_info; do
    uuid=${port_info%% *}
    mkdir -p $SCRATCH_AREA/ports/$uuid
    # note: format of this field changes across releases so this may need updating
    ip_address=`echo ${port_info#* }| \
                  sed -rn -e "s/.+ip_address='([[:digit:]\.]+)',\s+.+/\1/" \
                          -e "s/.+ip_address':\s+'([[:digit:]\.]+)'}.+/\1/p"`
    subnet_id=`echo ${port_info#* }| \
                 sed -rn -e "s/.+subnet_id='([[:alnum:]\-]+)',.+/\1/" \
                         -e "s/.+\{'subnet_id':\s+'([[:alnum:]\-]+)',.+/\1/p"`
    #[ -n "$ip_address" ] && [ -n "$subnet_id" ] || echo "WARNING: incomplete information for port $uuid"
    echo $ip_address > $SCRATCH_AREA/ports/$uuid/ip_address
    echo $subnet_id > $SCRATCH_AREA/ports/$uuid/subnet_id
done < $SCRATCH_AREA/port_list

# Get pools, listeners and members
echo -n "[pools+members+listeners]"
while read -r lb; do
    mkdir -p $SCRATCH_AREA/$lb/pools
    for pool in `openstack loadbalancer pool list -c id -f value --loadbalancer $lb`; do
        mkdir -p $SCRATCH_AREA/$lb/pools/$pool
    done &
    wait

    for pool in `ls $SCRATCH_AREA/$lb/pools`; do
        mkdir -p $SCRATCH_AREA/$lb/listeners
        for listener in `openstack loadbalancer listener list| awk "\\$4==\"$pool\" {print \\$2}"`; do
            mkdir -p $SCRATCH_AREA/$lb/listeners/$listener
            readarray -t listener_info<<<"`openstack loadbalancer listener show $listener -f value -c protocol -c protocol_port`"
            echo "${listener_info[0]}" > $SCRATCH_AREA/$lb/listeners/$listener/protocol
            echo "${listener_info[1]}" > $SCRATCH_AREA/$lb/listeners/$listener/port
        done &
        mkdir -p $SCRATCH_AREA/$lb/pools/$pool/members
        for member in `openstack loadbalancer member list -c id -f value $pool`; do
            mkdir -p $SCRATCH_AREA/$lb/pools/$pool/members/$member
            readarray -t member_info<<<"`openstack loadbalancer member show -c address -c subnet_id -f value $pool $member`"
            echo "${member_info[0]}" > $SCRATCH_AREA/$lb/pools/$pool/members/$member/address
            echo "${member_info[1]}" > $SCRATCH_AREA/$lb/pools/$pool/members/$member/subnet_id
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
    for rule in `openstack security group rule list $sg -c ID -f value`; do
        openstack security group rule show $rule > $sg_path/$rule &
    done
    wait
}

get_subnet_cidr ()
{
    local subnet=$1
    if ! [ -r "$SCRATCH_AREA/subnets/$subnet/cidr" ]; then
        mkdir -p $SCRATCH_AREA/subnets/$subnet/
        openstack subnet show $subnet -c cidr -f value > $SCRATCH_AREA/subnets/$subnet/cidr
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
    for pool in `ls $SCRATCH_AREA/$lb/pools`; do
        for listener in `ls $SCRATCH_AREA/$lb/listeners`; do
            listener_port=`cat $SCRATCH_AREA/$lb/listeners/$listener/port`
            error_idx=0
            for member_uuid in `ls $SCRATCH_AREA/$lb/pools/$pool/members`; do
                m_address=`cat $SCRATCH_AREA/$lb/pools/$pool/members/$member_uuid/address`
                m_subnet_id=`cat $SCRATCH_AREA/$lb/pools/$pool/members/$member_uuid/subnet_id`

                # find port with this address and subnet_id
                port_uuid=`get_member_port_uuid $m_subnet_id $m_address`
                if [[ -z "$port_uuid" ]]; then
                    echo "WARNING: unable to identify member port for address=$m_address, subnet=$m_subnet_id - skipping member $member_uuid"
                    continue
                fi

                for sg in `openstack port show -c security_group_ids -f value $port_uuid| egrep -o "[[:alnum:]\-]+"`; do
                    fetch_security_group_rules $sg
                    found=false
                    for rule in `find $SCRATCH_AREA/security_groups/$sg/rules/ -type f`; do
                        # THIS IS THE ACTUAL CHECK - ADD MORE AS NEEDED #
                        port_range_max=`awk "\\$2==\"port_range_min\" {print \\$4}" $rule`
                        port_range_min=`awk "\\$2==\"port_range_max\" {print \\$4}" $rule`
                        remote_ip_prefix=`awk "\\$2==\"remote_ip_prefix\" {print \\$4}" $rule`
                        direction=`awk "\\$2==\"direction\" {print \\$4}" $rule`
                        subnet_cidr=`get_subnet_cidr $m_subnet_id`

                        # ensure port range
                        [[ "${port_range_min}:${port_range_max}" == "${listener_port}:${listener_port}" ]] || continue
                        # ensure ingress
                        [[ "$direction" == "ingress" ]] || continue
                        # ensure correct network range
                        [[ "$remote_ip_prefix" == "$subnet_cidr" ]] || continue

                        found=true
                        break
                    done
                    if ! $found; then
                        error_path=$SCRATCH_AREA/results/$lb/errors/$error_idx
                        mkdir -p $error_path
                        echo "$listener_port" > $error_path/protocol_port
                        echo $member_uuid > $error_path/member
                        echo $port_uuid > $error_path/backend_vm_port
                        echo $subnet_cidr > $error_path/member_subnet_cidr
                        echo $sg > $error_path/security_group
                        for entry in `ls $error_path`; do
                            echo " - $entry: `cat $error_path/$entry`" >> $error_path/details
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
        port=`cat $errors/$error/protocol_port`
        echo -e "\nWARNING: loadbalancer $lb has member(s) with security groups that don't have required ports open: $port"
        echo "Details:"
        cat $errors/$error/details
    done
done
if `ls $SCRATCH_AREA/results/*/errors &>/dev/null`; then
    echo ""
else
    echo "INFO: no issues found."
fi

echo "Done."
