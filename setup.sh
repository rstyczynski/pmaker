#!/bin/bash

pmaker_home=/opt/pmaker

cd setup
ansible-playbook pmaker_create.yaml
if [ $? -ne 0 ]; then
  echo "Error. Installation error. Procedure broken."
  exit 1
fi

sudo chown -R pmaker $pmaker_home

sudo su pmaker bash -c"
mkdir -p $pmaker_home/state
mkdir -p $pmaker_home/state/dev
mkdir -p $pmaker_home/state/sit
mkdir -p $pmaker_home/state/uat
mkdir -p $pmaker_home/state/prod

cd
if [ !-d pmaker ]; then
   git clone https://github.com/rstyczynski/pmaker.git
else
   git pull
fi

cp -r pmaker/* $pmaker_home/

cd /opt/pmaker
\rm -f setup.sh
\rm -rf setup
"

exit 0
