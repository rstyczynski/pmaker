#!/bin/bash

#
# resend
#

function resend_credentials() {
    channel=$1
    user_group=$2
    server_env=$3
    username=$4
    #
    source ~/.umc/smtp.cfg

    case $channel in
    email)
        generateUserMessages $user_group $server_env $username
        clear_welcome_email $user_group $server_env $username
        welcome_email $user_group $server_env $username deliver
        ;;
    sms)
        clear_welcome_sms $user_group $server_env $username
        welcome_sms $user_group $server_env $username deliver aws
        ;;
    both)
        generateUserMessages $user_group $server_env $username
        clear_welcome_email $user_group $server_env $username
        welcome_email $user_group $server_env $username deliver
        clear_welcome_sms $user_group $server_env $username
        welcome_sms $user_group $server_env $username deliver aws
        ;;
    esac
}

#
# send email
#
function welcome_email() {
    user_group=$1
    server_groups=$2
    usernames=$3
    deliver=$4

    if [ ! -d state ]; then
        echo "Error. Email delivery must be started from pmaker home."
        return 1
    fi

    : ${usernames:=all}

    if [ "$server_groups" == all ]; then
        server_groups=$(cat data/$user_group.inventory.cfg | grep '\[' | cut -f2 -d'[' | cut -f1 -d']' | grep -v jumps | grep -v controller)
    fi

    for server_group in $server_groups; do

        if [ "$usernames" == all ]; then
            usernames=$(cat state/$user_group/$server_group/users.yaml | y2j | jq -r '.users[].username')
        fi

        for username in $usernames; do

            echo -n ">>> $server_group $username: "

            if [ ! -f state/$user_group/$server_group/$username/welcome.sent ]; then
                if [ "$deliver" == 'deliver' ]; then
                    echo -n " mail delivery...."

                    ready=$(getWelcomeEmail $user_group $server_group $username)

                    if [ -z "$ready" ]; then
                        echo "Skipping. e-mail not yet prepared."
                    else

                        TO_EMAIL_ADDRESS=$(getWelcomeEmail $user_group $server_group $username header | head -5 | grep 'TO:' | cut -d' ' -f2-999)
                        EMAIL_SUBJECT=$(getWelcomeEmail $user_group $server_group $username header | head -5 | grep 'SUBJECT:' | cut -d' ' -f2-999)

                        if [ ! -z "$TO_EMAIL_ADDRESS" ]; then
                            getWelcomeEmail $user_group $server_group $username |
                                timeout 30 mailx -v -s "$EMAIL_SUBJECT" \
                                    -S nss-config-dir=/etc/pki/nssdb/ \
                                    -S smtp-use-starttls \
                                    -S ssl-verify=ignore \
                                    -S smtp=smtp://$SMTP_ADDRESS:$SMTP_PORT \
                                    -S from=$FROM_EMAIL_ADDRESS \
                                    -S smtp-auth-user=$ACCOUNT_USER \
                                    -S smtp-auth-password=$ACCOUNT_PASSWORD \
                                    -S smtp-auth=plain \
                                    -a state/$user_group/$server_group/$username/outbox/id_rsa_$server_group.enc \
                                    -a state/$user_group/$server_group/$username/outbox/id_rsa_$server_group.ppk \
                                    $TO_EMAIL_ADDRESS 2>/tmp/email.$$.tmp

                            if [ $? -eq 0 ]; then
                                echo "Done."
                                cat /tmp/email.$$.tmp >state/$user_group/$server_group/$username/welcome.sent
                            else
                                echo "Error sending email. Code: $?. Connect log: "
                                cat /tmp/email.$$.tmp
                                read -p "press any key"
                            fi
                            rm /tmp/email.$$.tmp
                        else
                            echo Welcome mail not ready.
                        fi
                    fi
                else
                    echo
                    echo "============ mail verification ================="
                    getWelcomeEmail $user_group $server_group $username header
                    read -p "press any key"
                fi
            else
                echo "Email already sent at $(ls -l state/$user_group/$server_group/$username/welcome.sent | cut -d' ' -f6-8)"
            fi
        done
    done

}

#
# send key SMS
#

