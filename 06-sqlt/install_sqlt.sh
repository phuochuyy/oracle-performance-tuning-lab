#!/bin/bash
# Install SQLT (MOS Doc ID 215187.1, not in this repo — download it yourself) into the PDB PERF on prm3.
# usage (from the host): 06-sqlt/install_sqlt.sh <sqlt.zip>
# Passwords come from lab.env (SQLT_PASSWORD) and go to SQL*Plus on stdin, never on a command line.
# Notes from the first install (2026-10-29):
# - in a PDB SQLT stops with ORA-20103 unless a connect identifier is given: it reconnects as SQLTXPLAIN
# - PERF has no USERS tablespace: SQLT gets its own (SQLT_DATA, max 1 GB)
# - prm3 has no zip (and no internet for dnf): SQLT only prints "zip: command not found", files stay unzipped
# - ~80 ORA-01418/01435/00942 in the install logs are its drops of objects that do not exist yet
set -eu
zip=$1
H=$(cd "$(dirname "$0")/.." && pwd)
. "$H/lab.env"
P="ssh -o BatchMode=yes oracle@prm3"
src=$(mktemp -d)
unzip -q "$zip" -d "$src"
dir=$(ls -d "$src"/sqlt_*)
tar czf - -C "$dir" . | $P "rm -rf ~/sqlt; mkdir -p ~/sqlt && tar xzf - -C ~/sqlt"
rm -rf "$src"
printf "create tablespace sqlt_data datafile size 100m autoextend on next 50m maxsize 1g;\nexit\n" |
  $P ". ~/.bash_profile >/dev/null; export ORACLE_PDB_SID=PERF; sqlplus -s / as sysdba" | grep -E "created|ORA-" || true
$P ". ~/.bash_profile >/dev/null; export ORACLE_PDB_SID=PERF; cd ~/sqlt/install; sqlplus -s / as sysdba" <<EOF | grep -E "completed|ORA-20" || true
DEF connect_identifier      = '@//prm3.rac:1521/perf.rac';
DEF enter_tool_password     = '$SQLT_PASSWORD';
DEF re_enter_password       = '$SQLT_PASSWORD';
DEF default_tablespace      = 'SQLT_DATA';
DEF temporary_tablespace    = 'TEMP';
DEF main_application_schema = 'BANK';
DEF pack_license            = 'T';
@sqcsilent.sql
exit
EOF
printf "set heading off\nselect owner || ' ' || status || ' ' || count(*) from dba_objects where owner in ('SQLTXPLAIN','SQLTXADMIN') group by owner, status;\nexit\n" |
  $P ". ~/.bash_profile >/dev/null; export ORACLE_PDB_SID=PERF; sqlplus -s / as sysdba" | grep -E "SQLTX"
