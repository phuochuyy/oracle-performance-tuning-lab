# SQLT XTRACT — a second opinion on cases 2 and 5

SQLT (SQLTXPLAIN, MOS Doc ID 215187.1, version 2024-08-24, 10g–23ai) is Oracle Support's tool for one SQL:
it collects plans from memory and AWR, statistics, the optimizer environment and a health check into one
report. The tool itself is not in this repo (download it from MOS); only the scripts and the reports.

- [`install_sqlt.sh`](install_sqlt.sh) — installs SQLT into PERF (schemas SQLTXPLAIN/SQLTXADMIN, own
  tablespace `SQLT_DATA`), 1,008 objects, all VALID.
- [`xtract.sh`](xtract.sh) — `XTRACT` for one SQL_ID as BANK; about 2 min. The full output is ~46 MB on
  prm3 (test case, exports, 10053 trace, copies of the AWR/ASH/ADDM reports); only the main report,
  the lite report and the readme are copied here.

## The SQL

`8wx3gpt1vwa72` — `SELECT COUNT(*), SUM(AMOUNT) FROM BANK.TRANSACTIONS WHERE STATUS = :B1 AND TXN_TS ...`,
the SQL of [case 2](../03-cases/02-plan-regression-spm/) (plan regression) and
[case 5](../03-cases/05-partitioning/) (partitioning). Report:
[`runs/case2-plan-history/sqlt_s76702_main.html`](runs/case2-plan-history/sqlt_s76702_main.html)
(open it locally — GitHub shows the HTML source).

## Plans found — all four match what I measured

SQLT found every plan the SQL ever had, from AWR only (no cursor was left in memory):

| Plan hash | SQLT avg elapsed | SQLT avg gets | Executions | What it was in my cases |
|---|---|---|---|---|
| 1299576448 **[B]est** | 0.001 s | 30 | 807,912 | case 5 after the covering index `TRANSACTIONS_STATUS_TS_AMT_IX` |
| 3125427224 | 0.010 s | 6,211 | 49,879 | case 2 good plan, `INDEX RANGE SCAN` (my measurement: 10.3 ms) |
| 2776712995 | 0.017 s | 3,830 | 27,787 | case 5 after partitioning: full scan of one partition |
| 4088813652 **[W]orst** | 0.584 s | 93,312 | 824 | case 2 regression, `TABLE ACCESS FULL` (my measurement: 583.6 ms) |

My numbers came from my own workload tables; SQLT's from `DBA_HIST_SQLSTAT` — the two agree.

## Its health-check observations, checked one by one

| # | SQLT says | Checked | Verdict |
|---|---|---|---|
| 1 | a plan uses index `TRANSACTIONS_STATUS_TS_IX`, which no longer exists | case 5 replaced it with `TRANSACTIONS_STATUS_TS_AMT_IX` | true, intended — the old plan cannot come back |
| 2 | bug 13583722 (incremental stats, histograms from partitions) | patch already applied (SQLT says so); stats are not incremental | not applicable |
| 3 | 2 predicate columns with null low/high values | global stats of STATUS / TXN_TS are complete (analyzed 10-28); the nulls are in the empty partition below | harmless |
| 4 | 2 optimizer environments in AWR | the second one (676277196) appears only in snapshot 42, case 2 step 3 (the SPM baseline run), with the same good plan | harmless; why the environment differed there — not investigated |
| 5 | check the sample size of automatic stats gathering | default `AUTO_SAMPLE_SIZE` | advice, no action |
| 6 | 1 of 25 partitions has 0 rows | `P_BEFORE_2024`, the anchor partition of interval partitioning — empty by design | harmless |

So the health check found nothing new on this SQL — which is the useful result: the plan history and the
statistics it shows match my own analysis. What it adds that I did not have in one place: all plans with
their optimizer environment, and the 10053 trace (in the full output on prm3).

## Problems on the way

- In a PDB the install stops with `ORA-20103: Missing Connect Identifier` — SQLT reconnects as SQLTXPLAIN,
  so it needs `@//prm3.rac:1521/perf.rac`.
- `sqltxtract.sql` asks for the SQLTXPLAIN password with `ACCEPT ... HIDE`. Over ssh, with no terminal,
  it got an empty value (`ORA-20104`). The first time I put the password on the line after `START`,
  where the prompt I expected was for a description: that prompt is commented out in this version.
  `xtract.sh` uses a copy with the password as parameter 2 (sent on stdin).
- prm3 has no `zip`, and the VM has no internet for `dnf`: SQLT prints `zip: command not found` and leaves
  the files unzipped — which is fine here.
