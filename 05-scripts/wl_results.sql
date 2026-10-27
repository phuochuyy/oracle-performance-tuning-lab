-- Per-execution wall time and result checksum of the annual-report runs (BANK.WL_RESULTS).
-- usage: sqlplus -s / as sysdba @wl_results.sql <pdb_name> <run_tag>
set lines 150 pages 50 verify off
col run_tag for a40
col total_min for 99999999999999999999
col total_max for 99999999999999999999
alter session set container = &1;
select run_tag, dop, count(*) execs,
       round(avg(elapsed_cs) / 100, 2) avg_s, round(min(elapsed_cs) / 100, 2) min_s, round(max(elapsed_cs) / 100, 2) max_s,
       min(rows_out) rows_out, min(total) total_min, max(total) total_max, max(cnt) cnt
from bank.wl_results
where run_tag = '&2'
group by run_tag, dop;
exit
