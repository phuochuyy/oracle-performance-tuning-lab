215187.1 SQLT XTRACT 23.1.240824 Report: sqlt_s76702_readme.txt

Instructions to perform the following:

o Export SQLT repository
o Import SQLT repository
o Using SQLT COMPARE
o Restore CBO schema statistics
o Restore CBO system statistics
o Implement SQLT Test Case (TC)
o Create TC with no SQLT dependencies
o Restore SQL Set
o Create SQL Plan Baseline from SQL Set
o Gather CBO statistics without Histograms (using SYS.DBMS_STATS)
o Gather CBO statistics with Histograms (using SYS.DBMS_STATS)
o List generated files

********************************************************************************

Export SQLT repository
~~~~~~~~~~~~~~~~~~~~~~

Steps:
~~~~~

1. Unzip sqlt_s76702_driver.zip in order to get sqlt_s76702_export_parfile.txt.

2. Copy sqlt_s76702_export_parfile.txt to SOURCE server (TEXT).

3. Execute export on server:

exp sqltxplain@//PRM3.RAC:1521/PERF.RAC parfile=sqlt_s76702_export_parfile.txt


********************************************************************************

Import SQLT repository
~~~~~~~~~~~~~~~~~~~~~~

Steps:
~~~~~
1. Unzip sqlt_s76702_tc.zip in order to get sqlt_s76702_expdp.dmp.

2. Copy sqlt_s76702_exp.dmp to the server (BINARY).

3. Execute import on server:

imp sqltxplain FILE=sqlt_s76702_exp.dmp TABLES=sqlt% IGNORE=Y

Notes:
~~~~~
You can execute sqlt_s76702_import.sh instead.

********************************************************************************

Using SQLT COMPARE
~~~~~~~~~~~~~~~~~~

You need to have a set of SQLT files (sqlt_sNNNNN_method.zip) from two
executions of the SQLT tool. They can be from any method (XTRACT, XECUTE or
XPLAIN) and they can be from the same or different systems. They do not have to
be from same release or platform. For example, a SQLT from 10g on Linux and a
SQLT from 11g on Unix can be compared.

To use the COMPARE method you need 3 systems: SOURCE1, SOURCE2 and COMPARE.
The 3 could all be different, or all the same. For example, SOURCE1 could be
PROD, SOURCE2 DEV and COMPARE DEV. In other words, you could do the COMPARE in
one of the sources. Or the COMPARE could be done on a 3rd and remote system.

Basically you need to restore the SQLT repository from both SOURCES into the
COMPARE system. In most cases it means "restoring" the SQLT repository from at
least one SOURCE into the COMPARE. Once you have both SQLT repositories into the
COMPARE system, then you can execute this method.

Steps:
~~~~~

1. Unzip sqlt_s76702_tc.zip from this SOURCE in order to get sqlt_s76702_expdp.dmp.

2. Copy sqlt_s76702_exp.dmp to the server (BINARY).

3. Execute import on server:

imp sqltxplain FILE=sqlt_s76702_exp.dmp TABLES=sqlt% IGNORE=Y

4. Perform the equivalent steps for the 2nd SOURCE if needed. Follow its readme.

5. Execute the COMPARE method connecting into SQL*Plus as SYS.

START sqlt/run/sqltcompare.sql

********************************************************************************

Restore CBO schema statistics
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

CBO schema object statistics can be restored from the local SQLT repository, or
from an imported repository. Restoring CBO statistics associates them to
existing and compatible schema objects. These objects can be owned by the
original schema owner or by a different one. For example, table T is owned by
user U in SOURCE and by user TC76702 in TARGET.

When using restore script below, the second parameter allows to remap the schema
object statistics to a different user. Be aware that target user and schema
objects must exist before executing this script. To restore CBO schema object
statistics into the original schema owner(s) pass "null" (or just hit the
"Enter" key) when the second parameter is requested.

Steps:
~~~~~

1. Execute restore script connecting as SYSDBA:

START sqlt/utl/sqltimp.sql s76702_orcl3_prm3 TC76702

********************************************************************************

Restore CBO system statistics
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Steps:
~~~~~

1. Execute restore script connecting as SYSDBA:

START sqlt_s76702_system_stats.sql

********************************************************************************

Implement SQLT Test Case (TC)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

SOURCE and TARGET systems should be similar.
Proceed with Preparation followed by Express or Custom mode.

Preparation:
~~~~~~~~~~~

1. Unzip sqlt_s76702_tc.zip in server and navigate to TC directory.

unzip sqlt_s76702_tc.zip -d TC76702
cd TC76702

Express (XPRESS) mode:
~~~~~~~~~~~~~~~~~~~~~

1. Review and execute xpress.sh from OS or xpress.sql from sqlplus.

Option 1: ./xpress.sh

Option 2: sqlplus / as sysdba @xpress.sql


Custom mode:
~~~~~~~~~~~

1. Create test case user and schema objects connecting as SYSDBA:

sqlplus / as sysdba
START sqlt_s76702_metadata.sql

