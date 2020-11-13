#!/bin/bash -u
OPT_CHECK_ROUTER_L3HA_STATUS=true  # default to true since we have no other checks yet
ARG_CHECK_ROUTER_L3HA_STATUS=

usage ()
{
cat << EOF
USAGE: openstack-toolkit.neutron OPTIONS

DESCRIPTION
    Run the specified checks on Neutron resources. Supported checks are as follows:

    --check-l3ha-router-status [router]
        Check HA replica status for routers and report any that do not have exactly one "active".

        NOTE: this is currently the default.

EOF
}

while (($#)); do
    case "$1" in
        --check-l3ha-router-status)
          OPT_CHECK_ROUTER_L3HA_STATUS=true
          if (($#>1)) && [[ ${2:0:2} != "--" ]]; then
              ARG_CHECK_ROUTER_L3HA_STATUS=$2
              shift
          fi
          ;;
        --help|-h)
          usage
          exit 0
          ;;
    esac
    shift
done

if $OPT_CHECK_ROUTER_L3HA_STATUS; then
    `dirname $0`/plugins.d/check_router_l3agent_ha_status $ARG_CHECK_ROUTER_L3HA_STATUS
else
    usage
fi

echo Done.

