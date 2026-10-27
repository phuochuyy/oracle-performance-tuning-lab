-- Case 5 fix: convert TRANSACTIONS to monthly interval range partitions, online.
-- usage: sqlplus / as sysdba @fix.sql <pdb_name>
-- Needs free space for a full copy of the table + indexes (~1.1 GB) and generates redo
-- (FORCE LOGGING) — check the FRA first.
--   transactions_pk          GLOBAL: the PK (txn_id) does not contain the partition key
--   transactions_acct_ts_ix  LOCAL : case 1 query still prunes on txn_ts
--   transactions_status_ts_ix LOCAL: case 2 query prunes to December 2025
whenever sqlerror exit failure
set timing on verify off lines 200
alter session set container = &1;
-- index names in UPDATE INDEXES are resolved in the current schema (SYS when run as SYSDBA):
-- without this the statement fails with ORA-01418 'specified index does not exist'
alter session set current_schema = BANK;

alter table bank.transactions modify
  partition by range (txn_ts) interval (numtoyminterval(1, 'MONTH'))
  (partition p_before_2024 values less than (timestamp '2024-01-01 00:00:00'))
  online
  update indexes (transactions_pk global,
                  transactions_acct_ts_ix local,
                  transactions_status_ts_ix local);

exec dbms_stats.gather_table_stats('BANK', 'TRANSACTIONS', method_opt => 'FOR ALL COLUMNS SIZE 1 FOR COLUMNS STATUS SIZE 254', degree => 2, no_invalidate => false)

select count(*) partitions, min(num_rows) min_rows, max(num_rows) max_rows
from dba_tab_partitions where table_owner = 'BANK' and table_name = 'TRANSACTIONS';
select index_name, partitioned, status from dba_indexes where owner = 'BANK' and table_name = 'TRANSACTIONS';
exit
