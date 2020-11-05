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
state/sample/dev/alice/.ssh/id_rsa.secret
state/sample/dev/alice/.ssh/pass.secret
```

sample is directory having all users for given group; under this environments are reflected, with list of users in yaml format. Finally there is a directory having top secret user files.

id_rsa.pub - openssh sa public key. This one is distributed to all servers
id_rsa     - openssh rsa private key
id_rsa.enc - openssh encrypted rsa private key
id_rsa.ppk - putty encrypted rsa private key
id_rsa.secret - 15 character long password for encrypted keys
pass.secret - 12 character long password used for authentication.

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

# Exemplary welcome sms

```
getKeySMS sample dev alice
```

```
Password for your key: Ash3ungoo<ch4ba | Generated on 2020-03-25 22:20:55 to be sent to +48 001 002 003
```

# Exemplary welcome e-mail

```
getWelcomeEmail sample dev alice header
```

```
TO: alice@wonder.land
SUBJECT: Your access information for sample/dev
FROM: Linux account management.
DATE: 2020-03-25 22:20:55
---
Welcome Alice from The Wonderland!

Your access to dev has been granted as alice.

You may use password to authenticate. Password for authentication is sent by sms to your mobile at +48 001 002 003.

You may use private key to authenticate. Your openssh encrypted private key is:

cat >~/.ssh/id_rsa_dev.enc <<EOF
-----BEGIN RSA PRIVATE KEY-----
Proc-Type: 4,ENCRYPTED
DEK-Info: AES-256-CBC,D1DE8224F59D6663A150565971D6A3A8

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
-----END RSA PRIVATE KEY-----
EOF
chmod 600 ~/.ssh/id_rsa_dev.enc

With password delivered via sms. Copy and paste presented key to a bash session or to a text editor, and save to a file. Remember to store the key in safe directory with private access only.

You may use encrypted keys, or decrypted for your convinience. To decrypt the key, using SMS provided password, execute the following:

openssl rsa -in ~/.ssh/id_rsa_dev.enc -out ~/.ssh/id_rsa_dev

Your putty encrypted private key is:

