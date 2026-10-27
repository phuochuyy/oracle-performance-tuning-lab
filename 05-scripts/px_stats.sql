-- Parallel execution statistics between two AWR snapshots: how many operations got the requested
-- DOP and how many were downgraded (not enough PX servers).
-- usage: sqlplus -s / as sysdba @px_stats.sql <begin_snap> <end_snap>
set lines 150 pages 50 verify off
col stat_name for a50
select e.stat_name, e.value - b.value delta
from dba_hist_sysstat b join dba_hist_sysstat e
  on e.stat_id = b.stat_id and e.dbid = b.dbid and e.instance_number = b.instance_number
where b.snap_id = &1 and e.snap_id = &2
  and b.dbid = (select dbid from v$database)
  and (e.stat_name like 'Parallel operations%' or e.stat_name in ('queries parallelized', 'PX local messages sent'))
order by e.stat_name;
exit
