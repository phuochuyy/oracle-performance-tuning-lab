-- "Annual report": 2025 POSTED transactions per region and product (4-table join, ~4 M rows).
-- One procedure per degree of parallelism so each DOP has its own SQL text / sql_id in AWR.
-- Every execution also records the result checksum, to prove serial and parallel agree.
-- usage: sqlplus / as sysdba @wl_annual.sql <pdb_name>
whenever sqlerror exit failure
set verify off
alter session set container = &1;

create table bank.wl_results (run_tag varchar2(40), dop number, rows_out number, total number, cnt number, elapsed_cs number);

create or replace procedure bank.wl_annual(p_tag varchar2, p_seconds number, p_dop pls_integer) is
  l_end   timestamp := systimestamp + numtodsinterval(p_seconds, 'SECOND');
  l_start timestamp := systimestamp;
  l_hint  varchar2(30) := case when p_dop > 1 then 'parallel(' || p_dop || ')' else 'no_parallel' end;
  l_sql   varchar2(1000);
  l_cur   sys_refcursor;
  l_reg   varchar2(10); l_prod varchar2(10); l_cnt number; l_sum number;
  l_rows  pls_integer; l_tot number; l_tcnt number; l_t0 pls_integer;
  l_execs pls_integer := 0;
begin
  dbms_application_info.set_module('BANK_APP', 'ANNUAL_REPORT_DOP' || p_dop);
  l_sql := 'select /*+ ' || l_hint || ' */ b.region, a.product, count(*), sum(t.amount)'
        || ' from bank.transactions t'
        || ' join bank.accounts a on a.account_id = t.account_id'
        || ' join bank.customers c on c.customer_id = a.customer_id'
        || ' join bank.branches b on b.branch_id = c.branch_id'
        || ' where t.txn_ts >= timestamp ''2025-01-01 00:00:00'' and t.txn_ts < timestamp ''2026-01-01 00:00:00'''
        || ' and t.status = ''POSTED'''
        || ' group by b.region, a.product';
  while systimestamp < l_end loop
    l_t0 := dbms_utility.get_time; l_rows := 0; l_tot := 0; l_tcnt := 0;
    open l_cur for l_sql;
    loop
      fetch l_cur into l_reg, l_prod, l_cnt, l_sum;
      exit when l_cur%notfound;
      l_rows := l_rows + 1; l_tot := l_tot + l_sum; l_tcnt := l_tcnt + l_cnt;
    end loop;
    close l_cur;
    insert into bank.wl_results values (p_tag, p_dop, l_rows, l_tot, l_tcnt, dbms_utility.get_time - l_t0);
    commit;
    l_execs := l_execs + 1;
  end loop;
  insert into bank.wl_runs values (p_tag, sys_context('userenv', 'sid'), l_execs, l_execs, l_start, systimestamp);
  commit;
end;
/
create or replace procedure bank.wl_annual_serial(p_tag varchar2, p_seconds number) is
begin bank.wl_annual(p_tag, p_seconds, 1); end;
/
create or replace procedure bank.wl_annual_dop2(p_tag varchar2, p_seconds number) is
begin bank.wl_annual(p_tag, p_seconds, 2); end;
/
create or replace procedure bank.wl_annual_dop4(p_tag varchar2, p_seconds number) is
begin bank.wl_annual(p_tag, p_seconds, 4); end;
/
exit