function welcome_sms() {
    user_group=$1
    server_groups=$2
    usernames=$3
    deliver=$4
    channel=$5

    : ${usernames:=all}

    if [ -z "user_group" ]; then
        echo "Error. Usage: welcome_sms user_group server_groups usernames [deliver]"
        return 1
    fi

    if [ ! -d state ]; then
        echo "Error. SMS delivery must be started from pmaker home."
        return 1
    fi

    rm -rf state/$user_group/smskey_batch.csv
    rm -rf state/$user_group/smskey_batch.sh

    if [ "$server_groups" == all ]; then
        server_groups=$(cat data/$user_group.inventory.cfg | grep '\[' | cut -f2 -d'[' | cut -f1 -d']' | grep -v jumps | grep -v controller)
    fi

    for server_group in $server_groups; do

        if [ "$usernames" == all ]; then
            usernames=$(cat state/$user_group/$server_group/users.yaml | y2j | jq -r '.users[].username')
        fi

        for username in $usernames; do

            mobile=$(cat data/$user_group.users.yaml | y2j | jq -r ".users[] | select(.username==\"$username\") | .mobile")
            if [ ! -z "$mobile" ]; then
                echo -n ">>> $server_group $username: "
                if [ ! -f state/$user_group/$server_group/$username/sms.sent ]; then
                    if [ "$deliver" == 'deliver' ]; then
                        echo -n " sms delivery...."
                        sms_message=$(getKeySMS $user_group $server_group $username)

                        if [ -z "$sms_message" ]; then
                            echo "Skipping. sms not yet prepared."
                        else
                            case "$channel" in
                            aws)
                                aws sns publish --message "$sms_message" --phone-number "$mobile" | tee state/$user_group/$server_group/$username/sms.sent
                                ;;
                            csv)
                                echo "$mobile;$sms_message" | tee state/$user_group/$server_group/$username/sms.sent | tee -a state/$user_group/smskey_batch.csv
                                ;;
                            script)
                                echo "sendSMS \"$mobile\" \"$sms_message\"; sleep 5" | tee state/$user_group/$server_group/$username/sms.sent | tee -a state/$user_group/smskey_batch.sh
                                ;;
                            *)
                                echo "Not supported: $channel"
                                ;;
                            esac
                        fi
                    else
                        echo
                        echo "============ sms verification ================="
                        sms_message=$(getKeySMS $user_group $server_group $username header)
                        if [ -z "$sms_message" ]; then
                            echo "Skipping. sms not yet prepared."
                        else
                            echo $sms_message
                            read -p "press any key"
                        fi
                    fi
                else
                    echo "SMS already sent at $(ls -l state/$user_group/$server_group/$username/sms.sent | cut -d' ' -f6-8)"
                fi
            else
                echo User has no mobile number.
            fi
        done
    done

    if [ -f state/$user_group/smskey_batch.csv ]; then
        echo "SMS batch to send:"
        cat state/$user_group/smskey_batch.csv
    fi

    if [ -f state/$user_group/smskey_batch.sh ]; then
        echo "SMS script to send:"
        cat state/$user_group/smskey_batch.sh
    fi
}

#
# send key SMS
#

function welcome_password_sms() {
    user_group=$1
    server_groups=$2
    usernames=$3
    deliver=$4

    : ${usernames:=all}

    if [ -z "user_group" ]; then
        echo "Error. Usage: welcome_password_sms user_group server_groups usernames [deliver]"
        return 1
    fi

    if [ ! -d state ]; then
        echo "Error. SMS delivery must be started from pmaker home."
        return 1
    fi

    if [ "$usernames" == all ]; then
        usernames=$(cat data/$user_group.users.yaml | y2j | jq -r '.users[].username')
    fi

    rm -rf state/$user_group/smspass_batch.csv
    rm -rf state/$user_group/smskey_batch.sh

    if [ "$server_groups" == all ]; then
        server_groups=$(cat data/$user_group.inventory.cfg | grep '\[' | cut -f2 -d'[' | cut -f1 -d']' | grep -v jumps | grep -v controller)
    fi

    for server_group in $server_groups; do

        if [ "$usernames" == all ]; then
            usernames=$(cat state/$user_group/$server_group/users.yaml | y2j | jq -r '.users[].username')
        fi

        for username in $usernames; do

            mobile=$(cat data/$user_group.users.yaml | y2j | jq -r ".users[] | select(.username==\"$username\") | .mobile")
            if [ ! -z "$mobile" ]; then

                echo -n ">>> $server_group $username: "

                if [ ! -f state/$user_group/$server_group/$username/password_sms.sent ]; then
                    if [ "$deliver" == 'deliver' ]; then
                        echo -n " sms delivery...."
                        sms_message=$(getPasswordSMS $user_group $server_group $username)

                        if [ -z "$sms_message" ]; then
                            echo "Skipping. sms not yet prepared."
                        else
                            case "$channel" in
                            aws)
                                aws sns publish --message "$sms_message" --phone-number "$mobile" | tee state/$user_group/$server_group/$username/password_sms.sent
                                ;;
                            csv)
                                echo "$mobile;$sms_message" | tee state/$user_group/$server_group/$username/sms.sent | tee -a state/$user_group/smspass_batch.csv
                                ;;
                            script)
                                echo "sendSMS \"$mobile\" \"$sms_message\"; sleep 5" | tee state/$user_group/$server_group/$username/sms.sent | tee -a state/$user_group/smskey_batch.sh
                                ;;
                            *)
                                echo "Not supported: $channel"
                                ;;
                            esac
                        fi

                    else
                        echo
                        echo "============ sms verification ================="
                        sms_message=$(getPasswordSMS $user_group $server_group $username header)
                        if [ -z "$sms_message" ]; then
                            echo "Skipping. sms not yet prepared."
                        else
                            echo $sms_message
                            read -p "press any key"
                        fi
                    fi
                else
                    echo "Password SMS already sent at $(ls -l state/$user_group/$server_group/$username/password_sms.sent | cut -d' ' -f6-8)"
                fi
            else
                echo User has no mobile number.
            fi
        done
    done

    if [ -f state/$user_group/smspass_batch.csv ]; then
        echo "SMS batch to send:"
        cat state/$user_group/smspass_batch.csv
    fi

    if [ -f state/$user_group/smskey_batch.sh ]; then
        echo "SMS script to send:"
        cat state/$user_group/smskey_batch.sh
    fi
}

