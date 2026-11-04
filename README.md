# Oracle Performance Tuning Lab

Realistic performance problems on a banking dataset. Each case starts from a symptom, finds the cause with AWR, ASH, ADDM or SQL Monitor, applies a fix, and compares before and after with the same workload.

The problems are set up on purpose in a small lab, so the comparisons matter more than the absolute values.

## What is in it

- **SQL and plans**: a missing index, a plan regression fixed with SQL Plan Management, partitioning, compression.
- **Concurrency**: a batch job blocking money transfers.
- **Redo and I/O**: database writer throughput and the cost of zero data loss per commit.
- **Memory**: parallel query and PGA.
- **Checking the tools**: ADDM advice tested before trusting it, results compared with Oracle Support's SQLT.
- **The cost of security**: what TDE and Unified Auditing cost.

AWR, ASH, ADDM and SQL Monitor need the Diagnostics and Tuning Packs on a licensed database.

## Where to look

- [Results of all cases](docs/details.md)
- [Cases](03-cases/)
- [Reports](04-reports/)
- [Dataset](01-setup/bankdb/)
- [Worklog, including my mistakes](notes/worklog.md)
