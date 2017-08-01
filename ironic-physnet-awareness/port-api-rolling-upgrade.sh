#!/bin/bash -ex

# Tests for port physical networks during rolling upgrades.

export OS_BAREMETAL_API_VERSION=1.34
if [[ -z $OS_AUTH_URL ]]; then
    export OS_URL=http://localhost:6385
    export OS_TOKEN=fake
fi

NODE_UUID=$(uuidgen)
PORT1_MAC='00:11:22:33:44:55'
PORT2_MAC='00:11:22:33:44:56'
PORT3_MAC='00:11:22:33:44:57'

function cleanup {
	echo "Cleaning up"
	openstack baremetal node delete $NODE_UUID
}

trap cleanup EXIT

openstack baremetal node create --driver fake --uuid $NODE_UUID

echo "Test 1: No portgroup, no physnet, set physnet"
PORT1_UUID=$(openstack baremetal port create --node $NODE_UUID $PORT1_MAC -f value -c uuid)
if openstack baremetal port set $PORT1_UUID --physical-network physnet1; then
    echo "Setting physnet should fail during upgrade"
    exit 1
fi
if openstack baremetal port unset $PORT1_UUID --physical-network; then
    echo "Unsetting physnet should fail during upgrade"
    exit 1
fi
openstack baremetal port delete $PORT1_UUID

echo "Test 2: No portgroup, with physnet"
if openstack baremetal port create --node $NODE_UUID $PORT1_MAC --physical-network physnet1 -f value -c uuid; then
    echo "Creating port with physnet should fail during upgrade"
    exit 1
fi

echo "Test 3: Empty portgroup, no physnet"
PG1_UUID=$(openstack baremetal port group create --node $NODE_UUID -f value -c uuid)
if openstack baremetal port create --node $NODE_UUID $PORT1_MAC --port-group $PG1_UUID -f value -c uuid; then
    echo "Creating port in portgroup should fail during upgrade"
    exit 1
fi
openstack baremetal port group delete $PG1_UUID

echo "Test 4: No portgroup, no physnet, add to portgroup, remove from portgroup"
PG1_UUID=$(openstack baremetal port group create --node $NODE_UUID -f value -c uuid)
PORT1_UUID=$(openstack baremetal port create --node $NODE_UUID $PORT1_MAC -f value -c uuid)
openstack baremetal port set $PORT1_UUID --port-group $PG1_UUID
openstack baremetal port unset $PORT1_UUID --port-group
openstack baremetal port delete $PORT1_UUID
openstack baremetal port group delete $PG1_UUID
