-- Top foreground wait events + DB CPU between two AWR snapshots (where the time went).
-- usage: sqlplus -s / as sysdba @top_events.sql <begin_snap> <end_snap>
set lines 150 pages 50 verify off
col event for a40
col wait_class for a15
with ev as (
  select e.event_name event, e.wait_class,
         e.total_waits_fg - lag(e.total_waits_fg) over (partition by e.event_name order by e.snap_id) waits,
         e.time_waited_micro_fg - lag(e.time_waited_micro_fg) over (partition by e.event_name order by e.snap_id) us
  from dba_hist_system_event e
  where e.snap_id in (&1, &2) and e.wait_class != 'Idle'
    and e.dbid = (select dbid from v$database)
),
cpu as (
  select 'DB CPU' event, 'CPU' wait_class, null waits,
         max(case when snap_id = &2 then value end) - max(case when snap_id = &1 then value end) us
  from dba_hist_sys_time_model
  where stat_name = 'DB CPU' and snap_id in (&1, &2) and dbid = (select dbid from v$database)
),
all_t as (select event, wait_class, waits, us from ev where us > 0
          union all select event, wait_class, waits, us from cpu)
select event, wait_class, waits, round(us / 1e6, 1) seconds,
       round(100 * ratio_to_report(us) over (), 1) pct_db_time
from all_t
order by us desc
fetch first 8 rows only;
exit
