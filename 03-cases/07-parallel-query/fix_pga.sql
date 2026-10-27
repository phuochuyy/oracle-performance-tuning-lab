-- Case 7 fix: PGA_AGGREGATE_TARGET is far below the PGA the instance really uses.
-- Evidence (V$PGASTAT, CDB level): target 446 MB, in use 904 MB, allocated 1,227 MB (max 1,440 MB),
-- auto target collapsed to 28 MB, over allocation count 5,259 -> work areas starved, PX hash joins
-- spill to TEMP at random. V$PGA_TARGET_ADVICE: over-allocation reaches 0 at 1,338 MB.
-- pga_aggregate_limit is not set explicitly -> defaults to max(2 GB, 2 x target).
-- usage: sqlplus / as sysdba @fix_pga.sql
whenever sqlerror exit failure
alter system set pga_aggregate_target = 1400M scope = both;
select name, round(value / 1048576) mb from v$pgastat
 where con_id = 0 and name in ('aggregate PGA target parameter', 'aggregate PGA auto target', 'global memory bound');
show parameter pga_aggregate_limit
exit
