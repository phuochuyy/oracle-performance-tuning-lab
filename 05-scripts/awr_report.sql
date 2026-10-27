-- Write an AWR HTML report for a snapshot range.
-- usage: sqlplus -s / as sysdba @awr_report.sql <begin_snap> <end_snap> <outfile.html>
set heading off feedback off pages 0 lines 32767 trimspool on long 2000000 verify off termout off
column output format a32767
spool &3
select output
from table(dbms_workload_repository.awr_report_html(
       (select dbid from v$database), (select instance_number from v$instance), &1, &2));
spool off
exit
