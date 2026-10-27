-- Live blocking tree in the PERF PDB: who is waiting, on whom, and what the blocker is doing.
-- usage: sqlplus -s / as sysdba @blocking_tree.sql
-- A blocker that is idle (e.g. waiting for the client, or sleeping) is NOT sampled by ASH,
-- so this live view is the only place its state shows up.
set lines 220 pages 100
col who for a8
col event for a36
col module for a12
col action for a16
select case when s.blocking_session is null then 'BLOCKER' else 'waiter' end who,
       s.sid, s.serial#, s.blocking_session blk_sid, s.status, s.event, s.wait_class,
       s.seconds_in_wait secs, s.module, s.action, s.sql_id,
       (select count(*) from v$session w where w.blocking_session = s.sid) n_blocked
from v$session s
where s.con_id = (select con_id from v$pdbs where name = 'PERF')
  and (s.blocking_session is not null or s.sid in (select blocking_session from v$session where blocking_session is not null))
order by case when s.blocking_session is null then 0 else 1 end, s.sid;
exit
