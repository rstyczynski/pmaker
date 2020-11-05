#!/bin/bash

user_group=$1; shift
server_groups=$1; shift

function usage() {
   echo Usage: envs_update.sh user_group [server_groups]
   echo server_groups defaults to all
}

if [ -z "$user_group" ]; then
   usage
   error 1
fi


function j2y {
   ruby -ryaml -rjson -e 'puts YAML.dump(JSON.parse(STDIN.read))'
}

function y2j {
   ruby -ryaml -rjson -e 'puts JSON.dump(YAML.load(STDIN.read))'
}

if [ -z "$server_groups" ]; then
   server_groups=$(cat $pmaker_home/data/$user_group.users.yaml |  y2j |  jq -r '[.users[].server_groups[]] | unique | .[]')
   #Source: https://stackoverflow.com/questions/29822622/get-all-unique-json-key-names-with-jq
fi 

echo '==========================================================================='
echo Spliting usaers into group using: $server_groups
echo '==========================================================================='
for server_group in $server_groups; do
   echo '========================='
   echo Processing env: $server_group
   echo '========================='

   ansible-playbook $pmaker_home/env_users.yaml -e user_group=$user_group -e server_group=$server_group $@
   
   echo '========================='
   echo Done.
   echo '========================='
done
echo '==========================================================================='
echo Users ready.
echo '==========================================================================='

# it's controlld using ssh config
# echo 
# echo '==========================================================================='
# echo Activating ssh agent to handle ssh keys
# echo '==========================================================================='
# eval `ssh-agent`

echo
echo '==========================================================================='
echo Now updating environments: $server_groups
echo '==========================================================================='
for server_group in $server_groups; do
   # controller do manage local user list and key repository
   server_list="controller $(ansible-inventory -i $pmaker_home/data/$user_group.inventory.cfg  -y --list | y2j | jq -r  "[.all.children.$server_group.hosts | keys[]] | unique | .[]")"

   echo '========================='
   echo Processing env: $server_group
   echo \-having servers: $server_list
   echo '========================='

   # it's controlled using ssh config
   if [ -f state/$user_group/$server_group/pmaker/.ssh/id_rsa ]; then
      echo "Settgn up ssh config for $server_group"
      $pmaker_home/prepare_ssh_config.sh $user_group $server_group pmaker state/$user_group/$server_group/pmaker/.ssh/id_rsa
   fi

   ansible-playbook $pmaker_home/env_configure_controller.yaml \
   -e server_group=$server_group \
   -e user_group=$user_group \
   -i $pmaker_home/data/$user_group.inventory_hosts.cfg \
   -l localhost

   ansible-playbook $pmaker_home/env_configure_hosts.yaml \
   -e server_group=$server_group \
   -e user_group=$user_group \
   -i $pmaker_home/data/$user_group.inventory.cfg \
   -l "$server_list" $@

   echo '========================='
   echo Done.
   echo '========================='
done

echo '==========================================================================='
echo All done.
echo '==========================================================================='
