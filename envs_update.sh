#!/bin/bash

user_group=$1

server_groups=$(cat data/$user_group.users.yaml | 
y2j | 
jq -r '.users[].server_groups' | 
grep '"' | 
sed 's/[", ]//g' | 
sort -u)

echo '========================='
echo Processing users of: $server_groups
echo '========================='
for server_group in $server_groups; do
   echo '========================='
   echo Processing env: $server_group
   echo '========================='

   ansible-playbook env_users.yaml -e user_group=$user_group -e server_group=$server_group
   
   echo '========================='
   echo Done.
   echo '========================='
done

echo '========================='
echo Processing environments: $server_groups
echo '========================='
for server_group in $server_groups; do
   echo '========================='
   echo Processing env: $server_group
   echo '========================='

   ansible-playbook env_configure.yaml -e server_group=dev -e user_group=ocs -i data/ocs.inventory.cfg 

   echo '========================='
   echo Done.
   echo '========================='
done

echo '========================='
echo All done.
echo '========================='
