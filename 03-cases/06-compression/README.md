# Case 6 — Compressing historical partitions: space vs CPU

## Scenario

The 12 partitions of 2024 (4.0 M transactions, 379 MB) are historical and read-mostly. Compress them
and measure what it costs and saves: size, a serial yearly report over those partitions
(`bank.wl_year_report`, 1 session × 120 s) and a late correction on old rows
([`update_test.sql`](update_test.sql): update 10,980 rows of 2024-01-01, then roll back).

Compression type: **BASIC** (`ROW STORE COMPRESS BASIC`) — included in Enterprise Edition.
ADVANCED row compression needs the Advanced Compression Option license; Hybrid Columnar Compression
needs Exadata/ZFS storage. BASIC only compresses data written by direct-path load or `MOVE`; rows
updated later are stored uncompressed.

## Fix

[`compress.sql`](compress.sql): `ALTER TABLE ... MOVE PARTITION ... ROW STORE COMPRESS BASIC ONLINE
UPDATE INDEXES` for each 2024 partition — 4 min 43 s, table usable throughout, global PK stays VALID,
0 unusable index partitions. Redo for the move was handled by the archived-log housekeeping job.

## Result

| Metric | Before | After |
|--------|--------|-------|
| Size of the 2024 partitions | 379 MB, 47,877 blocks | **163 MB, 20,238 blocks** (−57 %, ratio 2.37) |
| Yearly report, blocks read per execution | 47,052 | 20,042 |
| Yearly report, CPU per execution | 350 ms | **505 ms** (+44 %) |
| Yearly report, executions in 120 s | 336 (357.6 ms each) | 235 (~511 ms each) — **~30 % slower** |
| Update 10,980 old rows: elapsed | 0.28 s | 0.28 s |
| Update: redo generated | 5.45 MB | **12.80 MB** (×2.35) |
| Update: partition size | 33 MB → 33 MB | 14 MB → 15 MB (updated rows decompressed and migrated) |

Both runs still read with `direct path read` (physical reads ≈ buffer gets) — my first guess, that
the smaller segment had switched to buffered reads, was wrong. The report is **CPU-bound** (DB CPU
~89 % of DB time) on a 2-vCPU VM whose virtual disk is cached in host RAM, so the 57 % IO saving is
cheap here and the decompression CPU dominates. On real storage, where scanning 379 MB from disk
costs more than decompressing 163 MB, the balance can flip — measure on the target system.

(In the after-run the report SQL itself was not among AWR's captured top SQL; per-execution numbers
come from the PL/SQL call that runs only that statement.)

## Decision for the lab

Kept compressed: it saves 216 MB, the data is historical, and reports on 2024 are rare. Not a good
choice for partitions that still take updates (2.35× redo, row migration) or for CPU-bound hot reports.

## Side finding (for the security project)

The AWR wait list showed `Failed Logon Delay` in both runs. The unified audit trail
([failed_logons_found.txt](../../04-reports/06-compression/failed_logons_found.txt)) shows 275 failed
SYS logons with ORA-01031 from the FSFO observer host `obs-r2` (`dgmgrl`) every ~12 s, and 5 ORA-01017
from `oracle@stb3` around the restarts. FSFO itself reports the observer as healthy. Not investigated
yet.
