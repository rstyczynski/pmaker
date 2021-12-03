#!/bin/bash

#
# init runtime context
#

unset executed
declare -A executed
unset prereq
declare -A prereq

# enter prerequisities. Use comma as command separator
prereq[deploy]="import_excel"
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
  if [ -z $organisation ]; then
    echo "Error. organisation must be defined."
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
    if [ -z $user_filter ]; then
      echo "Warning. user_filter not specified. All users will be processed. To avoid set user_filter variable to proper list using space as a separator."
    else
      # replace spaces with pipe. For some reson pipe was used.
      user_filter=$(echo $user_filter | tr ' ' '|')
    fi

    if [ -z $environments ]; then
      echo "Warning. environments not specified. All environments will be processed. To avoid set environments variable to proper list using space as a separator."
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
        echo "Can't run this command before: ${prereq[$command]}"
        return 100
      fi
    done
  else
    echo "Info. Dependency check disabled."
  fi

  # select environments to process
  if [ -f $pmaker_home/data/$organisation.users.yaml ]; then
    known_environments=$(cat $pmaker_home/data/$organisation.users.yaml |  y2j |  jq -r '[.users[].server_groups[]] | unique | .[]')
    if [ -z "$environments" ] || [ "$environments" = all ]; then
      environments=$known_environments
    fi

    if [ -z "$known_environments" ]; then
      echo "Warning. Environment list empty. Verify that spreadsheet contains proper access data."
    fi
  else
    echo "Warning. User directory not ready. Use import excel."
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
- import excel         - imports user access information from spreadsheet. Note that you may import only subset of users by setting user_flter.
- generate ssh config  - converts Ansible inventory to ssg config file, enabling pmaker user access to managed hosts.
- generate keys        - generates ssh keys for new users. Already existing keys are not changed.
- deploy               - deploys keys, and user configuration to managed hosts.
- validate             - tests user access with verification of sudo escalatio rights.
- message generate     - prepares welcome messages i.e. e-mails & sms'es.
- message validate     - displays welcome messages. Mssages are sent only once.
- message send         - delivers welcome emails. 
- message clear        - clears message sent flag; used to redeliver messages.

pmaker accepts following informative commands:
- list organisations   - lists organisation names with known spreadsheet with user access informaton
- list environments    - list server groups for current organisation.
- list users env       - list users for given environment, where env in server group name. Use all to see all users.

To proceed you need to set environment variables:
- pmaker_home          - pmaker's home directory. Typically already set via .bash_profile.
- organisation         - organization name. Used to get right inventory file and right source of users.
- environments         - environments to process. When not specified or set to all, all environments are processed.
- user_filter          - subset of users to process; usernames are separated by pipe. When not specified all users are processed

