#!/bin/bash

user_group=$1
shift
server_groups=$1
shift
user_to_process=$1
shift

function usage() {
    echo Usage: revoke_keys.sh user_group [server_groups]
    echo server_groups defaults to all
}

if [ -z "$user_group" ]; then
    usage
    error 1
fi

if [ -z "$pmaker_home" ]; then
    pmaker_home=/opt/pmaker
fi

function j2y() {
    ruby -ryaml -rjson -e 'puts YAML.dump(JSON.parse(STDIN.read))'
}

function y2j() {
    ruby -ryaml -rjson -e 'puts JSON.dump(YAML.load(STDIN.read))'
}

if [ -z "$server_groups" ]; then
    server_groups=$(cat data/$user_group.users.yaml | y2j | jq -r '[.users[].server_groups[]] | unique | .[]')
    #Source: https://stackoverflow.com/questions/29822622/get-all-unique-json-key-names-with-jq
fi

echo '==========================================================================='
echo " Configuring servers: $server_groups"
echo '==========================================================================='
for server_group in $server_groups; do
    server_list=$(ansible-inventory -i data/$user_group.inventory.cfg -y --list | y2j | jq -r "[.all.children.$server_group.hosts | keys[]] | unique | .[]")

    echo '========================='
    echo Processing env: $server_group
    echo \-having servers: $server_list
    echo '========================='

    # TODO select proper pmaker key
    if [ -f ~/.ssh/$server_group.key ]; then
        ssh-add ~/.ssh/$server_group.key
    fi

    # users=$(cat state/$user_group/$server_group/users.yaml | y2j | jq -r ".users[].username")
    

    if [ -z "$user_to_process" ]; then
    # use list of users known to the system i.e. already registered. 
    # this list may be different from users.yaml i.e. older
    users="pmaker $(ls state/$user_group/$server_group | grep -v users.yaml)"
    else
        users=$user_to_process
    fi

    # revoke key from pmaker, and known users
    for username in $users; do

        echo '========================='
        echo Processing user: $username
        echo '========================='

        if [ $user_group == pmaker ]; then
            ssh_root=$pmaker_home/.ssh
        else
            ssh_root=$pmaker_home/state/$user_group/$server_group/$username/.ssh
        fi

        # execute revoke procedure
        ansible-playbook  \
        setup/pmaker_revoke_keys.yaml \
        -e pmaker_type=env \
        -e server_group=$server_group \
        -e user_group=$user_group \
        -l $server_group \
        -i data/$user_group.inventory.cfg

        # check if all keys were revoked
        known_servers=$(ls $ssh_root/servers | grep -v localhost | wc -l)

        if [ ! -z "$known_servers" ]  && [ $known_servers -gt 0 ]; then
            revoked_keys=$(find $ssh_root/servers -name id_rsa.revoked | wc -l)
            if [ $revoked_keys -eq $known_servers ]; then
                echo OK
                # all done - change main rsa_id to unique name, kept to historical purposes
                mv $ssh_root/id_rsa.revoke $ssh_root/$(sha1sum $ssh_root/id_rsa | cut -f1 -d' ').revoked
                mv $ssh_root/id_rsa $ssh_root/$(sha1sum $ssh_root/id_rsa | cut -f1 -d' ').key

                # change id_rsa to unique names
                for key in $(find $ssh_root/servers -name id_rsa.revoked); do
                    mv $key $(dirname $key)/$(sha1sum $key | cut -f1 -d' ').revoked
                done

            else
                echo Some errors detected.
                find $ssh_root/servers -name id_rsa.revoke

                ls $ssh_root/servers | grep -v localhost | sort >/tmp/all
                find $ssh_root/servers -name id_rsa.revoked | cut -d'/' -f3 | sort >/tmp/revoked
                sdiff /tmp/all /tmp/revoked

            fi
        fi
    
    done

    echo '========================='
    echo Done.
    echo '========================='
done
