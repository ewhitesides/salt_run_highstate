#!/bin/bash

#Summary
#run highstate on nodegroups

#Parameter 1
#the salt function to run.
#accepts either "state.highstate" or "test.ping"

#Parameter 2
#the minimum number highstates executions per day on each nodegroup

#Parameter 3
#how many times a day this script is run

#Example call
#./run_highstate.sh "state.highstate" "4" "18"

#imports
current_dir="$(dirname "$0")"
source "$current_dir/functions.sh"

#functions
log_msg () {
    ts=$(date "+%Y-%m-%dT%H:%M:%S%z")
    message_format='Time="%s", Function="%s", NodeGroup="%s", Status="%s", Level="%s"\n'
    printf "$message_format" "$ts" "$2" "$3" "$4" "$5" | tee -a "$1"
}

get_nodegroup_count () {
    #get nodegroup count, subtract the excluded
    excluded="$1"
    readarray -t nodegroups < <(
        salt-run config.get nodegroups --out=json |
            jq --raw-output --sort-keys --argjson x "$excluded" 'keys - $x | .[]'
    )

    #output qty
    echo "${#nodegroups[@]}"
}

get_random_nodegroup () {
    #get nodegroups, subtract the excluded
    excluded="$1"
    readarray -t nodegroups < <(
        salt-run config.get nodegroups --out=json |
            jq --raw-output --sort-keys --argjson x "$excluded" 'keys - $x | .[]'
    )

    #choose a random number within the length of the nodegroups array
    nodegroups_length=$((${#nodegroups[@]}))
    random_num=$(($RANDOM % $nodegroups_length))

    #output the random element of the array
    echo "${nodegroups[$random_num]}"
}

get_minions_list () {
    #get minions that are pingable, not busy with existing job, subtract excluded
    nodegroup="$1"
    excluded="$2"
    salt -C "$nodegroup" saltutil.running --hide-timeout --out=json |
        jq --raw-output --argjson x "$excluded" '
            with_entries(select(.value==[])) | keys - $x | .[]' |
                awk 'NR > 1 { printf(", ") } {printf "%s",$0}'
}

#parameters
function="$1"
min_highstates_per_day="$2"
runs_per_day="$3"

#validation on function variable
if [ "$function" != "state.highstate" -a "$function" != "test.ping" ]; then
    log_msg "$logfile" "$function" "$nodegroup" "$function is an invalid selection" "ERROR"
    exit 2
fi

#logfile
logfile=$(init_log 'run_highstate')

#get excluded
excluded_nodegroups=$(get_excluded_nodegroups)
excluded_minions=$(get_excluded_minions)

#loose math to come up with number of nodegroups to select per run
#bash doesn't support floats, so we add +1 to ensure at least one run per execution
nodegroup_count=$(get_nodegroup_count "$excluded_nodegroups")
qty=$(( ($nodegroup_count * $min_highstates_per_day / $runs_per_day) + 1 ))

#loop getting random nodegroups until we have the right qty of unique nodegroups
unique_nodegroups=()
random_nodegroups=()

while [ "${#unique_nodegroups[@]}" -lt "$qty" ]; do

    #add random group to array
    random_nodegroups+=( $(get_random_nodegroup "$excluded_nodegroups") )

    #get unique elements from random group array
    unique_nodegroups=( $(printf '%s\n' "${random_nodegroups[@]}" | LC_ALL=C sort -u) )

done

#loop through nodegroups
for nodegroup in "${unique_nodegroups[@]}"; do

    #get minions in nodegroup
    log_msg "$logfile" "$function" "$nodegroup" "gathering minions" "INFO"
    minions_list=$(get_minions_list "N@$nodegroup" "$excluded_minions")

    #if no minions, continue to next nodegroup
    if [ -z "$minions_list" ]; then
        log_msg "$logfile" "$function" "$nodegroup" "no minions, skipping" "INFO"
        continue
    fi

    #run highstate using batching
    #CPU cores * (3 or 4) => max batch size
    #worker_threads => max batch size + 25 (spare)
    #https://github.com/saltstack/salt/issues/36654
    log_msg "$logfile" "$function" "$nodegroup" "start applying batch highstate" "INFO"
    salt --batch-size 5 --batch-wait 5 -L "$minions_list" "$function"

    #wait for minions to return from job
    log_msg "$logfile" "$function" "$nodegroup" "finish applying batch highstate" "INFO"

done
