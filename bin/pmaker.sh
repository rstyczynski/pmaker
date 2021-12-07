#!/bin/bash

#
# init runtime context
#

unset executed
declare -A executed
unset prereq
declare -A prereq

# enter prerequisities. Use comma as command separator
prereq[generate_keys]="import_excel"
prereq[deploy]="generate_keys"
prereq[welcome]="deploy"
prereq[welcome validate]="welcome_generate"
prereq[welcome send]="welcome_validate"

#
# helpers
#

function j2y {
   ruby -ryaml -rjson -e 'puts YAML.dump(JSON.parse(STDIN.read))'
}

function y2j {
   ruby -ryaml -rjson -e 'puts JSON.dump(YAML.load(STDIN.read))'
}

unset log
function log() {
  echo $@

  if [ "$1" == '-n' ]; then
    echo -n "$(date +%Y-%m-%dT%H:%M:%S)|" >> $pmaker_home/log/${pmaker_org}_state.log
  fi
  echo $@ >> $pmaker_home/log/${pmaker_org}_state.log
}



#
# main logic
#
function pmaker() {

  dependency_check=TRUE
  if [ "$1" == force ]; then
    dependency_check=FALSE
    shift
  fi

  if [ -z "$1" ]; then
    command=help
  else
    command=$1
    shift
  fi

  what=$1
  shift

  # variable verification
  if [ -z $pmaker_org ]; then
    echo "Error. pmaker_org must be defined."
    if [ $command != help ]; then
      command=exit_on_error
    fi
  fi

  if [ -z $pmaker_home ]; then
    echo "Error. pmaker_home must be defined."
    if [ $command != help ]; then
      command=exit_on_error
    fi
  fi

  if [ $command != exit_on_error ]; then
    if [ -z $pmaker_users ]; then
      echo "Warning. pmaker_users not specified. All users will be processed. To avoid set pmaker_users variable to proper list using space as a separator."
    else
      # replace spaces with pipe. For some reson pipe was used.
      pmaker_users=$(echo $pmaker_users | tr ' ' '|')
    fi

    if [ -z "$pmaker_envs" ]; then
      echo "Warning. pmaker_envs not specified. All pmaker_envs will be processed. To avoid set pmaker_envs variable to proper list using space as a separator."
    fi
  fi

  : ${sms_delivery:=aws}

  pmaker_bin=$pmaker_home/bin
  pmaker_lib=$pmaker_home/lib
  pmaker_log=$pmaker_home/log

  mkdir -p $pmaker_log


  if [ $dependency_check == TRUE ]; then
    # prerequisities verification
    IFS=,
    for prereq in ${prereq[$command]} ${prereq[${command}_${what}]}; do
      echo testing $prereq...
      if [ -z ${executed[$prereq]} ] || [ ${executed[$prereq]} == FAILED ]; then
        echo "Can't run this command before: $(${prereq[$command]} | tr _ ' ')"
        return 100
      fi
    done
    unset IFS
  else
    echo "Info. Dependency check disabled."
  fi



  if [ $command != exit_on_error ]; then
    # select pmaker_envs to process
    if [ -f $pmaker_home/data/$pmaker_org.users.yaml ]; then
      known_pmaker_envs=$(cat $pmaker_home/data/$pmaker_org.users.yaml |  y2j |  jq -r '[.users[].server_groups[]] | unique | .[]' | tr '\n' ' ')
      if [ -z "$pmaker_envs" ] || [ "$pmaker_envs" = all ]; then
        pmaker_envs=$known_pmaker_envs
      fi

      if [ -z "$known_pmaker_envs" ]; then
        echo "Warning. Environment list empty. Verify that spreadsheet contains proper access data."
      fi
    else
      echo "Warning. User directory not ready. Use import excel."
    fi
  fi

  # execute command
  result=0
  case $command in
  exit_on_error)
    echo "Error. Critical error occured. Cannot continue. "
    result=90
    ;;
  help)
    cat <<_help_EOF

