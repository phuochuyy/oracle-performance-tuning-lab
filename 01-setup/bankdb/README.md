# BANKDB — shared test dataset

A small retail-banking schema used by all my lab projects, so every project works on the same data:

| Project | How it uses BANKDB |
|---------|--------------------|
| oracle-performance-tuning-lab | large scale; `TRANSACTIONS` is the big table for AWR/ASH, partitioning, parallel cases |
| oracle-backup-recovery-drills | small scale; `verify_bankdb.sql` checksums prove the data is the same after each restore |
| oracle-security-compliance-lab | `CARDS.PAN` (fake card numbers) for TDE, redaction and PCI-DSS controls |
| oracle-dba-automation-cdc | ongoing transactions as the change stream for Debezium |

## Tables

| Table | Rows (per scale unit) | Notes |
|-------|-----------------------|-------|
| `BRANCHES` | 100 (fixed) | 5 regions |
| `CUSTOMERS` | 20,000 | segment skew: 85% RETAIL, 12% SME, 3% VIP |
| `ACCOUNTS` | 30,000 | 1–3 accounts per customer; ~1% are "hot" (payroll/merchant) accounts |
| `CARDS` | 24,000 | `PAN` is a 16-digit **fake** number (prefix `900001`, Luhn-valid) — never real card data |
| `TRANSACTIONS` | 500,000 | 2 years of history; ~30% of rows belong to the 1% hot accounts; status 97% POSTED / 2% PENDING / 1% REVERSED |

Scale 1 ≈ 60 MB, scale 16 ≈ 8 M transactions (~1 GB with indexes).

The skew is on purpose: hot accounts and rare statuses are what make bind peeking, histograms and
plan regressions show up in the tuning cases.

## Design choices

- **Deterministic:** every value is derived from `ORA_HASH(row number, …, salt)`, not `DBMS_RANDOM`,
  so the same scale always produces exactly the same rows. That makes checksums comparable between
  runs and between databases (restore drills, replication checks).
- **Only primary/unique keys are created at load.** Foreign-key columns are left unindexed on purpose;
  adding the right indexes is part of the tuning cases.
- Loaded with direct-path insert. The CDB runs `FORCE LOGGING` (Data Guard), so loading still
  generates redo — check FRA space before loading a large scale.

## Scripts

| Script | Run as | Purpose |
|--------|--------|---------|
| `00_create_pdb.sql` | SYSDBA in CDB | create PDB `PERF` (+ `STANDBYS=NONE`) |
| `01_schema.sql` | SYSDBA in PDB | tablespace, user `BANK`, tables |
| `02_load.sql` | SYSDBA in PDB | load data for a given scale, gather statistics |
| `03_verify.sql` | any user with read access | row counts + checksums |
