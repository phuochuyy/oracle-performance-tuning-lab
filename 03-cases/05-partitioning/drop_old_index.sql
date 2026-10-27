-- Case 5 cleanup: the covering index is confirmed (workload 3-after-covering-index), drop the
-- old (status, txn_ts) index that was kept INVISIBLE as a rollback option.
-- usage: sqlplus / as sysdba @drop_old_index.sql <pdb_name>
whenever sqlerror exit failure
set verify off
alter session set container = &1;
drop index bank.transactions_status_ts_ix;
select index_name, visibility from dba_indexes where owner = 'BANK' and table_name = 'TRANSACTIONS' order by 1;
exit
