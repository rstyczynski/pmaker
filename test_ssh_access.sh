#!/bin/bash

function usage() {
    cat <<EOF
Usage: test_ssh_access.sh user_group server_group inventory [user_filter|all] [server_filter|all]
EOF

}

function y2j() {
    ruby -ryaml -rjson -e 'puts JSON.dump(YAML.load(STDIN.read))'
}

function quit() {
    error_code=$1

    if [ ! -f $0 ]; then
        return $error_code
    else
        exit $error_code
    fi
}

function say() {
    echo $@ | tee -a $report
}

function summary() {
    say "##########################################"
    say "######### SSH access test summary ########"
    say "##########################################"
    say "# user group:   $user_group"
    say "# server group: $server_group"
    say "# all users:    $(cat $pmaker_home/state/$user_group/$server_group/users.yaml | y2j | jq -r '.users[].username')"
    say "# all servers:  $(ansible-inventory -i $inventory --list | jq -r ".$server_group.hosts[]")"
    say "# user filter:  $user_subset"
    say "# server filter:$server_subset"
    say "##########################################"
    say "# tested on:    $(date)"
    say "# tested at:    $(hostname)"
    say "# tested by:    $(whoami)"
    say "##########################################"
    say
    cat $tmp/$user_group.$server_group.access | tr -d \  | tr ';' '\t'
    say
    say 'Legend: + access ok, ! access error'
    say '+++ jump ok, server ok, server over jump ok'
    say '!+! jump error, server ok, server over jump error'
    say '+!+ jump ok, server error, server over jump ok'
}

function test_ssh_access() {
    user_group=$1
    shift
    server_group=$1
    shift
    inventory=$1
    shift
    user_subset=$1
    shift
    server_subset=$1
    shift

    if [ -z "$user_group" ] || [ -z "$server_group" ]; then
        usage
        quit 1
    fi

    : ${user_subset:=all}
    : ${server_subset:=all}

    oldTmp=$tmp
    tmp=$pmaker_home/tmp
    mkdir -p $tmp

    report=$pmaker_home/tmp/$(user_group)_$(server_group)_user_access_report_$(date -I).log
    rm -rf $report

    say "##############"
    say "### Processing: $server_group at $user_group"
    say "##############"

    say -n "Extracting users..."
    if [ ! -f "$pmaker_home/state/$user_group/$server_group/users.yaml" ]; then
        say "Error. User list file does not exit."
        quit 1
    else
        users_all=$(cat $pmaker_home/state/$user_group/$server_group/users.yaml | y2j | jq -r '.users[].username')
        if [ "$user_subset" == all ]; then
            cat $pmaker_home/state/$user_group/$server_group/users.yaml | y2j | jq -r '.users[].username' >$tmp/$user_group.$server_group.users
            say Done.
        else
            cat $pmaker_home/state/$user_group/$server_group/users.yaml | y2j | jq -r '.users[].username' |
                egrep "$(echo $user_subset | tr ' ,' '|')" \
                    >$tmp/$user_group.$server_group.users
            if [ $(cat $tmp/$user_group.$server_group.users | wc -l) -eq 0 ]; then
                say "Error. User list empty after applying filter."
                quit 1
            fi
        fi

    fi

    say -n "Extracting servers..."
    if [ ! -f "$inventory" ]; then
        say "Error. Inventory file does not exit."
        quit 1
    else
        server_all=$(cat $pmaker_home/state/$user_group/$server_group/users.yaml | y2j | jq -r '.users[].username')
        if [ "$server_subset" == all ]; then
            ansible-inventory -i $inventory --list | jq -r ".$server_group.hosts[]" >$tmp/$user_group.$server_group.servers
            say Done.
        else
            ansible-inventory -i $inventory --list |
                jq -r ".$server_group.hosts[]" |
                egrep "$(echo $server_subset | tr ' ,' '|')" \
                    >$tmp/$user_group.$server_group.servers
            if [ $(cat $tmp/$user_group.$server_group.servers | wc -l) -eq 0 ]; then
                say "Error. Server list empty after applying filter."
                quit 1
            fi
        fi
    fi

    say -n "Extracting jump server..."
    jump_server=$(cat $inventory | sed -n '/\[deves\]/,/\[/p' | grep 'host_type=jump' | tr -s ' ' | tr ' ' '\n' | grep public_ip | cut -f2 -d=)
    if [ ! -z "$jump_server" ]; then
        say Done.
    else
        say "Error. Jump server not detected."
        quit 1
    fi

    say -n "Testing user access..."

    server_header=instance
    for target_host in $(cat $tmp/$user_group.$server_group.servers); do
        server_header="$server_header;$target_host"
    done
    say $server_header >$tmp/$user_group.$server_group.access

    for username in $(cat $tmp/$user_group.$server_group.users); do
        ssh-add state/$user_group/$server_group/$username/.ssh/id_rsa >/dev/null 2>&1

        userline="$username;"
        for target_host in $(cat $tmp/$user_group.$server_group.servers); do
            say
            say "##########################################"
            say "### user: $username @ $target_host"
            say "##########################################"

            say -n "Connection to jump:"
            ssh $username@$jump_server 'echo Greetings from $(whoami).  $(hostname), $(date); exit' | tee -a $report
            if [ $? -eq 0 ]; then
                userline="$userline+"
            else
                userline="$userline\!"
            fi

            say -n "Connection to server:"
            ssh $username@$target_host 'echo Greetings from $(whoami).  $(hostname), $(date); exit' | tee -a $report
            if [ $? -eq 0 ]; then
                userline="$userline+"
            else
                userline="$userline\!"
            fi

            say -n "Connection to server over jump:"
            ssh -J $username@$jump_server $username@$target_host 'echo Greetings from $(whoami).  $(hostname), $(date); exit' | tee -a $report
            if [ $? -eq 0 ]; then
                userline="$userline+;"
            else
                userline="$userline\!;"
            fi
        done
        echo $userline >> $tmp/$user_group.$server_group.access

        ssh-add -d state/alshaya/deves/$username/.ssh/id_rsa >/dev/null 2>&1
    done

    summary

    tmp=$oldTmp
}

test_ssh_access $@
#test_ssh_access alshaya deves data/alshaya.inventory.cfg "psingh asaha" "10.106.4.52 10.106.6.97"



