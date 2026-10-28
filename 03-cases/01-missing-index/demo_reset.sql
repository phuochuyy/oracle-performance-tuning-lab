-- Put case 1 back to its "before" state for a live demo: drop the index that fix.sql creates.
-- Demo order: demo_reset.sql -> run_workload.sh (before) -> fix.sql -> run_workload.sh (after).
-- The table has been interval-partitioned since case 5, so the "before" timing will not be the original
-- 787.8 ms (measured on the unpartitioned table) — the shape (full scan vs index range scan) is the point.
-- usage: sqlplus / as sysdba @demo_reset.sql <pdb_name>
whenever sqlerror exit failure
alter session set container = &1;
drop index bank.transactions_acct_ts_ix;
select count(*) indexes_on_account_id from dba_ind_columns
 where table_owner = 'BANK' and table_name = 'TRANSACTIONS' and column_name = 'ACCOUNT_ID' and column_position = 1;
exit
