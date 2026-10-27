-- "2024 yearly report" (serial): count/sum per channel and type over the 12 historical partitions.
-- usage: sqlplus / as sysdba @wl_year_report.sql <pdb_name>
whenever sqlerror exit failure
set verify off
alter session set container = &1;
create or replace procedure bank.wl_year_report(p_tag varchar2, p_seconds number) is
  l_start timestamp := systimestamp;
  l_end   timestamp := systimestamp + numtodsinterval(p_seconds, 'SECOND');
  l_execs pls_integer := 0;
  l_rows  pls_integer := 0;
begin
  dbms_application_info.set_module('BANK_APP', 'YEAR_REPORT_2024');
  while systimestamp < l_end loop
    for r in (select /*+ no_parallel */ channel, txn_type, count(*) cnt, sum(amount) total
                from bank.transactions
               where txn_ts >= timestamp '2024-01-01 00:00:00' and txn_ts < timestamp '2025-01-01 00:00:00'
               group by channel, txn_type) loop
      l_rows := l_rows + 1;
    end loop;
    l_execs := l_execs + 1;
  end loop;
  insert into bank.wl_runs (run_tag, sid, execs, rows_fetched, started, ended, errors)
  values (p_tag, sys_context('userenv', 'sid'), l_execs, l_rows, l_start, systimestamp, 0);
  commit;
end;
/
exit
