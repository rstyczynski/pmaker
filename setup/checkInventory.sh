#!/bin/bash
server_group=$1; shift

ansible -m ping all -i data/$server_group.inventory.cfg $@
if [ $? -ne 0 ]; then
  #mkdir -p publicl chmod o+r+x public
  #cp data/$server_group.inventory.cfg public
  #chmod o+r public/*
  echo Some of machnes not accesible for pmaker. 
  echo Connect from different session as opc and prepare hosts for pmaker using:
  echo setup/configureInventory.sh $server_group $@
else
  echo Good to go.
fi