pmaker accepts following operational commands:
- import excel            - imports user access information from spreadsheet. Note that you may import only subset of users by setting user_flter.
- generate ssh config     - converts Ansible inventory to ssg config file, enabling pmaker user access to managed hosts.
- generate keys           - generates ssh keys for new users. Already existing keys are not changed.
- deploy                  - deploys keys, and user configuration to managed hosts.
- validate                - tests user access with verification of sudo escalatio rights.
- welcome generate        - prepares welcome messages i.e. e-mails & sms'es.
- welcome validate        - displays welcome messages. Mssages are sent only once.
- welcome deliver         - delivers welcome emails. 
- welcome clear           - clears message sent flag; used to redeliver messages.

pmaker makes it possible to share keys between organisations:
- share user key [id_rsa] - shares user's named key. Creates virtual org "shared".

pmaker accepts following configuration commands:
- set org to name         - set active organisation to name given on parameter
- set envs to list        - set active environments to givel list or just one env
- set users to list       - set active users to givel list or just one user

pmaker accepts following informative commands:
- list orgs               - lists pmaker_org names with known spreadsheet with user access informaton
- list envs               - list server groups for current pmaker_org.
- list users env          - list active users for given environment, where env in server group name. Use all to see all users. Active means that this subset of users will be processed by pmaker; list may be shorter than the real one.
- show context            - shows current values of pmaker home, org, envs, and user filter
- show home               - shows pmaker home
- show org                - shows selected organisation
- show envs               - shows selected environments to process
- show users              - shows selected users to process

To proceed you need to set environment variables via shell or set commands:
- pmaker_home             - pmaker's home directory. Typically already set via .bash_profile.
- pmaker_org              - organization name. Used to get right inventory file and right source of users.
- pmaker_envs             - pmaker_envs to process. When not specified or set to all, all pmaker_envs are processed.
- pmaker_users            - subset of users to process; usernames are separated by pipe. When not specified all users are processed

