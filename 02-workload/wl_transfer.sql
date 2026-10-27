-- "Transfer" workload: debit one account, credit another, log it, commit. 30 % of transfers touch a
-- hot account (account_id multiple of 100). Locks the two accounts in random order, like a naive app.
-- Deadlocks (ORA-00060) are caught, rolled back and counted in WL_RUNS.ERRORS.
-- Writes to BANK.TRANSFER_LOG, not TRANSACTIONS, so the BANKDB checksums stay valid.
-- usage: sqlplus / as sysdba @wl_transfer.sql <pdb_name>
whenever sqlerror exit failure
set verify off
alter session set container = &1;

alter table bank.wl_runs add (errors number);

create table bank.transfer_log (
  log_id      number generated always as identity,
  from_acct   number not null,
  to_acct     number not null,
  amount      number(18,2) not null,
  created     timestamp default systimestamp not null
);

create or replace procedure bank.wl_transfer(p_tag varchar2, p_seconds number) is
  l_start  timestamp := systimestamp;
  l_end    timestamp := systimestamp + numtodsinterval(p_seconds, 'SECOND');
  l_max    number;
  l_from   number; l_to number; l_amt number;
  l_execs  pls_integer := 0;
  l_dead   pls_integer := 0;
  e_deadlock exception;
  pragma exception_init(e_deadlock, -60);
  function pick return number is
  begin
    if dbms_random.value < 0.3 then
      return trunc(dbms_random.value(1, l_max / 100 + 1)) * 100;      -- hot account
    end if;
    return trunc(dbms_random.value(1, l_max + 1));
  end;
begin
  dbms_application_info.set_module('BANK_APP', 'TRANSFER');
  select max(account_id) into l_max from bank.accounts;
  while systimestamp < l_end loop
    l_from := pick; l_to := pick;
    if l_from != l_to then
      l_amt := round(dbms_random.value(10000, 5000000), -3);
      begin
        update bank.accounts set balance = balance - l_amt where account_id = l_from;
        update bank.accounts set balance = balance + l_amt where account_id = l_to;
        insert into bank.transfer_log (from_acct, to_acct, amount) values (l_from, l_to, l_amt);
        commit;
        l_execs := l_execs + 1;
      exception
        when e_deadlock then rollback; l_dead := l_dead + 1;
      end;
    end if;
  end loop;
  insert into bank.wl_runs (run_tag, sid, execs, rows_fetched, started, ended, errors)
  values (p_tag, sys_context('userenv', 'sid'), l_execs, l_execs, l_start, systimestamp, l_dead);
  commit;
end;
/
exit
