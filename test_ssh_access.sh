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
    nl=yes
    if [ "$1" == '-n' ]; then
        nl=no
        shift
    fi

    if [ $nl == yes ]; then
        echo "$@" | tee -a $report
    else
        echo -n "$@" | tee -a $report
    fi
}


maxip=999.999.999.999
iplth=$(echo -n $maxip | wc -c)

function sayatcell() {

    nl=yes
    if [ $1 == '-n' ]; then
        nl=no
        shift
    fi

    fr=no
    if [ $1 == '-f' ]; then
        fr=yes
        shift
    fi

    what=$1; shift
    size=$1; shift

    back='____________________________________________________________________________________________________________'
    back='                                                                                                            '
    dots='............................................................................................................'

    what_lth=$(echo -n $what | wc -c)

    if [ $what_lth -lt $size ]; then
        pre=$(echo "($size - $what_lth)/2" | bc)
        post=$(echo "$size - $what_lth - $pre" | bc)
        
        if [ $pre -gt 0 ]; then 
            echo -n "$back" | cut -b1-$pre | tr -d '\n'
        fi

        echo -n "$what"
        
        if [ $post -gt 0 ]; then
            echo -n "$back" | cut -b1-$post | tr -d '\n'
        fi

    elif [ $what_lth -gt $size ]; then
        echo -n "$what" | cut -b1-$(( $size - 2 )) | tr -d '\n'
        echo -n "$dots" | cut -b1-2 | tr -d '\n'
    elif [ $what_lth -eq $size ]; then
        echo -n "$what" 
    fi

    if [ $nl == yes ]; then
        if [ $fr == yes ]; then
            echo '|'
        else
            echo
        fi
    elif [ $fr == yes ]; then
            echo -n '|'
    fi
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
    say "# all users: $(cat $pmaker_home/data/$user_group.users.yaml | y2j | jq -r '.users[].username' | tr '\n' ' ')"
    say "# all users with access to server group: $(cat $pmaker_home/state/$user_group/$server_group/users.yaml | y2j | jq -r '.users[].username'| tr '\n' ' ')"
    say "# all servers in the group:  $(ansible-inventory -i $inventory --list | jq -r ".$server_group.hosts[]" | tr '\n' ' ')"
    say "# user filter:  $user_subset"
    say "# server filter:$server_subset"
    say "##########################################"
    say "# tested on:    $(date)"
    say "# tested at:    $(hostname)"
    say "# tested by:    $(whoami)"
    say "##########################################"
    say
    cat $tmp/$user_group.$server_group.access | tee -a $report
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

    : ${pmaker_home:=/opt/pmaker}
    
    oldTmp=$tmp
    tmp=$HOME/pmaker/tmp/$$
    rm -rf $HOME/pmaker/tmp/$$
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

    say -n "Preparing report header..."
    # server ip header
    server_header="$(sayatcell -n -f instance 15)"
    for target_host in $(cat $tmp/$user_group.$server_group.servers); do
        target_host_tab="$(sayatcell -n -f $target_host 15)"
        server_header="$server_header$target_host_tab"
    done
    say "$server_header" > $tmp/$user_group.$server_group.access

    # host names header
    server_name_header="$(sayatcell -n -f name 15)"
    for target_host in $(cat $tmp/$user_group.$server_group.servers); do
        server_name=$(nslookup $target_host | grep in-addr.arpa | tr '\t' ' ' | sed 's/\s*=\s*/\nname=/g' | grep 'name=' | cut -f2 -d= | cut -f1 -d.)
        : ${server_name:=unknown}
        server_name_header_tab="$(sayatcell -n -f "$server_name" 15)"
        server_name_header="$server_name_header$server_name_header_tab"
    done
    say "$server_name_header" >> $tmp/$user_group.$server_group.access

    # host type header
    server_type_header="$(sayatcell -n -f type 15)"
    for target_host in $(cat $tmp/$user_group.$server_group.servers); do
        server_type=$(cat $inventory | sed -n "/\[$server_group\]/,/\[/p" | grep "^$target_host" | tr -s ' ' | tr ' ' '\n' | grep 'host_type=' | cut -f2 -d=)
        : ${server_type:=unknown}
        server_type_header_tab="$(sayatcell -n -f "$server_type" 15)"
        server_type_header="$server_type_header$server_type_header_tab"
    done
    say "$server_type_header" >> $tmp/$user_group.$server_group.access
    say Done.


    say -n "Discovering jump servers..."
    declare -A host_cfg 
    jump_header="$(sayatcell -n -f jump 15)"
    for target_host in $(cat $tmp/$user_group.$server_group.servers); do
        if [ -z $jump_server_group ]; then
            jump_server_name=$(cat $inventory | sed -n "/\[$server_group\]/,/\[/p" | grep "^$target_host" | tr -s ' ' | tr ' ' '\n' | grep 'jump=' | cut -f2 -d=)
            if [ -z "$jump_server_name" ]; then
                jump_server_name=$(cat $inventory | sed -n "/\[$server_group\]/,/\[/p" | grep "^$target_host" | grep 'host_type=jump' | tr -s ' ' | tr ' ' '\n' | grep 'public_ip=' | cut -f2 -d=)
                if [ -z "$jump_server_name" ]; then
                    jump_server=none
                fi
            else
                jump_server=$(cat $inventory | sed -n "/\[jumps\]/,/\[/p" | grep "^$jump_server_name" | tr -s ' ' | tr ' ' '\n' | grep 'public_ip=' | cut -f2 -d=)
                if [ -z "$jump_server" ]; then
                    say "Error. Jump server IP not detected at jump section."
                    quit 1
                fi
            fi
        else
            jump_server=$jump_server_group
        fi
        host_cfg[$target_host|jump]=$jump_server

        jump_server_tab="$(sayatcell -n -f $jump_server 15)"
        jump_header="$jump_header$jump_server_tab"
    done
    say "$jump_header" >> $tmp/$user_group.$server_group.access
    say Done.

    say -n "Starting ssh agent..."
    eval $(ssh-agent)


    say "Testing user access..."
    for username in $(cat $tmp/$user_group.$server_group.users); do
        ssh-add state/$user_group/$server_group/$username/.ssh/id_rsa  | tee -a $report

        userline="$(sayatcell -n -f $username 15)"
        for target_host in $(cat $tmp/$user_group.$server_group.servers); do
            say
            say "##########################################"
            say "### user: $username @ $target_host"
            say "##########################################"

            jump_server=${host_cfg[$target_host|jump]}

            unset statusline

            if [ "$jump_server" != none ]; then
                say -n "Connection to jump:"
                timeout 10 ssh $username@$jump_server 'echo Greetings from $(whoami).  $(hostname), $(date); exit' | tee -a $report
                if [ ${PIPESTATUS[0]} -eq 0 ]; then
                    statusline="$statusline+"
                else
                    statusline="$statusline"'!'
                fi
            else
                say Skipped.
                statusline="${statusline}s"
            fi

            say -n "Connection to server:"
            timeout 10 ssh $username@$target_host 'echo Greetings from $(whoami).  $(hostname), $(date); exit' | tee -a $report
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                statusline="$statusline+"
            else
                statusline="$statusline"'!'
            fi

            say -n "Connection to server over jump:"
            if [ "$jump_server" != none ]; then
                timeout 10 ssh -J $username@$jump_server $username@$target_host 'echo Greetings from $(whoami).  $(hostname), $(date); exit' | tee -a $report
                if [ ${PIPESTATUS[0]} -eq 0 ]; then
                    statusline="$statusline+"
                else
                    statusline="$statusline"'!'
                fi
            else
                say Skipped.
                statusline="${statusline}s"
            fi
            status_tab="$(sayatcell -n -f $statusline 15)"
            userline="$userline$status_tab"
        done
        echo "$userline" >> $tmp/$user_group.$server_group.access

        ssh-add -d state/$user_group/$server_group/$username/.ssh/id_rsa | tee -a $report
    done

    mkdir -p $HOME/pmaker/report

    summary | tee $HOME/pmaker/report/$user_group\_$server_group\_user_access_report_summary_$dateStr.log

    cat $tmp/$user_group\_$server_group\_user_access_report_$dateStr.log |
    sed 's/Killed by signal 1//g' \
    > $HOME/pmaker/report/$user_group\_$server_group\_user_access_report_full_$dateStr.log

    echo
    echo "Full report available at: $HOME/pmaker/report/$user_group\_$server_group\_user_access_report_full_$dateStr.log"
    echo "Summary report availabe at: $HOME/pmaker/report/$user_group\_$server_group\_user_access_report_summary_$dateStr.log"
    
    rm -rf $HOME/pmaker/tmp/$$
    tmp=$oldTmp
}

test_ssh_access $@



