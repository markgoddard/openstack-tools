#!/bin/bash

# Create a 'fake' baremetal node, an instance for it, and all dependent
# resources (image, flavor, network, subnet, quotas, etc.)

# Requirements:
# python-openstackclient
# python-ironicclient
# OpenStack credential environment variables set.

set -e

IMAGE=test
FLAVOR=test
NETWORK=test
NODE=test
SERVER=test

NETWORK_INTERFACE=neutron
DISK=10
RAM=1024
CPUS=1
CPU_ARCH=x86_64
RESOURCE_CLASS=RC0
MAC=11:22:33:44:55:66

function cleanup {
  openstack server delete $SERVER || true
  openstack network delete $NETWORK || true
  openstack image delete $IMAGE || true
  openstack flavor delete $FLAVOR || true
  openstack baremetal node delete $NODE || true
}

if [[ $1 == cleanup ]]; then
  cleanup
  exit 0
elif [[ -n $1 ]]; then
  echo "Usage: $0 [cleanup]"
  exit 1
fi

# Create a node.
openstack baremetal node create \
--name $NODE \
--driver fake-hardware \
--boot-interface fake \
--deploy-interface fake \
--management-interface fake \
--network-interface $NETWORK_INTERFACE \
--power-interface fake \
--property local_gb=$DISK \
--property memory_mb=$RAM \
--property cpus=$CPUS \
--property cpu_arch=$CPU_ARCH \
--resource-class $RESOURCE_CLASS

node_uuid=$(openstack baremetal node show $NODE -f value -c uuid)

# Create a port.
if [[ $NETWORK_INTERFACE = noop ]]; then
    # For noop network interface:
    openstack baremetal port create \
    $MAC \
    --node $node_uuid
else
    # For neutron network interface:
    openstack baremetal port create \
    $MAC \
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
--vcpus $CPUS \
--ram $RAM \
--disk $DISK \
--property resources:CUSTOM_$RESOURCE_CLASS=1 \
--property resources:VCPUS=0 \
--property resources:MEMORY_MB=0 \
--property resources:DISK_GB=0 \
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
$SERVER \
--flavor $FLAVOR \
--image $IMAGE \
--network $NETWORK
