#!/bin/bash
user_group=$1
server_group=$2

function usage() {
    echo Usage: prepare_ssh_config.sh user_group server_group
}

if [ -z "$user_group" ] || [ -z "$server_group" ]; then
    usage
fi

server_groups=$(cat data/$user_group.inventory.cfg | grep '\[' | cut -f2 -d'[' | cut -f1 -d']' | grep -v jumps | grep -v controller)

jump_server=$(cat data/$user_group.inventory.cfg | sed -n "/\[$server_group\]/,/^\[/p" | grep -v '\[' | grep -v '^$' | grep 'host_type=jump' | tr -s ' ' | tr ' ' '\n' | grep public_ip | cut -d'=' -f2)

cat >>~/.ssh/config <<EOF

host ${server_group}_jump
    HostName $jump_server
    User opc
    IdentityFile ~/.ssh/${server_group}.key
    ForwardAgent yes
EOF

hosts=$(cat data/ocs.inventory.cfg | sed -n "/\[$server_group\]/,/^\[/p" | grep -v '\[' | grep -v '^$' | grep -v 'host_type=jump' | cut -f1 -d' ')

for host in $hosts; do
    cat >>~/.ssh/config <<EOF
host $host
    ProxyJump ${server_group}_jump
EOF
done
