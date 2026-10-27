-- Take an AWR snapshot (CDB root) and print its id.
-- usage: sqlplus -s / as sysdba @awr_snap.sql
-- Note: AWR/ASH/ADDM need the Diagnostics Pack license outside a lab.
set heading off feedback off pages 0 verify off
var s number
exec :s := dbms_workload_repository.create_snapshot
print s
exit
