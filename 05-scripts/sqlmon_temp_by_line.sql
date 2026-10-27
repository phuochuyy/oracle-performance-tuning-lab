-- TEMP use per hash operation of one SQL (V$SQL_PLAN_MONITOR) — tells a real spill of the big
-- hash join apart from the HASH JOIN BUFFERED that PX buffers by design. Edit the sql_id.
set lines 150 pages 50
col operation for a30
alter session set container=PERF;
select p.plan_line_id id, max(p.plan_operation || ' ' || p.plan_options) operation,
       count(distinct p.sql_exec_id) execs,
       count(distinct case when p.workarea_max_tempseg > 0 then p.sql_exec_id end) execs_with_temp,
       round(max(p.workarea_max_tempseg)/1048576) max_temp_mb,
       round(max(p.workarea_max_mem)/1048576, 1) max_mem_mb
from v$sql_plan_monitor p
where p.sql_id = 'a92rusu7xdqnf' and p.plan_operation like 'HASH%'
group by p.plan_line_id order by 1;
exit
