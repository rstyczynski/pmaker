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


ansible-playbook -i setup/controller.inventory.cfg setup/pmaker_create.yaml
if [ $? -ne 0 ]; then
  echo "Error. Installation error. Procedure broken. Fix the erros and retry. Exiting."
  exit 2
fi

sudo mkdir -p $pmaker_home
sudo chown -R pmaker $pmaker_home

ln -s $pmaker_home ~/pmaker

sudo su pmaker bash -c"
umask 077

# get from git as pmaker to avoid issue with file ownership / umask
cd /home/pmaker

if [ ! -d src ]; then
   git clone https://github.com/rstyczynski/pmaker.git
   mv pmaker src
else
  cd src
  git pull
fi

cp -r * $pmaker_home/ 2>/dev/null

grep 'umask 077' /home/pmaker/.bash_profile
if [ \$? -ne 0 ]; then
   echo >>/home/pmaker/.bash_profile
   echo umask 077 >>/home/pmaker/.bash_profile
fi

grep 'export pmaker_home=' /home/pmaker/.bash_profile
if [ \$? -ne 0 ]; then
   echo >>/home/pmaker/.bash_profile
   echo export pmaker_home=$pmaker_home >>/home/pmaker/.bash_profile
fi

grep '/lib/generate_welcome_msg.sh' /home/pmaker/.bash_profile
if [ \$? -ne 0 ]; then
   echo >>/home/pmaker/.bash_profile
   echo source $pmaker_home/lib/generate_welcome_msg.sh >>/home/pmaker/.bash_profile
fi

grep 'cd /opt/pmaker' /home/pmaker/.bash_profile
if [ \$? -ne 0 ]; then
   echo >>/home/pmaker/.bash_profile
   echo cd /opt/pmaker >>/home/pmaker/.bash_profile
fi

"

cd -
exit 0
