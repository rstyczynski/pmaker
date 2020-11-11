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

    #echo "Quit requested from $0"

    if [ ! -f "$0" ]; then
        return $error_code
    else
        exit $error_code
    fi
}

function say() {
    echo $@ | tee -a $report
}

function summary() {
    say
    say "##########################################"
    say "######### SSH access test summary ########"
    say "##########################################"
    say "# user group:   $user_group"
    say "# server group: $server_group"
    say "# jump server:  $jump_server"
    say "# inventory:    $inventory"
    say "# all users: $(cat $pmaker_home/data/$user_group.users.yaml | y2j | jq -r '.users[].username')"
    say "# all users with access to server group: $(cat $pmaker_home/state/$user_group/$server_group/users.yaml | y2j | jq -r '.users[].username')"
    say "# all servers in the group:  $(ansible-inventory -i $inventory --list | jq -r ".$server_group.hosts[]")"
    say "# user filter:  $user_subset"
    say "# server filter:$server_subset"
    say "##########################################"
    say "# tested on:    $(date)"
    say "# tested at:    $(hostname)"
    say "# tested by:    $(whoami)"
    say "##########################################"
    say
    cat $tmp/$user_group.$server_group.access | tr -d '\\'  | tr ';' '\t' | tee -a $report
    say
    say 'Legend: + access ok, ! access error, s access skipped'
    say '+++ jump ok, server ok, server over jump ok'
    say '!+! jump error, server ok, server over jump error'
    say '+!! jump ok, server error, server over jump error'
    say 's+s jump skiped, server ok, server over jump skiped'
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
    tmp=$pmaker_home/tmp/$$
    rm -rf $pmaker_home/tmp/$$
    mkdir -p $tmp

    dateStr=$(date -I)T$(date +%T)

    report=$tmp/$user_group\_$server_group\_user_access_report_$dateStr.log
    rm -rf $report

    say "##########################################"
    say "############# SSH access test ############"
    say "##########################################"
    say "# user group:   $user_group"
    say "# server group: $server_group"
    say "# inventory:    $inventory"
    say "# user filter:  $user_subset"
    say "# server filter:$server_subset"
    say "##########################################"
    say "# tested on:    $(date)"
    say "# tested at:    $(hostname)"
    say "# tested by:    $(whoami)"
    say "##########################################"

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
                say Done.
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
                say Done.
            if [ $(cat $tmp/$user_group.$server_group.servers | wc -l) -eq 0 ]; then
                say "Error. Server list empty after applying filter."
                quit 1
            fi
        fi
    fi

    say -n "Extracting jump server..."

    jumps_cnt=$(cat $inventory | sed -n "/\[$server_group\]/,/\[/p" | grep 'host_type=jump' | tr -s ' ' | tr ' ' '\n' | grep public_ip | cut -f2 -d= | wc -l)

    case $jumps_cnt in
    1)
        jump_server_group=$(cat $inventory | sed -n "/\[$server_group\]/,/\[/p" | grep 'host_type=jump' | tr -s ' ' | tr ' ' '\n' | grep public_ip | cut -f2 -d=)
        if [ ! -z "$jump_server_group" ]; then
            say Done.
        else
            say "Error. Jump server not detected."
            quit 1
        fi
        ;;
    0)
        unset jump_server_group
        say "Error. Jump server not detected. Maybe is set at host level..."
        ;;
    *)
        unset jump_server_group
        say "Error. Multiple jump servers detected. The one is set at host level..."
        ;;
    esac

    say -n "Testing user access..."

    server_header=instance
    for target_host in $(cat $tmp/$user_group.$server_group.servers); do
        server_header="$server_header;$target_host"
    done
    say $server_header > $tmp/$user_group.$server_group.access

    # discover jumps
    declare -A host_cfg 
    jump_header=jump
    for target_host in $(cat $tmp/$user_group.$server_group.servers); do
        if [ -z $jump_server_group ]; then
            jump_server_name=$(cat $inventory | sed -n "/\[$server_group\]/,/\[/p" | grep "^$target_host" | tr -s ' ' | tr ' ' '\n' | grep 'jump=' | cut -f2 -d=)
            if [ -z "$jump_server_name" ]; then
                jump_server=none
            else
                jump_server=$(cat $inventory | sed -n "/\[jumps\]/,/\[/p" | grep "^$jump_server_name" | tr -s ' ' | tr ' ' '\n' | grep 'public_ip=' | cut -f2 -d=)
                if [ -z "$jump_server" ]; then
                    say "Error. Jump server IP not detected at jump section."
                    quit 1
                fi
            fi
        fi
        host_cfg[$target_host|jump]=$jump_server
        jump_header="$jump_header;$jump_server"
    done
    say $jump_header >> $tmp/$user_group.$server_group.access

    for username in $(cat $tmp/$user_group.$server_group.users); do
        ssh-add state/$user_group/$server_group/$username/.ssh/id_rsa  | tee -a $report

        userline="$username;"
        for target_host in $(cat $tmp/$user_group.$server_group.servers); do
            say
            say "##########################################"
            say "### user: $username @ $target_host"
            say "##########################################"

            jump_server=${host_cfg[$target_host|jump]}

            if [ "$jump_server" != none ]; then
                say -n "Connection to jump:"
                timeout 10 ssh $username@$jump_server 'echo Greetings from $(whoami).  $(hostname), $(date); exit' | tee -a $report
                if [ ${PIPESTATUS[0]} -eq 0 ]; then
                    userline="$userline+"
                else
                    userline="$userline\!"
                fi
            else
                say Skipped.
                userline="$userline\s"
            fi

            say -n "Connection to server:"
            timeout 10 ssh $username@$target_host 'echo Greetings from $(whoami).  $(hostname), $(date); exit' | tee -a $report
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                userline="$userline+"
            else
                userline="$userline\!"
            fi

            say -n "Connection to server over jump:"
            if [ "$jump_server" != none ]; then
                timeout 10 ssh -J $username@$jump_server $username@$target_host 'echo Greetings from $(whoami).  $(hostname), $(date); exit' | tee -a $report
                if [ ${PIPESTATUS[0]} -eq 0 ]; then
                    userline="$userline+;"
                else
                    userline="$userline\!;"
                fi
            else
                say Skipped.
                userline="$userline\s;"
            fi
        done
        echo $userline >> $tmp/$user_group.$server_group.access

        ssh-add -d state/$user_group/$server_group/$username/.ssh/id_rsa | tee -a $report
    done

    summary | tee $pmaker_home/report/$user_group\_$server_group\_user_access_report_summary_$dateStr.log

    mkdir -p $pmaker_home/report
    cat $tmp/$user_group\_$server_group\_user_access_report_$dateStr.log | grep -v "Killed by signal 1" \
    > $pmaker_home/report/$user_group\_$server_group\_user_access_report_full_$dateStr.log

    echo
    echo "Full report available at: $pmaker_home/report/$user_group\_$server_group\_user_access_report_full_$dateStr.log"
    echo "Summary report availabe at: $pmaker_home/report/$user_group\_$server_group\_user_access_report_summary_$dateStr.log"
    
    rm -rf $pmaker_home/tmp/$$
    tmp=$oldTmp
}

test_ssh_access $@
