-- Size and compression of the 2024 partitions (positions 2-13) of BANK.TRANSACTIONS.
-- usage: sqlplus -s / as sysdba @sizes.sql <pdb_name>
set lines 150 pages 50 verify off
alter session set container = &1;
select count(*) partitions, sum(p.num_rows) num_rows, round(sum(s.bytes) / 1048576) mb,
       sum(p.blocks) blocks, listagg(distinct p.compression || '/' || nvl(p.compress_for, '-'), ' ') compression
from dba_tab_partitions p
join dba_segments s on s.owner = p.table_owner and s.segment_name = p.table_name and s.partition_name = p.partition_name
where p.table_owner = 'BANK' and p.table_name = 'TRANSACTIONS' and p.partition_position between 2 and 13;
exit
