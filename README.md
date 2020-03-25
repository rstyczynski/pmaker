User management
===============

```
cat /opt/pmaker/data/science.yaml
---
users:
  - username: carmen
    server_groups: [dev, sit, uat]

    became_oracle: [dev, sit, uat]
    became_appl:   [dev, sit, uat]
    became_root:   [dev]

    password:      yes
    key:           yes
    
    email: carmen@opera.world
    mobile: +48 007 008 009
```

Carmen is a member of Science project, having access to dozen of servers in dev, sit, and uat environments. She may connect to systems using password authentication or rsa identification key. She can switch to application accounts to manage dev as root, and other environments as oracle, applmgr, and applsoad. She may be contacted by email and mobile.

Creating accounts for Carmen, system admin uses auto generated safe password, and encrypted identification key. As Carmen may use putty to connect from Windows and ssh to connect from Linux, system admin creates keys in desired formats. 

---

Once accounts are created on all hosts Carmen receives text message on her mobile with Linux password, and another text message with password to encrypted keys. Username and keys are delivered using e-mail to her desktop. Carmen may access her key repository over https protocol with authentication.

Carmen has 1 week to connect to hosts and change passwords. After this time, system randomizes the password on all hosts having system generated ones.

Identification keys are revoked each 6 months. Carmen receives email with new key and its password over text message, month before key termination.

# Peace maker

Managing above user stories may easily became a nightmare for system operator. Doing above without extensive level of automation is a quite difficult job. To make it easier pmaker automates it with help of Ansible configuration manager.

Pmaker runs on dedicated host, and of cource does not need to use full capacity, ocuping just few megabytes in /opt/pmaker directory. From this directory system administrator runs all the tasks; it's the place with user details, and here are stored all the passwords, and keys. Pmaker account is like root for the system. System operator must take care of it in the same way root details are protected.

Pmaker sits in /opt/pmaker

```
ls -1 # manually sorted

data                user database
state               system state i.e. all password, keys
tasks_dev.yaml      ansible scripts to handle dev
users_split.yaml    ansible scripts to pre process user database       
config.yaml         default variables for ansible scripts
ansible.cfg         ansible configuration
README.md           this file
lib                 ansible functions
src                 pmaker project
```


## System layout

```
cat /opt/pmaker/inventory.cfg

[controller]
localhost ansible_connection=local

[dev]
dev1-dc2.cloud ansible_user=pmaker
dev2-dc1.cloud ansible_user=pmaker
dev3-dc2.cloud ansible_user=pmaker

[sit]
sit1-dc2.cloud ansible_user=pmaker

[uat]
uat1-dc3.cloud ansible_user=pmaker

```

Servers belonging to Science project are described in Ansible inventory file. With information Ansible is aware of instances belonging to logical groups and how to access them.

## Creating users

After adding users to science.yaml, system administrator runs parser which aplits users to lists associated with each environment.

```
cd /opt/pmaker
ansible-playbook tasks_dev.yaml 
```
