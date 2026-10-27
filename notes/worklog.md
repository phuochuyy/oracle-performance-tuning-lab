# Worklog

What I did, what went wrong, how I fixed it. Newest at the bottom.

## Dataset (branch `feature/bankdb-dataset`)

**Before loading — checked the target CDB (orcl3 on prm3):**

- `FORCE LOGGING = YES` (Data Guard) and `FLASHBACK ON` → direct-path/NOLOGGING does not avoid
  redo; every GB loaded becomes archived log + flashback log in the FRA.
- FRA was 10 GB with 4 GB used and almost nothing reclaimable (archived logs: 0% reclaimable,
  `ARCHIVELOG DELETION POLICY TO NONE`). A multi-GB load could fill it → `ORA-00257` and the
  database stops. Raised `db_recovery_file_dest_size` to 16 GB (the `/u02` disk had 30 GB free).
- Created the PDB with `STANDBYS=NONE`: it is a test sandbox, the standby does not need its data.

**Smoke test at scale 1:** loaded in ~7 s, distributions match the design (segments 85/12/3 %,
status 97/2/1 %, 30.7 % of rows on hot accounts), 0 Luhn failures, 0 orphan rows.

**Problem 1 — checksums were useless.** `03_verify.sql` printed `1.0745E+15`: SQL*Plus default
number format keeps ~5 significant digits, so two different datasets could print the same value.
Fix: `col checksum for 99999999999999999999`.

**Problem 2 — my determinism test passed when it should not have.** I compared two verify runs
with `grep "^[A-Z]+ +[0-9]"` and `diff` said IDENTICAL — but both files were empty: SQL*Plus
separates columns with tabs, not spaces. Fixed the pattern (`[[:space:]]+`) and added a check that
the file is not empty. Lesson: check that a test can fail before trusting a pass.
Real result: two loads at scale 1 → identical counts and checksums for all 5 tables.

**Reload:** truncating a parent table fails with `ORA-02266` while an enabled FK points to it, even
when the child is empty → `04_reset.sql` disables the FKs, truncates, re-enables.

**Scale 16 load:** 8 M transactions in 3 min 43 s. While it ran, the session waited on
`Data file init write` — the tablespace autoextending 256 MB at a time. A bigger `NEXT` (or
pre-sizing the datafile) would remove that wait; noted for the tuning cases. FRA 4.4 → 5.8 GB,
well under the new 16 GB limit. `TRANSACTIONS` = 736 MB, about the size of the buffer cache, so
full scans will do real physical reads.

## Case 1 — missing index (branch `case/01-missing-index`)

**Problem 3 — runner died silently.** `run_workload.sh` used `set -eu` and then sourced
`~/.bash_profile`; `/etc/bashrc` reads an unset variable (`BASHRCSOURCED`) so `set -u` killed the
script, and the error was hidden by `2>/dev/null`. Fix: source the profile before `set -eu`.

**Problem 4 — empty execution plan in the baseline evidence.** I committed `plan.txt` with no plan:
the runner read the plan from `V$SQL` after the run, but the cursor was already gone — shared pool
had ~81 MB free and even the workload's own INSERT showed `LOADS=3`, i.e. cursors age out quickly
on this VM. Fix: read plans from AWR (`DBMS_XPLAN.DISPLAY_WORKLOAD_REPOSITORY`) for the snapshot
range — the first call failed with ORA-01722 because I passed the arguments in the wrong order
(`format` comes before `dbid`); named parameters fixed it. Regenerated the baseline plan from AWR.
Lesson: open the evidence files before committing them.

## Case 2 — plan regression / SPM (branch `case/02-plan-regression-spm`)

**Problem 5 — evidence copied to the wrong folder.** `scp -r host:.../1-good 04-reports/02-.../`
when the local case folder did not exist yet created the folder and put the *files* in it, not a
`1-good/` subfolder. My `&&` chain then failed on `git add`, so the regression step did not run
(good — nothing ran half-done). Moved the files, and added `05-scripts/fetch_reports.sh` that
always `mkdir -p`s the target first.

**Problem 6 — ORA-13769 loading a plan from AWR inside the PDB.** Snapshots live in CDB$ROOT;
from the PDB, `DBMS_SPM.LOAD_PLANS_FROM_AWR` searches the PDB's AWR. Passing the CDB `dbid`
worked. On the way I also wrote two sloppy test queries (ambiguous column `NAME` joining
`V$DATABASE` and `V$PDBS`; a sub-query as a PL/SQL argument) — fixed before retrying.

**Result:** good 389/s → regressed 6.85/s → SPM 420/s (stats still bad) → stats restored and
baseline dropped 373/s.

**Problem 7 — `DBMS_OUTPUT` printed nothing** in `fix_stats.sql` although `serveroutput` was on.
Test: `set serveroutput on` in root → print works; `alter session set container=PERF` → print is
silent; `set serveroutput on` again → print works. Package state is per container, so DBMS_OUTPUT
must be enabled after the switch. Moved `set serveroutput on` below the `alter session`.
(Two failed attempts first: SQL*Plus read `: in` inside `exec` as a bind variable, then my
single quotes were eaten by the outer `ssh '...'` — wrote the test as a file and copied it.)

## FRA housekeeping before case 5

FRA on orcl3 reached 7.4 / 16 GB with only 55 MB reclaimable: the standby `ORCL3_STB` had been
down for days and `ARCHIVELOG DELETION POLICY` was `NONE`. Started Region B again (`labctl.sh dg-b`)
so the standby caught up (transport/apply lag 0 s), then set
`CONFIGURE ARCHIVELOG DELETION POLICY TO APPLIED ON ALL STANDBY`. Reclaimable went 55 MB → 3,755 MB
(archived logs 22 % reclaimable). The FRA now frees applied logs by itself when it needs space.
Note: with policy `NONE` and no backups, archived logs are never reclaimable — catching up the
standby alone would not have helped.

