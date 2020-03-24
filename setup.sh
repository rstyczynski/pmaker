#!/bin/bash

cp -r . ~/

cd setup
ansible-playbook pmaker_create.yml
if [ $? -eq 0 ]; then
  cd
  mkdir -p state
  mkdir -p state/dev
  mkdir -p state/sit
  mkdir -p state/uat
  mkdir -p state/prod
  exit 0
fi

exit 1