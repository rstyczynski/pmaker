#!/bin/bash

#
# functions
#
function j2y() {
    ruby -ryaml -rjson -e 'puts YAML.dump(JSON.parse(STDIN.read))'
}

function y2j() {
    ruby -ryaml -rjson -e 'puts JSON.dump(YAML.load(STDIN.read))'
}


function users2pmaker {
excel_file=$1
xlsx2csv $excel_file  | csvtojson | jq -c |  
sed 's/,"field[0-9]*":"[a-zA-Z_-]*"//g' |  
sed 's/{"field[0-9]*":"[a-zA-Z_-]*",/{/g'  |  
sed 's/"field[0-9][0-9]*":"[a-zA-Z_-]*",//g' |  
egrep 'username":|email":|}|{|\[|\]|become_|password":|key":|mobile":|full_name":' | 
jq 'del(.[0])' | 
sed 's/"\[/\[/g' |  sed 's/\]"/\]/g' | sed 's|\\"|"|g' | 
egrep -v '"\w+ \w+":' |
sed 's/"TRUE"/true/g' |
sed 's/"FALSE"/false/g' |
j2y | 
sed  '1a\
users:|' | # adds users: as name of data structure
tr '|' '\n'
}

users2pmaker $1

