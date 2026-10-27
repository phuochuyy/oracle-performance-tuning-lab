# Case 1 — Account statement without an index

## Symptom

The "account statement" query (last 50 transactions of one account since 2025-10-01) takes
~0.8 s per call under 4 concurrent sessions; throughput is only 5 statements/s.

```sql
select txn_ts, txn_type, amount, status
from bank.transactions
where account_id = :b1 and txn_ts >= timestamp '2025-10-01 00:00:00'
order by txn_ts desc fetch first 50 rows only;
```

Workload: `02-workload/run_workload.sh 01-missing-index <tag> 4 120` — 4 sessions, 120 s,
random account ids (bind variable), BANKDB scale 16 (8 M transactions, 736 MB).

## Evidence (before)

- **Top SQL** ([before/top_sql.txt](../../04-reports/01-missing-index/before/top_sql.txt)):
  `a4hv2brfqt1vf` — 186,670 buffer gets and 93,259 physical reads per execution to return 1.7 rows.
- **Plan** ([before/plan.txt](../../04-reports/01-missing-index/before/plan.txt)):
  `TABLE ACCESS FULL TRANSACTIONS` → `SORT ORDER BY STOPKEY`.
- **Where the time went** ([before/top_events.txt](../../04-reports/01-missing-index/before/top_events.txt)):
  DB CPU 59 %, `direct path read` 40 %. Large serial full scans read straight into the PGA
  (bypassing the 560 MB buffer cache), each preceded by an `enq: KO - fast object checkpoint`.
- Full AWR report: [before/awr.html](../../04-reports/01-missing-index/before/awr.html).

## Root cause

`TRANSACTIONS.ACCOUNT_ID` (a foreign key) has no index, so every statement scans all 8 M rows.

## Fix

[`fix.sql`](fix.sql): composite index `(account_id, txn_ts)`, created `ONLINE` (2 min 6 s, 209 MB).
Equality on the first column, range on the second, and the index order matches
`ORDER BY txn_ts DESC`, so Oracle reads the index backwards and stops after 50 rows — no sort.
Side benefit: the FK column is indexed (no full-table lock on `TRANSACTIONS` when a parent
`ACCOUNTS` row is deleted or its key updated).

## Result (same workload)

| Metric | Before | After |
|--------|--------|-------|
| Plan | `TABLE ACCESS FULL` + `SORT ORDER BY STOPKEY` (phv 212398583) | `INDEX RANGE SCAN DESCENDING` (phv 1121716283), no sort |
| Elapsed per execution | 787,757 µs | **38.9 µs** |
| CPU per execution | 357,003 µs | 17.8 µs |
| Buffer gets per execution | 186,670 | 5 |
| Physical reads per execution | 93,259 | 2 |
| Throughput (4 sessions) | 5.06 /s | 74,847 /s |
| Top wait | `direct path read` 40 % | `db file sequential read` 20 % |

Evidence: [after/](../../04-reports/01-missing-index/after/).

## Notes / caveats

- The VM's virtual disk is cached in the host's RAM: 14.5 M single-block reads averaged ~5 µs,
  far faster than real storage. The reduction in blocks read (186,670 → 5) is the reliable number;
  absolute throughput would be lower on real disks.
- After the fix `write complete waits` showed up (10 % of DB time). Not investigated yet.
- AWR/ASH need the Diagnostics Pack license outside a lab.
