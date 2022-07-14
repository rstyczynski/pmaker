#/bin/bash

function test_ssh_connectivity() {
  test_user=$1

  hosts_ip=$(cat $pmaker_home/data/$user_group.inventory.cfg | sed -n "/\[$env\]/,/\[/p" | egrep -v '\[|$^|#' |
  cut -f1 -d' ')

    for host_ip in $hosts_ip; do

    response_ip=$(ssh $test_user@$host_ip hostname -i)

    if [ "$response_ip" = $host_ip ]; then
      echo "Connectivity to $host_ip OK."
    else
      echo "Connectivity error. Expected: $host_ip, but received: $response_ip"

    fi
  done
}

test_ssh_connectivity $1