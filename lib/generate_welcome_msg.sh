#!/bin/bash

alias j2y="ruby -ryaml -rjson -e 'puts YAML.dump(JSON.parse(STDIN.read))'"
alias y2j="ruby -ryaml -rjson -e 'puts JSON.dump(YAML.load(STDIN.read))'"

function getField() {
	local user_group=$1
	local server_group=$2
	local username=$3
	local attr=$4

	users_def=state/$user_group/$server_group/users.yaml
	cat $users_def | y2j | jq -r ".users[] | select(.username == \"$username\") | .$attr"
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

	export full_name=$(getField $user_group $server_group $username full_name)
	export password_access=$(getField $user_group $server_group $username password)
	export key_access=$(getField $user_group $server_group $username key)
	export mobile_number=$(getField $user_group $server_group $username mobile)
	export email=$(getField $user_group $server_group $username email)

	export key_ssh_enc=$(cat state/$user_group/$server_group/$username/.ssh/id_rsa.enc)
	export key_ppk_enc=$(cat state/$user_group/$server_group/$username/.ssh/id_rsa.ppk)

	#export jump_server=$(ansible-inventory -i data/$user_group.inventory.cfg  -y --list | y2j | jq -r  ".all.children.$server_group.hosts[] | select(.host_type==\"jump\") | .public_ip")
	# Bug in ansible - not able to specify the same host in two groups
	# as workaround added jumps server group:
	# [jumps]
	# tst_jump ansible_user=pmaker public_ip=130.61.91.110 host_type=jump
	# dev_jump ansible_user=pmaker public_ip=130.61.91.110 host_type=jump

	server_group_real=$server_group\_jump
	export jump_server=$(ansible-inventory -i data/$user_group.inventory.cfg  -y --list | y2j | jq -r  ".all.children.jumps.hosts[\"$server_group_real\"].public_ip")
	
	
	export first_host=$(cat data/$user_group.inventory.cfg | grep -A1 "\[$server_group\]" | tail -1 | cut -f1 -d' ')

	export date=$(date +"%F %T")

	if [ -z "$admin" ]; then
		export admin="Linux account management."
	fi

}

function generateWelcomeEmailBody() {
	local user_group=$1
	local server_group=$2
	local username=$3
	local mail_template=$4

	: ${mail_template:=welcome_email-body}

	cp state/$user_group/$server_group/$username/.ssh/id_rsa.enc state/$user_group/$server_group/$username/outbox/id_rsa_$server_group.enc
	cp state/$user_group/$server_group/$username/.ssh/id_rsa.ppk state/$user_group/$server_group/$username/outbox/id_rsa_$server_group.ppk

	mkdir -p tmp
	cat templates/$mail_template.j2 |
		insertFile 'key_ssh_enc' 'key_ssh_enc_stop' state/$user_group/$server_group/$username/.ssh/id_rsa.enc |
		insertFile 'key_ppk_enc' 'key_ppk_enc_stop' state/$user_group/$server_group/$username/.ssh/id_rsa.ppk >tmp/$mail_template.j2
	j2 tmp/$mail_template.j2
	rm -f tmp/$mail_template.j2
}

function generateWelcomeEmailHeader() {
	j2 templates/welcome_email-header.j2
}

function generatePasswordSMS() {
	local user_group=$1
	local server_group=$2
	local username=$3

	export password_account=$(cat state/$user_group/$server_group/$username/.ssh/secret.txt)
	j2 templates/welcome_password_account.j2
}

function generateKeySMS() {
	local user_group=$1
	local server_group=$2
	local username=$3

	export password_key=$(cat state/$user_group/$server_group/$username/.ssh/secret.key)
	j2 templates/welcome_password_key.j2
}

function generateUserMessages() {
	local user_group=$1
	local server_group=$2
	local username=$3
	local mail_template=$4

	: ${mail_template:=welcome_email-body}

	mkdir -p state/$user_group/$server_group/$username/outbox

	echo Getting data...
	getUserData $user_group $server_group $username

	echo Generating messages...
	echo -n "\- welcome mail..."
	generateWelcomeEmailBody $user_group $server_group $username $mail_template >state/$user_group/$server_group/$username/outbox/welcome_mail-body.txt
	generateWelcomeEmailHeader >state/$user_group/$server_group/$username/outbox/welcome_mail-header.txt
	echo OK

	echo -n "\- access password..."
	if [ "$password_access" == true ]; then
		generatePasswordSMS $user_group $server_group $username >state/$user_group/$server_group/$username/outbox/pass_sms.txt
		echo OK
	else
		rm -f state/$user_group/$server_group/$username/outbox/pass_sms.txt
		echo Skipped
	fi

	echo -n "\- key password..."
	if [ "$key_access" == true ]; then
		generateKeySMS $user_group $server_group $username >state/$user_group/$server_group/$username/outbox/key_sms.txt
		echo OK
	else
		rm -f state/$user_group/$server_group/$username/outbox/key_sms.txt
		echo Skipped
	fi
}

function getAllUsers() {
	local user_group=$1
	local server_group=$2

	users_def=$pmaker_home/state/$user_group/$server_group/users.yaml
	cat $users_def | y2j | jq -r '.users[].username'
}

function generateEnvMessages() {
	local user_group=$1
	local server_group=$2

	echo "======================================================"
	echo "= Generating messages for $user_group at $server_group"
	echo "======================================================"

	users=$(getAllUsers $user_group $server_group)

	for username in $users; do
		echo Processing user $username...
		generateUserMessages $user_group $server_group $username
		if [ $? -ne 0 ]; then
			return 1
		fi
	done

	echo All done. Use getWelcomeEmail, getPasswordSMS, getKeySMS to get messages.
}

function generateAllMessages() {
	local user_group=$1
	local server_group=$2

	if [ "$server_group" == all ]; then

		server_groups=$(cat data/$user_group.inventory.cfg | grep '\[' | cut -f2 -d'[' | cut -f1 -d']' | grep -v jumps | grep -v controller)
		for server_group in $server_groups; do
			generateEnvMessages $user_group $server_group
			if [ $? -ne 0 ]; then
				echo "Error at $server_group"
				read -p 'Press enter.'
				return 1
			fi
		done
	else
		generateEnvMessages $user_group $server_group
		if [ $? -ne 0 ]; then
			echo "Error at $server_group"
			read -p 'Press enter.'
			return 1
		fi
	fi

	echo All done. Use getWelcomeEmail, getPasswordSMS, getKeySMS to get messages.
}




function getWelcomeEmail() {
	local user_group=$1
	local server_group=$2
	local username=$3
	local header=$4

	if [ ! -f state/$user_group/$server_group/$username/outbox/welcome_mail-body.txt ]; then
		return 1
	fi

	if [ "$header" == "header" ]; then
		cat state/$user_group/$server_group/$username/outbox/welcome_mail-header.txt
		echo '---'
	fi
	cat state/$user_group/$server_group/$username/outbox/welcome_mail-body.txt
}

function getPasswordSMS() {
	local user_group=$1
	local server_group=$2
	local username=$3

	if [ ! -f state/$user_group/$server_group/$username/outbox/pass_sms.txt ]; then
		return 1
	fi

	cat state/$user_group/$server_group/$username/outbox/pass_sms.txt
}

function getKeySMS() {
	local user_group=$1
	local server_group=$2
	local username=$3

	if [ ! -f state/$user_group/$server_group/$username/outbox/key_sms.txt ]; then
		return 1
	fi

	cat state/$user_group/$server_group/$username/outbox/key_sms.txt
}
