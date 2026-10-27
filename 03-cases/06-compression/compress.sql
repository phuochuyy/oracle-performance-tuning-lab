-- Case 6: Basic compression for the 12 historical 2024 partitions (read-mostly data).
-- BASIC is included in Enterprise Edition; ADVANCED row compression needs the Advanced Compression
-- Option license, HCC needs Exadata/ZFS. BASIC only compresses on direct-path loads / MOVE, rows that
-- are updated later are stored uncompressed again.
-- MOVE ... ONLINE keeps the table usable; UPDATE INDEXES keeps local and global indexes valid.
-- Generates redo for every moved block (FORCE LOGGING) -> archived-log housekeeping must be running.
-- usage: sqlplus / as sysdba @compress.sql <pdb_name>
whenever sqlerror exit failure
set serveroutput on timing on verify off
alter session set container = &1;
set serveroutput on
begin
  for p in (select partition_name from dba_tab_partitions
             where table_owner = 'BANK' and table_name = 'TRANSACTIONS' and partition_position between 2 and 13
             order by partition_position) loop
    execute immediate 'alter table bank.transactions move partition ' || p.partition_name
                   || ' row store compress basic online update indexes';
    dbms_output.put_line('moved ' || p.partition_name);
  end loop;
end;
/
exec dbms_stats.gather_table_stats('BANK', 'TRANSACTIONS', method_opt => 'FOR ALL COLUMNS SIZE 1 FOR COLUMNS STATUS SIZE 254', degree => 2, no_invalidate => false)
select index_name, status from dba_indexes where owner = 'BANK' and table_name = 'TRANSACTIONS' and partitioned = 'NO';
select count(*) unusable_index_partitions from dba_ind_partitions where index_owner = 'BANK' and status != 'USABLE';
exit
