#!/bin/bash
# Transfers (4 sessions, 120 s) with the interest batch started after 20 s.
# Live blocking tree captured at t=40 s, ASH lock analysis after the run.
# usage (on prm3): BANK_PASSWORD=... ./run_incident.sh <tag> <commit_every> <hold_seconds>
#   commit_every = -1 -> no batch at all (baseline)
. ~/.bash_profile >/dev/null 2>&1
set -eu
tag=$1 every=$2 hold=$3
H=$(cd "$(dirname "$0")/../.." && pwd)
out=$H/04-reports/03-row-lock-contention/$tag; mkdir -p "$out"
CONN="bank/${BANK_PASSWORD}@//localhost/perf.rac"
if [ "$every" -ge 0 ]; then
  ( sleep 20
    sqlplus -s -L "$CONN" > "$out/batch.log" 2>&1 <<SQL
set timing on
exec bank.batch_interest($every, $hold)
exit
SQL
  ) &
  ( sleep 40; sqlplus -s / as sysdba @"$H/05-scripts/blocking_tree.sql" > "$out/blocking_tree_t40.txt" ) &
fi
"$H/02-workload/run_workload.sh" 03-row-lock-contention "$tag" 4 120 bank.wl_transfer
wait
sqlplus -s / as sysdba @"$H/05-scripts/ash_blocking.sql" 3 > "$out/ash_blocking.txt"
