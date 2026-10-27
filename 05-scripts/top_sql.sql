-- Top SQL of the BANK schema between two AWR snapshots (per-execution averages).
-- usage: sqlplus -s / as sysdba @top_sql.sql <begin_snap> <end_snap>
set lines 220 pages 100 verify off
col sql_id for a13
col sql_text for a60
select s.sql_id,
       s.plan_hash_value                                                         phv,
       sum(s.executions_delta)                                                   execs,
       round(sum(s.elapsed_time_delta) / nullif(sum(s.executions_delta), 0) / 1000, 1) ms_per_exec,
       round(sum(s.buffer_gets_delta)  / nullif(sum(s.executions_delta), 0))     gets_per_exec,
       round(sum(s.disk_reads_delta)   / nullif(sum(s.executions_delta), 0))     reads_per_exec,
       round(sum(s.rows_processed_delta) / nullif(sum(s.executions_delta), 0), 1) rows_per_exec,
       (select dbms_lob.substr(t.sql_text, 60, 1) from dba_hist_sqltext t
         where t.sql_id = s.sql_id and t.dbid = s.dbid and rownum = 1)           sql_text
from dba_hist_sqlstat s
where s.snap_id > &1 and s.snap_id <= &2
  and s.parsing_schema_name = 'BANK'
group by s.dbid, s.sql_id, s.plan_hash_value
order by sum(s.elapsed_time_delta) desc
fetch first 5 rows only;
exit
