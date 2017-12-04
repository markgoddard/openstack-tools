#!/bin/bash

set -e

function get_status {
  local name=$1
  openstack server show $name -f value -c status
}

function get_ip {
  local name=$1
  local network=$2
  openstack server show $name -f value -c addresses | awk "\$1 ~ $network { print \$1 }" | sed -e "s/$network=//" -e "s/;//"
}

function run_ssh {
  local name=$1
  local network=$2
  local user=$3
  shift; shift; shift
  local commands=$@
  local ip=$(get_ip $name $network)
  # Don't use password authentication - otherwise we may get stuck at a
  # password prompt.
  local options="-o StrictHostKeyChecking=no -o PasswordAuthentication=no"
  ssh $user@$ip $options $commands
}

function wait_for_active {
  local name=$1
  local interval=10
  echo "Waiting for $name to become active"
  while true; do
    status=$(get_status $name)
    if [[ $status = ACTIVE ]]; then
      break
    fi
    if [[ $status = ERROR ]]; then
      echo "Instance $name went to ERROR while waiting for ACTIVE"
      return 1
    fi
    sleep $interval
  done
}

function wait_for_ssh {
  local name=$1
  local network=$2
  local user=$3
  local interval=10
  echo "Waiting for $name SSH access"
  until run_ssh $name $network $user hostname; do
    echo "Waiting for SSH access to $name ($user@$ip)"
    sleep $interval
  done
}

function wait_for_delete {
  local name=$1
  local interval=10
  echo "Waiting for $name to be deleted"
  while openstack server show $name >/dev/null 2>&1; do
    sleep $interval
  done
}

function check_networking {
  local name=$1
  local network=$2
  local user=$3
  run_ssh $name $network $user ping -c 1 google.com
}

function create_delete {
  local instance_name=$1
  local create_args=$2
  local ssh_network=$3
  local ssh_user=$4
  openstack server create $instance_name $create_args
  wait_for_active $instance_name
  wait_for_ssh $instance_name $ssh_network $ssh_user
  check_networking $instance_name $ssh_network $ssh_user
  openstack server delete $instance_name
  wait_for_delete $instance_name
  sleep 30
}

function usage {
  echo "Usage: $0"
  echo
  echo "Environment variables:"
  echo "BCDR_INSTANCE_NAME"
  echo "BCDR_CREATE_ARGS"
  echo "BCDR_SSH_NETWORK"
  echo "BCDR_SSH_USER"
}

function main {
  local instance_name=$BCDR_INSTANCE_NAME
  local create_args=$BCDR_CREATE_ARGS
  local ssh_network=$BCDR_SSH_NETWORK
  local ssh_user=$BCDR_SSH_USER
  if [[ $1 = -h ]]; then
    usage
    exit 0
  fi
  if [[ -z $instance_name ]] || [[ -z $create_args ]] || [[ -z $ssh_network ]] || [[ -z $ssh_user ]]; then
    echo "One or more required configuration variables not provided"
    exit 1
  fi
  local count=1
  while true; do
    echo "Attempt $count"
    create_delete $instance_name "$create_args" $ssh_network $ssh_user
    count=$((count + 1))
  done
}

main $@
