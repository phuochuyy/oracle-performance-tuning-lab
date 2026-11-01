-- Case 1 fix: composite index for the account-statement query.
-- usage: sqlplus / as sysdba @fix.sql <pdb_name>
--   account_id = :b       -> index access instead of a full scan of 8M rows
--   txn_ts >= ...         -> range on the second column
--   order by txn_ts desc  -> read the index backwards, no sort; stops after 50 rows
-- It also indexes the TRANSACTIONS -> ACCOUNTS foreign key column.
-- Since case 5 the table is interval-partitioned and this index is LOCAL (the query prunes on txn_ts).
-- The first version always built a global index: the case 1 live demo (demo_reset + fix) of 2026-10-29
-- silently replaced the local index of case 5 with a global one. Now: LOCAL when the table is partitioned.
whenever sqlerror exit failure
set timing on verify off serveroutput on
alter session set container = &1;
declare
  l_part number;
  l_ddl  varchar2(400) := 'create index bank.transactions_acct_ts_ix on bank.transactions (account_id, txn_ts)';
begin
  select count(*) into l_part from dba_part_tables where owner = 'BANK' and table_name = 'TRANSACTIONS';
  if l_part > 0 then l_ddl := l_ddl || ' local'; end if;
  execute immediate l_ddl || ' online parallel 2';
  execute immediate 'alter index bank.transactions_acct_ts_ix noparallel';
  dbms_output.put_line(case when l_part > 0 then 'LOCAL index (table is partitioned)' else 'index (table not partitioned)' end);
end;
/
select i.index_name, i.partitioned, round(sum(s.bytes) / 1048576) mb, max(i.blevel) blevel
from dba_indexes i join dba_segments s on s.owner = i.owner and s.segment_name = i.index_name
where i.owner = 'BANK' and i.index_name = 'TRANSACTIONS_ACCT_TS_IX'
group by i.index_name, i.partitioned;
exit
