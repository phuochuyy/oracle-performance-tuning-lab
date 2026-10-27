-- Throughput of a workload run recorded in BANK.WL_RUNS.
-- usage: sqlplus -s / as sysdba @wl_summary.sql <pdb_name> <run_tag>
set lines 150 pages 50 verify off
col run_tag for a40
alter session set container = &1;
select run_tag,
       count(*)                                                        sessions,
       sum(execs)                                                      execs,
       round(avg(extract(minute from ended - started) * 60 + extract(second from ended - started))) seconds,
       round(sum(execs) / avg(extract(minute from ended - started) * 60 + extract(second from ended - started)), 2) execs_per_sec,
       round(sum(rows_fetched) / nullif(sum(execs), 0), 1)            rows_per_exec,
       sum(errors)                                                     errors
from bank.wl_runs
where run_tag = '&2'
group by run_tag;
exit
