#!/bin/bash

#
# send email
#
function welcome_email() {
    user_group=$1
    envs=$2
    deliver=$3

    if [ ! -d state ]; then
        echo "Error. Email delivery must be started from pmaker home."
        return 1
    fi

    for user in $(cat data/$user_group.users.yaml | y2j | jq -r '.users[].username'); do
        for env in $envs; do
            echo -n ">>> $env $user: "
            if [ ! -f state/$user_group/$env/$user/welcome.sent ]; then            
                if [ "$deliver" == 'deliver' ]; then
                    echo -n " mail delivery...."
                    TO_EMAIL_ADDRESS=$(getWelcomeEmail $user_group $env $user header | head -5 | grep 'TO:' | cut -d' ' -f2-999)
                    EMAIL_SUBJECT=$(getWelcomeEmail $user_group $env $user header | head -5 | grep 'SUBJECT:' | cut -d' ' -f2-999)

                    getWelcomeEmail $user_group $env $user | 
                    mailx -v -s "$EMAIL_SUBJECT" \
                    -S nss-config-dir=/etc/pki/nssdb/ \
                    -S smtp-use-starttls \
                    -S ssl-verify=ignore \
                    -S smtp=smtp://$SMTP_ADDRESS:$SMTP_PORT \
                    -S from=$FROM_EMAIL_ADDRESS \
                    -S smtp-auth-user=$ACCOUNT_USER \
                    -S smtp-auth-password=$ACCOUNT_PASSWORD \
                    -S smtp-auth=plain \
                    -a /etc/passwd \
                    $TO_EMAIL_ADDRESS

                    if [ $? -eq 0 ]; then
                        echo "Done."
                        touch state/$user_group/$env/$user/welcome.sent
                    else
                        echo "Error code:$?."
                    fi
                else
                    echo 
                    echo "============ mail verification ================="
                    getWelcomeEmail $user_group $env $user header
                    read -p "press any key"
                fi
                
            else
                echo "Email already sent at $(ls -l state/$user_group/$env/$user/welcome.sent | cut -d' ' -f6-8)"
            fi
        done
    done

}

#
# send SMS
#

function welcome_sms() {
    user_group=$1
    envs=$2

    if [ ! -d state ]; then
        echo "Error. SMS delivery must be started from pmaker home."
        return 1
    fi

    for user in $(cat data/$user_group.users.yaml | y2j | jq -r '.users[].username'); do
        mobile=$(cat data/$user_group.users.yaml | y2j | jq -r ".users[] | select(.username==\"$user\") | .mobile")

        for env in $envs; do
            echo -n ">>> $env $user: "
            if [ ! -f state/$user_group/$env/$user/sms.sent ]; then

                sms_message=$(getKeySMS $user_group $env $user)
                aws sns publish --message "$sms_message" --phone-number "$mobile" | tee state/$user_group/$env/$user/sms.sent
            else
                echo "SMS already sent at $(ls -l state/$user_group/$env/$user/welcome.sent | cut -d' ' -f6-8)"
            fi
        done
    done
}

#
# clear email delivery status. all messages will be redelivered
#
function clear_welcome_email() {
    user_group=$1
    envs=$2

    if [ ! -d state ]; then
        echo "Error. Clear email delivery must be started from pmaker home."
        return 1
    fi

    for user in $(cat data/$user_group.users.yaml | y2j | jq -r '.users[].username'); do
        mobile=$(cat data/$user_group.users.yaml | y2j | jq -r ".users[] | select(.username==\"$user\") | .mobile")

        for env in $envs; do
            echo -n ">>> $env $user: "
            if [ -f state/$user_group/$env/$user/welcome.sent ]; then
                mv state/$user_group/$env/$user/welcome.sent state/$user_group/$env/$user/welcome.sent.$(date_now=$(date -u +"%Y%m%dT%H%M%S"))
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
    envs=$2

    if [ ! -d state ]; then
        echo "Error. Clear SMS delivery must be started from pmaker home."
        return 1
    fi

    for user in $(cat data/$user_group.users.yaml | y2j | jq -r '.users[].username'); do
        mobile=$(cat data/$user_group.users.yaml | y2j | jq -r ".users[] | select(.username==\"$user\") | .mobile")

        for env in $envs; do
            echo -n ">>> $env $user: "
            if [ -f state/$user_group/$env/$user/sms.sent ]; then
                mv state/$user_group/$env/$user/sms.sent state/$user_group/$env/$user/sms.sent.$(date_now=$(date -u +"%Y%m%dT%H%M%S"))
                echo "sent status removed."
            fi
        done
    done

}
