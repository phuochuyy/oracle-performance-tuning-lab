-- Keep the AWR snapshots of the 8 cases beyond the 8-day retention: one baseline per case, before + after.
-- The snapshot ranges come from the saved reports (04-reports/<case>/<run>/awr.html, Begin/End Snap).
-- Re-runnable: an existing baseline of the same name is dropped first. Expires after 90 days.
-- usage (on prm3): sqlplus / as sysdba @awr_baselines.sql
set serveroutput on feedback off
declare
  type t_case is record (name varchar2(64), first_snap number, last_snap number);
  type t_cases is table of t_case;
  c t_cases := t_cases(
    t_case('PERF_CASE1_MISSING_INDEX',  33,  36),
    t_case('PERF_CASE2_PLAN_REGRESSION', 37,  44),
    t_case('PERF_CASE3_ROW_LOCK',        77,  84),
    t_case('PERF_CASE4_REDO_COMMIT',     85,  98),
    t_case('PERF_CASE5_PARTITIONING',    45,  56),
    t_case('PERF_CASE6_COMPRESSION',     99, 102),
    t_case('PERF_CASE7_PARALLEL_PGA',    57,  76),
    t_case('PERF_CASE8_ADDM',           103, 108));
  n number;
begin
  for i in 1 .. c.count loop
    select count(*) into n from dba_hist_baseline where baseline_name = c(i).name;
    if n > 0 then dbms_workload_repository.drop_baseline(baseline_name => c(i).name, cascade => false); end if;
    dbms_workload_repository.create_baseline(start_snap_id => c(i).first_snap, end_snap_id => c(i).last_snap,
                                             baseline_name => c(i).name, expiration => 90);
    dbms_output.put_line(rpad(c(i).name, 28) || ' snaps ' || c(i).first_snap || '-' || c(i).last_snap);
  end loop;
end;
/
set lines 160 pages 50 feedback on
col baseline_name for a28
select baseline_name, start_snap_id, end_snap_id, to_char(start_snap_time, 'MM-DD HH24:MI') start_time,
       to_char(end_snap_time, 'MM-DD HH24:MI') end_time, expiration
  from dba_hist_baseline where baseline_name like 'PERF_CASE%' order by start_snap_id;
exit
