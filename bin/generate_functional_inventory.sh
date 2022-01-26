#!/bin/bash

#
# functions
#

# generate server's group inventory file by given variable e.g. host_product to have access to all WLS servers in the environment 
function build_functional_inventory() {
    group_by_variable=$1

    for server_group in $server_groups; do
        mkdir -p $pmaker_home/state/$user_group/$server_group/functional

        if [ $pmaker_home/state/$user_group/$server_group/functional/$group_by_variable.cfg -ot $pmaker_home/state/$user_group/$server_group/inventory.cfg ]; then
            rm -f $pmaker_home/state/$user_group/$server_group/functional/$group_by_variable.cfg

            keys=$(cat $pmaker_home/state/$user_group/$server_group/inventory.cfg | perl -ne "/$group_by_variable=(\w+) / && print(\$1 ,\"\n\")" 2>/dev/null | sort -u)

            for group_by in $keys; do
                echo "[$group_by]" >> $pmaker_home/state/$user_group/$server_group/functional/$group_by_variable.cfg

                grep "$group_by_variable=$group_by" $pmaker_home/state/$user_group/$server_group/inventory.cfg >> $pmaker_home/state/$user_group/$server_group/functional/$group_by_variable.cfg
                echo "" >> $pmaker_home/state/$user_group/$server_group/functional/$group_by_variable.cfg

                group_by_prev=$group_by
            done
            echo "Server group functional inventory by $group_by_variable file created for $server_group. File: $pmaker_home/state/$user_group/$server_group/functional/$group_by_variable.cfg"
            # backward compatiblity
            if [ $group_by_variable == 'host_product' ]; then 
                cp $pmaker_home/state/$user_group/$server_group/functional/$group_by_variable.cfg $pmaker_home/state/$user_group/$server_group/functional/inventory.cfg
            fi
        else
            echo "Server group functional inventory by $group_by_variable up to date for $server_group. File: $pmaker_home/state/$user_group/$server_group/functional/$group_by_variable.cfg"
        fi   
    done 
}

function generate_functional_inventory() {
    user_group=$1
    inventory_file=$2

    if [ -z "$user_group" ]; then
        echo "Error. User group can't be empty."
        echo
        echo "Usage: prepare_functional_inventory user_group inventory_file"
        return 1
    fi

    if [ ! -f $inventory_file ]; then
        echo "Error. Inventory file does not exist"
        echo
        echo "Usage: prepare_functional_inventory user_group inventory_file"
        return 1
    fi

    if [ ! -d $pmaker_home/state/$user_group ]; then
        echo "Error. User group does not exist."
        echo
        echo "Usage: prepare_functional_inventory user_group inventory_file"
        return 1
    fi

    #
    # build per server group inventory in state dir
    #
    server_groups=$(cat $pmaker_home/data/$user_group.inventory.cfg | grep '^\[' | egrep -v '\[jumps\]|\[controller\]' | tr -d '[\[\]]')

    for server_group in $server_groups; do
        cat $pmaker_home/data/$user_group.inventory.cfg | sed -n "/\[$server_group\]/,/\[/p" | sed '$ d' > $pmaker_home/state/$user_group/$server_group/inventory.cfg
    done

    #
    # build product inventory
    #
    build_functional_inventory host_product

    #
    # build component inventory
    #
    build_functional_inventory host_component

}


generate_functional_inventory $@
