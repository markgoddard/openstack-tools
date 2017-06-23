#!/bin/bash -ex

# Add segments to neutron.conf [DEFAULT] extensions.

export OS_BAREMETAL_API_VERSION=1.32
if [[ -z $OS_AUTH_URL ]]; then
    export OS_URL=http://localhost:6385
    export OS_TOKEN=fake
fi

NODE_UUID=$(uuidgen)
PORT1_MAC='00:11:22:33:44:01'
PORT2_MAC='00:11:22:33:44:02'
PORT3_MAC='00:11:22:33:44:03'
PORT4_MAC='00:11:22:33:44:04'
PORT5_MAC='00:11:22:33:44:05'
LLC_SI=switch_id=00:11:22:33:44:55
LLC_PI=port_id=x1234

function cleanup {
        echo "Cleaning up"

        [[ -n $PORT5_UUID ]] && openstack baremetal port delete $PORT5_UUID
        [[ -n $PORT4_UUID ]] && openstack baremetal port delete $PORT4_UUID
        [[ -n $PORT3_UUID ]] && openstack baremetal port delete $PORT3_UUID
        [[ -n $PORT2_UUID ]] && openstack baremetal port delete $PORT2_UUID
        [[ -n $PORT1_UUID ]] && openstack baremetal port delete $PORT1_UUID
        [[ -n $PG1_UUID ]] && openstack baremetal port group delete $PG1_UUID
        openstack baremetal node delete $NODE_UUID || true

        openstack port delete flat-physnet1 || true
        openstack network delete flat-physnet1 || true
        openstack port delete flat-physnet2 || true
        openstack network delete flat-physnet2 || true
        openstack port delete flat-physnet3-and-4 || true
        openstack network delete flat-physnet3-and-4 || true
        openstack port delete flat-physnet5 || true
        openstack port delete flat-physnet5-2 || true
        openstack network delete flat-physnet5 || true
}

trap cleanup EXIT

function setup {
    openstack network create flat-physnet1 --provider-physical-network physnet1 --provider-network-type flat
    VIF1_UUID=$(openstack port create --network flat-physnet1 flat-physnet1 -f value -c id)

    openstack network create flat-physnet2 --provider-physical-network physnet2 --provider-network-type flat
    VIF2_UUID=$(openstack port create --network flat-physnet2 flat-physnet2 -f value -c id)

    openstack network create flat-physnet3-and-4 --provider-physical-network physnet3 --provider-network-type flat
    openstack network segment create --network flat-physnet3-and-4 --network-type flat --physical-network physnet4 flat-physnet4
    VIF3_UUID=$(openstack port create --network flat-physnet3-and-4 flat-physnet3-and-4 -f value -c id)

    openstack network create flat-physnet5 --provider-physical-network physnet5 --provider-network-type flat
    VIF4_UUID=$(openstack port create --network flat-physnet5 flat-physnet5 -f value -c id)
    VIF5_UUID=$(openstack port create --network flat-physnet5 flat-physnet5-2 -f value -c id)

    openstack baremetal node create --driver fake-hardware --network-interface neutron --name vif-test --uuid $NODE_UUID --driver-info ipmi_address=10.45.253.1 --driver-info ipmi_username=root --driver-info ipmi_password=calvin
    openstack baremetal node manage vif-test
    sleep 1
    openstack baremetal node provide vif-test

    PG1_UUID=$(openstack baremetal port group create --node $NODE_UUID -f value -c uuid)
    PORT1_UUID=$(openstack baremetal port create --node $NODE_UUID --local-link-connection $LLC_SI --local-link-connection $LLC_PI $PORT1_MAC --physical-network physnet1 -f value -c uuid)
    PORT2_UUID=$(openstack baremetal port create --node $NODE_UUID --local-link-connection $LLC_SI --local-link-connection $LLC_PI $PORT2_MAC --physical-network physnet2 --port-group $PG1_UUID -f value -c uuid)
    PORT3_UUID=$(openstack baremetal port create --node $NODE_UUID --local-link-connection $LLC_SI --local-link-connection $LLC_PI $PORT3_MAC --physical-network physnet3 -f value -c uuid)
    PORT4_UUID=$(openstack baremetal port create --node $NODE_UUID --local-link-connection $LLC_SI --local-link-connection $LLC_PI $PORT4_MAC -f value -c uuid)
    PORT5_UUID=$(openstack baremetal port create --node $NODE_UUID --local-link-connection $LLC_SI --local-link-connection $LLC_PI $PORT5_MAC --physical-network physnet2 -f value -c uuid)
}

