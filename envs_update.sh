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
   server_groups=$(cat data/$user_group.users.yaml |  y2j |  jq -r '[.users[].server_groups[]] | unique | .[]')
   #Source: https://stackoverflow.com/questions/29822622/get-all-unique-json-key-names-with-jq
fi 

echo '==========================================================================='
echo Spliting usaers into group using: $server_groups
echo '==========================================================================='
for server_group in $server_groups; do
   echo '========================='
   echo Processing env: $server_group
   echo '========================='

   ansible-playbook env_users.yaml -e user_group=$user_group -e server_group=$server_group $@
   
   echo '========================='
   echo Done.
   echo '========================='
done
echo '==========================================================================='
echo Users ready.
echo '==========================================================================='


echo '==========================================================================='
echo Now updating environments: $server_groups
echo '==========================================================================='
for server_group in $server_groups; do
   server_list=$(ansible-inventory -i data/$user_group.inventory.cfg  -y --list | y2j | jq -r  "[.all.children.$server_group.hosts | keys[]] | unique | .[]")

   echo '========================='
   echo Processing env: $server_group
   echo \-having servers: $server_list
   echo '========================='

   ansible-playbook env_configure.yaml \
   -e server_group=$server_group \
   -e user_group=$user_group \
   -i data/$user_group.inventory.cfg \
   -l "controller $server_list" \          # conntroller to manage local key repo
   $@

   echo '========================='
   echo Done.
   echo '========================='
done

echo '==========================================================================='
echo All done.
echo '==========================================================================='
