-- Run ADDM for a snapshot range (CDB level) and print the text report.
-- usage: sqlplus -s / as sysdba @addm_report.sql <begin_snap> <end_snap> <task_name>
-- Note: ADDM is part of the Diagnostics Pack license.
set lines 200 pages 0 long 1000000 longchunksize 1000000 verify off trimspool on
var t varchar2(60)
exec :t := '&3'; dbms_addm.analyze_db(:t, &1, &2)
select dbms_addm.get_report(:t) from dual;
exit
