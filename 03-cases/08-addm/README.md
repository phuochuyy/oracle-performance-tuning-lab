# Case 8 — Following ADDM's advice (and checking it first)

## Scenario

Run the high-volume transfer workload (`bank.wl_transfer`, 4 sessions × 120 s), let ADDM analyse the
window ([`addm_report.sql`](../../05-scripts/addm_report.sql) → `DBMS_ADDM.ANALYZE_DB` for the two
AWR snapshots), apply the top **actionable** recommendation, and measure again.
ADDM is part of the Diagnostics Pack license.

## What ADDM said

[ADDM report](../../04-reports/08-addm/1-before/addm.txt) — DB time 503 s, 4.16 average active sessions:

| # | Finding | Impact | My assessment |
|---|---------|--------|---------------|
| 1 | Large number of database connections | 100 % | **Not actionable.** 128 sessions, but only 4 are the workload; the rest are Oracle background processes and GoldenGate. The rule "≤ 10 × CPU cores" always fires on a 2-core VM. |
| 2 | Sequence Usage — "sequence cache misses" | 94 % | Looked actionable: the identity column of `TRANSFER_LOG` uses the default `CACHE 20`; time model `sequence load elapsed time` = 474.9 s of 503.2 s DB time. |
| 3 | Top SQL | 85 % | the UPDATEs on ACCOUNTS and the INSERT — the workload itself |
| 5 | Log file switches | 15 % | "logs of 2048 MB" — same conclusion as case 4, not possible with a 16 GB FRA |

## Applying finding 2

[`fix_sequence_cache.sql`](fix_sequence_cache.sql): identity sequence `CACHE 20 → 10000`.
To change only one thing, the primary's `fast_start_mttr_target` (set to 300 in between for the
standby checkpoint problem) was put back to 0 for the measurement.

| Run | Sequence cache | Transfers / s | `sequence load elapsed time` | ADDM "Sequence Usage" |
|-----|----------------|---------------|------------------------------|-----------------------|
| 1 before | 20 | 15,876 | 474.9 s of 503 s DB time | 94 % |
| 2 after | 10,000 | 17,174 (+8 %) | 462.6 s of 497 s | 93 % |
| 3 control | 20 again | 16,452 | — | 93 % |

The finding did not go away, and the control run with the old setting landed between the two:
run-to-run variation is ±4 %, so the +8 % is not a proven effect.

## Why ADDM was wrong here

- ADDM's own Top SQL finding contradicts it: the UPDATEs on `ACCOUNTS`, which use no sequence,
  account for > 50 % of DB time. 93 % of DB time cannot also be "sequence loading".
- [`sequence_refill_test.sql`](sequence_refill_test.sql): 10,000 `NEXTVAL` with `CACHE 20` caused
  only **4** `dc_sequences` row-cache modifications (vs 1 with `CACHE 10000`) and took 50 ms vs 40 ms.
  23ai sizes the sequence cache dynamically under heavy use, so the refills ADDM blamed hardly happen.
- The time model statistic `sequence load elapsed time` stays at ~93 % no matter what the cache is.
  My reading: the whole 120 s run is one PL/SQL call, and the statistic is accounted against that
  long call once a sequence load happened inside it. ADDM builds the finding on that number.

## Take-aways

- Read ADDM as a list of leads, not a to-do list. Cross-check each finding with something independent
  (Top SQL, wait events, a direct test) before changing the system.
- Always run a control: without run 3 I would have reported "+8 % thanks to ADDM".
- Real problems that ADDM *did* see correctly — log switches, redo log buffer — match what cases 4
  and 7 had found by hand.

The sequence cache was left at 10,000 (harmless for a log table, gaps are fine).
