User management
===============

```
cat /opt/pmaker/data/science.users.yaml
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
tasks_dev.yaml      playbook to handle dev
users_split.yaml    playbook to pre process user database       
config.yaml         playbook defaults (user group)
ansible.cfg         ansible defaults (server group)
README.md           this file
lib                 ansible functions
src                 pmaker project
```

Pmaker comes with sample system, described in data directory. Note that both user nad server database is started with name of the group. In real life it will be department, organisation, or project name, or any other business level name identifying group of people.

```
ls -1 data

sample.users.yaml       list of users
sample.inventory.cfg    list of insnaces
```

User database is the place where all uses are described. username is users identifier on all the servers; server_groups says to wchich environments user has access; password/key defines authentication method; become informs is user may sodo to oracle, root, and/or appl* users. Email and phone are informative for system operator. 


Let's take a look how the user is described:

```
head -15 data/sample.users.yaml

---
users:
  - username: alice
    server_groups: [dev]
    
    password: yes
    key: yes

    became_oracle: [dev]
    became_root:   [dev]
    became_appl:  [dev]

    email: alice@wonder.land
    mobile: +48 001 002 003
```

Servers belonging to Sample project are described in Ansible inventory file. With this information Ansible is aware of instances belonging to logical groups and how to access them.

```
cat data/sample.inventory.cfg 

[controller]
localhost ansible_connection=local

[dev]
pmaker-test-1 ansible_user=pmaker
pmaker-test-2 ansible_user=pmaker

[sit]
pmaker-test-3 ansible_user=pmaker

[uat]
pmaker-test-4 ansible_user=pmaker
```


## Deploying user accounts to servers

After adding users to science.users.yaml, system administrator runs parser which aplits users to lists associated with each environment. Note the this time system admin specifies user group name and host definition file.

```
cd /opt/pmaker
ansible-playbook users_split.yaml -e user_group=sample -i data/sample.inventory.cfg 
```

Having users split into environments, system admin runs ansible playbook for each environment.

```
cd /opt/pmaker
ansible-playbook tasks_dev.yaml -e user_group=sample -i data/sample.inventory.cfg 
```