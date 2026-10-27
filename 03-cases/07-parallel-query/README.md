# Case 7 — Parallel query for a big report (and why it was unpredictable)

## Scenario

An annual report — 2025 POSTED transactions per region and product, a 4-table join over ~3.9 M rows:

```sql
select /*+ parallel(N) */ b.region, a.product, count(*), sum(t.amount)
from bank.transactions t
join bank.accounts a  on a.account_id = t.account_id
join bank.customers c on c.customer_id = a.customer_id
join bank.branches b  on b.branch_id = c.branch_id
where t.txn_ts >= timestamp '2025-01-01 00:00:00' and t.txn_ts < timestamp '2026-01-01 00:00:00'
  and t.status = 'POSTED'
group by b.region, a.product;
```

Question: does parallel execution help, for one batch job and for 4 users at once? The VM has
**2 vCPUs** (`cpu_count = 2`, `parallel_degree_policy = MANUAL`). Workload `bank.wl_annual_*`,
matrix in [`run_matrix.sh`](run_matrix.sh): 1 session × {serial, DOP 2, DOP 4}, 4 sessions × {serial,
DOP 2}, 120 s each. Every execution stores its result checksum: all runs returned the same total
(37191981667600 over 3,862,128 rows), so parallel never changed the answer.

## First result: parallel was fast *sometimes*

| 1 session | avg | min | max |
|-----------|-----|-----|-----|
| serial | 2.07 s | 1.64 s | 2.76 s |
| DOP 2 | 1.18 s | 0.50 s | **4.34 s** |
| DOP 4 | 1.67 s | 0.57 s | **6.51 s** |

No downgrades (`Parallel operations not downgraded` = 100 %), so it was not a shortage of PX servers.

## Diagnosis

1. **SQL Monitor per execution** ([`sqlmon_px_executions.sql`](../../05-scripts/sqlmon_px_executions.sql),
   summing QC + all PX server rows): fast DOP 4 runs read 440 MB with ~0.3 s IO wait; slow runs read
   571–583 MB with 15–21 s IO wait (summed over 8 PX servers). Same buffer gets — the extra reads
   are not table data.
2. **Plan lines** ([`sqlmon_plan_lines.sql`](../../05-scripts/sqlmon_plan_lines.sql)): in a fast run the
   big `HASH JOIN` (ACCOUNTS ⋈ 3.9 M transactions) got **34.4 MB** of work area memory; in a slow run
   only **3.4 MB** and spilled **136 MB to TEMP** (132 MB written and read back).
3. **V$PGASTAT** (CDB level): `pga_aggregate_target` 446 MB, but PGA in use 904 MB / allocated
   1,227 MB (max 1,440 MB) — background processes (MMON 120 MB, 3 × ARCn 42 MB) and GoldenGate use
   it before any query runs. `aggregate PGA auto target` had collapsed to **28 MB**,
   `over allocation count` 5,259. Work areas got whatever was left at that moment → random spills.
4. **V$PGA_TARGET_ADVICE**: estimated over-allocation drops to 0 at 1,338 MB.

## Fix

[`fix_pga.sql`](fix_pga.sql): `pga_aggregate_target = 1400M` (dynamic, `scope=both`;
`pga_aggregate_limit` is not set explicitly and follows to 2,800 MB). The VM still had ~3.7 GB
available; the target only allows work areas to grow, it does not allocate memory up front.
After the change: auto target 28 → 431 MB, global memory bound 89 → 140 MB.

## Result (same matrix)

| Run | PGA 446 MB: avg (min–max) | PGA 1,400 MB: avg (min–max) | Executions in 120 s |
|-----|---------------------------|-----------------------------|---------------------|
| 1 session serial | 2.07 s (1.64–2.76) | 1.84 s (1.73–2.66) | 58 → 66 |
| 1 session DOP 2 | 1.18 s (0.50–4.34) | **0.62 s (0.55–0.81)** | 102 → 193 |
| 1 session DOP 4 | 1.67 s (0.57–6.51) | 0.68 s (0.56–1.26) | 72 → 177 |
| 4 sessions serial | 12.4 s (4.16–15.48) | **4.59 s** (3.53–5.93) | 40 → 107 |
| 4 sessions DOP 2 | 9.48 s (6.86–11.56) | **2.34 s** (1.93–3.03) | 52 → 206 |

TEMP after the fix ([`temp_by_line_after_fix.txt`](../../04-reports/07-parallel-query/temp_by_line_after_fix.txt)):
the big hash join spilled in **4 of 80** monitored DOP 2 executions (max 15 MB, was 136 MB). The
remaining TEMP use is `HASH JOIN BUFFERED` (≤ 11 MB), which PX buffers by design. Older executions
had already aged out of `V$SQL_MONITOR`, so I cannot give the before-fix spill ratio, only the
examples above. `over allocation count` still rose by 323 during the after-fix runs (it is
cumulative since startup; not explained yet).

## Take-aways

- The biggest win was **not** parallel execution, it was sizing PGA for what the instance really
  uses: even the 4-session *serial* run got 2.7× faster.
- With 2 vCPUs, DOP 2 is the useful maximum; DOP 4 adds PX servers without CPU to run them.
- Parallel still helped under concurrency here (4 users: 107 → 206 reports in 120 s), because the
  serial plan waited on memory/IO, not CPU. On a CPU-bound system the answer could be the opposite.
- When parallel run times are bimodal, look at work area memory per plan line before blaming
  parallelism itself.
