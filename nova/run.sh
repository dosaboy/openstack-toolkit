#!/bin/bash -u
export LIB_PATH=$(dirname $0)/../lib
OPT_GET_L2POP_MAP=false
ARG_GET_L2POP_MAP=
ARG_TMP=

usage ()
{
cat << EOF
USAGE: openstack-toolkit.nova OPTIONS

DESCRIPTION
    A set of tools is provided here for Nova. Tools are categorised as ones to be run against the Openstack API or on a host running Nova services/agents.

OPTIONS

    API:

    --get-l2pop-map OUTFILE

        This tool creates a map of hypervisors to networks and ports to networks that can be used as input to checks for Neutron layer2 population flow consistency. For example if you have an instance that has a port of network X and you want to check that the hypervisor running that vm has the correct flows to be able to reach any compute host running vms or network resources on the same network, you cannot know if you are missing anything by the information on that node alone. This map provides the information necessary to make those decisions. Output format is json.

        NOTE: this is currently the default.

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
        --get-l2pop-map)
              OPT_GET_L2POP_MAP=true
              if (($#>1)) && [[ ${2:0:2} != "--" ]]; then
                  ARG_GET_L2POP_MAP=$2
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

if $OPT_GET_L2POP_MAP || $use_default; then
    if [[ -z $ARG_GET_L2POP_MAP ]] && [[ -n $ARG_TMP ]]; then
        ARG_GET_L2POP_MAP=$ARG_TMP
    fi
    $api_plugins/get_l2pop_map $ARG_GET_L2POP_MAP
else
    usage
fi

echo Done.

