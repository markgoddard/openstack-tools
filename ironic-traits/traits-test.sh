#!/bin/bash

set -ex
set -o pipefail

export OS_BAREMETAL_API_VERSION=1.37
if [[ -z $OS_AUTH_URL ]]; then
    export OS_URL=http://localhost:6385
    export OS_TOKEN=fake
fi

NODE_UUID=$(uuidgen)
url=$(openstack endpoint list --service baremetal --interface public -f value -c URL)
token=$(openstack token issue -f value -c id)

function cleanup {
    echo "Cleaning up"
    openstack baremetal node delete $NODE_UUID
}

trap cleanup EXIT

openstack baremetal node create --driver fake-hardware --uuid $NODE_UUID

echo "Test 1: Set standard traits"
openstack baremetal node add trait $NODE_UUID HW_CPU_X86_VMX
openstack baremetal node show $NODE_UUID -f value --fields traits | grep HW_CPU_X86_VMX
openstack baremetal node remove trait $NODE_UUID HW_CPU_X86_VMX
openstack baremetal node show $NODE_UUID -f value --fields traits | grep HW_CPU_X86_VMX && false

echo "Test 2: Set custom traits"
openstack baremetal node add trait $NODE_UUID CUSTOM_TRAIT1
openstack baremetal node show $NODE_UUID -f value --fields traits | grep CUSTOM_TRAIT1
openstack baremetal node remove trait $NODE_UUID CUSTOM_TRAIT1
openstack baremetal node show $NODE_UUID -f value --fields traits | grep CUSTOM_TRAIT1 && false

echo "Test 3: Remove all traits"
openstack baremetal node add trait $NODE_UUID CUSTOM_TRAIT1 CUSTOM_TRAIT2
openstack baremetal node show $NODE_UUID -f value --fields traits | grep CUSTOM_TRAIT1
openstack baremetal node show $NODE_UUID -f value --fields traits | grep CUSTOM_TRAIT2
openstack baremetal node remove trait $NODE_UUID --all
openstack baremetal node show $NODE_UUID -f value --fields traits | grep CUSTOM_TRAIT1 && false
openstack baremetal node show $NODE_UUID -f value --fields traits | grep CUSTOM_TRAIT2 && false

echo "Test 4: Set all traits"
curl -f -g -i -X PUT $url/v1/nodes/$NODE_UUID/traits \
-H "X-OpenStack-Ironic-API-Version: 1.37" \
-H "Content-Type: application/json" \
-H "Accept: application/json" \
-H "X-Auth-Token: $token" \
-d '{"traits": ["CUSTOM_TRAIT1", "CUSTOM_TRAIT2"]}'
openstack baremetal node show $NODE_UUID -f value --fields traits | grep CUSTOM_TRAIT1
openstack baremetal node show $NODE_UUID -f value --fields traits | grep CUSTOM_TRAIT2
openstack baremetal node remove trait $NODE_UUID --all

echo "Test 5: Create node with traits"
curl -f -g -i -X POST $url/v1/nodes \
-H "X-OpenStack-Ironic-API-Version: 1.37" \
-H "Content-Type: application/json" \
-H "Accept: application/json" \
-H "X-Auth-Token: $token" \
-d '{"driver": "fake-hardware", "traits": []}' && false

echo "Test 6: Filter nodes by traits"
openstack baremetal node add trait $NODE_UUID CUSTOM_TRAIT1
curl -f -g -i -X GET $url/v1/nodes?traits=CUSTOM_1 \
-H "X-OpenStack-Ironic-API-Version: 1.37" \
-H "Content-Type: application/json" \
-H "Accept: application/json" \
-H "X-Auth-Token: $token" && false
openstack baremetal node remove trait $NODE_UUID --all

echo "Test 7: Send both trait and traits"
curl -f -g -i -X PUT $url/v1/nodes/$NODE_UUID/traits/CUSTOM_TRAIT1 \
-H "X-OpenStack-Ironic-API-Version: 1.37" \
-H "Content-Type: application/json" \
-H "Accept: application/json" \
-H "X-Auth-Token: $token" \
-d '{"traits": ["CUSTOM_TRAIT1", "CUSTOM_TRAIT2"]}' && false
openstack baremetal node show $NODE_UUID -f value --fields traits | grep CUSTOM_TRAIT1 && false
openstack baremetal node remove trait $NODE_UUID --all
