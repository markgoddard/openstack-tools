#!/bin/bash

# Create a baremetal node backed by a VM, an instance for it, and all dependent
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
KEYPAIR=test
SERVER=test

CIRROS_VERSION=0.3.5

NETWORK_INTERFACE=neutron
DISK=10
RAM=1024
CPUS=1
CPU_ARCH=x86_64
RESOURCE_CLASS=RC0

function cleanup {
  openstack server delete $SERVER || true
  openstack keypair delete $KEYPAIR || true
  openstack network delete $NETWORK || true
  openstack image delete $IMAGE || true
  openstack flavor delete $FLAVOR || true
  openstack baremetal node delete $NODE || true
  sudo vbmc-venv/bin/vbmc stop $NODE || true
  sudo vbmc-venv/bin/vbmc remove $NODE || true
  sudo virsh destroy $NODE || true
  sudo virsh undefine $NODE || true
  sudo virsh vol-delete $NODE-root
}

if [[ $1 == cleanup ]]; then
  cleanup
  exit 0
elif [[ -n $1 ]]; then
  echo "Usage: $0 [cleanup]"
  exit 1
fi

# Install libvirt hypervisor
sudo yum -y install ansible
sudo pip install -U 'jinja2<2.9'
mkdir -p roles
ansible-galaxy install stackhpc.libvirt-host -p roles
ansible-playbook libvirt-host.yml

# Create bare metal VM
sudo virsh vol-create-as --pool default --name $NODE-root --capacity ${DISK}G --format qcow2
sudo virsh define $PWD/bm.xml
sudo virsh start $NODE
sleep 120

# Install VBMC
sudo yum -y install libvirt-devel
virtualenv vbmc-venv
vbmc-venv/bin/pip install -U pip
vbmc-venv/bin/pip install virtualbmc
# sudo required for libvirt currently
sudo vbmc-venv/bin/vbmc add $NODE --port 1234 --username admin --password admin
sudo vbmc-venv/bin/vbmc start $NODE

# Fix up ironic node.
node_uuid=$(openstack baremetal node list -f value --fields uuid)
openstack baremetal node set \
$node_uuid \
--name $NODE \
--driver-info ipmi_address=127.0.0.1 \
--driver-info ipmi_username=admin \
--driver-info ipmi_password=admin \
--driver-info ipmi_port=1234 \
--driver ipmi \
--boot-interface pxe \
--deploy-interface iscsi \
--management-interface ipmitool \
--network-interface $NETWORK_INTERFACE \
--power-interface ipmitool \
--resource-class $RESOURCE_CLASS

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
curl \
  -o cirros-${CIRROS_VERSION}-x86_64-disk.img \
  http://download.cirros-cloud.net/${CIRROS_VERSION}/cirros-${CIRROS_VERSION}-x86_64-disk.img
openstack image create \
  $IMAGE \
  --container-format bare \
  --disk-format raw \
  --public \
  --file cirros-${CIRROS_VERSION}-x86_64-disk.img

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
--provider-network-type flat \
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

# Create an SSH keypair
openstack keypair create \
  --public-key ~/.ssh/id_rsa \
  $KEYPAIR

# Create an instance
openstack server create \
$SERVER \
--flavor $FLAVOR \
--image $IMAGE \
--network $NETWORK \
--key-name $KEYPAIR
