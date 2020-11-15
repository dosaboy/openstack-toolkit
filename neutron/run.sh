#!/bin/bash -u
OPT_CHECK_ROUTER_L3HA_STATUS=false
ARG_CHECK_ROUTER_L3HA_STATUS=
OPT_CHECK_ROUTER_L3HA_STATE_DIST=false

usage ()
{
cat << EOF
USAGE: openstack-toolkit.neutron OPTIONS

DESCRIPTION
    Run the specified checks on Neutron resources. Supported checks are as follows:

    --check-l3ha-router-status [router]
        Check HA replica status for routers and report any that do not have exactly one "active".

        NOTE: this is currently the default.

    --check-l3ha-router-state-distribution

        Show tally of active/standby counts for HA routers per host/l3-agent.

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
    `dirname $0`/plugins.d/check_router_l3agent_ha_status $ARG_CHECK_ROUTER_L3HA_STATUS
elif $OPT_CHECK_ROUTER_L3HA_STATE_DIST; then
    `dirname $0`/plugins.d/check_router_l3agent_ha_state_distribution
else
    usage
fi

echo Done.

