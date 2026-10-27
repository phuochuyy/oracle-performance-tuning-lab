#!/bin/bash
# Run a workload with N concurrent sessions between two AWR snapshots and save the evidence.
# usage (on prm3, as oracle): BANK_PASSWORD=... ./run_workload.sh <case> <tag> <sessions> <seconds> [procedure]
#   output: 04-reports/<case>/<tag>/{awr.html, top_sql.txt, top_events.txt, summary.txt, plan.txt}
# profile first: /etc/bashrc reads unset variables and would abort under set -u
. ~/.bash_profile >/dev/null 2>&1
set -eu
case=$1 tag=$2 n=$3 secs=$4 proc=${5:-bank.wl_statement}
: "${BANK_PASSWORD:?set BANK_PASSWORD}"
H=$(cd "$(dirname "$0")/.." && pwd)
out=$H/04-reports/$case/$tag; mkdir -p "$out"
CONN="bank/${BANK_PASSWORD}@//localhost/perf.rac"

snap() { sqlplus -s / as sysdba @"$H/05-scripts/awr_snap.sql" | tr -d ' \t' | grep -E '^[0-9]+$'; }

b=$(snap)
for i in $(seq 1 "$n"); do
  sqlplus -s -L "$CONN" > "$out/session_$i.log" 2>&1 <<SQL &
whenever sqlerror exit failure
exec $proc('$case/$tag', $secs)
exit
SQL
done
wait
e=$(snap)

sqlplus -s / as sysdba @"$H/05-scripts/awr_report.sql" "$b" "$e" "$out/awr.html" > /dev/null
sqlplus -s / as sysdba @"$H/05-scripts/top_sql.sql" "$b" "$e" > "$out/top_sql.txt"
sqlplus -s / as sysdba @"$H/05-scripts/top_events.sql" "$b" "$e" > "$out/top_events.txt"
sqlplus -s / as sysdba @"$H/05-scripts/wl_summary.sql" PERF "$case/$tag" > "$out/summary.txt"
sqlplus -s / as sysdba @"$H/05-scripts/awr_plan.sql" "$b" "$e" > "$out/plan.txt"
grep -l -E "ORA-|SP2-" "$out"/session_*.log && { echo "session errors, see $out"; exit 1; }
rm -f "$out"/session_*.log
echo "AWR snaps $b..$e -> $out"
cat "$out/summary.txt"
