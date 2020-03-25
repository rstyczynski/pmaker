#!/bin/bash

alias j2y="ruby -ryaml -rjson -e 'puts YAML.dump(JSON.parse(STDIN.read))'"
alias y2j="ruby -ryaml -rjson -e 'puts JSON.dump(YAML.load(STDIN.read))'"

function getField() {
	local uname=$1
	local attr=$2
	cat $users_def | y2j | jq -r ".users[] | select(.username == \"$uname\") | .$attr"
}

function insertFile() {
	local BLOCK_StartRegexp="${1}"
	local BLOCK_EndRegexp="${2}"
	local FILE="${3}"
	sed -e "/${BLOCK_EndRegexp}/a ___tmpMark___" -e "/${BLOCK_StartRegexp}/,/${BLOCK_EndRegexp}/d" | sed -e "/___tmpMark___/r ${FILE}" -e '/___tmpMark___/d'
}
# Source: https://unix.stackexchange.com/questions/141387/sed-replace-string-with-file-contents

function getUserData() {

	export user_group=$1
	export server_group=$2
	export username=$3

	export users_def=state/$user_group/$server_group/users.yaml
	export full_name=$(getField $username username)
	export password_access=$(getField $username password)
	export key_access=$(getField $username key)
	export mobile_number=$(getField $username mobile_number)
	export email=$(getField $username email)

	export key_ssh_enc=$(cat state/$user_group/$server_group/$username/.ssh/id_rsa.enc)
	export key_ppk_enc=$(cat state/$user_group/$server_group/$username/.ssh/id_rsa.ppk)

	export jump_server=$(cat data/$user_group.inventory.cfg | grep -A1 $server_group\_jump | grep ansible_user | cut -f1 -d' ')
	export date=$(date +"%F %T")

	if [ -z "$admin" ]; then
		export admin="Linux account management."
	fi

}

function generateWelcomeEmail() {
	mkdir -p tmp
	cat templates/welcome_email.j2 |
		insertFile 'key_ssh_enc' 'key_ssh_enc_stop' state/$user_group/$server_group/$username/.ssh/id_rsa.enc |
		insertFile 'key_ppk_enc' 'key_ppk_enc_stop' state/$user_group/$server_group/$username/.ssh/id_rsa.enc >tmp/welcome_email.j2
	j2 tmp/welcome_email.j2
}

function generatePasswordSMS() {
	export password_account=$(cat state/$user_group/$server_group/$username/.ssh/secret.txt)
	j2 templates/welcome_password_account.j2
}

function generateKeySMS() {
	export password_key=$(cat state/$user_group/$server_group/$username/.ssh/secret.key)
	j2 templates/welcome_password_key.j2
}

function generateUserMessages() {
	local user_group=$1
	local server_group=$2
	local user_id=$1

	mkdir -p state/$user_group/$server_group/$username/outbox
	getUserData $user_id
	generateWelcomeEmail >state/$user_group/$server_group/$username/outbox/welcome_mail.txt
	generatePasswordSMS >state/$user_group/$server_group/$username/outbox/pass_sms.txt
	ggenerateKeySMS >state/$user_group/$server_group/$username/outbox/key_sms.txt

}

function generateAllMessages() {
	local user_group=$1
	local server_group=$2

	users_def=$pmaker_home/state/$user_group/$server_group/users.yaml
	users=$(cat $users_def | y2j | jq -r '.users[].username')

	for user_id in $users; do
		generateUserMessages $user_group $server_group $user_id
	done
}

function getWelcomeEmail() {
	cat state/$user_group/$server_group/$username/outbox/welcome_mail.txt
}

function getPasswordSMS() {
	cat state/$user_group/$server_group/$username/outbox/pass_sms.txt
}

function getKeySMS() {
	cat state/$user_group/$server_group/$username/outbox/key_sms.txt
}