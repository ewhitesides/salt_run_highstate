#!/bin/bash

#Summary
#outputs to log how many times a minion has received a highstate run in last 24 hrs

#Example call
#./get_highstate_status.sh

#imports
current_dir="$(dirname "$0")"
source "$current_dir/functions.sh"

#functions
log_msg () {
    ts=$(date "+%Y-%m-%dT%H:%M:%S%z")
    message_format='Time="%s", NodeGroup="%s", Minion="%s", Qty_Highstate_Runs="%s", Level="%s"\n'
    printf "$message_format" "$ts" "$2" "$3" "$4" "$5" | tee -a "$1"
}

get_highstate_json_data () {
    #get highstate data from cache (default cache is last 24 hrs, but we add start time to ensure)
    yesterday=$(date -d 'yesterday' +"%Y, %b %d %H:%M")
    salt-run jobs.list_jobs search_function='state.highstate' start_time="$yesterday" --out=json
}

get_nodegroups () {
    #summary
    #get nodegroup count, subtract the excluded
    excluded="$1"
    salt-run config.get nodegroups --out=json |
        jq --raw-output --argjson x "$excluded" 'keys - $x | .[]'
}

get_minions () {
    #summary
    #get minions that are pingable, not in excluded list
    #this function contrasts with get_minions_list in run_highstate
    #in run_highstate, we get pingable and not busy minions
    #in this function, we get just pingable minions
    #we want to catch situations where a minion never
    #gets a highstate run because the minion is perpetually busy
    nodegroup="$1"
    excluded="$2"
    salt -C "$nodegroup" test.ping --hide-timeout --out=json |
        jq --raw-output --argjson x "$excluded" 'keys - $x | .[]'
}

#logfile
logfile=$(init_log 'highstate_status')

#get highstate json data
highstate_json_data=$(get_highstate_json_data)

#get excluded
excluded_nodegroups=$(get_excluded_nodegroups)
excluded_minions=$(get_excluded_minions)

#loop through nodegroups
readarray -t nodegroups < <(get_nodegroups "$excluded_nodegroups")
for nodegroup in "${nodegroups[@]}"; do

    #loop through minions
    readarray -t minions < <(get_minions "N@$nodegroup" "$excluded_minions")

    for minion in "${minions[@]}"; do

        #count how many occurrences
        count=$(echo "$highstate_json_data" | jq '.' | grep -c "$minion")

        #level
        if [ $count -eq 0 ]; then
            level='ERROR'
        else
            level='INFO'
        fi

        #output to log
        log_msg "$logfile" "$nodegroup" "$minion" "$count" "$level"

    done

done
