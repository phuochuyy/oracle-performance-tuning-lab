-- Work area memory, TEMP and IO per plan line for two executions (V$SQL_PLAN_MONITOR):
-- shows whether a hash join ran in memory or spilled. Edit sql_id / sql_exec_id as needed.
set lines 220 pages 100
col operation for a36
col object_name for a16
alter session set container=PERF;
select p.sql_exec_id, p.plan_line_id id, max(lpad(' ', p.plan_depth) || p.plan_operation || ' ' || p.plan_options) operation,
       max(p.plan_object_name) object_name, sum(p.output_rows) out_rows,
       round(max(p.workarea_max_mem)/1048576, 1) max_mem_mb, round(sum(p.workarea_max_tempseg)/1048576, 1) temp_mb,
       round(sum(p.physical_read_bytes)/1048576) read_mb, round(sum(p.physical_write_bytes)/1048576) write_mb
from v$sql_plan_monitor p
where p.sql_id = 'by010kzs43yzc' and p.sql_exec_id in (16777236, 16777235)
group by p.sql_exec_id, p.plan_line_id
having sum(p.physical_read_bytes) > 0 or max(p.workarea_max_mem) > 0 or sum(p.workarea_max_tempseg) > 0
order by p.sql_exec_id, p.plan_line_id;
exit
