#!/bin/bash

ssh-add -D
ssh-add ~/.ssh/ip-sec

cd setup
ansible-playbook pmaker_create.yml 
cd -

