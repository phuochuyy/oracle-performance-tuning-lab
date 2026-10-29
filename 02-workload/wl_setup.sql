-- Workload objects in the BANK schema.
-- usage: sqlplus / as sysdba @wl_setup.sql <pdb_name>
whenever sqlerror exit failure
set verify off
alter session set container = &1;

-- inserts into WL_RUNS name their columns: case 3 adds ERRORS (wl_transfer.sql), and the positional
-- INSERTs of the older procedures then failed to compile (ORA-00947) — found months later by a health check
create table bank.wl_runs (
  run_tag       varchar2(100),
  sid           number,
  execs         number,
  rows_fetched  number,
  started       timestamp,
  ended         timestamp
);

-- "Account statement": last 50 transactions of a random account since 2025-10-01.
-- Static SQL in PL/SQL, so the account id is a bind variable like in a real app.
create or replace procedure bank.wl_statement(p_tag varchar2, p_seconds number) is
  l_start  timestamp := systimestamp;
  l_end    timestamp := systimestamp + numtodsinterval(p_seconds, 'SECOND');
  l_max    number;
  l_acct   number;
  l_execs  pls_integer := 0;
  l_rows   pls_integer := 0;
begin
  dbms_application_info.set_module('BANK_APP', 'STATEMENT');
  select max(account_id) into l_max from bank.accounts;
  while systimestamp < l_end loop
    l_acct := trunc(dbms_random.value(1, l_max + 1));
    for r in (select txn_ts, txn_type, amount, status
                from bank.transactions
               where account_id = l_acct
                 and txn_ts >= timestamp '2025-10-01 00:00:00'
               order by txn_ts desc
               fetch first 50 rows only) loop
      l_rows := l_rows + 1;
    end loop;
    l_execs := l_execs + 1;
  end loop;
  insert into bank.wl_runs (run_tag, sid, execs, rows_fetched, started, ended) values (p_tag, sys_context('userenv', 'sid'), l_execs, l_rows, l_start, systimestamp);
  commit;
end;
/
exit
