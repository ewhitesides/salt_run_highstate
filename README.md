# Summary

- bash scripts for running highstate, and outputting logs for consumption by splunk

- these are intended to be run from cron on salt-master.

- it is expected the salt-master has a nodegroups conf file with various nodegroups configured

- salt-master should have jq tool installed

## Examples

```bash
#run in test mode (runs test.ping instead of state.highstate)
#see top of script file for info on parameters/arguments
./run_highstate.sh "test.ping" "4" "18"

#run highstate
#see top of script file for info on parameters/arguments
./run_highstate.sh "state.highstate" "4" "18"

#get status of qty of highstate runs in last 24 hrs
./get_highstate_status.sh

#get results of highstate run (summary of succeeded,changed,failed)
./get_highstate_results.sh
```
