User management
===============
> rstyczynski@gmail.com, march 2020, version 0.1-dev

```
> cat /opt/pmaker/data/science.users.yaml
---
users:
  - username: carmen
    server_groups: [dev, sit, uat]

    became_oracle: [dev, sit, uat]
    became_appl:   [dev, sit, uat]
    became_root:   [dev]

    password:      yes
    key:           yes
    
    full_name: O.W. Carmen
    email: carmen@opera.world
    mobile: +48 007 008 009
```

Carmen is a member of Science project, having access to dozens of servers in dev, sit, and uat environments. She may connect to systems using password authentication or rsa identification key. She can switch to application accounts to manage dev as root, and other environments as oracle, applmgr, and applsoad. She may be contacted by email and mobile.

Creating accounts for Carmen, system admin uses auto generated safe password, and encrypted identification key. As Carmen may use putty to connect from Windows and ssh to connect from Linux, system admin creates keys in desired formats. 

---

Once accounts are created on all hosts Carmen receives text message on her mobile with Linux password, and another text message with password to encrypted keys. Username and keys are delivered using e-mail to her desktop. Carmen may access her key repository over https protocol with authentication.

From this moment Carmen may access all the servers, however from internet side she uses bastion host to connect to rest of machines.

Carmen has one week to connect to hosts and change passwords. After this time, system randomizes the password on all hosts having system generated ones.

Identification keys are revoked each 6 months. Carmen receives email with new key and its password over text message, month before key termination.

# Peacemaker

Managing above user stories may easily became a nightmare for system operator. Doing above without extensive level of automation is a quite difficult job. To make it easier pmaker automates it with help of Ansible configuration manager.

Pmaker runs on dedicated host - the controller; of course, does not need to use its full capacity, occupying just few megabytes in /opt/pmaker directory. From this directory system administrator as pmaker runs all the tasks; it's the place with user details, and here are stored all the passwords, and keys. Pmaker account is like root for the system. System operator must take care of it in the same way root details are protected.

Each group of servers has associated jump server, where pmaker creates accounts, however without other services as ability to sudo. According to preferences user may connect to jump using password authentication or in password less way. Preferred method is the latter one.

```
ssh -J carmen@dev_jump.science.org carmen@dev1.science.org
```

## file layout

Pmaker sits in /opt/pmaker

```
> ls -1 # manually sorted

data                user database
state               system state i.e. all password, keys
tasks_dev.yaml      playbook to handle dev
users_split.yaml    playbook to preprocess user database       
config.yaml         playbook defaults (user group)
ansible.cfg         ansible defaults (server group)
README.md           this file
templates           notificatino message templates
lib                 ansible functions
src                 pmaker project
```

Pmaker comes with sample system, described in data directory. Note that both user and server database is started with name of the group. In real life it will be department, organization, or project name, or any other business level name identifying group of people.

```
> ls -1 data

sample.users.yaml       list of users
sample.inventory.cfg    list of instances
```

# user definition

User database is the place where all uses are described. username is user’s identifier on all the servers; server_groups says to which environments user has access; password/key defines authentication method; become informs is user may sodo to oracle, root, and/or appl* users. Email and phone are informative for system operator. 

Let's take a look how the user is described:

```
> head -15 data/sample.users.yaml

---
users:
  - username: alice
    server_groups: [dev]
    
    password: yes
    key: yes

    became_oracle: [dev]
    became_root:   [dev]
    became_appl:   [dev]

    full_name: Alice Liddell
    email: alice@wonder.land
    mobile: +48 001 002 003
```

# server definition

Servers belonging to Sample project are described in Ansible inventory file. With this information Ansible is aware of instances belonging to logical groups and how to access them.

