# Oracle Performance Tuning Lab — AWR · ASH · ADDM · SQL tuning · Partitioning

> Status: **all 8 cases done**. Every case ends with real before/after numbers and the AWR evidence
> that proves them. Shared dataset: [BANKDB](01-setup/bankdb/) (8 M transactions).

## Results

| # | Case | Before | After | Fix |
|---|------|--------|-------|-----|
| 1 | [Missing index](03-cases/01-missing-index/) | 787.8 ms/exec, 186,670 gets, full scan | 0.039 ms/exec, 5 gets | composite index `(account_id, txn_ts)`, no sort |
| 2 | [Plan regression after stats refresh](03-cases/02-plan-regression-spm/) | 10.3 ms → **583.6 ms** after histograms were dropped | 9.5 ms with SPM, 10.7 ms after stats restore | SPM baseline from AWR, then `RESTORE_TABLE_STATS` |
| 3 | [Row lock contention](03-cases/03-row-lock-contention/) | transfers 4,100/s during the interest batch, `enq: TX` 41.9 % | 6,535/s (baseline 6,619/s), no `enq: TX` | blocker found with live blocking tree + ASH; batch commits every 100 rows |
| 4 | [Redo, DBWR, commit latency](03-cases/04-redo-io-commit-latency/) | volume 7,014 tx/s, `write complete waits` 33 %; commit 7.53 ms (SYNC) | 16,032 tx/s with async/direct IO + 2 DBWR; FASTSYNC 6.48 ms, ASYNC 5.96 ms | `filesystemio_options=SETALL`, `db_writer_processes=2`; measured the cost of zero data loss |
| 5 | [Partitioning](03-cases/05-partitioning/) | monthly report 779.9 ms, 93,426 gets | 81.9 ms, 3,907 gets (pruning) | online interval partitioning; regression found in another query → covering local index (17.0 → 0.58 ms) |
| 6 | [Compression of historical partitions](03-cases/06-compression/) | 2024 partitions 379 MB; yearly report 357.6 ms | 163 MB (−57 %); report ~30 % **slower** (CPU +44 %), updates 2.35× redo | BASIC compression (EE, no extra license); kept for space, trade-off documented |
| 7 | [Parallel query / PGA](03-cases/07-parallel-query/) | DOP 2 report 0.50–4.34 s (random TEMP spills), 4 users serial 12.4 s | DOP 2 0.55–0.81 s, 4 users serial 4.59 s / DOP 2 2.34 s | PGA target 446 MB → 1,400 MB (instance really used ~1.2 GB) |
| 8 | [Checking ADDM's advice](03-cases/08-addm/) | ADDM: "Sequence Usage" 94 % of activity | finding unchanged after the fix; control run ±4 % | not a real problem (23ai dynamic sequence cache, misleading time-model stat) — verify ADDM before acting |

Problems I hit while building this (and how I fixed them): [notes/worklog.md](notes/worklog.md).

## Goal

Diagnose and fix realistic performance problems the way an enterprise DBA does it: start from the
symptom, find the cause with AWR/ASH/ADDM, fix it, and prove the improvement with numbers.

## Environment

- Oracle 23ai single instance orcl3 (prm3, 7 GB), PDB `PERF`, outside GoldenGate's scope; its Data Guard
  standby on stb3 was part of case 4 (commit latency per transport mode).
- Data: BANKDB — branches, customers, accounts, cards, 8 M transactions, generated deterministically
  ([`01-setup/bankdb`](01-setup/bankdb/), counts and checksums to verify a reload).
- Load: [`02-workload/run_workload.sh`](02-workload/run_workload.sh) — fixed-parameter sessions (transfers,
  monthly/annual reports, the interest batch); results per run in a table, summarised by
  [`05-scripts/wl_summary.sql`](05-scripts/wl_summary.sql).

## Layout

| Folder | Contents |
|--------|----------|
| `01-setup/` | PDB, schema, data load, verification |
| `02-workload/` | workload sessions and driver |
| `03-cases/<n>-<name>/` | per case: symptom → evidence → root cause → fix → result table |
| `04-reports/` | AWR, ASH, ADDM and SQL Monitor reports for each before/after pair |
| `05-scripts/` | reusable diagnostics: top SQL/events from AWR, plans from AWR, blocking tree, ASH blocking, redo and PX stats, SQL Monitor helpers |

AWR, ASH, ADDM and SQL Monitor need the Diagnostics and Tuning Pack licenses on a licensed database —
check the licenses and `control_management_pack_access` before using them at work (Statspack is the free
alternative).
