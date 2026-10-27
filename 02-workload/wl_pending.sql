-- "Pending review" workload: count/sum of PENDING (and sometimes REVERSED) transactions in
-- December 2025. Both statuses are rare (2 % / 1 %), so an index on (status, txn_ts) is the
-- right plan — but only if the optimizer knows the column is skewed (histogram).
-- usage: sqlplus / as sysdba @wl_pending.sql <pdb_name>
whenever sqlerror exit failure
set verify off
alter session set container = &1;

create or replace procedure bank.wl_pending(p_tag varchar2, p_seconds number) is
  l_start  timestamp := systimestamp;
  l_end    timestamp := systimestamp + numtodsinterval(p_seconds, 'SECOND');
  l_status varchar2(10);
  l_cnt    number;
  l_sum    number;
  l_execs  pls_integer := 0;
begin
  dbms_application_info.set_module('BANK_APP', 'PENDING_REVIEW');
  while systimestamp < l_end loop
    l_status := case when mod(l_execs, 10) = 9 then 'REVERSED' else 'PENDING' end;
    select count(*), sum(amount) into l_cnt, l_sum
      from bank.transactions
     where status = l_status
       and txn_ts >= timestamp '2025-12-01 00:00:00';
    l_execs := l_execs + 1;
  end loop;
  insert into bank.wl_runs values (p_tag, sys_context('userenv', 'sid'), l_execs, l_execs, l_start, systimestamp);
  commit;
end;
/
exit
