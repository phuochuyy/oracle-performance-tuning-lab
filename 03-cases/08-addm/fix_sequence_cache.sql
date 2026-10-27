-- Case 8 fix, following ADDM finding 2 "Sequence Usage" (94 % of activity): the identity column of
-- TRANSFER_LOG uses the default CACHE 20, so at ~16 K inserts/s the sequence is refilled ~800 times/s;
-- each refill is a recursive UPDATE of SEQ$ + commit. Time model: 'sequence load elapsed time'
-- 474.9 s of 503.2 s DB time. Gaps in LOG_ID values are acceptable for a log table.
-- usage: sqlplus / as sysdba @fix_sequence_cache.sql <pdb_name>
whenever sqlerror exit failure
set verify off lines 150
alter session set container = &1;
alter table bank.transfer_log modify (log_id generated always as identity (cache 10000));
select s.sequence_name, s.cache_size from dba_tab_identity_cols t
  join dba_sequences s on s.sequence_owner = t.owner and s.sequence_name = t.sequence_name
 where t.owner = 'BANK' and t.table_name = 'TRANSFER_LOG';
exit
