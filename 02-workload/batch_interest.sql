-- Month-end interest batch on the hot accounts (account_id multiple of 100), in account_id order.
-- p_commit_every = 0 : one transaction for all rows, then waits p_hold_seconds before COMMIT
--                      (stands in for a slow batch that does more work before committing)
-- p_commit_every = n : commit every n rows, no hold
-- usage: sqlplus / as sysdba @batch_interest.sql <pdb_name>
whenever sqlerror exit failure
set verify off
alter session set container = &1;
create or replace procedure bank.batch_interest(p_commit_every pls_integer, p_hold_seconds number) is
  l_n pls_integer := 0;
begin
  dbms_application_info.set_module('BANK_BATCH', 'INTEREST');
  for r in (select account_id from bank.accounts where mod(account_id, 100) = 0 order by account_id) loop
    update bank.accounts set balance = round(balance * 1.001, 2) where account_id = r.account_id;
    l_n := l_n + 1;
    if p_commit_every > 0 and mod(l_n, p_commit_every) = 0 then commit; end if;
  end loop;
  if p_commit_every = 0 then dbms_session.sleep(p_hold_seconds); end if;
  commit;
end;
/
exit
