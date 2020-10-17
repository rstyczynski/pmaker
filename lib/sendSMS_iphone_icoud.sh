
#
# Send SMS over iMessages / iCloud / iPhone infrastructure
# 
# Configure:
# 1. setup iCloud for iMessages on your Mac
# 2. enable iCloud for iMessages on your iPhone
# 3. enable SMS Forwarding to/form your Mac. Info: https://support.apple.com/en-nz/HT208386
# 4. run sendSMS function from Mac
# 
# Note that function sends message always twice; first message is used to open chat channel; second to send SMS.
# First one may be delivered by iMessgvae if buddy has iMessages configured for mobile numnber used to send SMS.

function sendSMS {
    mobile_no=$1
    sms_text=$2
    skip_chat=$3

    cat >/tmp/openChat.scpt  <<EOF
on run {targetBuddyPhone, targetMessage}
    activate application "Messages"
    tell application "System Events" to tell process "Messages"
        key code 45 using command down
        keystroke targetBuddyPhone
        key code 36
        keystroke targetMessage
        key code 36
    end tell
end run
EOF

    cat >/tmp/sendSMS.scpt <<EOF
on run {targetBuddyPhone, targetMessage}
    tell application "Messages"
        send targetMessage to buddy targetBuddyPhone of service "SMS"
    end tell
end run
EOF

    if [ "$skip_chat" != "chat_ready" ]; then 
        echo "Open chat to $mobile_no..."
        osascript /tmp/openChat.scpt "$mobile_no" "$sms_text"
    fi

    echo "Send to $mobile_no SMS $sms_text"
    osascript /tmp/sendSMS.scpt "$mobile_no" "$sms_text"

    rm -f /tmp/openChat.scpt
    rm -f /tmp/sendSMS.scpt
}

function sendSMSes {

    rm -rf /tmp/sendSMSes
    mkfifo /tmp/sendSMSes

    while [ 1 ]; do
        while IFS= read -r line
        do
            mobile_no=$(echo $line | cut -d';' -f1 )
            sms_text=$(echo $line | cut -d';' -f2-999)

            sendSMS "$mobile_no" "$sms_text" >> sms_report.log
            sleep 5

        done  < /tmp/sendSMSes
    done
}

