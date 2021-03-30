#!/bin/bash -u
export LIB_PATH=$(dirname $0)/../lib
OPT_CHECK_ROUTER_L3HA_STATUS=false
ARG_CHECK_ROUTER_L3HA_STATUS=
OPT_CHECK_ROUTER_L3HA_STATE_DIST=false
OPT_DISCOVER_LP1891673=false
OPT_GET_L2POP_MAP=false
ARG_GET_L2POP_MAP=
ARG_TMP=

usage ()
{
cat << EOF
USAGE: openstack-toolkit.neutron OPTIONS

DESCRIPTION
    A set of tools is provided here for Neutron. Tools are categorised as ones to be run against the Openstack API or on a host running Neutron services/agents.

OPTIONS

    API:

    --check-l3ha-router-status [router]
        Check HA replica status for routers and report any that do not have exactly one "active".

        NOTE: this is currently the default.

    --check-l3ha-router-state-distribution
        Show tally of active/standby counts for HA routers per host/l3-agent.

    --get-l2pop-map OUTFILE

        This tool creates a map of hypervisors to networks and ports to networks that can be used as input to checks for Neutron layer2 population flow consistency. For example if you have an instance that has a port of network X and you want to check that the hypervisor running that vm has the correct flows to be able to reach any compute host running vms or network resources on the same network, you cannot know if you are missing anything by the information on that node alone. This map provides the information necessary to make those decisions. Output format is json.

    AGENT:

    --discover-ip-rules-affected-by-lp1891673
        Discover qrouter namespaces that have incorrect ip rules. This issue is described in https://pad.lv/1891673.

        NOTE: requires network-control interface (snap connect openstack-toolkit:network-control)

        This tool is experimental since it requires access that no existing snapd interface can provide.

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
        --check-l3ha-router-status)
              OPT_CHECK_ROUTER_L3HA_STATUS=true
              if (($#>1)) && [[ ${2:0:2} != "--" ]]; then
                  ARG_CHECK_ROUTER_L3HA_STATUS=$2
                  shift
              fi
              use_default=false
              ;;
        --check-l3ha-router-state-distribution)
              OPT_CHECK_ROUTER_L3HA_STATE_DIST=true
              use_default=false
              ;;
        --discover-ip-rules-affected-by-lp1891673)
              OPT_DISCOVER_LP1891673=true
              use_default=false
              ;;
        --get-l2pop-map)
              OPT_GET_L2POP_MAP=true
              use_default=false
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

if $OPT_CHECK_ROUTER_L3HA_STATUS || $use_default; then
    if [[ -z $ARG_CHECK_ROUTER_L3HA_STATUS ]] && [[ -n $ARG_TMP ]]; then
        ARG_CHECK_ROUTER_L3HA_STATUS=$ARG_TMP
    fi
    $api_plugins/check_router_l3agent_ha_status $ARG_CHECK_ROUTER_L3HA_STATUS
elif $OPT_CHECK_ROUTER_L3HA_STATE_DIST; then
    $api_plugins/check_router_l3agent_ha_state_distribution
elif $OPT_DISCOVER_LP1891673; then
    $agent_plugins/discover_ip_rules_affected_by_lp1891673
elif $OPT_GET_L2POP_MAP; then
    $api_plugins/get_l2pop_map $ARG_GET_L2POP_MAP
else
    usage
fi

echo Done.

