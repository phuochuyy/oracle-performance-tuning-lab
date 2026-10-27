-- Case 1 fix: composite index for the account-statement query.
-- usage: sqlplus / as sysdba @fix.sql <pdb_name>
--   account_id = :b       -> index access instead of a full scan of 8M rows
--   txn_ts >= ...         -> range on the second column
--   order by txn_ts desc  -> read the index backwards, no sort; stops after 50 rows
-- It also indexes the TRANSACTIONS -> ACCOUNTS foreign key column.
whenever sqlerror exit failure
set timing on verify off
alter session set container = &1;
create index bank.transactions_acct_ts_ix on bank.transactions (account_id, txn_ts) online parallel 2;
alter index bank.transactions_acct_ts_ix noparallel;
select index_name, round(bytes / 1048576) mb, blevel, leaf_blocks, clustering_factor
from dba_indexes i join dba_segments s on s.owner = i.owner and s.segment_name = i.index_name
where i.owner = 'BANK' and i.index_name = 'TRANSACTIONS_ACCT_TS_IX';
exit