cat >~/.ssh/id_rsa_dev.ppk <<EOF
PuTTY-User-Key-File-2: ssh-rsa
Encryption: aes256-cbc
Comment: imported-openssh-key
Public-Lines: 12
AAAAB3NzaC1yc2EAAAADAQABAAACAQChWpByAT6rA8yXt2Q6bhVjFyYV6qJ59Y1p
BLpXRt7kNUiNcEVF0qHfFZnTXl2OxJdA6wdtGMsQLUPZz9+HL89W+kceqyiwz7M8
ZscJPZO8BZZslXlkbQ34GcyeDMirkM8f9uY0m5+i0cZKufv2llHx0yU7039oht3K
D4Ge/58IOx5P2RvzPG8ql92tyRvtUD1UF/0tHxHhFosBb9+atcbiZSW9Eg09qy6t
J3b4emhouQCLmvdoTn5ORSE7q95XvVRKr/bNFAFxjZdxBDp2um888+IgXbUDFYUE
BufwKXxvcO2tlQ90LKYDxmRM4tr0CgHvJvV+Mc1y5MC0vqkaYTCBuepZNmfkUJPR
444SemG0kLCn91iZCs8Y+03lXJyZ6QJ+8OJ2rYBKQNhLaEiXPSivIvc7qDnkjt45
aEbcSD9LD1Dath24LY1en/NZTSwWThdAIr8jqON3IODPRXpkpTnR7kYe2e4sbqWg
fUhqAXHZ4r/dhfvHYccN6dx+8QEs8P6pdayycoD0yi2REOHL8laqPZhj9/vXhTP5
hjpMPIpZHGex0A/Ln1EK1XT8fGepJjhbVm/hYsnkdHrHOhPthHefTy9KQNmiAy7G
5a4LC8vA+if/fcVNGdQ3Mv6uZHLUUwdnINrwjq8jxyYp3hznw9jFyhQMJ+xv9aWW
Q4IMqKa1Sw==
Private-Lines: 28
wMDatqYAXQKtcFkQuKHCjzLSHfTu+/rC6xkWeulCfkSrOMtvqvhRPhrzCOhRVqr8
pMWUcfWpoXKP//AxYB+aSkIqm9h/g9wlMtTAkb2eZqwAP6Hj1sLAiv18GLL/2UBn
34Oz31mGmeb8O+x/MI0h9vknotRycWqDTFT7JXqPKlZLL2khjw3rvolq/EGDJ52V
zKrv1KBkRs+i5MNNoJtTFBEpQiRfZ/W8xZN0jzdzE2V1skOUv213WIZ91JrZ+5a/
PtdwVKmxBMWcoWojQK7LYZL9skglJ8Kg3h+n7F7lyY0RMU5Vlj50LA7HM7zdNIX7
m2Wxx5Jyl0qged1umhwaZot1rP/43sAHq0PrfT3t/ZAQgEhgVrniosGweFjMXM8Q
NlgtkH50qJZoUdhq1H76HqKzdIRjX3s+AEhusOdrIR5IX7SWOW2TqCr6PwNzq7yB
S4BImldBLB5RgsztpyZUVj1Sq5EYeehmhfZMokeBWyGLNWZRBGBKSauPVRe2B53E
da2G4/SxCahTEV7wTbBykGPR3OqsSAtwkbUDyuEYqScU4/gEa04WDtKNf7SFS+kN
sD+c5I473lu2WFpjf4fEqFAF/6VI5jPkc2fbGIQf/jMbLzQLzG83RRb4LIoK6i/O
13FnuOwx9BVmyti93sfo88tfNot2slRIrLm1Y9cK/FTYSh5T09Z9wC1OgspGg26b
vKOwkuGxW3/NIxoUM86Y7oGB2EKrghnQklmW0ZryU2skr5d+FRtom8uJgrdeeTcJ
Zkn/igaPzNEpeumc4st0V0ehPbloo8hwQ7CWHU+i3HEUPTomOTt5bC8iELJAEn/R
H7PsRB3tYRVR83+GzRqMeAFdP1N9Quo/D1kaJsK44XNi4iyL34988qaW2NdoRf1m
ShpUOlymohzbtWFY8QfVF7WsK+JEAawDxH1s/aA8rPkICJ4en5NY2fG3+WKOJlov
C+w1YEsnZveNMYJFlt8gLldf7IFDcXyfzjcNROSNX/W9zCEfF7kdNVeYZZHp5LvX
sjNNnhvTAip+MSeWzDdni0cyy3+0Oq2mexP4pU7ZH8G5Ae30TX4fJ7N3MqDdqmh/
J6EXvUmmTTUO9DXy46ajIsSBteDZX3MLtKCr/Lz5ArbfgqMejkKndzPTzovXmiPw
gmrlF74/xlhJnibdktfkH+4FLNSB3mvir2ek3OQHY96W/HA22S6zolO5Un6gDjS/
Ck7Y1cm/ZSB32P9NhNrP0GJCxp7Fg0D+3vNzGG+4YTKq/v+0vo4CMp0vVRXK1N4n
0ARkGQVO7jRO4wDJZamuFueyEtxCoKc13HIeWb1GrRxAGPMGSNYDmz2u727nByLm
8gudw98EveAm92nK8uyAcZFAxnUBKb1ILsO7J4iexJjTzy3+qJmJtYJ5FevK3kQF
p97b0IbJFF1/y1A3RLZp5H2GvFdPBk7C5Q8XQEH+p31Vcn9qquL166meUKGqlhHT
rcdDkJwuccvj7IHLuv1/eO0LmdauCSCdFBRJpfsH3EMqpYIzvuF0WKU0Cpgep6y8
b2RRCDrs9KUNa0fOEuXU0cmuAxyRu42TYNCawLZJJC2VOa+5rjzRWDeSLTUNMRu1
NVZQpzLD0GLu9hNt6t0fL6mXnTON+xGnb87t7CNDfuATsdQjoC5Fic/QwFF8X5XN
LNclyYIw6t7oKVlFwTqdcDLHStY5HsjAm8H2lKBRTfMt9usCijr0sS78qBZdB2B0
Ll4PG49TE6WZuVqJi6OrXw==
Private-MAC: b9278558629994598deae1abf87146e21a127305
EOF
chmod 600 ~/.ssh/id_rsa_dev.ppk

With password delivered via sms. Copy and paste presented key to a bash session or to a text editor, and save to a file. Remember to store the key in safe directory with private access only.

You may use encrypted keys, or decrypted for your convinience. To decrypt the key, decrypt ssh key first, and convert to ppk format.

openssl rsa -in ~/.ssh/id_rsa_dev.enc -out ~/.ssh/id_rsa_dev
puttygen ~/.ssh/id_rsa_dev  -o ~/.ssh/id_rsa.ppk -O private

Access to dev servers is possible via bastion host: 168.192.0.1. 

When using ssh, remember to benefit from jump server support. Assuming that you want to access pmaker-test-2, execute:

ssh -i -J alice@168.192.0.1 alice@pmaker-test-2
scp -o 'ProxyJump alice@168.192.0.1' local_file alice@pmaker-test-2:~/
scp -o 'ProxyJump alice@168.192.0.1' alice@pmaker-test-2:~/remote_file .

Note that even having Windows you can benefit from ssh after installing Cygwin.

Regards,
Linux account management.

---
Generated on 2020-03-25 22:20:55 to be sent to alice@wonder.land.
If you are not the proper recipient, please delete this message.
```


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