# Oracle Performance Tuning Lab — AWR · ASH · ADDM · SQL tuning · Partitioning

> Status: **planned**. Supersedes the `oracle-awr-lab` skeleton. Every case below must end with
> real before/after numbers and the reports that prove them.

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
