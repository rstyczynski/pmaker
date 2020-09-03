#!/bin/bash
user_group=$1
server_group=$2
proxy_user=$3
server_group_key=$4

function usage() {
    echo Usage: prepare_ssh_config.sh user_group server_group
}

if [ -z "$user_group" ] || [ -z "$server_group" ]; then
    usage
    exit 1
fi

: ${proxy_user:=opc}
: ${server_group_key:=no}

server_groups=$(cat data/$user_group.inventory.cfg | grep '\[' | cut -f2 -d'[' | cut -f1 -d']' | grep -v jumps | grep -v controller)
# take from [env] section
#jump_server=$(cat data/$user_group.inventory.cfg | sed -n "/\[$server_group\]/,/^\[/p" | grep -v '\[' | grep -v '^$' | grep 'host_type=jump' | tr -s ' ' | tr ' ' '\n' | grep public_ip | cut -d'=' -f2)
# take from [jumps] sectino
jump_server=$(cat data/$user_group.inventory.cfg | sed -n "/\[jumps]/,/^\[/p" | grep "$server_group\_jump" | tr -s ' ' | tr ' ' '\n' | grep public_ip | cut -d= -f2)

if [ -z "$jump_server" ]; then
    echo "Error. jump server does not found in inventory file."
    return 1
fi

# TODO add confiog secuton update using "cron" technique

cat >>~/.ssh/config <<EOF

host ${server_group}_jump
    HostName $jump_server
    ForwardAgent yes
    User $proxy_user
EOF

if [ $server_group_key != no ]; then
cat >>~/.ssh/config <<EOF
    IdentityFile ~/.ssh/${server_group_key}.key
EOF
fi

hosts=$(cat data/$user_group.inventory.cfg | sed -n "/\[$server_group\]/,/^\[/p" | grep -v '\[' | grep -v '^$' | cut -f1 -d' ')

for host in $hosts; do
    cat >>~/.ssh/config <<EOF
host $host
    ProxyJump ${server_group}_jump
EOF
done
