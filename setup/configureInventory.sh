#!/bin/bash

user_group=$1; shift
server_groups=$1; shift
skip_hosts=$1; shift


function usage() {
   echo Usage: configureInventory.sh user_group [server_groups]
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

if [ -z "$user_group" ]; then
  user_group=sample
  cat data/$user_group.inventory.cfg | sed "s/=pmaker/=opc/g" >data/$user_group.inventory.opc
else
  cat data/$user_group.inventory.cfg | sed "s/=pmaker/=opc/g" >data/$user_group.inventory.opc
fi

export ANSIBLE_HOST_KEY_CHECKING=False


echo '==========================================================================='
echo " Checking communication with servers belonging to: $user_group"
echo '==========================================================================='

# remove jumps | skpis given hosts
#cat data/$user_group.inventory.opc | sed '/jumps/,/^$/d' | grep -v "$skip_hosts" > data/$user_group.inventory.opc.no_jumps
cat data/$user_group.inventory.opc | grep -v "$skip_hosts" > data/$user_group.inventory.opc.selected

for server_group in $server_groups; do
   ansible -m ping $server_group -i data/$user_group.inventory.opc.selected
   if [ $? -ne 0 ]; then
   echo "Error. SSH communication not possible to all servers. Fix the erros and retry. Exiting."
   exit 1
   fi
done

# moved to ssh config
# eval `ssh-agent -s`

echo '==========================================================================='
echo " Configuring servers: $server_groups"
echo '==========================================================================='
for server_group in $server_groups; do
   server_list=$(ansible-inventory -i data/$user_group.inventory.cfg  -y --list | y2j | jq -r  "[.all.children.$server_group.hosts | keys[]] | unique | .[]")

   echo '========================='
   echo Processing env: $server_group
   echo \-having servers: $server_list
   echo '========================='

   # moved to ssh config
   # if [ -f ~/.ssh/$server_group.key ]; then
   #  ssh-add ~/.ssh/$server_group.key
   # fi

   ansible-playbook  \
   setup/pmaker_create.yaml \
   -i data/$user_group.inventory.opc.selected \
   -l "controller $server_group" \
   -e pmaker_type=env \
   -e server_group=$server_group \
   -e user_group=$user_group \
   $@
   if [ $? -ne 0 ]; then
     echo "Error. Installation error. Procedure broken. Fix errors and retry. Exiting."
     exit 2
   fi

   echo '========================='
   echo Done.
   echo '========================='
done

rm -f data/$user_group.inventory.opc.no_jumps
rm -f data/$user_group.inventory.opc
