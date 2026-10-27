-- Empty all BANKDB tables so 02_load.sql can be run again (e.g. with another scale).
-- usage: sqlplus / as sysdba @04_reset.sql <pdb_name>
-- A parent table cannot be truncated while an enabled foreign key points to it
-- (ORA-02266), even if the child is empty: disable the FKs first.
whenever sqlerror exit failure
set verify off
alter session set container = &1;
alter table bank.transactions disable constraint transactions_account_fk;
alter table bank.cards        disable constraint cards_account_fk;
alter table bank.accounts     disable constraint accounts_customer_fk;
alter table bank.customers    disable constraint customers_branch_fk;
truncate table bank.transactions;
truncate table bank.cards;
truncate table bank.accounts;
truncate table bank.customers;
truncate table bank.branches;
alter table bank.customers    enable constraint customers_branch_fk;
alter table bank.accounts     enable constraint accounts_customer_fk;
alter table bank.cards        enable constraint cards_account_fk;
alter table bank.transactions enable constraint transactions_account_fk;
exit