```
> cat data/sample.inventory.cfg 

[controller]
localhost ansible_connection=local

[dev_jump]
pmaker-test-1 ansible_user=pmaker public_ip=132.168.0.1 host_type=jump

[dev]
pmaker-test-2 ansible_user=pmaker host_type=application

[sit_jump]
pmaker-test-1 ansible_user=pmaker public_ip=132.168.0.1 host_type=jump

[sit]
pmaker-test-3 ansible_user=pmaker host_type=application
pmaker-test-4 ansible_user=pmaker host_type=application

[uat_jump]
pmaker-test-1 ansible_user=pmaker public_ip=132.168.0.1 host_type=jump

[uat]
pmaker-test-4 ansible_user=pmaker host_type=application
```

Plese note that apart of regular Ansible varibles pmaker uses two more ones:
1. public_ip is used to keep track of external public addresses of jump servers. It's mainly used for user notification after account creation. 
2. host_type is used to execute various sections of configuration flows for diferent host types. For now it's not possible to set sudoers on non application hosts 

# Installation

Pacemaker is an open source project hosted on github. To install, one clones the repository using git, and runs setup.sh script.

```
sudo yum install -y  git

git clone https://github.com/rstyczynski/pmaker.git
./pmaker/setup/setup.sh
```

Initial script prepares localhost as the ansible controller. Please note that after succesful setup you will see pmaker user on the host with sodo rights. Pmaker takes /opt/pmaker directory for its private use.

Having controller ready, you need to configure your whole system. Collect list of servers of all your environments, and put this information into Ansible inventory file. At beginning use the sample file, shipped with pmaker, keep dev, sit, uat env names to simplify configuration, and just replace hostnames. Once completed you may create sample team of alice, bob, carmen, and derek. Please remember to keep pmaker as connection user. 

```
vi data/sample.inventory.cfg 

<< do the editing >>
```

Note that ansible uses password less SSH protocol to access all the hosts. It's mandatory to ensure that:
- you may access all the servers this way. Setup scripts pings all the hosts before proceeding. In case of any communication issues setup stops,
- you operate from user with sudo rights. setup script creates pmaker user which will be used after installation to work with user management.

Once configured proceed with setup of all the hosts.

```
cd pmaker
./setup/configure.sh
```

After successful completion, pmaker will be created with password less access on all the hosts. Moreover, sshd will be configured for password access to make it possible to use passwords if any user needs it. In case of ssh issues configure will give up. In such situatuion fix errors, and retry.

# Definition of user accounts

Look info sample.users.yaml file in data directory. The file is almost self describing. Specify your users in presented format taking into account comments presented below. 

```
---
users:
  - username: alice               unix login name
    server_groups: [dev]          environments user has access to
    
    password: yes                 can user use password to authenticate?
    key: yes                      can user authenticate using key?

    became_oracle: [dev]          can user sudo to oracle?
    became_root:   [dev]          can user sudo to root?
    became_appl:   [dev]          can user sudo to users prefixed by appl e.g. applsoa, applodi?

    full_name: Alice Liddell      full name
    email: alice@wonder.land      e-mail is used to send welcome letter
    mobile: +48 001 002 003       mobile number. provide with spaces to avoind interpretaing as a number, as + will be lost.
```

That's all. Quite simple user definition. 

# Support for multiple projects

Both user and host definition files are prefixed by project name aka user group.

```
sample.users.yaml
sample.inventory.cfg
```

Use your prefferend name to keep users and hosts in a files with meaningful names. user group will be used as parameter to scritps.

# Permament switch to project name

To set default name of user group to freal value, and escape from sample one, set your value in ansible.cfg and config.yaml.

```
> cat ansible.cfg 

[defaults]
inventory = /opt/pmaker/data/science.inventory.cfg

> cat config.yaml 
---
pmaker_home: /opt/pmaker
user_group: science
```

Having this playbooks will default to science inventory and science user group.

# Deploying user accounts to servers

Having all the users defined in data/sample.users.yaml, system administrator runs parser which splits users into lists associated with each environment and actual ansible intercting with managed hosts. Both ansible blaybooks are wrapped by bash script taking one parameter - user group name or rather project name. 

Note that sysadmin operated as pmaker user; use sudo to switch identity.

```
> sudo su - pmaker
> whoami
pmaker

> cd /opt/pmaker
./envs_update.sh sample
```

