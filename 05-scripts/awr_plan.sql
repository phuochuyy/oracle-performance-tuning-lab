-- Execution plans of the BANK_APP SQL captured by AWR between two snapshots.
-- usage: sqlplus -s / as sysdba @awr_plan.sql <begin_snap> <end_snap>
-- Uses AWR instead of V$SQL: on this small VM cursors age out of the shared pool within seconds.
set lines 200 pages 200 verify off
select p.plan_table_output
from (select distinct s.sql_id, s.plan_hash_value, s.dbid, s.con_dbid
        from dba_hist_sqlstat s
       where s.snap_id > &1 and s.snap_id <= &2 and s.parsing_schema_name = 'BANK' and s.module = 'BANK_APP'
         and s.plan_hash_value != 0
       order by 1) s,
     table(dbms_xplan.display_workload_repository(sql_id => s.sql_id, plan_hash_value => s.plan_hash_value,
                                                  format => 'TYPICAL', dbid => s.dbid, con_dbid => s.con_dbid)) p;
exit
