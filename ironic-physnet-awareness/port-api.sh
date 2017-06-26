#!/bin/bash -ex

export OS_BAREMETAL_API_VERSION=1.32
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
openstack baremetal port set $PORT1_UUID --physical-network physnet1
openstack baremetal port delete $PORT1_UUID

echo "Test 2: No portgroup, with physnet, set physnet, unset physnet"
PORT1_UUID=$(openstack baremetal port create --node $NODE_UUID $PORT1_MAC --physical-network physnet1 -f value -c uuid)
openstack baremetal port set $PORT1_UUID --physical-network physnet2
openstack baremetal port unset $PORT1_UUID --physical-network
openstack baremetal port delete $PORT1_UUID

echo "Test 3: Empty portgroup, no physnet, set physnet, unset portgroup"
PG1_UUID=$(openstack baremetal port group create --node $NODE_UUID -f value -c uuid)
PORT1_UUID=$(openstack baremetal port create --node $NODE_UUID $PORT1_MAC --port-group $PG1_UUID -f value -c uuid)
openstack baremetal port set $PORT1_UUID --physical-network physnet1
openstack baremetal port unset $PORT1_UUID --port-group
openstack baremetal port delete $PORT1_UUID
openstack baremetal port group delete $PG1_UUID

echo "Test 4: Empty portgroup, with physnet, set physnet, unset physnet, unset portgroup"
PG1_UUID=$(openstack baremetal port group create --node $NODE_UUID -f value -c uuid)
PORT1_UUID=$(openstack baremetal port create --node $NODE_UUID $PORT1_MAC --port-group $PG1_UUID --physical-network physnet1 -f value -c uuid)
openstack baremetal port set $PORT1_UUID --physical-network physnet2
openstack baremetal port unset $PORT1_UUID --physical-network
openstack baremetal port unset $PORT1_UUID --port-group
openstack baremetal port delete $PORT1_UUID
openstack baremetal port group delete $PG1_UUID

echo "Test 5: 1-port portgroup, no physnet, set physnet, unset portgroup..."
PG1_UUID=$(openstack baremetal port group create --node $NODE_UUID -f value -c uuid)
PORT1_UUID=$(openstack baremetal port create --node $NODE_UUID $PORT1_MAC --port-group $PG1_UUID -f value -c uuid)
PORT2_UUID=$(openstack baremetal port create --node $NODE_UUID $PORT2_MAC --port-group $PG1_UUID -f value -c uuid)
PORT3_UUID=$(openstack baremetal port create --node $NODE_UUID $PORT3_MAC --physical-network physnet1 -f value -c uuid)
if openstack baremetal port set $PORT1_UUID --physical-network physnet1; then
    exit 1
fi
openstack baremetal port unset $PORT1_UUID --port-group
openstack baremetal port set $PORT1_UUID --port-group $PG1_UUID
if openstack baremetal port set $PORT3_UUID --port-group $PG1_UUID; then
    exit 1
fi
openstack baremetal port delete $PORT1_UUID
openstack baremetal port delete $PORT2_UUID
openstack baremetal port delete $PORT3_UUID
openstack baremetal port group delete $PG1_UUID

echo "Test 6: 1-port portgroup, with physnet, set physnet, unset portgroup"
PG1_UUID=$(openstack baremetal port group create --node $NODE_UUID -f value -c uuid)
PORT1_UUID=$(openstack baremetal port create --node $NODE_UUID $PORT1_MAC --port-group $PG1_UUID --physical-network physnet1 -f value -c uuid)
PORT2_UUID=$(openstack baremetal port create --node $NODE_UUID $PORT2_MAC --port-group $PG1_UUID --physical-network physnet1 -f value -c uuid)
PORT3_UUID=$(openstack baremetal port create --node $NODE_UUID $PORT3_MAC --physical-network physnet2 -f value -c uuid)
if openstack baremetal port set $PORT1_UUID --physical-network physnet2; then
    exit 1
fi
if openstack baremetal port unset $PORT1_UUID --physical-network; then
    exit 1
fi
openstack baremetal port unset $PORT1_UUID --port-group
openstack baremetal port set $PORT1_UUID --port-group $PG1_UUID
if openstack baremetal port set $PORT3_UUID --port-group $PG1_UUID; then
    exit 1
fi
openstack baremetal port unset $PORT3_UUID --physical-network
if openstack baremetal port set $PORT3_UUID --port-group $PG1_UUID; then
    exit 1
fi
openstack baremetal port delete $PORT1_UUID
openstack baremetal port delete $PORT2_UUID
openstack baremetal port delete $PORT3_UUID
openstack baremetal port group delete $PG1_UUID
