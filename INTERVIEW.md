# Interview notes — Oracle Performance Tuning Lab

## The 2-minute story

I built a banking dataset (BANKDB: 8 M transactions, deliberately skewed) and worked through eight
performance problems on Oracle 23ai, each the same way: reproduce it with a workload, find the cause in
AWR/ASH/SQL Monitor, fix it, measure again under the same load. Every number in the repo comes from AWR
snapshots taken around the runs.

Three results I like to talk about:
- A **plan regression** after a statistics refresh dropped a histogram (10 ms → 584 ms). I pinned the
  good plan from AWR with SPM to stop the damage, then restored the statistics from history and removed
  the baseline so the optimizer was free again.
- Parallel queries were **randomly 8× slower**. SQL Monitor per plan line showed the hash join got
  3.4 MB of memory instead of 34 MB and spilled to TEMP; the instance really used ~1.2 GB of PGA against
  a 446 MB target. Sizing PGA from the advisor fixed it — even serial runs got 2.7× faster.
- **ADDM's top finding was wrong.** It blamed sequence cache misses for 94 % of DB time; a control run
  and a direct test showed 23ai's dynamic sequence cache made it a non-issue. I learned to treat ADDM as
  leads, not a to-do list.

## Likely questions

**How do you start with "the database is slow"?** Define the time window, take AWR for it, look at DB time
by wait class and top SQL, then drill into ASH for the sessions/SQL involved. Don't tune what isn't in
DB time. (Cases 1, 3, 4.)

**AWR vs ASH vs ADDM?** AWR: hourly (or manual) snapshots of cumulative statistics — what changed between
two points. ASH: 1-second samples of active sessions — who was waiting on what, when. ADDM: an expert
system on top of AWR that proposes findings. All three need the Diagnostics Pack license.

**A query became slow overnight. What do you check?** Did the plan change (same `sql_id`, different plan
hash in `DBA_HIST_SQLSTAT`)? Did statistics change (`DBA_TAB_STATS_HISTORY`, histograms)? Fix fast with an
SPM baseline from AWR, then fix the cause. (Case 2.)

**SPM vs SQL profile?** SPM fixes a whole plan and is included in Enterprise Edition; a SQL profile adjusts
estimates and needs the Tuning Pack.

**When does partitioning help, and what is the risk?** It helps when queries filter on the partition key
(pruning: monthly report 780 → 82 ms). Risk: every access path changes — in my case another query switched
to a full partition scan and got slower; a covering local index fixed it. Always re-test other queries.
(Case 5.)

**Is compression always good?** No. Basic compression cut 57 % of space, but the CPU-bound report got 30 %
slower and updates generated 2.35× redo. Good for read-mostly history, bad for hot data. BASIC is in EE;
ADVANCED needs the Advanced Compression Option. (Case 6.)

**What is `log file sync` and how do you reduce it?** The time a session waits on COMMIT for LGWR to write
the redo. It includes the local write, the standby round trip with SYNC, and CPU scheduling. Measured:
SYNC 7.53 ms, FASTSYNC 6.48 ms (still zero-data-loss FSFO), ASYNC 5.96 ms. (Case 4.)

**How do you find a blocking session?** Live: `V$SESSION.BLOCKING_SESSION`. Afterwards: ASH
`BLOCKING_SESSION` — but an idle blocker is not sampled by ASH, so capture the live tree during the
incident. (Case 3.)

## 5-minute demo

```bash
# on prm3, as oracle (BANKDB loaded in PDB PERF)
BANK_PASSWORD=... ./02-workload/run_workload.sh 01-missing-index demo-before 4 60
sqlplus / as sysdba @03-cases/01-missing-index/fix.sql PERF
BANK_PASSWORD=... ./02-workload/run_workload.sh 01-missing-index demo-after 4 60
cat 04-reports/01-missing-index/demo-*/top_sql.txt   # 186,670 -> 5 buffer gets per execution
```

## Limitations

- 2 vCPU VM, virtual disks cached in host RAM: IO-bound results are optimistic, CPU-bound results are
  pessimistic. I say which one applies in each case.
- Redo log sizing (case 4) and logs of 2 GB (ADDM) could not be applied: the FRA is 16 GB.
