#!/bin/bash
user_group=$1

if [ -z "$user_group " ]; then
    echo "Usage: pmaker_ssh_config user_group"
    echo
    echo "Warning: script replace .ssh/config. Backup copy is made."
    exit 1
fi

if [ ! -f data/$user_group.inventory.cfg ]; then
    echo "Error: data/$user_group.inventory.cfg doe not exist!"
    exit 2
fi

# 
# build ssh config
#

cd $pmaker_home/state/$user_group
server_groups=$(ls -d */ | egrep -v 'functional|outbox' | tr -d '/')
cd - 2>/dev/null

if [ -f ~/.ssh/config ]; then
  mv ~/.ssh/config ~/.ssh/config_$(date -I).bak
fi 

for server_group in $server_groups; do
   if [ -f $pmaker_home/state/$user_group/$server_group/pmaker/.ssh/id_rsa ]; then
      echo "Settgn up ssh config for $server_group"
      $pmaker_home/bin/prepare_ssh_config.sh $user_group $server_group pmaker $pmaker_home/state/$user_group/$server_group/pmaker/.ssh/id_rsa
   else
     echo No pmaker key for $server_group. Using global pmaker key
     $pmaker_home/bin/prepare_ssh_config.sh $user_group $server_group pmaker ~/.ssh/id_rsa
   fi
done
