# Oracle Performance Tuning Lab — AWR · ASH · ADDM · SQL tuning · Partitioning

> Status: **in progress** — 6 of 8 cases done. Every case ends with real before/after numbers and
> the AWR evidence that proves them. Shared dataset: [BANKDB](01-setup/bankdb/) (8 M transactions).

## Results so far

| # | Case | Before | After | Fix |
|---|------|--------|-------|-----|
| 1 | [Missing index](03-cases/01-missing-index/) | 787.8 ms/exec, 186,670 gets, full scan | 0.039 ms/exec, 5 gets | composite index `(account_id, txn_ts)`, no sort |
| 2 | [Plan regression after stats refresh](03-cases/02-plan-regression-spm/) | 10.3 ms → **583.6 ms** after histograms were dropped | 9.5 ms with SPM, 10.7 ms after stats restore | SPM baseline from AWR, then `RESTORE_TABLE_STATS` |
| 3 | [Row lock contention](03-cases/03-row-lock-contention/) | transfers 4,100/s during the interest batch, `enq: TX` 41.9 % | 6,535/s (baseline 6,619/s), no `enq: TX` | blocker found with live blocking tree + ASH; batch commits every 100 rows |
| 4 | [Redo, DBWR, commit latency](03-cases/04-redo-io-commit-latency/) | volume 7,014 tx/s, `write complete waits` 33 %; commit 7.53 ms (SYNC) | 16,032 tx/s with async/direct IO + 2 DBWR; FASTSYNC 6.48 ms, ASYNC 5.96 ms | `filesystemio_options=SETALL`, `db_writer_processes=2`; measured the cost of zero data loss |
| 5 | [Partitioning](03-cases/05-partitioning/) | monthly report 779.9 ms, 93,426 gets | 81.9 ms, 3,907 gets (pruning) | online interval partitioning; regression found in another query → covering local index (17.0 → 0.58 ms) |
| 7 | [Parallel query / PGA](03-cases/07-parallel-query/) | DOP 2 report 0.50–4.34 s (random TEMP spills), 4 users serial 12.4 s | DOP 2 0.55–0.81 s, 4 users serial 4.59 s / DOP 2 2.34 s | PGA target 446 MB → 1,400 MB (instance really used ~1.2 GB) |

Problems I hit while building this (and how I fixed them): [notes/worklog.md](notes/worklog.md).

## Goal

Diagnose and fix realistic performance problems the way an enterprise DBA does it: start from the
symptom, find the cause with AWR/ASH/ADDM, fix it, and prove the improvement with numbers.

## Environment

- Oracle 23ai single instance (prm3, 7 GB) — PDB `PERF`; optional RAC (prm1) for cluster waits.
- Load: Swingbench (Order Entry schema) or `02-workload/` scripts; data volume ≥ 10 M rows on the
  main fact table so plans and partition pruning matter.

## Cases

| # | Problem injected | Diagnose with | Fix | Evidence |
|---|------------------|---------------|-----|----------|
| 1 | Missing index → full scans on hot query | AWR Top SQL by elapsed/gets, SQL Monitor | Index / rewrite | elapsed, buffer gets, executions/s before vs after |
| 2 | Plan regression after stats change | ASH by SQL_ID + plan hash, `DBMS_XPLAN.DISPLAY_AWR` | SQL Plan Baseline (SPM) | both plans, baseline accepted, response time |
| 3 | Row-lock contention (`enq: TX - row lock contention`) | ASH blocking session chain | application fix / commit scope | ASH wait breakdown before/after |
| 4 | Undersized redo / log switches | AWR load profile, `log file sync` | redo size, SRL check | waits/s, switches/hour |
| 5 | Large table scans by date | execution plan, segment stats | Interval range partitioning + local indexes | pruning in plan, elapsed |
| 6 | Storage growth | segment sizes | Advanced Row / basic compression | GB before/after, query impact |
| 7 | Batch report too slow | SQL Monitor | Parallel query / parallel DML with sensible DOP | elapsed, PX servers used |
| 8 | ADDM findings on a busy hour | ADDM report | apply top recommendation | ADDM finding resolved |

## Deliverables checklist

- [ ] `01-setup/` schema + data generation scripts (repeatable)
- [ ] `02-workload/` load scripts with fixed parameters
- [ ] `03-cases/<n>-<name>/README.md` per case: symptom → evidence → root cause → fix → result table
- [ ] `04-reports/` AWR, ASH, ADDM, SQL Monitor HTML for each before/after pair
- [ ] `05-scripts/` reusable diagnostic SQL (top SQL, ASH by wait, blocking tree)
- [ ] Summary table in this README with the measured improvement of each case

## CV line (fill only with measured numbers)

`Diagnosed N performance cases using AWR/ASH/ADDM; e.g. reduced <query> from X s to Y s via <fix>.`
