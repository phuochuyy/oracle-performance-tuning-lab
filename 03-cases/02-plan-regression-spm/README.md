# Case 2 — Plan regression after a statistics refresh, fixed with SPM

## Scenario

An operations query counts PENDING (2 % of rows) and REVERSED (1 %) transactions for December 2025:

```sql
select count(*), sum(amount) from bank.transactions
where status = :b1 and txn_ts >= timestamp '2025-12-01 00:00:00';
```

It is fast because of an index on `(status, txn_ts)` **and** a frequency histogram on `STATUS`
that tells the optimizer these values are rare. Then a "routine" statistics refresh with
`METHOD_OPT => 'FOR ALL COLUMNS SIZE 1'` removes all histograms — the same SQL suddenly runs 57×
slower. Workload: `bank.wl_pending`, 4 sessions × 120 s per step.

## Steps and results

| Step | Script | Plan (phv) | Rows estimate | Time / exec | Throughput |
|------|--------|-----------|---------------|-------------|------------|
| 1. Good: index + histogram | [`setup.sql`](setup.sql) | `INDEX RANGE SCAN` (3125427224) | 6,545 | 10.3 ms | 389 /s |
| 2. Regressed: histogram dropped | [`regress.sql`](regress.sql) | `TABLE ACCESS FULL` (4088813652) | 109 K | **583.6 ms** | **6.85 /s** |
| 3. Emergency fix: SPM baseline from AWR, stats still bad | [`fix_spm.sql`](fix_spm.sql) | `INDEX RANGE SCAN` (3125427224) | – | 9.5 ms | 420 /s |
| 4. Root fix: stats restored, baseline dropped | [`fix_stats.sql`](fix_stats.sql) | `INDEX RANGE SCAN` (3125427224) | 6,545 | 10.7 ms | 373 /s |

Same `sql_id` (`8wx3gpt1vwa72`) in every step. Evidence per step in
[`04-reports/02-plan-regression-spm/`](../../04-reports/02-plan-regression-spm/)
(AWR report, top SQL, wait events, plan from AWR).

## Diagnosis

- Top SQL in the regressed window: same `sql_id`, new plan hash, buffer gets per execution
  6,214 → 93,312, physical reads 0 → 93,194; top waits DB CPU 59 % and `direct path read` 40 %.
- Plan comparison (AWR, `DBMS_XPLAN.DISPLAY_WORKLOAD_REPOSITORY`): the cardinality estimate jumped
  from 6,545 to 109 K rows. Without a histogram the optimizer assumes the 3 statuses are equally
  common (1/3 of 8 M rows × the date range), so a full scan looks cheaper than ~110 K index lookups.
- `DBA_TAB_COL_STATISTICS.HISTOGRAM` for `STATUS`: `FREQUENCY` → `NONE`.

## Fix

1. **Stop the bleeding — SQL Plan Management.** Load the good plan for this `sql_id` from the AWR
   snapshots of step 1 as a `FIXED` baseline (`DBMS_SPM.LOAD_PLANS_FROM_AWR`). The optimizer must
   use it even though the statistics are still wrong. SPM is part of Enterprise Edition (no Tuning
   Pack needed).
2. **Fix the cause — statistics history.** `DBMS_STATS.RESTORE_TABLE_STATS` back to the time just
   before the bad refresh (default history retention is 31 days), which brings the histogram back.
3. **Remove the crutch.** Drop the baseline: a fixed baseline would also block better plans later.
   Step 4 shows the optimizer picks the good plan on its own.

## Problems on the way

- `LOAD_PLANS_FROM_AWR` from inside the PDB failed with `ORA-13769: Snapshots 37 and 38 do not
  exist`: the snapshots are taken in CDB$ROOT, and from a PDB the package looks at the PDB's own
  AWR. Passing the CDB `dbid` fixed it (the script now reads it before switching container).
- `V$SQL` was already empty after each run (cursors age out on this VM), so baseline usage is shown
  with `DBA_SQL_PLAN_BASELINES.EXECUTIONS / LAST_EXECUTED` instead
  ([`baseline_usage.txt`](../../04-reports/02-plan-regression-spm/3-spm-baseline/baseline_usage.txt)).

## Take-aways

- Never refresh statistics with `SIZE 1` on columns with skewed data the application filters on.
- Keep statistics history (it is on by default) — it is the fastest undo for a bad refresh.
- SPM is the safe emergency brake for a plan regression; use it to buy time, then fix the cause.
