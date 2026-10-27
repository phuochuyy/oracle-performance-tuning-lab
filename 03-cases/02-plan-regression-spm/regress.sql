-- Case 2 trigger: a "routine" statistics refresh that drops all histograms.
-- usage: sqlplus / as sysdba @regress.sql <pdb_name>
-- Prints the time just before the change: needed later for DBMS_STATS.RESTORE_TABLE_STATS.
whenever sqlerror exit failure
set verify off
alter session set container = &1;
select 'BEFORE_REGRESS=' || to_char(systimestamp, 'YYYY-MM-DD HH24:MI:SS.FF6 TZR') marker from dual;
exec dbms_stats.gather_table_stats('BANK', 'TRANSACTIONS', method_opt => 'FOR ALL COLUMNS SIZE 1', degree => 2, no_invalidate => false)
select column_name, num_distinct, histogram from dba_tab_col_statistics
 where owner = 'BANK' and table_name = 'TRANSACTIONS' and column_name = 'STATUS';
exit
