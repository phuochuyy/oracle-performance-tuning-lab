-- Case 2 root-cause fix: restore the TRANSACTIONS statistics from before the bad refresh,
-- then drop the emergency baseline so the optimizer is free again.
-- usage: sqlplus / as sysdba @fix_stats.sql <pdb_name> '<BEFORE_REGRESS timestamp from regress.sql>'
whenever sqlerror exit failure
set verify off lines 200 serveroutput on
alter session set container = &1;
exec dbms_stats.restore_table_stats('BANK', 'TRANSACTIONS', as_of_timestamp => to_timestamp_tz('&2', 'YYYY-MM-DD HH24:MI:SS.FF6 TZR'), no_invalidate => false)
select column_name, num_distinct, histogram from dba_tab_col_statistics
 where owner = 'BANK' and table_name = 'TRANSACTIONS' and column_name = 'STATUS';
declare
  n pls_integer;
begin
  for b in (select distinct sql_handle from dba_sql_plan_baselines where origin like 'MANUAL-LOAD%') loop
    n := dbms_spm.drop_sql_plan_baseline(sql_handle => b.sql_handle);
    dbms_output.put_line('dropped ' || n || ' plan(s) for ' || b.sql_handle);
  end loop;
end;
/
select count(*) baselines_left from dba_sql_plan_baselines;
exit
