#!/bin/bash


# Rules
# 1. state change detecton
# - state.modified flag
# - paranoid mode - compare state.modified timestamp with newest file. Must be newer.
# - newest file - to check modification.
# https://stackoverflow.com/questions/4561895/how-to-recursively-find-the-latest-modified-file-in-a-directory
#
# 2. state access processes
# - stop when state push flag is in place
# - requires state pull operation to proceed
#
# 3. state update processes - generate keys, deliver message, deploy, revoke 
# - state push is mandatory after these operations
# - creates modify flag state.modified
# - each time state is modified must be pushed to object storage


#
# functions
#

unset log
function log() {
  echo $@

  if [ "$1" == '-n' ]; then
    echo -n "$(date +%Y-%m-%dT%H:%M:%S)|" >> $pmaker_home/log/${pmaker_org}_state.log
  fi
  echo $@ >> $pmaker_home/log/${pmaker_org}_state.log
}

#
# run
#

unset pmaker_state_push
function pmaker_state_push() {
  pmaker_oc_bucket=$1

  : ${oci_tools:=~/oci-tools}

  preliminary_checks=0
  if [ -z "$pmaker_oc_bucket" ]; then
    echo "Error. OCI Object Storage bucket not configured. Set pmaker_oc_bucket variable."
    preliminary_checks=1
  fi

  if [ -z "$pmaker_home" ]; then
    echo "Error. pmaker_home not set. State cannot be stored."
    preliminary_checks=1
  fi
    
  if [ -z "$pmaker_org" ]; then
    echo "Error. pmaker_org not set. State cannot be stored."
    preliminary_checks=1
  fi
    
  if [ ! -f $oci_tools/bin/secure_object_storage.sh ]; then
    echo "Error. Secure object storage script not found. Set oci_tools variable to oci-tools location."
    preliminary_checks=1
  fi
  source $oci_tools/bin/secure_object_storage.sh

  if [ $preliminary_checks -ne 0 ]; then
    return $preliminary_checks
  fi

  pmaker_tmp=$pmaker_home/tmp/$$
  mkdir -p $pmaker_tmp

  secure_dir=$pmaker_home/state/$pmaker_org
  secure_dir_name=pmaker_state_$pmaker_org

  echo "$(date +%Y-%m-%dT%H:%M:%S)|pmaker state push"  > $secure_dir/state.push.progress

  log -n "Selecting files for upload..."
  current_PWD=$PWD
  cd $secure_dir
  find . -type f | grep -v "^\./state.push.progress$" > $pmaker_tmp/files.storage; result_find=${PIPESTATUS[0]}
  find . -type d | grep -v "^\.$" > $pmaker_tmp/dirs.storage; result_find=$(($result_find + ${PIPESTATUS[0]}))
  cat $pmaker_tmp/dirs.storage $pmaker_tmp/files.storage > $pmaker_tmp/filesdirs.storage
  if [ $result_find -ne 0 ]; then
    result=1
    log "Error. Not able to locate files."
  else
    log OK
    log -n "Creating package..."
    rm -rf $pmaker_tmp/$secure_dir_name.tar.gz
    tar -czf $pmaker_tmp/$secure_dir_name.tar.gz -T $pmaker_tmp/filesdirs.storage
    result_tar=$?
    if [ $result_tar -ne 0 ]; then
      result=1
      log "Error. Tar reported error. Not able to prepare package."
    else
      log "OK. Created: $secure_dir_name.tar.gz"

      log -n "Performing secure upload...."
      cd $pmaker_tmp
      os_response=$(secure_put $pmaker_oc_bucket $secure_dir_name.tar.gz 2>&1)
      result_secureput=$?
      cd - >/dev/null
      if [ $result_secureput -ne 0 ]; then
        result=1
        log "Error. Secure put reported error. Not able to upload secure files."
      else
        log "OK. Uploaded: $secure_dir_name.tar.gz"

        log -n "Removing uploaded files..."
        cd $secure_dir
        xargs rm < $pmaker_tmp/files.storage; cleanup_result=$?
        xargs rm -rf < $pmaker_tmp/dirs.storage; cleanup_result=$(($cleanup_result + $?))
        cd -
        rm -rf $pmaker_tmp; cleanup_result=$(($cleanup_result + $?))
        if [ $cleanup_result -ne 0 ]; then
          log "Warning. Cleaning up reported problems."
        else
          log OK
        fi

        log -n "Leaving upload mark..."
        echo $os_response >> $secure_dir/state.push.progress
        mv $secure_dir/state.push.progress $secure_dir/state.push
        log "OK, id: $os_response"

      fi
    fi
  fi

  cd $current_PWD

  return $result
}


