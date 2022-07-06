#!/bin/bash

function install_tools() {
    sudo pip install xlsx2csv
    npm install csvtojson

    # sudo npm install -g csvtojson
    # sudo chown pmaker /usr/lib/node_modules/csvtojson/bin/csvtojson
    # sudo chown pmaker /usr/lib/node_modules/csvtojson/bin/csvtojson
    # sudo rm /usr/bin/csvtojson
    # sudo ln /usr/lib/node_modules/csvtojson/bin/csvtojson /usr/bin/csvtojson
    # sudo chown -R pmaker /usr/lib/node_modules/csvtojson
    # cp /usr/lib/node_modules/csvtojson/bin/csvtojson.js .
}

#
# functions
#
function j2y() {
    #ruby -ryaml -rjson -e 'puts YAML.dump(JSON.parse(STDIN.read))'
    echo '---'
    python -c 'import sys, yaml, json; j=json.loads(sys.stdin.read()); print yaml.safe_dump(j)'
}

function y2j() {
    ruby -ryaml -rjson -e 'puts JSON.dump(YAML.load(STDIN.read))'
}

function users2pmaker() {
    excel_file="$1"
    # usernames separated by space if more than one provided
    usernames="$2"

    tmp=$pmaker_home/tmp; mkdir -p $tmp
    users_file=$(basename $excel_file)

    # user_filter structure:    
    # ^user1,|^user2,|^user3,|^user4,
    unset user_filter
    if [ ! -z "$usernames" ]; then

        for username in $usernames; do
            if [ -z "$user_filter" ]; then
                user_filter="^$username,"
            else
                user_filter="$user_filter|^$username,"
            fi
        done
    fi

    xlsx2csv $excel_file | 
        grep -v '^,,,,,,' | 
        egrep "username,date,team,manager|$user_filter" |
        $pmaker_home/node_modules/csvtojson/bin/csvtojson | 
        jq -M '.' |
        sed 's/,"field[0-9]*":"[a-zA-Z_-]*"//g' |
        sed 's/{"field[0-9]*":"[a-zA-Z_-]*",/{/g' |
        sed 's/"field[0-9][0-9]*":"[a-zA-Z_-]*",//g' |
        egrep '"username":|"user_groups":|"server_groups":|"email":|"password":|"key":|"mobile":|"full_name":|}|{|\[|\]|become_' |
        sed 's/"\[/\[/g' | sed 's/\]"/\]/g' | sed 's|\\"|"|g' |
        egrep -v '"\w+ \w+":' |
        sed 's/"TRUE"/true/g' |
        sed 's/"FALSE"/false/g' |
        j2y |
        sed '1a\
users:|' | # adds users: as name of data structure
        tr '|' '\n'

}

users2pmaker "$1" "$2"
