#!/bin/bash

#
# functions
#

function generate_functional_inventory() {
    user_group=$1
    inventory_file=$2

    if [ -z "$user_group" ]; then
        echo "Error. Group can't be empty."
        echo
        echo "Usage: prepare_functional_inventory group inventory"
        return 1
    fi

    if [ ! -f $inventory_file ]; then
        echo "Error. Inventory file does not exist"
        echo
        echo "Usage: prepare_functional_inventory group inventory"
        return 1
    fi

    if [ ! -d state/$user_group ]; then
        echo "Error. Group does not exist."
        echo
        echo "Usage: prepare_functional_inventory group inventory"
        return 1
    fi

    #
    # global
    #
    host_product_prev=''
    mkdir -p state/$user_group/functional

    if [ state/$user_group/functional/inventory.cfg -ot $inventory_file ]; then
        rm -f state/$user_group/functional/inventory.cfg

        host_products=$(cat $inventory_file | perl -ne '/host_product=(\w+) / && print($1 ,"\n")' 2>/dev/null | sort -u)
        for host_product in $host_products; do
            if [ "$host_product" != "$host_product_prev" ]; then
                echo "[$host_product]" >>state/$user_group/functional/inventory.cfg
            fi
            grep "host_product=$host_product" $inventory_file >>state/$user_group/functional/inventory.cfg
            echo "" >>state/$user_group/functional/inventory.cfg
        done
        echo "Global functional inventory file created."
    else
        echo "Global functional inventory up to date."
    fi

    #
    # build per server group inventory in state dir
    #

    server_groups=$(cat data/ocs.inventory.cfg | grep '^\[' | egrep -v '\[jumps\]|\[controller\]' | tr -d '[\[\]]')

    for server_group in $server_groups; do
        cat data/ocs.inventory.cfg | sed -n "/\[$server_group\]/,/\[/p" | sed '$ d' > state/$user_group/$server_group/inventory.cfg
    done

    #
    # buibuild per server group functional inventory
    #

    for server_group in $server_groups; do
        host_product_prev=''
        mkdir -p state/$user_group/$server_group/functional

        if [ state/$user_group/$server_group/functional/inventory.cfg -ot state/$user_group/$server_group/inventory.cfg ]; then
            rm -f state/$user_group/$server_group/functional/inventory.cfg

            host_products=$(cat state/$user_group/$server_group/inventory.cfg | perl -ne '/host_product=(\w+) / && print($1 ,"\n")' 2>/dev/null | sort -u)

            for host_product in $host_products; do
                if [ "$host_product" != "$host_product_prev" ]; then
                    echo "[$host_product]" | tee -a state/$user_group/$server_group/functional/inventory.cfg
                fi
                grep "host_product=$host_product" state/$user_group/$server_group/inventory.cfg | tee -a state/$user_group/$server_group/functional/inventory.cfg
                echo "" | tee -a  state/$user_group/$server_group/functional/inventory.cfg
            done
            echo "Server group functional inventory file created for $server_group."
        else
            echo "Server group functional inventory up to date for $server_group."
        fi   
    done 

}


generate_functional_inventory $@