## Case 5 — partitioning (branch `case/05-partitioning`)

**Problem 8 — ORA-01418 on the online conversion.** `UPDATE INDEXES (transactions_pk GLOBAL, ...)`
resolves unqualified index names in the current schema — SYS, because I run as SYSDBA. The statement
failed at parse time (nothing changed). Fix: `alter session set current_schema = BANK`.

**Problem 9 — a regression I almost missed, and a baseline I did miss.** After partitioning I
re-ran the other workloads on purpose: the statement query was fine, but the pending query went
from index to a full scan of the December partition and got slower. I had not re-measured that
query in the new environment before the change — lesson: baseline every query a change can touch.
Compared both plans directly (index 3.07 ms vs optimizer's full scan 7.33 ms), then fixed it with a
covering local index (0.58 ms). Kept the old index INVISIBLE until the workload confirmed the fix.

## Incident after case 5 — standby FRA full, FSFO unsynchronized

**Symptom:** Region B broker status `ERROR` — `ORA-16857 member disconnected from redo source`,
`ORA-16817 unsynchronized fast-start failover configuration`. Standby alert log:
`ORA-19809: limit exceeded for recovery files` (stb3 FRA 10,226 / 10,240 MB, 0 reclaimable).
**Cause:** the online partition conversion generated several GB of redo (FORCE LOGGING), and the
standby also had `ARCHIVELOG DELETION POLICY NONE`, so applied logs were never freed.
**Impact:** while it lasted, a failover would not have been zero data loss.
**Fix:** on stb3 `CONFIGURE ARCHIVELOG DELETION POLICY TO APPLIED ON ALL STANDBY` +
`DELETE ARCHIVELOG ALL` (only applied logs are deleted) → 10.2 GB → 2.0 GB; transport reconnected by
itself and the configuration returned to SUCCESS, FSFO target valid again. On prm3 deleted logs
already applied on the standby (logs not yet applied were kept: RMAN-08120), FRA 12.9 → 5.3 GB.
Then `fstrim -a` in prm3 and stb3 (disks use discard=unmap): host free space 23 → 31 GB.

**My mistake while checking:** my wait loop grepped `^SUCCESS` over the output of
`show configuration` + `show database` and stopped on the *database* status line while the
*configuration* was still ERROR. Fixed by grepping only the line after `Configuration Status:`.
Second time today a check of mine passed for the wrong reason.

**Not done on purpose:** `BANK_DATA` has 1.7 GB free inside a 3.3 GB datafile (old table copy),
but the high-water mark is at the end of the file (ORA-03297 on resize). 23ai
`DBMS_SPACE.SHRINK_TABLESPACE` (analyze mode) would move 76 objects / 1.4 GB to reach 1.78 GB — that
move would itself generate ~1.4 GB of redo on both sites under FORCE LOGGING. No real gain now; left
as is.

**Before the next big change:** check FRA on the primary *and* the standby.

## Case 7 — parallel query (branch `case/07-parallel-query`)

**Problem 10 — my "wait until finished" loops never finished.** I waited for the background matrix
with `until ssh prm3 '! pgrep -f run_matrix.sh'`. The remote `bash -c '... run_matrix.sh ...'`
started by ssh contains the pattern itself, so `pgrep -f` always matched its own shell and the loop
spun forever (the matrix itself finished fine). Noticed only when asked why it took so long. Fix:
wait on the matrix log (`grep -c " done "` reaching 5) instead of on process names. Same family of
mistake as problems 2 and the broker-status check: a check that cannot return the other answer.

**Case 7 diagnosis notes.** My first SQL Monitor query looked only at QC rows (0.01 s, 90 gets —
the coordinator does almost nothing) and had `OR ... AND` without brackets; summing QC + PX rows per
`sql_exec_id` showed the real picture. I also repeated the checksum-rounding mistake in
`wl_results.sql` (fixed the same way as `03_verify.sql`). Root cause: PGA target 446 MB vs ~1.2 GB
really used → auto target 28 MB → random hash-join spills. Raised target to 1,400 MB (advisor:
over-allocation 0 from 1,338 MB). Even 4-session serial went 12.4 s → 4.59 s.

## Case 3 — row lock contention (branch `case/03-row-lock-contention`)

**Problem 11 — ORA-12899 at the end of the incident run.** `RUN_TAG VARCHAR2(40)` and the tag
`03-row-lock-contention/2-batch-one-transaction` is 46 characters. The 120 s workload ran, only the
final result insert failed, and `run_workload.sh` stopped (`set -e`) before the ASH step. Widened
the column to 100 (`wl_widen_tag.sql`, and in the create scripts) and re-ran the incident.

**What I learned:** ASH showed *that* SID 330 blocked 4 sessions, but not *what* it was doing — an
idle blocker is not sampled, and it was gone when I queried. The live `v$session` tree at t=40 s
is what showed `BANK_BATCH / INTEREST` sleeping with locks held. Capture the live tree during the
incident; ASH alone is not enough.

**Found on the way (for case 4):** baseline spends 65 % of DB time in `write complete waits`;
redo groups stay ACTIVE; `filesystemio_options = none`, 1 DB writer. And PL/SQL commits inside a
loop do not wait for `log file sync`, so commit latency must be measured from a client.
