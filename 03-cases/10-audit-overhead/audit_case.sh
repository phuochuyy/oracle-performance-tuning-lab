#!/bin/bash
# Case 10 — what Unified Auditing costs on the BANKDB workload (PDB PERF on orcl3, prm3).
#   create      two policies, not enabled:  CASE10_BALANCE_CHANGE = UPDATE ON bank.accounts  (every transfer: 2 records)
#                                           CASE10_TXN_READ       = SELECT ON bank.transactions (worst case: a hot read)
#   on <policy> / off <policy>    AUDIT / NOAUDIT POLICY
#   size        audit records in PERF and the size of the AUDSYS segments (MB)
# Nothing here deletes audit records; the retention runbook (README) needs an explicit go before a purge job exists.
# usage (from the host): ./audit_case.sh create | on CASE10_BALANCE_CHANGE | off CASE10_BALANCE_CHANGE | size
set -eu
sql() { { echo "whenever sqlerror exit failure"; echo "set lines 200 pages 50 feedback off"; echo "alter session set container=PERF;"; cat; echo "exit"; } \
          | ssh -o BatchMode=yes oracle@prm3 '. ~/.bash_profile >/dev/null 2>&1; sqlplus -s / as sysdba' 2>&1 | grep -v '^$'; }
case ${1:?create|on|off|size} in
create) sql <<'SQL'
create audit policy case10_balance_change actions update on bank.accounts;
create audit policy case10_txn_read actions select on bank.transactions;
select policy_name, object_name, audit_option from audit_unified_policies where policy_name like 'CASE10%' order by 1;
SQL
;;
on)  printf '%s\n' "audit policy ${2:?policy};" "select policy_name, enabled_option from audit_unified_enabled_policies where policy_name like 'CASE10%';" | sql ;;
off) printf '%s\n' "noaudit policy ${2:?policy};" "select count(*) case10_enabled from audit_unified_enabled_policies where policy_name like 'CASE10%';" | sql ;;
size) sql <<'SQL'
set heading off
select 'records total: '||count(*)||'   case10: '||sum(case when unified_audit_policies like '%CASE10%' then 1 else 0 end) from unified_audit_trail;
select 'AUDSYS MB: '||round(sum(bytes)/1048576,1) from dba_segments where owner = 'AUDSYS';
SQL
;;
esac
