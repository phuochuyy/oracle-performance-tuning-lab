-- DML on historical rows: update the description of every transaction of 2024-01-01 (~11 K rows),
-- measure time, redo and segment growth, then ROLLBACK (data unchanged, allocated space stays).
-- usage: sqlplus -s / as sysdba @update_test.sql <pdb_name>
set lines 150 pages 50 verify off timing on
alter session set container = &1;
col seg_mb for 9999.9
select round(bytes / 1048576, 1) seg_mb_before from dba_segments s
 where owner = 'BANK' and segment_name = 'TRANSACTIONS'
   and partition_name = (select partition_name from dba_tab_partitions where table_owner = 'BANK' and table_name = 'TRANSACTIONS' and partition_position = 2);
select value redo_before from v$mystat m join v$statname n on n.statistic# = m.statistic# where n.name = 'redo size';
update bank.transactions set description = description || ' (late correction)'
 where txn_ts >= timestamp '2024-01-01 00:00:00' and txn_ts < timestamp '2024-01-02 00:00:00';
select value redo_after from v$mystat m join v$statname n on n.statistic# = m.statistic# where n.name = 'redo size';
select round(bytes / 1048576, 1) seg_mb_after_update from dba_segments s
 where owner = 'BANK' and segment_name = 'TRANSACTIONS'
   and partition_name = (select partition_name from dba_tab_partitions where table_owner = 'BANK' and table_name = 'TRANSACTIONS' and partition_position = 2);
rollback;
exit
