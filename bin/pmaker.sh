#!/bin/bash

#unset executed
declare -A executed
declare -A prereq

# enter prerequisities. Use comma as command separator
prereq[deploy]="import excel"

prereq[rebuild]="deploy"
prereq[validate]="rebuild users"
prereq[welcome]="deploy"
prereq[welcome validate]="welcome generate"
prereq[welcome send]="welcome validate"

function pmaker() {
  command=$1
  shift
  what=$1
  shift

  # variable verification
  if [ -z $user_group ]; then
    echo "Error. user_group must be defined."
    command=exit_on_error
  fi

  if [ -z $pmaker_home ]; then
    echo "Error. pmaker_home must be defined."
    command=exit_on_error
  fi

  if [ -z $user_filter ]; then
    echo "Warning. user_filter not specified. All users will be processed. To avoid set user_filter variable to proper list using space as a separator."
  else
    # replace spaces with pipe. For some reson pipe was used.
    user_filter=$(echo $user_filter | tr ' ' '|')
  fi

  if [ -z $envs ]; then
    echo "Warning. envs not specified. All environments will be processed. To avoid set envs variable to proper list using space as a separator."
  fi

  : ${sms_delivery:=aws}

  pmaker_bin=$pmaker_home/bin
  pmaker_lib=$pmaker_home/lib
  pmaker_log=$pmaker_home/log

  mkdir -p $pmaker_log

  # prerequisities verification
  IFS=,
  for prereq in ${prereq[$command]} ${prereq[$command $what]}; do
    echo testing $prereq...
    if [ -z ${executed[$prereq]} ] || [ ${executed[$prereq]} == FAILED ]; then
      echo "Can't run this command before: ${prereq[$command]}"
      return 100
    fi
  done

  # not all functions use pmaker_hoem, so It's mandatory to set current dir
  cd $pmaker_home

  known_envs=$(cat $pmaker_home/data/$user_group.users.yaml |  y2j |  jq -r '[.users[].server_groups[]] | unique | .[]')

  # execute command
  result=0
  case $command in
  exit_on_error)
    echo "Error. Critical error occured. Cannot continue. "
    result=90
    ;;
  import)
    command="$command $what"
    case $what in
    excel)
      $pmaker_bin/users2pmaker.sh $pmaker_home/data/$user_group.users.xlsm "$user_filter" >$pmaker_home/data/$user_group.users.yaml || result=$?
      ;;
    *)
      echo "Error. Unknown object for import."
      result=1
      ;;
    esac

    known_envs=$(cat $pmaker_home/data/$user_group.users.yaml |  y2j |  jq -r '[.users[].server_groups[]] | unique | .[]')

    ;;
  deploy)

    if [ -z "$envs" ] || [ "$envs" = all ]; then
      $pmaker_bin/envs_update.sh $user_group | tee -a $pmaker_log/envs_update-$user_group-ALL-$(date -I).log
      result=${PIPESTATUS[0]}
    else
      result=0
      for env in $envs; do
        $pmaker_bin/envs_update.sh $user_group $env | tee -a $pmaker_log/envs_update-$user_group-$env-$(date -I).log
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
          result=1
        fi
      done
    fi
    ;;

  rebuild)
    command="$command $what"
    case $what in
    users)

      if [ -z "$envs" ] || [ "$envs" = all ]; then
        #envs=$(find $pmaker_home/state/$user_group -maxdepth 1 -type d | egrep -v 'all|functional' | sed "s|$pmaker_home/state/$user_group/||g" | grep -v '^$')
        envs=$known_envs
      fi

      result=0
      for this_env in $envs; do
        ansible-playbook $pmaker_lib/env_users.yaml -e user_group=$user_group -e server_group=$this_env -l localhost || result=$?
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
    command="$command $what"

    source $pmaker_bin/deliver_welcome_msg.sh
    source $pmaker_bin/generate_welcome_msg.sh

    if [ -z "$envs" ] || [ "$envs" = all ]; then
      #
      # all environments
      #
      #process_envs=$(cat $pmaker_home/data/$user_group.inventory.cfg | grep '^\[' | grep '\]$' | egrep -v 'controller|jumps' | tr -d '][')
      process_envs=$known_envs
    else
      #
      # selected environments
      #
      process_envs="$envs"
    fi

    case $what in
    generate)
      #
      # generate
      #
      result=0
      for env in $process_envs; do
        # generate e-mail and sms
        generateAllMessages $user_group $env || result=$?
      done
      ;;

    validate)
      result=0
      for env in $process_envs; do
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
        for env in $process_envs; do
          # deliver emails and sms
          welcome_email $user_group $env all deliver || result=$?
          welcome_sms $user_group $env all deliver $sms_delivery || result=$?
          welcome_password_sms $user_group $env all deliver $sms_delivery || result=$?
        done
      fi
      ;;

    redeliver)
      result=0
      for env in $process_envs; do
        # clear sent flag
        clear_welcome_email $user_group $env $user_filter || result=$?
        clear_welcome_sms $user_group $env $user_filter || result=$?
        clear_welcome_password_sms $user_group $env $user_filter || result=$?

        # regenerate mesages
        generateUserMessages $user_group $env $user_filter || result=$?

        # deliver emails and sms
        welcome_email $user_group $env $user_filter deliver || result=$?
        welcome_sms $user_group $env $user_filter deliver $sms_delivery || result=$?
        welcome_password_sms $user_group $env $user_filter deliver $sms_delivery || result=$?
      done

      ;;


      *)
      echo "Error. Unknown action for welcome."
      result=1
      ;;
    esac
    ;;

  *)
    echo "unknown comnand."
    ;;
  esac

  # store executon result
  if [ $result -eq 0 ]; then
    executed["$command"]=YES
    echo Done.
  else
    executed["$command"]=FAILED
    echo Failed.
  fi

  cd - >/dev/null
  return $result

}
