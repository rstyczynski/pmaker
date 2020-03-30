#!/bin/bash
user_group=$1; shift

if [ -z "$user_group" ]; then
  user_group=sample
  cat data/$user_group.inventory.cfg | sed "s/=pmaker/=$(whoami)/g" >setup/inventory.cfg
else
  cat /opt/pmaker/public/$user_group.inventory.cfg | sed "s/=pmaker/=$(whoami)/g" >setup/inventory.cfg
fi

export ANSIBLE_HOST_KEY_CHECKING=False

# hosts=$(cat setup/inventory.cfg | egrep '[0-9]+.' | grep -v '^#' | cut -f1 -d' ')
# for host in $hosts; do
# 	echo $host...
# 	ssh-keyscan -H $host >>~/.ssh/known_hosts
# done

ansible -m ping all -i setup/inventory.cfg $@
if [ $? -ne 0 ]; then
  echo "Error. SSH communication not possible to all servers. Fix the erros and retry. Exiting."
  exit 1
fi

ansible-playbook -i setup/inventory.cfg setup/pmaker_create.yaml $@
if [ $? -ne 0 ]; then
  echo "Error. Installation error. Procedure broken. Fix the erros and retry. Exiting."
  exit 2
fi

rm -f setup/inventory.cfg