Ansible playbooks do the following things:
1. prepares state directory with envronments names - it's the place where all names, keys, passwords, etc. are stored.
2. splits user database into environment

, and:

1. prepares passwords and openssh/putty keys incl. encrypted ones
2. creates user accounts
3. sets passwords
4. register public keys in servers' authorized keys
5. maintains sudoers configuration.

Once completed user admin may distribute keys and passwords them to users. 

# System state repository

Pmaker playbooks configure the system, having reflected system cfg. in state reposistory. Of course it's generally speaking unsafe, however all pmaker files are available only for this user. 

*Remeber: pmaker is like a root user! Protect this account, and use only to manage users.*

Let's take a look into state directory.

```
> whoami
pmaker
cd /opt/pmaker

find state | head -12

state
state/sample
state/sample/dev
state/sample/dev/users.yaml
state/sample/dev/alice
state/sample/dev/alice/.ssh
state/sample/dev/alice/.ssh/id_rsa
state/sample/dev/alice/.ssh/id_rsa.pub
state/sample/dev/alice/.ssh/id_rsa.enc
state/sample/dev/alice/.ssh/id_rsa.ppk
state/sample/dev/alice/.ssh/secret.key
state/sample/dev/alice/.ssh/secret.txt
```

sample is directory having all users for given group; under this environments are reflected, with list of users in yaml format. Finally there is a directory having top secret user files.

id_rsa.pub - openssh sa public key. This one is distributed to all servers
id_rsa     - openssh rsa private key
id_rsa.enc - openssh encrypted rsa private key
id_rsa.ppk - putty encrypted rsa private key
secret.key - 15 character long password for encrypted keys
secret.txt - 12 character long password used for authentication.

*Remeber: pmaker is like a root user! Protect this account, and use only to manage users.*

# Keys and passwords delivery to users

User management administrator should deliver password and keys in a secure way. One of commonly used techniques is to send passwords using gsm sms channel, and encrypted keys using e-mail.

Pmaker does not deliver data to users on this stage, however generates messages for both e-mail and sms channels.

```
> generateAllMessages sample dev

Processing user alice...
Getting data...
Generating messages...
\- welcome mail...OK
\- access password...OK
\- key password...OK
Processing user bob...
Getting data...
Generating messages...
\- welcome mail...OK
\- access password...Skipped
\- key password...OK
Processing user carmen...
Getting data...
Generating messages...
\- welcome mail...OK
\- access password...OK
\- key password...Skipped
Processing user derek...
Getting data...
Generating messages...
\- welcome mail...OK
\- access password...Skipped
\- key password...Skipped
All done. Use getWelcomeEmail, getPasswordSMS, getKeySMS to get messages.
```

Generated messages are stored in user's state repository under directory outbox. All messages are generated using templates, so customisation is not only possible, but is easy.

```
> ls -1 state/sample/dev/alice/outbox/
key_sms.txt
pass_sms.txt
welcome_mail-body.txt
welcome_mail-header.txt

> cat state/sample/dev/alice/outbox/key_sms.txt
Password for your account: aeYee4Eec@ee | Generated on 2020-03-25 22:20:55 to be sent to +48 001 002 003

> cat templates/welcome_password_key.j2 
Password for your key: {{ password_key }} | Generated on {{ date }} to be sent to {{ mobile_number }}
```

You may access messages directly or use one of available functions:
- getWelcomeEmail sample dev alice
- getWelcomeEmail sample dev alice header
- getKeySMS sample dev alice
- getPasswordSMS sample dev alice

Above should be used to privide data do CLI e-mail and sms senders. If not available you may scp files to your desktop and use copy to clipboard utilities as e.g. pbcopy available on OSX to speed up e-mail and sms delivery process.


<verbatim>


<p align="center">###</p>
</verbatim>

# AUTHOR
rstyczynski@gmail.com, march 2020

# TODO
- protect top secret files using additional level of encryption
- automated email/sms delivery
- http access to repository
- remove granted passoword access
- remove granted key access
- delete from host with revoked access