#
# clear email delivery status. all messages will be redelivered
#
function clear_welcome_email() {
    user_group=$1
    server_groups=$2
    usernames=$3

    if [ ! -d state ]; then
        echo "Error. SMS delivery must be started from pmaker home."
        return 1
    fi

    : ${usernames:=all}

    if [ "$server_groups" == all ]; then
        server_groups=$(cat data/$user_group.inventory.cfg | grep '\[' | cut -f2 -d'[' | cut -f1 -d']' | grep -v jumps | grep -v controller)
    fi

    for server_group in $server_groups; do

        if [ "$usernames" == all ]; then
            usernames=$(cat state/$user_group/$server_group/users.yaml | y2j | jq -r '.users[].username')
        fi

        for username in $usernames; do
            echo -n ">>> $server_group $username: "
            if [ -f state/$user_group/$server_group/$username/welcome.sent ]; then
                mv state/$user_group/$server_group/$username/welcome.sent state/$user_group/$server_group/$username/welcome.sent.$(date_now=$(date -u +"%Y%m%dT%H%M%S"))
                echo "sent status removed."
            fi
        done
    done

}

#
# clear SMS delivery status. all messages will be redelivered
#
function clear_welcome_sms() {
    user_group=$1
    server_groups=$2
    usernames=$3

    if [ ! -d state ]; then
        echo "Error. SMS delivery must be started from pmaker home."
        return 1
    fi

    : ${usernames:=all}

    if [ "$server_groups" == all ]; then
        server_groups=$(cat data/$user_group.inventory.cfg | grep '\[' | cut -f2 -d'[' | cut -f1 -d']' | grep -v jumps | grep -v controller)
    fi

    for server_group in $server_groups; do

        if [ "$usernames" == all ]; then
            usernames=$(cat state/$user_group/$server_group/users.yaml | y2j | jq -r '.users[].username')
        fi

        for username in $usernames; do
            echo -n ">>> $server_group $username: "
            if [ -f state/$user_group/$server_group/$username/sms.sent ]; then
                mv state/$user_group/$server_group/$username/sms.sent state/$user_group/$server_group/$username/sms.sent.$(date_now=$(date -u +"%Y%m%dT%H%M%S"))
                echo "sent status removed."
            fi
        done
    done

}

#
# clear SMS delivery status. all messages will be redelivered
#
function clear_welcome_password_sms() {
    user_group=$1
    server_groups=$2
    usernames=$3

    if [ ! -d state ]; then
        echo "Error. SMS delivery must be started from pmaker home."
        return 1
    fi

    : ${usernames:=all}

    if [ "$server_groups" == all ]; then
        server_groups=$(cat data/$user_group.inventory.cfg | grep '\[' | cut -f2 -d'[' | cut -f1 -d']' | grep -v jumps | grep -v controller)
    fi

    for server_group in $server_groups; do

        if [ "$usernames" == all ]; then
            usernames=$(cat state/$user_group/$server_group/users.yaml | y2j | jq -r '.users[].username')
        fi

        for username in $usernames; do
            echo -n ">>> $server_group $username: "
            if [ -f state/$user_group/$server_group/$username/password_sms.sent ]; then
                mv state/$user_group/$server_group/$username/password_sms.sent state/$user_group/$server_group/$username/password_sms.sent.$(date_now=$(date -u +"%Y%m%dT%H%M%S"))
                echo "sent status removed."
            fi
        done
    done

}
