-- Per-execution totals (QC + all PX servers) from V$SQL_MONITOR for the annual-report SQL.
-- A QC row alone only shows the coordinator work; sum over the sql_exec_id to see the real cost.
set lines 220 pages 100
alter session set container=PERF;
select m.sql_id, m.sql_exec_id,
       round((max(m.last_refresh_time) - min(m.sql_exec_start)) * 86400, 1) wall_s,
       count(*) - 1 px_rows,
       round(sum(m.cpu_time)/1e6, 2) cpu_s, round(sum(m.user_io_wait_time)/1e6, 2) io_s,
       round(sum(m.concurrency_wait_time)/1e6, 2) conc_s,
       sum(m.buffer_gets) gets, round(sum(m.physical_read_bytes)/1048576) read_mb
from v$sql_monitor m
where m.sql_id in (select sql_id from v$sql_monitor where px_qcsid is null and (sql_text like 'select /*+ parallel(4)%' or sql_text like 'select /*+ parallel(2)%' or sql_text like 'select /*+ no_parallel%'))
group by m.sql_id, m.sql_exec_id
order by min(m.sql_exec_start) desc fetch first 16 rows only;
exit
