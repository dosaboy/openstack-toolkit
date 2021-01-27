#!/bin/bash -u
export LIB_PATH=$(dirname $0)/../lib

export OSREPORT_OUTPUT_DIR=$(mktemp -d -p . osreport.XXXXXX)

SUPPORTED_PLUGINS="neutron,nova,octavia,nova-hypervisors"

check_plugin_list(){
    IFS=","
    for plugin in $1; do
        supported="False"
        for supported_plugin in ${SUPPORTED_PLUGINS}; do
            if [ "${plugin}" == "${supported_plugin}" ]; then
                supported=True
                break
            fi
        done

        if [ "${supported}" == "False" ]; then
            echo "${plugin} is not a supported plugin"
            usage
            exit 1
        fi
    done
    IFS=$' \t\n'
}

usage () {
cat << EOF
Usage: openstack-toolkit.osreport <options>

Description:
    Collects OpenStack information for a cloud and builds useful relations
    between the cloud resources.

Options:
  --help: Print this info.
  --plugins <plugins>: Can be any of: neutron, nova, nova-hypervisors or octavia. You can
    use multiple options separated by commas.
  --all-plugins: Runs all the above plugins. Can take some time to run.

Environment:
    OS_AUTH_URL
    OS_AUTH_VERSION
    OS_IDENTITY_API_VERSION
    OS_PASSWORD
    OS_PROJECT_DOMAIN_NAME
    OS_PROJECT_NAME
    OS_REGION_NAME
    OS_USERNAME
    OS_USER_DOMAIN_NAME
EOF
}

plugins=${SUPPORTED_PLUGINS}
while (($#)); do
    case "$1" in
        --plugins)
            plugins=${2:-}
            shift
            ;;
        --all-plugins)
            plugins=${SUPPORTED_PLUGINS}
            ;;
        --help|-h)
            usage
            exit 0
            ;;
    esac
    shift
done

api_plugins=`dirname $0`/api/plugins.d
agent_plugins=`dirname $0`/agent/plugins.d

if [ -z ${OS_AUTH_URL} ] || [ -z ${OS_PROJECT_NAME} ] || [ -z ${OS_USERNAME} ];
then
    echo "OS_ environment vars should be set"
    usage
    exit 1
fi

if [ ${OS_USERNAME} != "admin" ]; then
    echo "OS_USERNAME must be admin"
    exit 1
fi

if [ -e ${plugins} ]; then
    echo "No plugins selected".
    usage
    exit 1
fi

echo "Plugins list is: ${plugins}"
check_plugin_list ${plugins}

mkdir -p ${OSREPORT_OUTPUT_DIR}

## Run common scripts in the sequence they need to be
for common_src in "neutron-common" "nova-common"; do
    echo "Collecting ${common_src} information..."
    . ${api_plugins}/${common_src}
done

IFS=","
for plugin in ${plugins}; do
    IFS=$' \t\n'

    echo "Collecting ${plugin} information..."
    . ${api_plugins}/${plugin}
done

echo "Compressing results..."
REPORT_NAME="osreport-$(date +%Y-%m-%d_%H%M).tar.xz"
tar -Jcvf ${REPORT_NAME} ${OSREPORT_OUTPUT_DIR} &> /dev/null
echo "Done. Report created in ${REPORT_NAME}"

