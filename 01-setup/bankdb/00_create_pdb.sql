-- Create the PERF pluggable database for the tuning lab.
-- usage: sqlplus / as sysdba @00_create_pdb.sql <pdbadmin_password>
--
-- STANDBYS=NONE: PERF is a sandbox for performance tests, it does not need to be
-- protected by Data Guard, and the standby should not carry its test data.
whenever sqlerror exit failure
set echo on

create pluggable database perf
  admin user pdbadmin identified by "&1"
  create_file_dest = '/u02/oradata/ORCL3'
  standbys = none;

alter pluggable database perf open;
alter pluggable database perf save state;

select name, open_mode from v$pdbs where name = 'PERF';
exit