function get_port_attached_vif {
    openstack baremetal port show $1 -f value -c internal_info | sed -e "s/{u'tenant_vif_port_id': u'//" -e "s/'}//"
}

function get_portgroup_attached_vif {
    openstack baremetal port group show $1 -f value -c internal_info | sed -e "s/{u'tenant_vif_port_id': u'//" -e "s/'}//"
}

setup

echo "Test 1: VIF on physnet1 -> port on physnet1"
openstack baremetal node vif attach vif-test $VIF1_UUID
ATTACHED_VIF=$(openstack baremetal node vif list vif-test -f value -c ID)
[[ $ATTACHED_VIF = $VIF1_UUID ]]
ATTACHED_VIF=$(get_port_attached_vif $PORT1_UUID)
[[ $ATTACHED_VIF = $VIF1_UUID ]]
openstack baremetal node vif detach vif-test $VIF1_UUID

echo "Test 2: VIF on physnet2 -> portgroup on physnet2"
openstack baremetal node vif attach vif-test $VIF2_UUID
ATTACHED_VIF=$(openstack baremetal node vif list vif-test -f value -c ID)
[[ $ATTACHED_VIF = $VIF2_UUID ]]
ATTACHED_VIF=$(get_portgroup_attached_vif $PG1_UUID)
[[ $ATTACHED_VIF = $VIF2_UUID ]]
openstack baremetal node vif detach vif-test $VIF2_UUID

echo "Test 3: VIF on physnet3 and physnet4 -> port on physnet3"
openstack baremetal node vif attach vif-test $VIF3_UUID
ATTACHED_VIF=$(openstack baremetal node vif list vif-test -f value -c ID)
[[ $ATTACHED_VIF = $VIF3_UUID ]]
ATTACHED_VIF=$(get_port_attached_vif $PORT3_UUID)
[[ $ATTACHED_VIF = $VIF3_UUID ]]
openstack baremetal node vif detach vif-test $VIF3_UUID

echo "Test 4: VIF on physnet5 -> port on no physnet"
openstack baremetal node vif attach vif-test $VIF4_UUID
ATTACHED_VIF=$(openstack baremetal node vif list vif-test -f value -c ID)
[[ $ATTACHED_VIF = $VIF4_UUID ]]
ATTACHED_VIF=$(get_port_attached_vif $PORT4_UUID)
[[ $ATTACHED_VIF = $VIF4_UUID ]]
openstack baremetal node vif detach vif-test $VIF4_UUID

echo "Test 5: All VIFS"
openstack baremetal node vif attach vif-test $VIF1_UUID
openstack baremetal node vif attach vif-test $VIF2_UUID
openstack baremetal node vif attach vif-test $VIF3_UUID
openstack baremetal node vif attach vif-test $VIF4_UUID
ATTACHED_VIF=$(get_port_attached_vif $PORT1_UUID)
[[ $ATTACHED_VIF = $VIF1_UUID ]]
ATTACHED_VIF=$(get_portgroup_attached_vif $PG1_UUID)
[[ $ATTACHED_VIF = $VIF2_UUID ]]
ATTACHED_VIF=$(get_port_attached_vif $PORT3_UUID)
[[ $ATTACHED_VIF = $VIF3_UUID ]]
ATTACHED_VIF=$(get_port_attached_vif $PORT4_UUID)
[[ $ATTACHED_VIF = $VIF4_UUID ]]
openstack baremetal node vif detach vif-test $VIF4_UUID
openstack baremetal node vif detach vif-test $VIF3_UUID
openstack baremetal node vif detach vif-test $VIF2_UUID
openstack baremetal node vif detach vif-test $VIF1_UUID

echo "Test 6: Failure"
openstack baremetal node vif attach vif-test $VIF4_UUID
if openstack baremetal node vif attach vif-test $VIF5_UUID; then
    echo "Expected attachment to fail"
    exit 1
fi
