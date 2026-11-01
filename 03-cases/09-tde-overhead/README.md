# Case 9 — What TDE costs on the banking workload

## Question

"If we turn on Transparent Data Encryption, how much slower does the database get?" — measured on the same BANKDB
workloads as the other cases, and closing a real gap at the same time: PDB `PERF` holds 8 M transactions and
384,000 card-like numbers in `BANK_DATA`, and orcl3 had no TDE at all.

[`check_pan.sh`](check_pan.sh) counts the PAN of card 1 in the raw bytes of the `BANK_DATA` datafile (no database
login needed for the grep): **4 hits** before ([`pan-before.txt`](../../04-reports/09-tde-overhead/pan-before.txt)).

## Setup — [`tde_setup.sh`](tde_setup.sh)

| Step | What | Evidence |
|------|------|----------|
| `keystore` | `WALLET_ROOT` (static → orcl3 restarted, GoldenGate GG_B stopped/started around it), `TDE_CONFIGURATION=FILE`, united keystore, master key for the root and every PDB, auto-login keystore; off-host copy of `ewallet.p12` only, same md5 as on the server | [`01-keystore.log`](../../04-reports/09-tde-overhead/01-keystore.log) |
| `encrypt` | `ALTER TABLESPACE bank_data ENCRYPTION OFFLINE USING 'AES256' ENCRYPT` — 3.3 GB in **11.78 s** | [`02-encrypt-offline.log`](../../04-reports/09-tde-overhead/02-encrypt-offline.log) |

**Offline, not online, on purpose.** Online encryption writes a complete new copy of the datafile (and the redo for
it); the host had 3.7 GB free and the file is 3.3 GB. Offline encryption converts the file in place: no extra space,
almost no redo — at the price of the tablespace being offline for those 12 s. In production that choice is
"maintenance window vs. twice the space".

After: **0 hits** ([`pan-after.txt`](../../04-reports/09-tde-overhead/pan-after.txt)). The keystore password is in
the git-ignored `lab.env` and only travels on stdin; every output is masked (a failing `ADMINISTER KEY MANAGEMENT`
statement echoes its password — learned in the security lab). The vCPUs have AES-NI
([`cpu-aes.txt`](../../04-reports/09-tde-overhead/cpu-aes.txt)).

## Result

Same four workloads before and after, 120 s each ([`run_workload.sh`](../../02-workload/run_workload.sh)). The first
"after" round ran right after the restart, with a cold buffer cache — so a second round was run as a control.

| Workload | Before | After, 1st (cold cache) | After, 2nd (warm) | Change (warm) |
|----------|--------|-------------------------|-------------------|---------------|
| Transfers with commit wait, 4 sessions | 516.33 /s, commit 7.54 ms | 427.6 /s, 9.04 ms | 424.13 /s, 9.17 ms | **−17.9 %** |
| Monthly report, 4 sessions | 46.35 /s, CPU 39.8 ms/exec | 39.29 /s, 46.8 ms (1,260 physical reads/exec vs 29: cold cache) | 42.65 /s, 44.0 ms | **−8.0 %** |
| Yearly report on compressed partitions, 1 session (direct path) | 1.85 /s, CPU 534.7 ms/exec | 1.67 /s, 588.5 ms | 1.72 /s, 574.8 ms | **−7.0 %** (CPU +7.5 %) |
| Account statement via index, 4 sessions (cached) | 77,105 /s | 79,493 /s | 71,439 /s | none: within the run-to-run noise (+3 % / −7 %) |

Evidence per run: `04-reports/09-tde-overhead/{before,after,after2}-<workload>/` (AWR report, top SQL, top events,
summary).

## Reading the numbers

- **Reads from the buffer cache cost nothing extra:** a block is decrypted once when it is read from disk; the cached
  index lookups of the account statement did not change beyond noise.
- **Reads from disk pay decryption every time:** the yearly report reads its 20,002 blocks with direct path reads
  (no cache) in every execution — the same number of blocks before and after, and +7.5 % CPU per execution.
- **The commit path paid most:** the transfer's `UPDATE` went from 43.9 to 61–73 µs of CPU and `log file sync` from
  7.54 to ~9.1 ms. Changes to an encrypted tablespace are encrypted in redo and undo too, and on this 2-vCPU VM the
  commit path is CPU-bound (case 4), so that work shows up directly as commit latency. Both "after" rounds agree
  (−17.2 % and −17.9 %), so it is not the cold cache.
- Rule of thumb from this lab: **~0 % for cached reads, ~7–10 % for scans from disk, ~18 % for a commit-heavy OLTP
  load on 2 vCPUs** — measure on the target hardware before promising a number; more cores leave more room for LGWR.

## Notes / caveats

- One run per state (plus the control); the account-statement workload shows how large run-to-run noise is (±7 %).
- VM disks are cached in host RAM, so I/O is cheap and CPU dominates — on real storage the relative cost of
  decryption is usually smaller.
- Redo and undo written **before** the encryption (archived logs, backups) still hold clear data until they age out.
- The standby stb3 needs the same keystore before it applies the redo of the key creation, otherwise redo apply
  stops (`ORA-28374`, see the security lab, finding 5). Done before transport was turned back on: `WALLET_ROOT` set,
  `ewallet.p12` + `cwallet.sso` copied (same md5), auto-login keystore open; apply went through the key creation with
  no error and caught up (lag 0). `PERF` itself is `STANDBYS=NONE`.
- Turning transport back on also shipped ~3.7 GB of archived redo from these workloads to stb3 — more than the lab
  host had free (thin-provisioned VM disks), and the VMs paused. Applied logs were deleted on the standby and the
  disks trimmed; lesson: estimate the redo gap before re-enabling transport to a standby that was down.
- License: TDE is part of Oracle Advanced Security (extra cost on Enterprise Edition on-premises).

## Problems on the way

- `run_workload.sh` put the `BANK` password on the `sqlplus` command line (`bank/<password>@…`, visible in `ps`) —
  now `/nolog` + `CONNECT` on stdin, like the HA/DR harness.
- The first "after" round alone would have told a wrong story for the monthly report (−15 %: cold cache after the
  restart); the control round shows −8 %.
