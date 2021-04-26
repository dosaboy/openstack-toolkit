#!/bin/bash -u
export LIB_PATH=$(dirname $0)/../lib
OPT_ENSURE_LB_MEMBER_SG_RULES=false
ARG_ENSURE_LB_MEMBER_SG_RULES=
OPT_CREATE_LB_MONITOR_MAP=false
ARG_CREATE_LB_MONITOR_MAP=
ARG_TMP=

usage ()
{
cat << EOF
USAGE: openstack-toolkit.octavia OPTIONS

DESCRIPTION
    A set of tools is provided here for Octavia. Tools are categorised as ones to be run against the Openstack API or on a host running Octavia services/agents.

OPTIONS

    API:

    --ensure-member-sg-rules [loadbalancer]
        Check all members of loadbalancers to ensure that their corresponding instances are using a port with a security group that allows access for loadbalanced packets. If a loadbalancer uuid is provided it will be checked otherwise all loadbalancers will be checked.

        NOTE: this is currently the default.

    --create-lb-monitor-map [loadbalancer]

        Create a map of monitors used by LB resources along with their state.

    AGENT:

    none supported yet.

    COMMON:

    --token token
        Optional token to be used as opposed to fetching a new one.

ENVIRONMENT
    OS_TOKEN
        If set to a valid openstack token, this will be used as opposed to fetching a new one.

EOF
}

use_default=true
while (($#)); do
    case "$1" in
        --ensure-member-sg-rules)
              OPT_ENSURE_LB_MEMBER_SG_RULES=true
              if (($#>1)) && [[ ${2:0:2} != "--" ]]; then
                  ARG_ENSURE_LB_MEMBER_SG_RULES=$2
                  shift
              fi
              ;;
        --create-lb-monitor-map)
              use_default=false
              OPT_CREATE_LB_MONITOR_MAP=true
              if (($#>1)) && [[ ${2:0:2} != "--" ]]; then
                  ARG_CREATE_LB_MONITOR_MAP=$2
                  shift
              fi
              ;;
        --help|-h)
              usage
              exit 0
              ;;
        *)
              if [[ ${1:0:2} != "--" ]]; then
                  # use this an arg to the default action if non specified
                  ARG_TMP=$1
              fi
              ;;
    esac
    shift
done

api_plugins=`dirname $0`/api/plugins.d
agent_plugins=`dirname $0`/agent/plugins.d

if $OPT_ENSURE_LB_MEMBER_SG_RULES || $use_default; then
    if [[ -z $ARG_ENSURE_LB_MEMBER_SG_RULES ]] && [[ -n $ARG_TMP ]]; then
        ARG_ENSURE_LB_MEMBER_SG_RULES=$ARG_TMP
    fi
    $api_plugins/ensure_member_security_groups $ARG_ENSURE_LB_MEMBER_SG_RULES
elif $OPT_CREATE_LB_MONITOR_MAP; then
    if [[ -z $ARG_CREATE_LB_MONITOR_MAP ]] && [[ -n $ARG_TMP ]]; then
        ARG_CREATE_LB_MONITOR_MAP=$ARG_TMP
    fi
    $api_plugins/create_lb_monitor_map $ARG_CREATE_LB_MONITOR_MAP
else
    usage
fi

echo Done.

