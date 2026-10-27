-- Case 2 immediate fix: pin the known-good plan with a SQL plan baseline loaded from AWR.
-- usage: sqlplus / as sysdba @fix_spm.sql <pdb_name> <begin_snap> <end_snap> <sql_id> <good_plan_hash>
-- SPM is part of Enterprise Edition (no Tuning Pack needed, unlike SQL Profiles).
whenever sqlerror exit failure
set verify off lines 200
col sql_handle for a22
col plan_name for a32
-- AWR snapshots are taken in CDB$ROOT; from inside the PDB DBMS_SPM looks in the PDB's own AWR
-- and fails with ORA-13769 'Snapshots do not exist' -> pass the CDB dbid explicitly.
column dbid new_value cdb_dbid noprint
select dbid from v$database;
alter session set container = &1;
var n number
exec :n := dbms_spm.load_plans_from_awr(begin_snap => &2, end_snap => &3, basic_filter => q'[sql_id = '&4' and plan_hash_value = &5]', fixed => 'YES', enabled => 'YES', dbid => &cdb_dbid)
print n
select sql_handle, plan_name, enabled, accepted, fixed, origin from dba_sql_plan_baselines;
exit
