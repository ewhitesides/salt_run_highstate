#shared functions

init_log () {
    #setup log directory
    logdir="/var/log/$1"
    mkdir -p "$logdir"

    #log file
    epoch_timestamp=$(date "+%s")
    logfile_prefix="$1"
    logfile="${logdir}/${logfile_prefix}_${epoch_timestamp}.log"

    #rm logs older than 1 days
    find "$logdir" -regextype posix-extended -regex "${logdir}/${logfile_prefix}_[0-9]*\.log" -mtime +1 -exec rm {} \;

    #output logfile name
    echo "$logfile"
}

get_excluded_minions () {
    #get excluded minons from excluded_minions pillar and output as compact json
    pillar_name='excluded_minions'
    salt-call saltutil.refresh_pillar --out=json | jq -c '.local' > /dev/null
    salt-call pillar.get $pillar_name --out=json | jq -c '.local'
}

get_excluded_nodegroups () {
    #get excluded nodegroups from excluded_nodegroups pillar and output as compact json
    pillar_name='excluded_nodegroups'
    salt-call saltutil.refresh_pillar --out=json | jq -c '.local' > /dev/null
    salt-call pillar.get $pillar_name --out=json | jq -c '.local'
}
