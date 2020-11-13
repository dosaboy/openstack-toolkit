#!/bin/bash -u
OPT_ENSURE_LB_MEMBER_SG_RULES=true  # default to true since we have no other checks yet
ARG_ENSURE_LB_MEMBER_SG_RULES=

usage ()
{
cat << EOF
USAGE: openstack-toolkit.octavia OPTIONS

DESCRIPTION
    Run the specified checks on Neutron resources. Supported checks are as follows:

    --ensure-member-sg-rules [loadbalancer]
        Check all members of loadbalancers to ensure that their corresponding instances are using a port with a security group that allows access for loadbalanced packets. If a loadbalancer uuid is provided it will be checked otherwise all loadbalancers will be checked.

        NOTE: this is currently the default.

EOF
}

while (($#)); do
    case "$1" in
        --ensure-member-sg-rules)
          OPT_ENSURE_LB_MEMBER_SG_RULES=true
          if (($#>1)) && [[ ${2:0:2} != "--" ]]; then
              ARG_ENSURE_LB_MEMBER_SG_RULES=$2
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

if $OPT_ENSURE_LB_MEMBER_SG_RULES; then
    `dirname $0`/plugins.d/ensure_member_security_groups $ARG_ENSURE_LB_MEMBER_SG_RULES
else
    usage
fi

echo Done.

