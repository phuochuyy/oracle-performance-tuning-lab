#!/bin/bash
# Case 4 part A fix: async + direct IO on the datafile filesystem and a second DB writer.
# Both parameters are static -> restart standby then primary. FSFO is disabled around the restart so
# the observer does not treat a restarting primary as a failure.
# usage (from the host): DB_PASSWORD=... ./fix_dbwr_io.sh
set -eu
: "${DB_PASSWORD:?}"
dg() { printf '%s;\n' "$@" | ssh -o BatchMode=yes oracle@prm3 ". ~/.bash_profile >/dev/null 2>&1; dgmgrl -silent sys/$DB_PASSWORD@orcl3"; }
sql() { ssh -o BatchMode=yes oracle@$1 ". ~/.bash_profile >/dev/null 2>&1; sqlplus -s / as sysdba" ; }

echo "== before"; for h in prm3 stb3; do printf "show parameter filesystemio_options\nshow parameter db_writer_processes\nexit\n" | sql $h | grep -E "filesystemio|db_writer"; done
dg "disable fast_start failover"
for h in stb3 prm3; do
  printf "alter system set filesystemio_options = SETALL scope = spfile;\nalter system set db_writer_processes = 2 scope = spfile;\nexit\n" | sql $h
done
echo "== restart standby"
printf "shutdown immediate\nstartup mount\nexit\n" | sql stb3
echo "== restart primary"
printf "shutdown immediate\nstartup\nexit\n" | sql prm3
for i in $(seq 1 30); do dg "show configuration" | grep -A1 "Configuration Status:" | grep -q "^SUCCESS" && break; sleep 10; done
dg "enable fast_start failover"
echo "== after"; for h in prm3 stb3; do printf "show parameter filesystemio_options\nshow parameter db_writer_processes\nselect open_mode from v\$database;\nexit\n" | sql $h | grep -E "filesystemio|db_writer|READ|MOUNTED"; done
dg "show configuration" | grep -A1 -E "Fast-Start Failover:|Configuration Status:"
