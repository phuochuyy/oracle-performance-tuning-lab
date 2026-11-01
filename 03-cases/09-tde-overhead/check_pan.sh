#!/bin/bash
# Is card data readable in the raw PERF datafile? Counts the PAN of card 1 in the bytes of BANK_DATA.
# Runs on prm3 as root (no database login needed for the grep itself). The PAN is never printed in full.
# usage (from the host): ssh root@prm3 'bash -s' < check_pan.sh
set -eu
q() { su - oracle -c "sqlplus -s / as sysdba" <<SQL | grep -v '^$'
set heading off feedback off pages 0 lines 300
alter session set container=PERF;
$1
exit
SQL
}
pan=$(q "select pan from bank.cards where card_id = 1;" | tail -1 | tr -d ' ')
f=$(q "select file_name from dba_data_files where tablespace_name = 'BANK_DATA';" | tail -1 | tr -d ' ')
enc=$(q "select encrypted from dba_tablespaces where tablespace_name = 'BANK_DATA';" | tail -1 | tr -d ' ')
echo "PAN of card 1: ${pan:0:4}********${pan: -4}   BANK_DATA encrypted: $enc"
echo "datafile $(basename "$f") ($(du -h "$f" | cut -f1)): hits=$(grep -a -o -F "$pan" "$f" | wc -l)"