2. Purge pre-existing s76702 from local SQLT repository connected as SYSDBA:

START sqlt_s76702_purge.sql

3. Import SQLT repository for s76702 (provide SQLTXPLAIN password):

HOS imp sqltxplain FILE=sqlt_s76702_exp.dmp LOG=sqlt_s76702_imp.log TABLES=sqlt% IGNORE=Y

4. Restore CBO schema statistics for test case user connected as SYSDBA:

START sqlt_s76702_restore.sql

5. Restore CBO system statistics connected as SYSDBA:

START sqlt_s76702_system_stats.sql

6. Set the CBO environment connecting as test case user TC76702
   (include optional test case user suffix):

CONN TC76702/TC76702
START sqlt_s76702_set_cbo_env.sql

7. Execute test case.

START tc.sql


********************************************************************************

Create TC with no SQLT dependencies
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

After creating a local test case using SQLT files, you can create a stand-alone
TC with no dependencies on SQLT.

Steps:
~~~~~
1. Export TC schema object statistics to staging table within TC schema:

DELETE TC76702.CBO_STAT_TAB_4TC;
EXEC SYS.DBMS_STATS.EXPORT_SCHEMA_STATS(ownname => 'TC76702', stattab => 'CBO_STAT_TAB_4TC');
2. Export TC schema object statistics from staging table:

HOS exp TC76702/TC76702 FILE=cbo_stat_tab_4tc.dmp LOG=cbo_stat_tab_4tc.log TABLES=cbo_stat_tab_4tc STATISTICS=NONE

3. Review setup.sql script and adjust if needed.

4. Review readme.txt file and adjust if needed.

5. Create and zip a new directory with the following files:

CBO schema object statistics dump: cbo_stat_tab_4tc.dmp
Plan script:                       plan.sql
Query script:                      q.sql
Instructions:                      readme.txt
Setup script:                      setup.sql
Metadata script:                   sqlt_s76702_metadata.sql
OPatch (if needed):                sqlt_s76702_opatch.zip
Set CBO env script (if needed):    sqlt_s76702_set_cbo_env.sql
System statistics setup:           sqlt_s76702_system_stats.sql
Test case script:                  tc.sql

6. Test your new stand-alone TC following your own readme.txt in another system.

Note: You may want to use tc_pkg.sql to execute commands above.

********************************************************************************

Restore SQL Set
~~~~~~~~~~~~~~~

SOURCE and TARGET systems should be similar.

SQLT exported from SOURCE at least one SQL Set with a plan associated to your
query. The SQL Set name below includes the plan hash value and its source
(memory or awr).

You can copy a SQL Set into your TARGET system following these steps. After a
SQL Set with one plan is restored, you can proceed to load it as a SQL Plan into
its SQL Baseline.

Steps:
~~~~~

