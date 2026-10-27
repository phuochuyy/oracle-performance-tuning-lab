-- Is sequence refilling really expensive here? Count dc_sequences row-cache modifications for
-- 10,000 NEXTVAL with CACHE 20 and CACHE 10000 (run as SYSDBA). Result on 23ai: +4 vs +1.
set serveroutput on lines 150 feedback off
alter session set container=PERF;
set serveroutput on
create sequence bank.zz_seq_test cache 20;
declare
  m0 number; m1 number; n number; t0 pls_integer;
  function mods return number is r number; begin select sum(modifications) into r from v$rowcache where parameter = 'dc_sequences'; return r; end;
begin
  m0 := mods; t0 := dbms_utility.get_time;
  for i in 1 .. 10000 loop n := bank.zz_seq_test.nextval; end loop;
  m1 := mods;
  dbms_output.put_line('cache 20   : 10000 nextval, dc_sequences modifications +' || (m1 - m0) || ', ' || (dbms_utility.get_time - t0) * 10 || ' ms');
  execute immediate 'alter sequence bank.zz_seq_test cache 10000';
  m0 := mods; t0 := dbms_utility.get_time;
  for i in 1 .. 10000 loop n := bank.zz_seq_test.nextval; end loop;
  m1 := mods;
  dbms_output.put_line('cache 10000: 10000 nextval, dc_sequences modifications +' || (m1 - m0) || ', ' || (dbms_utility.get_time - t0) * 10 || ' ms');
end;
/
drop sequence bank.zz_seq_test;
exit
