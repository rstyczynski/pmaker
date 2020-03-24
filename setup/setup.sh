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
  return 0
fi

return 1
