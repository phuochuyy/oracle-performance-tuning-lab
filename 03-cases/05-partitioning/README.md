# Case 5 — Monthly report on a non-partitioned 8 M-row table

## Symptom

A monthly channel report reads one month out of 24, but takes ~0.8 s and reads the whole table:

```sql
select channel, count(*), sum(amount) from bank.transactions
where txn_ts >= :m_start and txn_ts < :m_end and status = 'POSTED'
group by channel;
```

Workload `bank.wl_monthly` (random month, binds), 4 sessions × 120 s.
Environment for this case: prm3 with its standby stb3 running (SYNC), so the baselines were
measured again here instead of reusing case 1/2 numbers.

## Fix

[`fix.sql`](fix.sql): convert `TRANSACTIONS` **online** to monthly interval range partitions on
`txn_ts` (2 min 46 s, the table stays usable). Indexes: PK on `txn_id` stays **global** (it does not
contain the partition key); `(account_id, txn_ts)` and `(status, txn_ts)` become **local**.

## Result — monthly report

| Metric | Before | After |
|--------|--------|-------|
| Plan | `TABLE ACCESS FULL` (phv 1083525209) | `PARTITION RANGE ITERATOR` KEY/KEY → full scan of one partition (phv 3410498840) |
| Elapsed per execution | 779.9 ms | **81.9 ms** (9.5×) |
| Buffer gets per execution | 93,426 | 3,907 (≈ 1/24) |
| Throughput | 5.13 /s | 48.73 /s |

`KEY/KEY` = partition pruning decided at run time from the bind values.

## Regression check of the other queries

A partitioning change rewrites every access path to the table, so the queries from case 1 and 2
were run again.

| Query | Before partitioning | After partitioning | |
|-------|---------------------|--------------------|-|
| Case 1 statement | 47.8 µs, 5 gets | 33.2 µs, 11 gets | OK — more gets (probes the Dec, Nov, Oct local index partitions newest-first until 50 rows), but smaller cached partitions → faster |
| Case 2 pending review | 10.7 ms in case 2 (*) | **17.0 ms**, plan changed to a full scan of the December partition | **regression** |

(*) My mistake: I re-measured the statement and monthly queries before the change but forgot the
pending query, so its "before" comes from case 2 (fewer VMs running). The direct comparison below
does not depend on it.

### Diagnosing the pending-query regression

[`compare_pending_plans.sql`](compare_pending_plans.sql) runs both plans 300 times in one session
([output](../../04-reports/05-partitioning/compare_pending_plans.txt)):

| Plan | ms / exec |
|------|-----------|
| optimizer choice (full scan of the Dec partition) | 7.33 |
| forced local index `(status, txn_ts)` | **3.07** |

The optimizer was wrong by 2.4×. PENDING rows are scattered over the partition (clustering factor ≈
number of rows), so ~6.5 K table-by-rowid visits look more expensive than scanning 3.9 K blocks — but
those blocks are cached, while the full scan burns CPU filtering ~333 K rows.

### Fix: covering local index

[`fix_pending_index.sql`](fix_pending_index.sql): local index `(status, txn_ts, amount)` — the query
needs only `count(*)` and `sum(amount)`, so it never touches the table. The old index was made
`INVISIBLE` first (instant rollback) and dropped only after the workload confirmed the new plan
([`drop_old_index.sql`](drop_old_index.sql)).

| Pending query | After partitioning | With covering index |
|---------------|--------------------|---------------------|
| Plan | `TABLE ACCESS FULL` partition (phv 2776712995) | `INDEX RANGE SCAN TRANSACTIONS_STATUS_TS_AMT_IX` only (phv 1299576448) |
| Elapsed per execution | 17,035 µs | **575.7 µs** (30×) |
| Buffer gets per execution | 3,830 | 30 |
| Throughput | 234 /s | 6,740 /s |

In the after-fix comparison the "forced local index" hint shows the same 0.27 ms as the covering
index because the hinted index was already INVISIBLE, so the hint was ignored — not a real result.

## Take-aways

- Partitioning is not just "make the big query faster": re-test every important query on the table.
- When the optimizer avoids an index because of the clustering factor, a covering index removes the
  table access completely — better than forcing a plan with hints or baselines.
- Make an index INVISIBLE before dropping it.

Evidence: [`04-reports/05-partitioning/`](../../04-reports/05-partitioning/).