unset pmaker_state_pull
function pmaker_state_pull() {
  pmaker_oc_bucket=$1

  : ${oci_tools:=~/oci-tools}

  preliminary_checks=0
  if [ -z "$pmaker_oc_bucket" ]; then
    echo "Error. OCI Object Storage bucket not configured. Set pmaker_oc_bucket variable."
    preliminary_checks=1
  fi

  if [ -z "$pmaker_home" ]; then
    echo "Error. pmaker_home not set. State cannot be stored."
    preliminary_checks=1
  fi
    
  if [ -z "$pmaker_org" ]; then
    echo "Error. pmaker_org not set. State cannot be stored."
    preliminary_checks=1
  fi
    
  if [ ! -f $oci_tools/bin/secure_object_storage.sh ]; then
    echo "Error. Secure object storage script not found. Set oci_tools variable to oci-tools location."
    preliminary_checks=1
  fi
  source $oci_tools/bin/secure_object_storage.sh

  if [ $preliminary_checks -ne 0 ]; then
    return $preliminary_checks
  fi

  pmaker_tmp=$pmaker_home/tmp/$$
  mkdir -p $pmaker_tmp

  secure_dir=$pmaker_home/state/$pmaker_org
  secure_dir_name=pmaker_state_$pmaker_org

  if [ ! -f $secure_dir/state.push ]; then
    echo "Info. Secured direcotry not uploaded to Object Storage. Nothing to do...."
    return 1
  fi

  echo "$(date +%Y-%m-%dT%H:%M:%S)|pmaker state pull" > $secure_dir/state.pull.progress

  log -n "Checking if push flag is the newest file..."
  # check if newest file in secured direcotry is push flag. This is the only proper situation.
  find $secure_dir -type f -printf '%T@ %p\n' | sort -n | tail -2 | head -1 | cut -f2- -d" " | grep $secure_dir/state.push >/dev/null
  state_push_check=$?
  if [ $state_push_check -ne 0 ]; then
    find $secure_dir -type f -printf '%T@ %p\n' | sort -n | tail -2 | head -1 | cut -f2- -d" " | grep $secure_dir/state.pull >/dev/null
    if [ $? -eq 0 ]; then
      log "Info. State already pulled. Nothing to do."
      return 0
    else
      log "Error. state push flag older than newest file in secure directory. Error code: $state_push_check"
      return 2
    fi
  fi
  log OK

  log -n "Pulling state..."
  current_PWD=$PWD
  cd $secure_dir
  os_response=$(secure_get $pmaker_oc_bucket $secure_dir_name.tar.gz 2>&1)
  result_secureput=$?
  if [ $result_secureput -ne 0 ]; then
    log "Error. Secure get operation failed. Error code: $result_secureput, response: $os_response"
    return 3
  fi
  log OK

  log -n "Putting fles in place..."
  tar -xzf $secure_dir_name.tar.gz
  result_tar=$?
  if [ $result_tar -ne 0 ]; then
    log "Error. Putting files in place failed. Error code: $result_tar"
    return 3
  fi
  log OK
  rm $secure_dir_name.tar.gz

  log -n "Leaving download mark..."
  mv $secure_dir/state.pull.progress $secure_dir/state.pull
  log "OK"

}

pmaker_state_push pmaker
ll

pmaker_state_pull pmaker
ll
