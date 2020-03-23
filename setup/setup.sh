#!/bin/bash

cp -r . ~/

ansible-playbook pmaker_create.yml 
if [ $? -eq 0 ]; then
  cd
  mkdir state
  mkdir state/dev
  mkdir state/sit
  mkdir state/uat
  mkdir state/prod
  exit 0
fi

exit 1