_help_EOF
    ;;
  list)
    command="${command}_${what}"
    case $what in
    organisations)
      echo "All known to pmaker organisations:"
      ls $pmaker_home/data/*.users.xlsm | sed "s|$pmaker_home/data/||g" | sed 's|\.users\.xlsm||g'
      ;;
    environments)
      echo "All server groups known at $organisation:"
      echo $known_environments
      ;;
    users)
      env=$(echo $1 | tr [A-Z] [a-z]); shift
      if [ -z "$env" ] || [ "$env" == all ]; then
        echo "All users known at $organisation:"
        cat $pmaker_home/data/$organisation.users.yaml | y2j | jq -r '.users[].username'
      else
        if [ -f $pmaker_home/state/$user_group/$env/users.yaml ]; then
          echo "Users known at $organisation / $env:"
          cat $pmaker_home/state/$user_group/$env/users.yaml | y2j | jq -r '.users[].username'
        else
          result=1
          echo "Error. Environment does not exist"
        fi
      fi
      ;;
    *)
      echo "Error. Unknown object for list."
      ;;
    esac
    ;;
  import)
    command="${command}_${what}"
    case $what in
    excel)
      $pmaker_bin/users2pmaker.sh $pmaker_home/data/$organisation.users.xlsm "$user_filter" >$pmaker_home/data/$organisation.users.yaml || result=$?
      ;;
    *)
      echo "Error. Unknown object for import."
      result=1
      ;;
    esac

    if [ $result -eq 0 ]; then
      for env in $environments; do
        ansible-playbook $pmaker_lib/env_users.yaml \
        -e pmaker_home=$pmaker_home \
        -e user_group=$organisation \
        -e server_group=$env || result=$?
      done
      known_environments=$(cat $pmaker_home/data/$organisation.users.yaml |  y2j |  jq -r '[.users[].server_groups[]] | unique | .[]')
    fi

    ;;
  generate)
    command="${command}_${what}"
    case $what in
    keys)
      for env in $environments; do
        ansible-playbook $pmaker_lib/env_configure_controller.yaml \
        -e pmaker_home=$pmaker_home \
        -e server_group=$env \
        -e user_group=$organisation \
        -i $pmaker_home/data/$organisation.inventory_hosts.cfg \
        -l localhost || result=$?
      done
      ;;
    ssh)
      where=$1; shift
      command="${command}_${what} $where"
      case $where in
      config)
        for env in $environments; do
          if [ -f $pmaker_home/data/$organisation.inventory.cfg ]; then
            echo "Setting up ssh config for $env"
            if [ -f state/$organisation/$env/pmaker/.ssh/id_rsa ]; then
                $pmaker_bin/prepare_ssh_config.sh $organisation $env pmaker $pmaker_home/state/$organisation/$env/pmaker/.ssh/id_rsa || result=$?
            else
              result=1
              echo "Error. pmaker key not available."
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

    for env in $environments; do

      server_list="controller $(ansible-inventory -i $pmaker_home/data/$organisation.inventory.cfg  -y --list | y2j | jq -r  "[.all.children.$env.hosts | keys[]] | unique | .[]")"

      echo '========================='
      echo Processing env: $env
      echo \-having servers: $server_list
      echo '========================='

      ansible-playbook $pmaker_lib/env_configure_hosts.yaml \
      -e pmaker_home=$pmaker_home \
      -e server_group=$env \
      -e user_group=$organisation \
      -i $pmaker_home/data/$organisation.inventory.cfg \
      -l "$server_list" | 
      tee -a $pmaker_log/environments_update-$organisation-$env-$(date -I).log
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
      for env in $environments; do
        ansible-playbook $pmaker_lib/env_users.yaml \
        -e pmaker_home=$pmaker_home \
        -e user_group=$organisation \
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

    user_subset=$(echo $user_filter | tr '|' ,)
    if [ -z "$environments" ] || [ "$environments" = all ]; then
      environments=$(cat $pmaker_home/data/$organisation.inventory.cfg |
        grep '^\[' |
        grep -v '\[jumps\]' |
        grep -v '\[controller\]' |
        tr -d '[]')
    fi

    for env in $environments; do
        $pmaker_bin/test_ssh_access.sh \
        $organisation \
        $env \
        $pmaker_home/data/$organisation.inventory.cfg \
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
      for env in $environments; do
        # generate e-mail and sms
        generateAllMessages $organisation $env || result=$?
      done
      ;;

    validate)
      result=0
      for env in $environments; do
        # verify emails and sms
        welcome_email $organisation $env || result=$?
        welcome_sms $organisation $env || result=$?
        welcome_password_sms $organisation $env || result=$?
      done
      ;;

    deliver)
      if [ ! -f ~/.pmaker/smtp.cfg ]; then
        echo "Error. SMTP server configuration not found."
        result=1
      else
        source ~/.pmaker/smtp.cfg

        result=0
        for env in $environments; do
          # deliver emails and sms
          welcome_email $organisation $env all deliver || result=$?
          welcome_sms $organisation $env all deliver $sms_delivery || result=$?
          welcome_password_sms $organisation $env all deliver $sms_delivery || result=$?
        done
      fi
      ;;

    clear)
      result=0
      for env in $environments; do
        # clear sent flag
        clear_welcome_email $organisation $env $user_filter || result=$?
        clear_welcome_sms $organisation $env $user_filter || result=$?
        clear_welcome_password_sms $organisation $env $user_filter || result=$?
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
