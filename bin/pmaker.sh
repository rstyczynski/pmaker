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
  if [ -z $user_group ]; then
    echo "Error. user_group must be defined."
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

    if [ -z $envs ]; then
      echo "Warning. envs not specified. All environments will be processed. To avoid set envs variable to proper list using space as a separator."
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
  if [ -f $pmaker_home/data/$user_group.users.yaml ]; then
    known_envs=$(cat $pmaker_home/data/$user_group.users.yaml |  y2j |  jq -r '[.users[].server_groups[]] | unique | .[]')
    if [ -z "$envs" ] || [ "$envs" = all ]; then
      envs=$known_envs
    fi

    if [ -z "$known_envs" ]; then
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

pmaker accepts following commands:
- import excel         - imports user access information from spreadsheet.
- generate ssh config  - converts Ansible inventory to ssg config file, enabling pmaker user access to managed hosts.
- generate keys        - generates ssh keys for new users. Already existing keys are not changed.
- deploy               - deploys keys, and user configuration to managed hosts.
- validate             - tests user access with verification of sudo escalatio rights.
- message generate     - prepares welcome messages i.e. e-mails & sms'es.
- message validate     - displays welcome messages. Mssages are sent only once.
- message send         - delivers welcome emails. 
- message clear        - clears message sent flag; used to redeliver messages.

To proceed you need to set environment variables:
- pmaker_home          - pmaker's home directory. Typically already set via .bash_profile.
- user_group           - organization name. Used to get right inventory file and right source of users.
- envs                 - environments to process. When not specified or set to all, all environments are processed.
- user_filter          - subset of users to process; usernames are separated by pipe. When not specified all users are processed

_help_EOF
    ;;
  import)
    command="${command}_${what}"
    case $what in
    excel)
      $pmaker_bin/users2pmaker.sh $pmaker_home/data/$user_group.users.xlsm "$user_filter" >$pmaker_home/data/$user_group.users.yaml || result=$?
      ;;
    *)
      echo "Error. Unknown object for import."
      result=1
      ;;
    esac

    if [ $result -eq 0 ]; then
      for this_env in $envs; do
        ansible-playbook $pmaker_lib/env_users.yaml \
        -e pmaker_home=$pmaker_home \
        -e user_group=$user_group \
        -e server_group=$this_env \
        -l localhost || result=$?
      done
      known_envs=$(cat $pmaker_home/data/$user_group.users.yaml |  y2j |  jq -r '[.users[].server_groups[]] | unique | .[]')
    fi

    ;;
  generate)
    command="${command}_${what}"
    case $what in
    keys)
      for env in $envs; do
        ansible-playbook $pmaker_lib/env_configure_controller.yaml \
        -e pmaker_home=$pmaker_home \
        -e server_group=$env \
        -e user_group=$user_group \
        -i $pmaker_home/data/$user_group.inventory_hosts.cfg \
        -l localhost || result=$?
      done
      ;;
    ssh)
      where=$1; shift
      command="${command}_${what} $where"
      case $where in
      config)
        for env in $envs; do
          if [ -f $pmaker_home/data/$user_group.inventory.cfg ]; then
            echo "Setting up ssh config for $env"
            if [ -f state/$user_group/$env/pmaker/.ssh/id_rsa ]; then
                $pmaker_bin/prepare_ssh_config.sh $user_group $env pmaker $pmaker_home/state/$user_group/$env/pmaker/.ssh/id_rsa || result=$?
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

    for env in $envs; do

      server_list="controller $(ansible-inventory -i $pmaker_home/data/$user_group.inventory.cfg  -y --list | y2j | jq -r  "[.all.children.$env.hosts | keys[]] | unique | .[]")"

      echo '========================='
      echo Processing env: $env
      echo \-having servers: $server_list
      echo '========================='

      ansible-playbook $pmaker_lib/env_configure_hosts.yaml \
      -e pmaker_home=$pmaker_home \
      -e server_group=$env \
      -e user_group=$user_group \
      -i $pmaker_home/data/$user_group.inventory.cfg \
      -l "$server_list" | 
      tee -a $pmaker_log/envs_update-$user_group-$env-$(date -I).log
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
      for this_env in $envs; do
        ansible-playbook $pmaker_lib/env_users.yaml \
        -e pmaker_home=$pmaker_home \
        -e user_group=$user_group \
        -e server_group=$this_env \
        -l localhost || result=$?
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
    if [ -z "$envs" ] || [ "$envs" = all ]; then
      envs=$(cat $pmaker_home/data/$user_group.inventory.cfg |
        grep '^\[' |
        grep -v '\[jumps\]' |
        grep -v '\[controller\]' |
        tr -d '[]')
    fi

    for env in $envs; do
        $pmaker_bin/test_ssh_access.sh \
        $user_group \
        $env \
        $pmaker_home/data/$user_group.inventory.cfg \
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
      for env in $envs; do
        # generate e-mail and sms
        generateAllMessages $user_group $env || result=$?
      done
      ;;

    validate)
      result=0
      for env in $envs; do
        # verify emails and sms
        welcome_email $user_group $env || result=$?
        welcome_sms $user_group $env || result=$?
        welcome_password_sms $user_group $env || result=$?
      done
      ;;

    deliver)
      if [ ! -f ~/.pmaker/smtp.cfg ]; then
        echo "Error. SMTP server configuration not found."
        result=1
      else
        source ~/.pmaker/smtp.cfg

        result=0
        for env in $envs; do
          # deliver emails and sms
          welcome_email $user_group $env all deliver || result=$?
          welcome_sms $user_group $env all deliver $sms_delivery || result=$?
          welcome_password_sms $user_group $env all deliver $sms_delivery || result=$?
        done
      fi
      ;;

    clear)
      result=0
      for env in $envs; do
        # clear sent flag
        clear_welcome_email $user_group $env $user_filter || result=$?
        clear_welcome_sms $user_group $env $user_filter || result=$?
        clear_welcome_password_sms $user_group $env $user_filter || result=$?
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
