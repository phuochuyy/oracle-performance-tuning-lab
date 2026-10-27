-- Case 2 setup: index on (status, txn_ts) + a frequency histogram on STATUS.
-- usage: sqlplus / as sysdba @setup.sql <pdb_name>
whenever sqlerror exit failure
set timing on verify off
alter session set container = &1;
create index bank.transactions_status_ts_ix on bank.transactions (status, txn_ts) online parallel 2;
alter index bank.transactions_status_ts_ix noparallel;
exec dbms_stats.gather_table_stats('BANK', 'TRANSACTIONS', method_opt => 'FOR ALL COLUMNS SIZE 1 FOR COLUMNS STATUS SIZE 254', degree => 2, no_invalidate => false)
select column_name, num_distinct, histogram from dba_tab_col_statistics
 where owner = 'BANK' and table_name = 'TRANSACTIONS' and column_name = 'STATUS';
exit
