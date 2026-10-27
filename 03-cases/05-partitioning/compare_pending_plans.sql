-- After partitioning, the optimizer switched the case-2 query to a full scan of the December
-- partition. Is that right? Run both plans 300 times in one session and compare elapsed and CPU.
-- usage: sqlplus / as sysdba @compare_pending_plans.sql <pdb_name>
set serveroutput on verify off
alter session set container = &1;
set serveroutput on
declare
  procedure run(p_label varchar2, p_hint varchar2) is
    t0 pls_integer; c0 pls_integer; n number; s number;
  begin
    t0 := dbms_utility.get_time; c0 := dbms_utility.get_cpu_time;
    for i in 1 .. 300 loop
      execute immediate 'select /*+ ' || p_hint || ' */ count(*), sum(amount) from bank.transactions t '
                     || 'where status = :s and txn_ts >= timestamp ''2025-12-01 00:00:00'''
        into n, s using case when mod(i, 10) = 0 then 'REVERSED' else 'PENDING' end;
    end loop;
    dbms_output.put_line(rpad(p_label, 32) || ' elapsed ' || round((dbms_utility.get_time - t0) * 10 / 300, 2)
                         || ' ms/exec, cpu ' || round((dbms_utility.get_cpu_time - c0) * 10 / 300, 2) || ' ms/exec');
  end;
begin
  run('warm-up (optimizer choice)', 'qb_name(warm)');
  run('optimizer choice', 'qb_name(opt)');
  run('forced local index', 'index(t transactions_status_ts_ix)');
  run('forced full partition scan', 'full(t)');
  run('covering index (if present)', 'index(t transactions_status_ts_amt_ix)');
end;
/
exit
