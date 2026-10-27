-- ASH (1 s samples) for the last N minutes in the PERF PDB: where DB time went and who blocked whom.
-- usage: sqlplus -s / as sysdba @ash_blocking.sql <minutes>
set lines 200 pages 100 verify off
col event for a36
col module for a12
col action for a16
prompt == DB time by event (samples ~ seconds)
select nvl(event, 'ON CPU') event, count(*) samples, round(100 * ratio_to_report(count(*)) over (), 1) pct
from v$active_session_history
where sample_time > systimestamp - numtodsinterval(&1, 'MINUTE')
  and con_id = (select con_id from v$pdbs where name = 'PERF')
group by nvl(event, 'ON CPU') order by 2 desc fetch first 8 rows only;
prompt == Lock waits by blocking session
select h.blocking_session blk_sid, h.blocking_session_serial# blk_serial, count(*) wait_samples,
       count(distinct h.session_id) waiting_sessions,
       max(b.module) blk_module, max(b.action) blk_action, max(b.status) blk_status_now
from v$active_session_history h left join v$session b
  on b.sid = h.blocking_session and b.serial# = h.blocking_session_serial#
where h.sample_time > systimestamp - numtodsinterval(&1, 'MINUTE')
  and h.con_id = (select con_id from v$pdbs where name = 'PERF')
  and h.event like 'enq: TX%'
group by h.blocking_session, h.blocking_session_serial# order by 3 desc fetch first 5 rows only;
exit
