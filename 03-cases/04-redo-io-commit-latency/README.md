# Case 4 — Redo, DB writer and the cost of zero data loss

Two workloads, 4 sessions × 120 s each, on orcl3 (prm3) with its standby stb3:

- **volume** (`bank.wl_transfer`, from case 3): commits inside a PL/SQL loop, which does not wait
  for the redo write → as much redo as the system can generate; stresses DBWR and log switches.
- **commit latency** (`bank.wl_transfer_wait`): same transfer with `COMMIT WRITE WAIT`, so every
  commit waits like a client commit and `log file sync` is the real commit latency.

Statistics per run: [`redo_stats.sql`](../../05-scripts/redo_stats.sql) (commit/write events, redo
volume, log switches between the AWR snapshots).

## Part A — the DB writer could not keep up

Case 3 showed 65 % of DB time in `write complete waits` and redo groups stuck `ACTIVE`.
Settings: `filesystemio_options = none` (datafiles on a filesystem → synchronous, buffered IO),
`db_writer_processes = 1`, redo logs 6 × 200 MB.

| Volume workload | Before | After (`SETALL`, 2 DB writers) |
|-----------------|--------|-------------------------------|
| Transfers / s | 7,014 | **16,032** (2.3×) |
| `write complete waits` | 259.6 s (avg ~10 s per wait!) | 4.6 s |
| `free buffer waits` | 214.3 s (18,026 waits) | none |
| `log file switch (checkpoint incomplete)` | 151.3 s | 13.6 s |
| Blocks written by DBWR | 59,404 (~3.8 MB/s) | 162,542 (~10.6 MB/s) |
| Redo generated | 1.6 GB | 3.6 GB |

Fix: [`fix_dbwr_io.sh`](fix_dbwr_io.sh) — `filesystemio_options = SETALL` (asynchronous + direct
IO) and `db_writer_processes = 2` on **both** primary and standby (Data Guard best practice: keep
them alike). Both are static: FSFO was disabled, the standby and then the primary restarted, FSFO
re-enabled, configuration back to SUCCESS ([log](../../04-reports/04-redo-io-commit-latency/fix_dbwr_io.log)).
Trade-off: with direct IO the guest OS page cache no longer hides a small buffer cache.

The remaining `checkpoint incomplete` comes from ~9 log switches per minute (3.6 GB of redo in 2 min
on 200 MB logs). The usual target is a switch every 15–20 minutes at peak, which here would need
logs of tens of GB — not possible in this lab (16 GB FRA), so the logs were left at 200 MB.

For the commit-latency workload part A changed little: 493.7 → 516.3 transfers/s,
`log file sync` 7.87 → 7.53 ms. Commit latency was never a DBWR problem.

## Part B — what zero data loss costs per commit

Same commit-latency workload, three redo transport modes
([`set_transport.sh`](set_transport.sh)):

| Transport | Protection mode / FSFO | Transfers / s | `log file sync` avg | `SYNC Remote Write` avg | Local `log file parallel write` |
|-----------|-----------------------|---------------|---------------------|-------------------------|-------------------------------|
| SYNC (AFFIRM) | MaxAvailability, FSFO zero data loss | 516.3 | 7.53 ms | 1.52 ms | 2.34 ms |
| FASTSYNC (SYNC NOAFFIRM) | MaxAvailability, FSFO zero data loss | 596.7 (+15.6 %) | 6.48 ms | 0.03 ms | 3.33 ms |
| ASYNC | MaxPerformance, **FSFO disabled** | 644.8 (+24.9 %) | 5.96 ms | – | 3.92 ms |

- Zero data loss with SYNC costs ~1.6 ms per commit (≈ 20 % throughput) against ASYNC here.
- FASTSYNC keeps MaxAvailability and FSFO zero data loss and gets most of that back: the primary
  waits for the standby to *receive* the redo, not to *write* it. The remaining risk is losing redo
  that sat only in the standby's memory if both sites fail at the same moment.
- `log file sync` (≈ 6–7.5 ms) is much larger than local write + remote write (≈ 3–4 ms) in every
  mode: with 2 vCPUs, LGWR and 4 busy sessions compete for CPU, so posting the waiting sessions
  takes time. On this VM CPU, not storage, is the floor of commit latency.
- The lab was set back to **SYNC / MaxAvailability / FSFO enabled** after the test.

## Problems on the way

- **ORA-16654** — the FSFO target's `LogXptMode` cannot change while FSFO is enabled. My first run
  changed the primary's property and failed on the standby, leaving them different; the script now
  disables FSFO first.
- **Script stopped silently** — `dgmgrl` printed only `Connected` for `disable fast_start failover`,
  so my `grep -v` filter returned 1 and `set -e` ended the script with FSFO disabled. Fixed with
  `|| true` on the filter.
- **Standby FRA filled up again** (ORA-19809, FSFO unsynchronized) after the 3.6 GB volume run —
  see the worklog. I had written "check the FRA on both sites before a big change" two days earlier
  and did not do it.
