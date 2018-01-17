#!/bin/bash

# Create a 'fake' baremetal node, an instance for it, and all dependent
# resources (image, flavor, network, subnet, quotas, etc.)

# Requirements:
# python-openstackclient
# python-ironicclient
# OpenStack credential environment variables set.

set -e

IMAGE=test
FLAVOR=compute-A
NETWORK=test-net
NETWORK_INTERFACE=neutron

# Create a node.
openstack baremetal node create \
--name test \
--driver fake-hardware \
--network-interface $NETWORK_INTERFACE \
--property local_gb=222 \
--property memory_mb=262144 \
--property cpus=40 \
--property cpu_arch=x86_64
node_uuid=$(openstack baremetal node show test -f value -c uuid)

# Create a port.
if [[ $NETWORK_INTERFACE = noop ]]; then
    # For noop network interface:
    openstack baremetal port create \
    11:22:33:44:55:66 \
    --node $node_uuid
else
    # For neutron network interface:
    openstack baremetal port create \
    11:22:33:44:55:66 \
    --node $node_uuid \
    --local-link-connection switch_id=00:11:22:33:44:55 \
    --local-link-connection port_id=eth0
fi

# Make the node available for use:
openstack baremetal node power off test
openstack baremetal node manage test
openstack baremetal node provide test
openstack baremetal node validate test

# Wait for the nova hypervisor’s resources to be populated:
until openstack hypervisor show $node_uuid >/dev/null 2>&1; do
    echo "Waiting for node to appear as a nova hypervisor"
    sleep 10
done

until [[ $(openstack hypervisor show $node_uuid -f value -c free_ram_mb) -ne 0 ]]; do
    echo "Waiting for node's nova hypervisor to become schedulable"
    sleep 10
done

# Create a fake image:
echo hi > hi
openstack image create $IMAGE < hi

# Create a flavor:
openstack flavor create \
$FLAVOR \
--vcpus 40 \
--ram 262144 \
--disk 222 \
--public

# Create a network:
openstack network create \
$NETWORK \
--provider-network-type vlan \
--provider-segment 42 \
--provider-physical-network physnet1

# Create a subnet:
openstack subnet create \
$NETWORK \
--network $NETWORK \
--subnet-range 10.0.0.0/24

openstack quota set $OS_PROJECT_NAME \
  --ram -1 \
  --key-pairs -1 \
  --instances -1 \
  --fixed-ips -1 \
  --cores -1 \
  --ports -1 \
  --subnets -1 \
  --networks -1

# Create an instance
openstack server create \
test \
--flavor $FLAVOR \
--image $IMAGE \
--network $NETWORK
