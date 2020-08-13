#!/bin/bash

sudo yum install -y ansible pwgen putty openssl python-pip
sudo pip install --upgrade pip
pip install Jinja2 j2cli

pmaker_home=/opt/pmaker

if [ ! -d pmaker ]; then
   git clone https://github.com/rstyczynski/pmaker.git
fi

ansible-playbook -i pmaker/setup/controller.inventory.cfg pmaker/setup/pmaker_create.yaml
if [ $? -ne 0 ]; then
  echo "Error. Installation error. Procedure broken. Fix the erros and retry. Exiting."
  exit 2
fi

sudo mkdir -p $pmaker_home
sudo chown -R pmaker $pmaker_home

sudo su - pmaker bash -c"
umask 077

# get from git as pmaker to avoid issue with file ownership / umask
if [ ! -d $pmaker_home/src ]; then
   cd $pmaker_home
   git clone https://github.com/rstyczynski/pmaker.git
   mv pmaker $pmaker_home/src
else
  cd $pmaker_home/src
  git pull
  cd ..
fi

#
# copy files to pmaker_home to have always fresh version, but not to change git workign directory
#
cp -R $pmaker_home/src/* $pmaker_home/ 2>/dev/null

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

rm -rf ~/pmaker
ln -s $pmaker_home ~/pmaker

exit 0
