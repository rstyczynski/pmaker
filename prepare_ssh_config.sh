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

server_groups=$(cat data/$user_group.inventory.cfg | grep -v '^#' | grep '\[' | cut -f2 -d'[' | cut -f1 -d']' | grep -v jumps | grep -v controller)
# take from [env] section
#jump_server=$(cat data/$user_group.inventory.cfg | sed -n "/\[$server_group\]/,/^\[/p" | grep -v '\[' | grep -v '^$' | grep 'host_type=jump' | tr -s ' ' | tr ' ' '\n' | grep public_ip | cut -d'=' -f2)
# take from [jumps] sectino
group_jump_server=$(cat data/$user_group.inventory.cfg | sed -n "/\[jumps]/,/^\[/p" | grep "^$server_group\_jump" | tr -s ' ' | cut -f1 -d' ' )

tmp=$pmaker_home/tmp; mkdir -p $tmp

# take copy of ssh config w/o section
cat ~/.ssh/config | sed "/# START - $user_group $server_group access/,/# STOP - $user_group $server_group access/d" >$tmp/ssh_config

    cat >>$tmp/ssh_config <<EOF
# START - $user_group $server_group access
EOF

# prepare new ssh connection info for users / env
if [ ! -z "$group_jump_server" ]; then
    cat >>$tmp/ssh_config <<EOF
Host ${server_group}_jump
    HostName $group_jump_server
    ForwardAgent yes
    User $proxy_user
EOF
if [ $server_group_key != no ]; then
    cat >>$tmp/ssh_config <<EOF
    IdentityFile $server_group_key
EOF
fi
fi


hosts=$(cat data/$user_group.inventory.cfg | 
sed -n "/\[$server_group\]/,/^\[/p" | grep -v '\[' | 
grep -v '^$' | 
grep -v '^#' | 
cut -f1 -d' ')

for host in $hosts; do

    jump_server=$(cat data/$user_group.inventory.cfg | grep $host | tr -s ' ' | tr ' ' '\n' | grep "^jump=" | cut -d= -f2)
    
    if [ ! -z "$jump_server" ]; then
        cat >>$tmp/ssh_config<<EOF
Host $host
    ProxyJump $jump_server
EOF
        if [ $server_group_key != no ]; then
    cat >>$tmp/ssh_config <<EOF
    IdentityFile $server_group_key
EOF
        fi
    else
        if [ -z "$group_jump_server" ]; then
            echo "Error. jump server does not found in inventory file."
            exit 1
        fi
        cat >>$tmp/ssh_config<<EOF
Host $host
    ProxyJump $group_jump_server
EOF
        if [ $server_group_key != no ]; then
            cat >>$tmp/ssh_config <<EOF
    IdentityFile $server_group_key
EOF
        fi
    fi
done

echo "# STOP - $user_group $server_group access" >>$tmp/ssh_config

mv ~/.ssh/config ~/.ssh/config.old
mv $tmp/ssh_config ~/.ssh/config
chmod 600 ~/.ssh/config