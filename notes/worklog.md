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

Open question: `DBMS_OUTPUT` from the baseline-drop block did not print although
`serveroutput` is on — the count query confirms the drop, but I want to understand why.
