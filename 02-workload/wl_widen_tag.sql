-- RUN_TAG was 40 chars; "03-row-lock-contention/2-batch-one-transaction" is 46 -> ORA-12899 at the end of the
-- workload (the run itself was fine, only the result row failed). Widen it in both result tables.
-- usage: sqlplus / as sysdba @wl_widen_tag.sql <pdb_name>
whenever sqlerror exit failure
set verify off
alter session set container = &1;
alter table bank.wl_runs modify (run_tag varchar2(100));
alter table bank.wl_results modify (run_tag varchar2(100));
exit
