-- "Monthly channel report": count and sum of POSTED transactions per channel for one random
-- month of the 24 in the dataset. Reads ~1/24 of the table — if the database can skip the rest.
-- usage: sqlplus / as sysdba @wl_monthly.sql <pdb_name>
whenever sqlerror exit failure
set verify off
alter session set container = &1;

create or replace procedure bank.wl_monthly(p_tag varchar2, p_seconds number) is
  l_start  timestamp := systimestamp;
  l_end    timestamp := systimestamp + numtodsinterval(p_seconds, 'SECOND');
  l_from   timestamp;
  l_to     timestamp;
  l_rows   pls_integer := 0;
  l_execs  pls_integer := 0;
begin
  dbms_application_info.set_module('BANK_APP', 'MONTHLY_REPORT');
  while systimestamp < l_end loop
    l_from := timestamp '2024-01-01 00:00:00' + numtoyminterval(trunc(dbms_random.value(0, 24)), 'MONTH');
    l_to   := l_from + numtoyminterval(1, 'MONTH');
    for r in (select channel, count(*) cnt, sum(amount) total
                from bank.transactions
               where txn_ts >= l_from and txn_ts < l_to and status = 'POSTED'
               group by channel) loop
      l_rows := l_rows + 1;
    end loop;
    l_execs := l_execs + 1;
  end loop;
  insert into bank.wl_runs (run_tag, sid, execs, rows_fetched, started, ended) values (p_tag, sys_context('userenv', 'sid'), l_execs, l_rows, l_start, systimestamp);
  commit;
end;
/
exit
