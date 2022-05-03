#!/bin/bash

#Summary
#outputs to log how many states have succeeded,failed,changed on a highstate run

#Example call
#./get_highstate_results.sh

#function to convert salt job id to timestamp
jid_to_timestamp () {

    #job id is timestamp in GMT timezone out to milliseconds
    input=$1

    #extract year month day hour minute second from job id
    Y=${input:0:4}; m=${input:4:2}; d=${input:6:2}; H=${input:8:2}; M=${input:10:2}; S=${input:12:2}

    #output to format 2021-02-03T08:45:30-00:00 and append -0000 to let splunk know it is GMT timezone
    date --date="$Y-$m-$d $H:$M:$S" "+%Y-%m-%dT%H:%M:%S-0000"
}

#function to get highstate job ids
get_job_ids () {
    salt-run jobs.list_jobs search_function='state.highstate' --out=json |
    jq -r 'to_entries[] | .key'
}

#get job ids into array variable
readarray -t jids < <(get_job_ids)

#log file
logdir='/var/log/highstate_results'
mkdir -p "$logdir"
logfile_prefix='hr'

#rm logs older than 1 day
find "$logdir" -regextype posix-extended -regex "${logdir}/${logfile_prefix}_[0-9]*\.log" -mtime +1 -exec rm {} \;

#loop through jids
for jid in "${jids[@]}"; do

    #log file
    logfile="${logdir}/${logfile_prefix}_${jid}.log"

    #if log exists then go to next job id
    if [ -f "$logfile" ];then
        continue
    fi

    #timestamp
    timestamp=$(jid_to_timestamp "$jid")

    #parse job with jq
    salt-run jobs.lookup_jid "$jid" --out=json |
        jq -r --arg t "$timestamp" '
            to_entries[] | {
                t: ($t),
                m: (.key),
                s: (
                    try ( [ .value[].result | select(.==true) ] | length ) catch ( "null" )
                ),
                f: (
                    try ( [ .value[].result | select(.==false) ] | length ) catch ( "null" )
                ),
                c: (
                    try ( [ .value[].changes | select(.!={}) ] | length ) catch ( "null" )
                )
            } | . + {
                l: (
                    if (.s == "null" or .f == "null" or .c == "null") then
                        "WARNING"
                    elif (.f > 0) then
                        "ERROR"
                    else
                        "INFO"
                    end
                )
            } |
            "Time=\(.t), Minion=\(.m), Succeeded=\(.s), Failed=\(.f), Changed=\(.c), Level=\(.l)"
        ' | tee -a "$logfile"
done
