#!/bin/bash
# Case 7 measurement matrix (on prm3): 1 session x {serial, DOP 2, DOP 4}, then 4 sessions x {serial, DOP 2}.
# usage: BANK_PASSWORD=... ./run_matrix.sh <label> [seconds]
. ~/.bash_profile >/dev/null 2>&1
set -eu
label=$1 secs=${2:-120}
H=$(cd "$(dirname "$0")/../.." && pwd)
run() {   # run <sessions> <dop-name>
  local tag="$label-${1}s-$2" out
  out=$("$H/02-workload/run_workload.sh" 07-parallel-query "$tag" "$1" "$secs" "bank.wl_annual_$2" | grep -oE "AWR snaps [0-9]+\.\.[0-9]+")
  local b=${out#AWR snaps }; b=${b%..*}; local e=${out##*..}
  local dir="$H/04-reports/07-parallel-query/$tag"
  sqlplus -s / as sysdba @"$H/05-scripts/wl_results.sql" PERF "07-parallel-query/$tag" > "$dir/results.txt"
  sqlplus -s / as sysdba @"$H/05-scripts/px_stats.sql" "$b" "$e" > "$dir/px_stats.txt"
  echo "$(date +%T) done $tag (snaps $b..$e)"
}
run 1 serial; run 1 dop2; run 1 dop4
run 4 serial; run 4 dop2
