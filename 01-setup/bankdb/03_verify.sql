-- Row counts + checksums of BANKDB. Same scale => same numbers on any database.
-- usage: sqlplus / as sysdba @03_verify.sql <pdb_name>
set lines 120 pages 50 verify off
col table_name for a14
-- full digits: the default format rounds the sum to 5 significant digits
col checksum for 99999999999999999999
alter session set container = &1;

select 'BRANCHES' table_name, count(*) row_count,
       sum(ora_hash(branch_id || '|' || branch_code || '|' || city)) checksum
from bank.branches
union all
select 'CUSTOMERS', count(*),
       sum(ora_hash(customer_id || '|' || national_id || '|' || segment || '|' || to_char(dob, 'YYYYMMDD')))
from bank.customers
union all
select 'ACCOUNTS', count(*),
       sum(ora_hash(account_id || '|' || customer_id || '|' || status || '|' || balance))
from bank.accounts
union all
select 'CARDS', count(*),
       sum(ora_hash(card_id || '|' || pan || '|' || status))
from bank.cards
union all
select 'TRANSACTIONS', count(*),
       sum(ora_hash(txn_id || '|' || account_id || '|' || to_char(txn_ts, 'YYYYMMDDHH24MISS') || '|' || amount || '|' || status))
from bank.transactions;
exit
