#!/bin/bash

user_group=$1
shift
server_groups=$1
shift
user_to_process=$1
shift
keyfile=$1
shift

function usage() {
    echo Usage: revoke_keys.sh user_group [server_groups] [user] [keyfile]
    echo server_groups defaults to all
    echo user to process defaults to pmaker, and all
    echo keyfile to process, defaults to id_rsa
}

if [ -z "$user_group" ]; then
    usage
    error 1
fi

: ${server_groups:=all}
: ${user_to_process:=all}
: ${keyfile:=id_rsa}

if [ -z "$pmaker_home" ]; then
    pmaker_home=/opt/pmaker
fi

function j2y() {
    ruby -ryaml -rjson -e 'puts YAML.dump(JSON.parse(STDIN.read))'
}

function y2j() {
    ruby -ryaml -rjson -e 'puts JSON.dump(YAML.load(STDIN.read))'
}

if [ "$server_groups" == all ]; then
    server_groups=$(cat $pmaker_home/data/$user_group.users.yaml | y2j | jq -r '[.users[].server_groups[]] | unique | .[]')
    #Source: https://stackoverflow.com/questions/29822622/get-all-unique-json-key-names-with-jq
fi

echo '==========================================================================='
echo " Configuring servers: $server_groups"
echo '==========================================================================='
for server_group in $server_groups; do
    server_list=$(ansible-inventory -i $pmaker_home/data/$user_group.inventory.cfg -y --list | y2j | jq -r "[.all.children.$server_group.hosts | keys[]] | unique | .[]")

    echo '========================='
    echo Processing env: $server_group
    echo \-having servers: $server_list
    echo '========================='

    # TODO select proper pmaker key
    # if [ -f ~/.ssh/$server_group.key ]; then
    #     ssh-add ~/.ssh/$server_group.key
    # fi
    # users=$(cat $pmaker_home/state/$user_group/$server_group/users.yaml | y2j | jq -r ".users[].username")
    
    if [ "$user_to_process" == all ]; then
        # use list of users known to the system i.e. already registered. 
        # this list may be different from users.yaml i.e. older
        users="pmaker_global pmaker_env $(ls $pmaker_home/state/$user_group/$server_group | grep -v users.yaml)"
    else
        users=$user_to_process
    fi

    # revoke key from pmaker, and known users
    for username in $users; do

        echo '========================='
        echo Processing user: $username
        echo '========================='

        # execute revoke procedure
        case $username in
            pmaker_global)
                ssh_root=$pmaker_home/.ssh

                ansible-playbook  \
                setup/pmaker_revoke_keys.yaml \
                -e pmaker_type=global \
                -e pmaker_home=$pmaker_home \
                -e keyfile=$keyfile \ 
                -e server_group=$server_group \
                -e user_group=$user_group \
                -l $server_group \
                -i $pmaker_home/data/$user_group.inventory.cfg
                ;;
            pmaker_env)
                ssh_root=$pmaker_home/state/$user_group/$server_group/$username/.ssh

                ansible-playbook  \
                setup/pmaker_revoke_keys.yaml \
                -e pmaker_type=env \
                -e pmaker_home=$pmaker_home \
                -e keyfile=$keyfile \ 
                -e server_group=$server_group \
                -e user_group=$user_group \
                -l $server_group \
                -i $pmaker_home/data/$user_group.inventory.cfg
                ;;
            *)
                ssh_root=$pmaker_home/state/$user_group/$server_group/$username/.ssh
                
                ansible-playbook  \
                lib/user_revoke_keys.yaml \
                -e username=$username \
                -e pmaker_home=$pmaker_home \
                -e keyfile=$keyfile \
                -e server_group=$server_group \
                -e user_group=$user_group \
                -l $server_group \
                -i $pmaker_home/data/$user_group.inventory.cfg
                ;;  
        esac
        if [ $? -eq 0 ]; then
            # check if all keys were revoked
            known_servers=$(ls $ssh_root/servers | grep -v localhost | wc -l)

            if [ ! -z "$known_servers" ]  && [ $known_servers -gt 0 ]; then
                revoked_keys=$(find $ssh_root/servers -name $keyfile.revoked | wc -l)
                if [ $revoked_keys -eq $known_servers ]; then
                    echo OK

                    [ -f $ssh_root/$keyfile ] && fprint=$(sha1sum $ssh_root/$keyfile | cut -f1 -d ' ')
                    [ -f $ssh_root/$keyfile.key ] && fprint=$(sha1sum $ssh_root/$keyfile.key | cut -f1 -d ' ')
                    
                    if [ -z "$fprint" ]; then
                        echo "Error. Key not found."
                        exit 1
                    fi

                    # Change $keyfile.pub to unique names in server's directory
                    # Note that change is tracked per-server to catch potential problems with e.g. crashed machines
                    for key in $(find $ssh_root/servers -name $keyfile.revoked); do
                        mv $key "$(dirname $key)/$fprint.revoked"
                    done

                    # all done - change main rsa_id to unique name, kept for historical purposes
                    [ -f $ssh_root/$keyfile ]        && mv $ssh_root/$keyfile $ssh_root/$fprint.key
                    [ -f $ssh_root/$keyfile.key ]    && mv $ssh_root/$keyfile.key $ssh_root/$fprint.key 
                    [ -f $ssh_root/$keyfile.pub ]    && mv $ssh_root/$keyfile.pub $ssh_root/$fprint.pub 
                    [ -f $ssh_root/$keyfile.revoke ] && mv $ssh_root/$keyfile.revoke $ssh_root/$fprint.revoked
                    [ -f $ssh_root/$keyfile.enc ]    && mv $ssh_root/$keyfile.enc $ssh_root/$fprint.enc
                    [ -f $ssh_root/$keyfile.ppk ]    && mv $ssh_root/$keyfile.ppk $ssh_root/$fprint.ppk
                    [ -f $ssh_root/$keyfile.secret ] && mv $ssh_root/$keyfile.secret $ssh_root/$fprint.secret
                else
                    echo Some errors detected.
                    find $ssh_root/servers -name $keyfile.revoke

                    ls $ssh_root/servers | grep -v localhost | sort >/tmp/all
                    find $ssh_root/servers -name $keyfile.revoked | cut -d'/' -f3 | sort >/tmp/revoked
                    sdiff /tmp/all /tmp/revoked
                fi
            else
                echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
                echo "ERROR processing user: $username"
                echo "No servers found."
                echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
            fi
        else
            echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
            echo "ERROR processing user: $username"
            echo "General error."
            echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
        fi
    
    done

    echo '========================='
    echo Done.
    echo '========================='
done
