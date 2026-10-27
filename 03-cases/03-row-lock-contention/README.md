# Case 3 — Transfers hang during the month-end interest batch (row lock contention)

## Scenario

4 sessions run money transfers for 120 s (`bank.wl_transfer`): debit one account, credit another,
log the transfer, commit. 30 % of transfers touch a "hot" account (payroll/merchant, account_id
multiple of 100). After 20 s the month-end interest batch (`bank.batch_interest`) updates all 4,800
hot accounts. Runner: [`run_incident.sh`](run_incident.sh) — also captures a live blocking tree at
t = 40 s and ASH after the run.

| Run | Batch | Transfers / s | Top event | Deadlocks |
|-----|-------|---------------|-----------|-----------|
| 1 baseline | none | 6,619 | `write complete waits` 65 % (see note) | 0 |
| 2 incident | one transaction for all 4,800 rows, commit after 60 s | **4,100** (−38 %) | **`enq: TX - row lock contention` 41.9 %** | 1 |
| 3 fixed | commit every 100 rows | 6,535 | no `enq: TX` in top events | 0 |

## Diagnosis (run 2)

- **AWR top events:** `enq: TX - row lock contention` 41.9 % of DB time.
- **ASH, lock waits by blocking session** ([ash_blocking.txt](../../04-reports/03-row-lock-contention/2-batch-one-transaction/ash_blocking.txt)):
  SID 330 is behind 252 of the lock-wait samples, blocking all 4 transfer sessions. But ASH cannot
  say *what* SID 330 was doing: a blocker that is idle is not sampled, and by the time I queried it
  the session was gone (module column empty).
- **Live blocking tree at t = 40 s** ([blocking_tree_t40.txt](../../04-reports/03-row-lock-contention/2-batch-one-transaction/blocking_tree_t40.txt)):
  `BLOCKER 330 BANK_BATCH / INTEREST, event PL/SQL lock timer (Idle)`, blocking 4 sessions, each
  waiting 14–19 s on `enq: TX`. That identifies the batch holding uncommitted row locks.

[`blocking_tree.sql`](../../05-scripts/blocking_tree.sql) (live) and
[`ash_blocking.sql`](../../05-scripts/ash_blocking.sql) (after the fact) are the two reusable scripts.

## Root cause and fix

The batch updated every hot account in a single transaction and committed only at the end, so each
row lock was held for the whole batch (here 60 s, standing in for a slow batch doing more work).
Any transfer touching a hot account queued behind it.

Fix: commit in small chunks (`batch_interest(100, 0)`: commit every 100 rows, in `account_id`
order). Each lock now lives only for the time of 100 updates; the batch took 0.19 s and transfers
stayed at baseline speed.

Note: run 3 also drops the artificial 60 s hold, so two things change at once. The point stands
either way — with commit-every-100 a slow batch holds each lock for the time of one chunk, not for
the whole run. If the business needs the batch to be atomic, the alternative is to run it outside
peak hours, not to keep 4,800 rows locked during them.

## Things I noticed but did not solve here

- **Baseline is dominated by `write complete waits` (65 %)**, and runs 2–3 show
  `log file switch (checkpoint incomplete)` and `free buffer waits`: 5 of 6 redo groups were
  `ACTIVE`, i.e. DBWR cannot keep up. `filesystemio_options = none` (synchronous buffered IO on the
  datafile filesystem) with one DB writer. → case 4.
- **Only 92 `log file sync` waits for ~888 K commits:** PL/SQL does not wait for the redo write on
  each `COMMIT` inside a loop (only when the call returns). This workload therefore cannot measure
  commit latency; case 4 must commit from the client.
- `enq: HW - contention` (8–11 %) from 4 sessions inserting into `TRANSFER_LOG`.
- In run 3, 30 ASH samples of `enq: TX` were blocked by an MMON slave running Auto ADDM. Not
  investigated.
