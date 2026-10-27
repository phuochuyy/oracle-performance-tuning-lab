-- Redo / commit / DBWR picture between two AWR snapshots.
-- usage: sqlplus -s / as sysdba @redo_stats.sql <begin_snap> <end_snap>
set lines 160 pages 50 verify off
col event for a42
col stat_name for a32
prompt == commit and write latency (foreground + background events)
select e.event_name event, e.total_waits - b.total_waits waits,
       round((e.time_waited_micro - b.time_waited_micro) / 1000 / nullif(e.total_waits - b.total_waits, 0), 2) avg_ms,
       round((e.time_waited_micro - b.time_waited_micro) / 1e6, 1) total_s
from dba_hist_system_event b join dba_hist_system_event e
  on e.event_id = b.event_id and e.dbid = b.dbid and e.instance_number = b.instance_number
where b.snap_id = &1 and e.snap_id = &2 and b.dbid = (select dbid from v$database)
  and e.event_name in ('log file sync', 'log file parallel write', 'SYNC Remote Write', 'LGWR wait for redo copy',
                       'write complete waits', 'free buffer waits', 'log file switch (checkpoint incomplete)',
                       'db file parallel write', 'log buffer space')
  and e.total_waits - b.total_waits > 0
order by total_s desc;
prompt == volume
select e.stat_name, e.value - b.value delta
from dba_hist_sysstat b join dba_hist_sysstat e
  on e.stat_id = b.stat_id and e.dbid = b.dbid and e.instance_number = b.instance_number
where b.snap_id = &1 and e.snap_id = &2 and b.dbid = (select dbid from v$database)
  and e.stat_name in ('redo size', 'user commits', 'physical writes', 'DBWR checkpoints', 'redo log space requests')
order by 1;
prompt == log switches in the interval
select count(*) log_switches
from v$log_history
where first_time between (select end_interval_time from dba_hist_snapshot where snap_id = &1 and dbid = (select dbid from v$database) and rownum = 1)
                     and (select end_interval_time from dba_hist_snapshot where snap_id = &2 and dbid = (select dbid from v$database) and rownum = 1);
exit
