-- Case 5 follow-up: the pending query regressed after partitioning (optimizer picked a full scan
-- of the December partition, 7.3 ms, while the local index plan takes 3.1 ms). Root cause: high
-- clustering factor makes table-by-rowid access look expensive. Fix: a covering local index so the
-- query never visits the table. The old index is made INVISIBLE first (instant rollback), not dropped.
-- usage: sqlplus / as sysdba @fix_pending_index.sql <pdb_name>
whenever sqlerror exit failure
set timing on verify off lines 200
alter session set container = &1;
alter session set current_schema = BANK;
create index bank.transactions_status_ts_amt_ix on bank.transactions (status, txn_ts, amount) local online parallel 2;
alter index bank.transactions_status_ts_amt_ix noparallel;
alter index bank.transactions_status_ts_ix invisible;
select index_name, visibility, round(sum(bytes) / 1048576) mb
from dba_indexes i join dba_segments s on s.owner = i.owner and s.segment_name = i.index_name
where i.owner = 'BANK' and i.table_name = 'TRANSACTIONS'
group by index_name, visibility order by 1;
exit
