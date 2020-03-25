#!/bin/bash

sudo yum install -y git pwgen putty openssl python-pip
sudo pip install --upgrade pip
pip install Jinja2 j2cli

pmaker_home=/opt/pmaker

cd ~
if [ ! -d pmaker ]; then
   git clone https://github.com/rstyczynski/pmaker.git
else
  cd pmaker
  git pull
fi

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

sudo mkdir -p $pmaker_home
sudo chown -R pmaker $pmaker_home

sudo su pmaker bash -c"
umask 077

ln -s $pmaker_home ~/pmaker

# get from git as pmaker to avoid issue with file ownership / umask
cd /home/pmaker
if [ ! -d src ]; then
   git clone https://github.com/rstyczynski/pmaker.git
   mv pmaker src
else
  cd src
  git pull
fi

cp -r * $pmaker_home/

grep 'umask 077' /home/pmaker/.bash_profile
if [ $? -ne 0 ]; then
   echo umask 077 >>/home/pmaker/.bash_profile
fi

grep 'export pmaker_home=' /home/pmaker/.bash_profile
if [ $? -ne 0 ]; then
   echo export pmaker_home=$pmaker_home >>/home/pmaker/.bash_profile
fi

grep '/bin/generate_welcome_msg.sh' /home/pmaker/.bash_profile
if [ $? -ne 0 ]; then
   echo "source $pmaker_home/bin/generate_welcome_msg.sh" >>/home/pmaker/.bash_profile
fi


"

cd -
exit 0
