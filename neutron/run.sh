#!/bin/bash -u
export LIB_PATH=$(dirname $0)/../lib
OPT_CHECK_ROUTER_L3HA_STATUS=false
ARG_CHECK_ROUTER_L3HA_STATUS=
OPT_CHECK_ROUTER_L3HA_STATE_DIST=false

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

    AGENT:

    tbd

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
        --help|-h)
              usage
              exit 0
              ;;
    esac
    shift
done

if $OPT_CHECK_ROUTER_L3HA_STATUS || $use_default; then
    `dirname $0`/api/plugins.d/check_router_l3agent_ha_status $ARG_CHECK_ROUTER_L3HA_STATUS
elif $OPT_CHECK_ROUTER_L3HA_STATE_DIST; then
    `dirname $0`/api/plugins.d/check_router_l3agent_ha_state_distribution
else
    usage
fi

echo Done.

