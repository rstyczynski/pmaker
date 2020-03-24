#!/bin/bash

pmaker_home=/opt/pmaker

cd setup
ansible-playbook pmaker_create.yaml
if [ $? -ne 0 ]; then
  echo "Error. Installation error. Procedure broken. Fix the erros and retry. Exiting."
  exit 1
fi

sudo chown -R pmaker $pmaker_home

sudo su pmaker bash -c"
umask 077

mkdir -p $pmaker_home/state
mkdir -p $pmaker_home/state/dev
mkdir -p $pmaker_home/state/sit
mkdir -p $pmaker_home/state/uat
mkdir -p $pmaker_home/state/prod

cd
if [ ! -d pmaker ]; then
   git clone https://github.com/rstyczynski/pmaker.git
else
  cd pmaker
  git pull
fi

cp -r * $pmaker_home/

cd /opt/pmaker
\rm -f setup.sh
\rm -rf setup

grep 'umask 077' /home/pmaker/.bash_profile
if [ $? -ne 0 ]; then
   echo umask 077 >>/home/pmaker/.bash_profile
fi
"

exit 0
