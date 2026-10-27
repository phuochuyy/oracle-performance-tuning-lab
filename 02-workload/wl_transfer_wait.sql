-- Same transfer as wl_transfer, but COMMIT WRITE WAIT: PL/SQL normally does not wait for the redo
-- write on a COMMIT inside a loop (case 3 saw 92 'log file sync' waits for ~888 K commits). WRITE WAIT
-- makes every commit wait like a client commit, so 'log file sync' measures real commit latency.
-- No hot accounts: this case is about redo/commit, not locks.
-- usage: sqlplus / as sysdba @wl_transfer_wait.sql <pdb_name>
whenever sqlerror exit failure
set verify off
alter session set container = &1;
create or replace procedure bank.wl_transfer_wait(p_tag varchar2, p_seconds number) is
  l_start  timestamp := systimestamp;
  l_end    timestamp := systimestamp + numtodsinterval(p_seconds, 'SECOND');
  l_max    number;
  l_from   number; l_to number; l_amt number;
  l_execs  pls_integer := 0;
begin
  dbms_application_info.set_module('BANK_APP', 'TRANSFER_WAIT');
  select max(account_id) into l_max from bank.accounts;
  while systimestamp < l_end loop
    l_from := trunc(dbms_random.value(1, l_max + 1));
    l_to   := trunc(dbms_random.value(1, l_max + 1));
    if l_from != l_to then
      l_amt := round(dbms_random.value(10000, 5000000), -3);
      update bank.accounts set balance = balance - l_amt where account_id = l_from;
      update bank.accounts set balance = balance + l_amt where account_id = l_to;
      insert into bank.transfer_log (from_acct, to_acct, amount) values (l_from, l_to, l_amt);
      commit write wait;
      l_execs := l_execs + 1;
    end if;
  end loop;
  insert into bank.wl_runs (run_tag, sid, execs, rows_fetched, started, ended, errors)
  values (p_tag, sys_context('userenv', 'sid'), l_execs, l_execs, l_start, systimestamp, 0);
  commit;
end;
/
exit
