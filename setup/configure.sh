#!/bin/bash


cat data/sample.inventory.cfg | sed "s/=pmaker/=$(whoami)/g" > setup/inventory.cfg

ansible -m ping all -i setup/inventory.cfg
if [ $? -ne 0 ]; then
  echo "Error. SSH communication not possible to all servers. Fix the erros and retry. Exiting."
  exit 1
fi

ansible-playbook -i setup/inventory.cfg setup/pmaker_create.yaml
if [ $? -ne 0 ]; then
  echo "Error. Installation error. Procedure broken. Fix the erros and retry. Exiting."
  exit 2
fi

