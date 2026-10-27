#!/bin/bash
# Case 4 part B: switch the redo transport of dg_orcl3 between SYNC, FASTSYNC and ASYNC.
#   SYNC     : MaxAvailability, primary waits until the standby has written the redo (current setup)
#   FASTSYNC : MaxAvailability, primary waits until the standby has received it (SYNC NOAFFIRM)
#   ASYNC    : MaxPerformance, primary does not wait; needs FSFO disabled (zero data loss mode impossible)
# Order matters: protection mode can only be raised to MaxAvailability once transport is (FAST)SYNC.
# usage (from the host): DB_PASSWORD=... ./set_transport.sh SYNC|FASTSYNC|ASYNC
set -eu
mode=$1; : "${DB_PASSWORD:?}"
dg() { printf '%s;\n' "$@" | ssh -o BatchMode=yes oracle@prm3 ". ~/.bash_profile >/dev/null 2>&1; dgmgrl -silent sys/$DB_PASSWORD@orcl3" | { grep -vE "^$|^Connected" || true; }; }   # empty output is fine (e.g. "disable fast_start failover")
case $mode in
  SYNC|FASTSYNC)
    # the FSFO target's LogXptMode cannot change while FSFO is enabled (ORA-16654)
    dg "disable fast_start failover"
    dg "edit database ORCL3_STB set property LogXptMode='$mode'" "edit database orcl3 set property LogXptMode='$mode'"
    dg "edit configuration set protection mode as MaxAvailability"
    dg "enable fast_start failover" ;;
  ASYNC)
    dg "disable fast_start failover"
    dg "edit configuration set protection mode as MaxPerformance"
    dg "edit database ORCL3_STB set property LogXptMode='ASYNC'" "edit database orcl3 set property LogXptMode='ASYNC'" ;;
  *) echo "mode must be SYNC, FASTSYNC or ASYNC"; exit 2 ;;
esac
for i in $(seq 1 30); do dg "show configuration" | grep -A1 "Configuration Status:" | grep -q "^SUCCESS" && break; sleep 10; done
dg "show configuration" | grep -E "Protection Mode|Fast-Start Failover:|^SUCCESS|^WARNING|^ERROR"
dg "show database ORCL3_STB LogXptMode"
