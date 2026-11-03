# Case 10 — What Unified Auditing costs, and how big the audit trail gets

## Question

"If we audit card and balance access, how much slower does it get — and how much space does a year of audit
records need?" PCI-DSS 10 wants the access logged and kept 12 months (3 months at hand). Before this case PDB
`PERF` had only the default policies, and **no retention at all**: no archive timestamp, no purge job, the trail
in `SYSAUX` (29 MB free, autoextend), oldest record from January.

## Setup — [`audit_case.sh`](audit_case.sh)

Two object policies, enabled one at a time:

| Policy | Audits | Fires |
|--------|--------|-------|
| `CASE10_BALANCE_CHANGE` | `UPDATE ON bank.accounts` | twice per transfer (debit + credit) — the realistic one |
| `CASE10_TXN_READ` | `SELECT ON bank.transactions` | on every account-statement query — the worst case: auditing a hot read |

Workloads ([`run_workload.sh`](../../02-workload/run_workload.sh)): transfers with commit wait (4 sessions, 120 s) and
the account statement (1 session, 30 s — short on purpose: the hot-read run writes ~2.9 k audit records per second,
and the lab host had ~3.5 GB free). TDE from case 9 stays on in every run.

## Result

| Workload | Without audit | With audit | Change | Audit records |
|----------|---------------|------------|--------|---------------|
| Transfers, `UPDATE ON accounts` audited | 414.92 / 422.35 /s | 369.53 /s | **−11.7 %** | 88,694 = 2 per transfer |
| Account statement, `UPDATE ON accounts` audited (control: it does not update accounts) | 40,019 – 43,588 /s (5 runs, mean 42,015) | 41,269 / 42,368 /s | **none** (−0.5 %) | 0 |
| Account statement, `SELECT ON transactions` audited | same 5 runs | 2,884.67 /s | **−93.1 %** | 86,541 = 1 per query |

Evidence: `04-reports/10-audit-overhead/<run>/` (AWR, top SQL, top events, summary) and `size-*.txt` (records and
`AUDSYS` MB before and after each step).

## Reading the numbers

- **One audit record costs ~0.35 ms of CPU here.** Hot read: 30 s / 86,541 queries = 347 µs per loop, against 23 µs
  without audit — the query itself only went from 16 to 34 µs; the rest is writing the audit record. Transfers: DB
  CPU went from 17.8 to 51 s for 88,694 records (~0.37 ms each). Same number, two ways.
- **So the cost depends on how often the policy fires, not on the policy existing.** A transfer already waits
  ~9 ms for its commit, two records add ~0.7 ms of CPU → −11.7 % on 2 vCPUs. A 23 µs read with a 0.35 ms record
  becomes 15× slower. The control run (policy on, workload not touching the audited action) shows no cost.
- **Space: 0.68 KB per record** (balance updates: `AUDSYS` +59 MB for 88,694) and 0.91 KB (statement query,
  longer SQL text: +77 MB for 86,541).
- Rule: audit **changes** and access to **sensitive columns/tables** (`CARDS`), by user or condition; do not audit
  every read of a hot table — that is what the −93 % run is for.

## Retention (PCI-DSS 10.5.1) — now running in PERF

Sizing: records/day × 0.68 KB. Example: 1 M transfers/day × 2 records = 2 M records ≈ **1.4 GB/day, ~500 GB/year**;
3 months in the database ≈ 125 GB. At the lab's peak (739 records/s) it would be 1.8 GB/hour — another reason to
audit changes, not reads.

1. **Own tablespace** instead of `SYSAUX`:
   `dbms_audit_mgmt.set_audit_trail_location(dbms_audit_mgmt.audit_trail_unified, 'AUDIT_TBS')` (new partitions).
2. **Daily partitions** — already `INTERVAL '1' DAY` here; the purge then drops whole partitions instead of deleting
   rows.
3. **Archive before purge:** each night export the records older than 90 days (Data Pump with a query on
   `UNIFIED_AUDIT_TRAIL`, or to the SIEM), verify the file, keep files 12 months off the database.
4. **Mark what is archived:** `dbms_audit_mgmt.set_last_archive_timestamp(audit_trail_unified,
   last_archive_time => <upper bound of the verified export>)` — only after the export is checked.
5. **Purge job:** `dbms_audit_mgmt.create_purge_job(audit_trail_unified, audit_trail_purge_interval => 24,
   audit_trail_purge_name => 'PURGE_UNIFIED_DAILY', use_last_arch_timestamp => true)` — it can never delete
   something that was not archived.
6. Watch: `dba_audit_mgmt_last_arch_ts` moves every day; `AUDSYS` size stays flat after 90 days.

Switched on in PERF afterwards, with an archive procedure that marks records archived only when the CSV holds as
many rows as the trail: [security lab, retention](https://github.com/phuochuyy/oracle-security-compliance-lab/blob/main/04-auditing/README.md#retention--02_retentionsh)
(first run: 13,849 records older than 90 days archived and marked).

## Problems on the way

- The first try never enabled a policy: `audit policy x; select …` on one line → `ORA-03405` in 26ai (one statement
  per line). Those runs are kept as repeat baselines (`before2-*`, `before3-*`, with a `RENAMED.txt`), their rows in
  `bank.wl_runs` retagged — they show the run-to-run noise (±4 %).
- The first control run read −14 % with no audit record written: it ran right after the audited transfers. Two
  repeats of the pair (off / on / on / off) showed no difference — reported as no cost.
- The 175,235 test records stay in the trail: deleting audit records on request is exactly what an auditor
  flags. They leave through the retention job after 90 days, archived like everything else.
