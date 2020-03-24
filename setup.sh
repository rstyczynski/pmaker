#!/bin/bash

pmaker_home=/opt/pmaker

cd setup
ansible-playbook pmaker_create.yml
if [ $? -eq 0 ]; then
  sudo su pmaker bash -c"
  mkdir -p $pmaker_home/state
  mkdir -p $pmaker_home/state/dev
  mkdir -p $pmaker_home/state/sit
  mkdir -p $pmaker_home/state/uat
  mkdir -p $pmaker_home/state/prod
  
  cd
  git clone https://github.com/rstyczynski/pmaker.git
  cp -r pmaker/* $pmaker_home/
  "

  exit 0
fi

exit 1