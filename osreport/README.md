# OpenStack Report Plugin

Collects OpenStack information for a cloud.

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