1. Import SQLT repository (only if you haven't done so as part of another operation like TC creation)

imp sqltxplain FILE=sqlt_s76702_exp.dmp TABLES=sqlt% IGNORE=Y

2. Copy one SQL Set by following corresponding syntaxt below.

-- 002 s76702_orcl3_prm3_8wx3gpt1vwa72_3125427224_awr (et:0.010s, cpu:0.005s, buffers:6204, rows:1)
BEGIN
  SYS.DBMS_SQLTUNE.UNPACK_STGTAB_SQLSET (
    sqlset_name          => 's76702_3125427224_awr',
    sqlset_owner         => 'SQLTXADMIN',
    replace              => TRUE,
    staging_table_name   => 'SQLT$_STGTAB_SQLSET',
    staging_schema_owner => 'SQLTXPLAIN' );
END;
/

********************************************************************************

Create SQL Plan Baseline from SQL Set
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

You can load one SQL Plan into its SQL Plan Baseline from a SQL Set created by
SQLT for each plan found in memory or AWR.

This method only works on the same system where SQLT was executed. Unless you
first restore a SQL Set from a different source.

The SQL Set name below includes the plan hash value and its source
(memory or awr). You can load one or more plans into a SQL Plan Baseline.

-- 002 s76702_orcl3_prm3_8wx3gpt1vwa72_3125427224_awr (et:0.010s, cpu:0.005s, buffers:6204, rows:1)
SET SERVEROUT ON;
DECLARE
  x NUMBER;
  time DATE := SYSDATE;
  l_planame sys.dba_sql_plan_baselines.plan_name%TYPE;
  l_sql_handle sys.dba_sql_plan_baselines.sql_handle%TYPE;
BEGIN
  DBMS_LOCK.SLEEP(5);
  x := SYS.DBMS_SPM.LOAD_PLANS_FROM_SQLSET (
    sqlset_name  => 's76702_3125427224_awr',
    sqlset_owner => 'SQLTXADMIN' );
  SYS.DBMS_OUTPUT.PUT_LINE('Plans: '||x);
  IF x = 1 THEN
    SELECT plan_name, sql_handle
      INTO l_planame, l_sql_handle
      FROM sys.dba_sql_plan_baselines
     WHERE signature = 3040525825808326550
       AND created >= time;
    x := DBMS_SPM.ALTER_SQL_PLAN_BASELINE (
      sql_handle      => l_sql_handle,
      plan_name       => l_planame,
      attribute_name  => 'DESCRIPTION',
      attribute_value => TRIM('002 s76702_orcl3_prm3_8wx3gpt1vwa72_3125427224_awr (et:0.010s, cpu:0.005s, buffers:6204, rows:1)') );
    x := DBMS_SPM.ALTER_SQL_PLAN_BASELINE (
      sql_handle      => l_sql_handle,
      plan_name       => l_planame,
      attribute_name  => 'PLAN_NAME',
      attribute_value => UPPER('s76702_3125427224_awr') );
    SYS.DBMS_OUTPUT.PUT_LINE('Renamed: '||x||' '||UPPER('s76702_3125427224_awr'));
  END IF;
END;
/
SET SERVEROUT OFF;
********************************************************************************

Gather CBO statistics without Histograms (using SYS.DBMS_STATS)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Use commands below to generate a fresh set of CBO statistics for the schema
objects accessed by your SQL. Histograms will be dropped.

BEGIN -- generated by SQLT
  SYS.DBMS_STATS.UNLOCK_TABLE_STATS (
    ownname       => '"BANK"',
    tabname       => '"TRANSACTIONS"'
  );
  SYS.DBMS_STATS.GATHER_TABLE_STATS (
    ownname          => '"BANK"',
    tabname          => '"TRANSACTIONS"',
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
    method_opt       => 'FOR ALL COLUMNS SIZE 1',
    granularity      => 'GLOBAL AND PARTITION',
    cascade          => TRUE,
    no_invalidate    => FALSE
  );
END;
/

********************************************************************************

Gather CBO statistics with Histograms (using SYS.DBMS_STATS)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Use commands below to generate a fresh set of CBO statistics for the schema
objects accessed by your SQL. Histograms will be generated for some columns.

BEGIN -- generated by SQLT
  SYS.DBMS_STATS.UNLOCK_TABLE_STATS (
    ownname       => '"BANK"',
    tabname       => '"TRANSACTIONS"'
  );
  SYS.DBMS_STATS.GATHER_TABLE_STATS (
    ownname          => '"BANK"',
    tabname          => '"TRANSACTIONS"',
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
    method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
    granularity      => 'GLOBAL AND PARTITION',
    cascade          => TRUE,
    no_invalidate    => FALSE
  );
END;
/

********************************************************************************

List generated files
~~~~~~~~~~~~~~~~~~~~

Files generated under current SQL*Plus directory.
Not all files may be available.

sqlt_s76702_main.html
sqlt_s76702_metadata.sql
sqlt_s76702_metadata1.sql
sqlt_s76702_metadata2.sql
sqlt_s76702_system_stats.sql
sqlt_s76702_schema_stats.sql
sqlt_s76702_set_cbo_env.sql
sqlt_s76702_lite.html
sqlt_s76702_readme.txt
sqlt_s76702_readme.html
sqlt_s76702_tc_script.sql
sqlt_s76702_tc_sql.sql
sqlt_s76702_xpand_sql_driver.sql
sqlt_s76702_tcb.zip
sqlt_s76702_remote_driver.sql
sqlt_s76702_tkprof_px_driver.sql
sqlt_s76702_export_parfile.txt
sqlt_s76702_export_parfile2.txt
sqlt_s76702_export_driver.sql
sqlt_s76702_import.sh
sqlt_s76702_export.zip
sqlt_s76702_tc.zip
sqlt_s76702_log.zip
sqlt_s76702_opatch.zip
sqlt_s76702_remote.zip
sqlt_s76702_sql_detail_active.html
sqlt_s76702_10053_explain.trc
sqlt_s76702_xtract.log
sqltxtract.log
sqltxhost.log
plan.sql
10053.sql
flush.sql
purge.sql
restore.sql
del_hgrm.sql
tc.sql
tc_pkg.sql
xpress.sql
xpress.sh
setup.sql
q.sql
sel.sql
sel_aux.sql
install.sql
install.sh
tcx_pkg.sql

Files generated under SQLT$UDUMP directory.
ORCL3_ora_73499_s76702_10053.trc

Files generated under SQLT$BDUMP directory.
*_s76702_*.trc

Files generated under SQLT$STAGE directory.
sqlt_s76702_tcb_*
README.txt

Notes:
~~~~~
To locate SQLT$UDUMP:
SELECT directory_path FROM sys.dba_directories WHERE directory_name = 'SQLT$UDUMP';

To locate SQLT$BDUMP:
SELECT directory_path FROM sys.dba_directories WHERE directory_name = 'SQLT$BDUMP';

To locate SQLT$STAGE:
SELECT directory_path FROM sys.dba_directories WHERE directory_name = 'SQLT$STAGE';

Not all files may be available.

********************************************************************************

215187.1 sqlt_s76702_readme.txt 2026-10-29/16:44:11