_help_EOF
    ;;
  share)
    subject=$1; shift
    command="${command}_${what}_${subject}"
    case ${what}_${subject} in
    user_key)
      shared_key=$1

      log -n "Sharing $shared_key... "
      : ${shared_key:=id_rsa}
      mkdir -p $pmaker_home/state/shared
      env=$(echo $pmaker_envs | cut -f1 -d' ')

      if [ -f $pmaker_home/state/$pmaker_org/$env/pmaker/.ssh/$shared_key ]; then
        shared_key_md5=$(echo $pmaker_home/state/$pmaker_org/$env/pmaker/.ssh/$shared_key | md5sum | cut -f1 -d' ' )
        mkdir -p $pmaker_home/state/shared/.ssh
        cp $pmaker_home/state/$pmaker_org/$env/pmaker/.ssh/$shared_key $pmaker_home/state/shared/.ssh/$shared_key_md5
        log OK
      else
        log "Error. Key not found."
      fi
      ;;
    *)
      result=1
      echo "Error. Unknown object for share."
      ;;
    esac 
    ;;   
  list)
    command="${command}_${what}"
    case $what in
    orgs)
      echo "All known to pmaker pmaker_orgs:"
      ls $pmaker_home/data/*.users.xlsm | sed "s|$pmaker_home/data/||g" | sed 's|\.users\.xlsm||g'
      ;;
    envs)
      echo "All server groups known at $pmaker_org:"
      echo $known_pmaker_envs
      ;;
    users)
      env=$(echo $1 | tr [A-Z] [a-z]); shift
      if [ -z "$env" ] || [ "$env" == all ]; then
        echo "All users known at $pmaker_org:"
        cat $pmaker_home/data/$pmaker_org.users.yaml | y2j | jq -r '.users[].username'
      else
        if [ -f $pmaker_home/state/$pmaker_org/$env/users.yaml ]; then
          echo "Users known at $pmaker_org/$env:"
          cat $pmaker_home/state/$pmaker_org/$env/users.yaml | y2j | jq -r '.users[].username'
        else
          result=1
          echo "Error. Environment does not exist"
        fi
      fi
      ;;
    *)
      result=1
      echo "Error. Unknown object for list."
      ;;
    esac
    ;;
  show)
    command="${command}_${what}"
    case $what in
    envs)
      if [ -z "$pmaker_envs" ]; then
        echo "Environments to process in this session: all"
      else
        echo "Environments to process in this session: $pmaker_envs"
      fi
      ;;
    users)
      if [ -z "$pmaker_users" ]; then
        echo "Users to process in this session: all"
      else
        echo "Users to process in this session: $pmaker_users"
      fi
      ;;
    home)
      echo "pmaker home: $pmaker_home"
      ;;
    org)
      echo "pmaker organisation: $pmaker_org"
      ;;
    context)
      echo "pmaker home:                             $pmaker_home"
      echo "pmaker organisation:                     $pmaker_org"

      if [ -z "$pmaker_envs" ]; then
        echo "Environments to process in this session: all"
      else
        echo "Environments to process in this session: $pmaker_envs"
      fi

      if [ -z "$pmaker_users" ]; then
        echo "Users to process in this session: all"
      else
        echo "Users to process in this session: $pmaker_users"
      fi
      ;;
    *)
      result=1
      echo "Error. Unknown object for show."
      ;;
    esac
    ;;
  set)
    command="${command}_${what}"
    if [ "$1" == to ]; then
      shift
      case $what in
      org)
        pmaker_org=$@
        unset pmaker_envs
        unset pmaker_users
        ;;
      envs)
        pmaker_envs="$@"
        ;;
      users)
        pmaker_users="$@"
        ;;
      *)
        result=1
        echo "Error. Unknown object for set."
        ;;
      esac
    else
      result=1
      echo "Error. Syntax violated. Use set what to value"
    fi
    ;;
  import)
    command="${command}_${what}"
    case $what in
    excel)
      $pmaker_bin/users2pmaker.sh $pmaker_home/data/$pmaker_org.users.xlsm "$pmaker_users" >$pmaker_home/data/$pmaker_org.users.yaml || result=$?
      ;;
    *)
      echo "Error. Unknown object for import."
      result=1
      ;;
    esac

    if [ $result -eq 0 ]; then
      for env in $pmaker_envs; do
        echo '======================='
        echo "Processing $env"
        echo '======================='

        ansible-playbook $pmaker_lib/env_users.yaml \
        -e pmaker_home=$pmaker_home \
        -e user_group=$pmaker_org \
        -e server_group=$env || result=$?
      done
      known_pmaker_envs=$(cat $pmaker_home/data/$pmaker_org.users.yaml |  y2j |  jq -r '[.users[].server_groups[]] | unique | .[]')
    fi

    ;;
  generate)
    command="${command}_${what}"
    case $what in
    keys)
      for env in $pmaker_envs; do
        ansible-playbook $pmaker_lib/env_configure_controller.yaml \
        -e pmaker_home=$pmaker_home \
        -e server_group=$env \
        -e user_group=$pmaker_org \
        -i $pmaker_home/data/$pmaker_org.inventory_hosts.cfg \
        -l localhost || result=$?
      done
      ;;
    ssh)
      where=$1; shift
      command="${command}_${what}_${where}"
      case $where in
      config)
        for env in $pmaker_envs; do
          if [ -f $pmaker_home/data/$pmaker_org.inventory.cfg ]; then
            echo "Setting up ssh config for $env"
            if [ -f $pmaker_home/state/$pmaker_org/$env/pmaker/.ssh/id_rsa ]; then
              $pmaker_bin/prepare_ssh_config.sh $pmaker_org $env pmaker $pmaker_home/state/$pmaker_org/$env/pmaker/.ssh/id_rsa || result=$?
            else
              
              # check if pmaker key is shared
              if [ -f $pmaker_home/state/$pmaker_org/$env/pmaker/.ssh/shared ]; then
                shared_by=$(cat $pmaker_home/state/$pmaker_org/$env/pmaker/.ssh/shared | cut -f1 -d'|')
                shared_key=$(cat $pmaker_home/state/$pmaker_org/$env/pmaker/.ssh/shared | cut -f2 -d'|')

                shared_key_md5=$(echo $pmaker_home/state/$shared_by/$env/pmaker/.ssh/$shared_key | md5sum | cut -f1 -d' ' )

                $pmaker_bin/prepare_ssh_config.sh $pmaker_org $env pmaker $pmaker_home/state/shared/.ssh/$shared_key_md5 || result=$?

              else
                $pmaker_bin/prepare_ssh_config.sh $pmaker_org $env pmaker ~/.ssh/id_rsa || result=$?
              fi
            fi
          else
            result=1
            echo "Error. Inventory file not found."
          fi
        done
        ;;
      *)
        echo "Error. Unknown object for generate ssh."
        result=1
        ;;
      esac
      ;;
    *)
      echo "Error. Unknown object for generate."
      result=1
      ;;
    esac
    ;;

  deploy)

    for env in $pmaker_envs; do

      server_list="controller $(ansible-inventory -i $pmaker_home/data/$pmaker_org.inventory.cfg  -y --list | y2j | jq -r  "[.all.children.$env.hosts | keys[]] | unique | .[]")"

      echo '========================='
      echo Processing env: $env
      echo \-having servers: $server_list
      echo '========================='

      ansible-playbook $pmaker_lib/env_configure_hosts.yaml \
      -e pmaker_home=$pmaker_home \
      -e server_group=$env \
      -e user_group=$pmaker_org \
      -i $pmaker_home/data/$pmaker_org.inventory.cfg \
      -l "$server_list" | 
      tee -a $pmaker_log/pmaker_envs_update-$pmaker_org-$env-$(date -I).log
      if [ ${PIPESTATUS[0]} -ne 0 ]; then
        result=1
      fi
    done
    ;;

  rebuild)
    command="${command}_${what}"
    case $what in
    users)

      result=0
      for env in $pmaker_envs; do
        ansible-playbook $pmaker_lib/env_users.yaml \
        -e pmaker_home=$pmaker_home \
        -e user_group=$pmaker_org \
        -e server_group=$env || result=$?
      done
      ;;
    *)
      echo "Error. Unknown object for rebuild."
      result=1
      ;;
    esac
    ;;
  validate)
    eval $(ssh-agent)
    ssh-add -D

    user_subset=$(echo $pmaker_users | tr '|' ,)
    if [ -z "$pmaker_envs" ] || [ "$pmaker_envs" = all ]; then
      pmaker_envs=$(cat $pmaker_home/data/$pmaker_org.inventory.cfg |
        grep '^\[' |
        grep -v '\[jumps\]' |
        grep -v '\[controller\]' |
        tr -d '[]')
    fi

    for env in $pmaker_envs; do
        $pmaker_bin/test_ssh_access.sh \
        $pmaker_org \
        $env \
        $pmaker_home/data/$pmaker_org.inventory.cfg \
        $user_subset \
        all &
    done
    wait
    result=0
    ;;

  welcome)
    command="${command}_${what}"

    source $pmaker_lib/generate_welcome_msg.sh
    source $pmaker_lib/deliver_welcome_msg.sh

    case $what in
    generate)
      #
      # generate
      #
      result=0
      for env in $pmaker_envs; do
        # generate e-mail and sms
        generateAllMessages $pmaker_org $env || result=$?
      done
      ;;

    validate)
      result=0
      for env in $pmaker_envs; do
        # verify emails and sms
        welcome_email $pmaker_org $env || result=$?
        welcome_sms $pmaker_org $env || result=$?
        welcome_password_sms $pmaker_org $env || result=$?
      done
      ;;

    deliver)
      if [ ! -f ~/.pmaker/smtp.cfg ]; then
        echo "Error. SMTP server configuration not found."
        result=1
      else
        source ~/.pmaker/smtp.cfg

        result=0
        for env in $pmaker_envs; do
          # deliver emails and sms
          welcome_email $pmaker_org $env all deliver || result=$?
          welcome_sms $pmaker_org $env all deliver $sms_delivery || result=$?
          welcome_password_sms $pmaker_org $env all deliver $sms_delivery || result=$?
        done
      fi
      ;;

    clear)
      result=0
      for env in $pmaker_envs; do
        # clear sent flag
        clear_welcome_email $pmaker_org $env $pmaker_users || result=$?
        clear_welcome_sms $pmaker_org $env $pmaker_users || result=$?
        clear_welcome_password_sms $pmaker_org $env $pmaker_users || result=$?
      done
      ;;
    *)
      echo "Error. Unknown action for welcome."
      result=1
      ;;
    esac
    ;;

  *)
    echo "Error. Unknown comnand."
    ;;
  esac

  # store executon result
  if [ $result -eq 0 ]; then
    executed[$command]=YES
    echo 'Done.'
  else
    executed[$command]=FAILED
    echo 'Failed.'
  fi

  return $result
}

echo "pmaker loaded. Use pmaker to proceed."
