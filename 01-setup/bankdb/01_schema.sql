-- BANKDB schema: tablespace, owner and tables.
-- usage: sqlplus / as sysdba @01_schema.sql <pdb_name> <bank_password>
whenever sqlerror exit failure
set echo on
alter session set container = &1;

create bigfile tablespace bank_data datafile size 512m autoextend on next 256m maxsize 8g;

create user bank identified by "&2"
  default tablespace bank_data quota unlimited on bank_data;
grant create session, create table, create view, create sequence, create procedure to bank;

create table bank.branches (
  branch_id    number(4)     not null,
  branch_code  varchar2(6)   not null,
  name         varchar2(40)  not null,
  city         varchar2(30)  not null,
  region       varchar2(10)  not null,
  opened_date  date          not null,
  constraint branches_pk primary key (branch_id),
  constraint branches_code_uk unique (branch_code)
);

create table bank.customers (
  customer_id  number(10)    not null,
  branch_id    number(4)     not null,
  full_name    varchar2(60)  not null,
  national_id  varchar2(12)  not null,
  dob          date          not null,
  phone        varchar2(12),
  email        varchar2(60),
  segment      varchar2(10)  not null,
  kyc_status   varchar2(10)  not null,
  created_at   date          not null,
  constraint customers_pk primary key (customer_id),
  constraint customers_nid_uk unique (national_id),
  constraint customers_branch_fk foreign key (branch_id) references bank.branches
);

create table bank.accounts (
  account_id   number(10)    not null,
  customer_id  number(10)    not null,
  account_no   varchar2(12)  not null,
  product      varchar2(10)  not null,
  currency     varchar2(3)   not null,
  status       varchar2(10)  not null,
  balance      number(18,2)  not null,
  opened_at    date          not null,
  constraint accounts_pk primary key (account_id),
  constraint accounts_no_uk unique (account_no),
  constraint accounts_customer_fk foreign key (customer_id) references bank.customers
);

create table bank.cards (
  card_id      number(10)    not null,
  account_id   number(10)    not null,
  pan          varchar2(19)  not null,
  expiry       varchar2(5)   not null,
  status       varchar2(10)  not null,
  issued_at    date          not null,
  constraint cards_pk primary key (card_id),
  constraint cards_pan_uk unique (pan),
  constraint cards_account_fk foreign key (account_id) references bank.accounts
);

create table bank.transactions (
  txn_id               number(12)    not null,
  account_id           number(10)    not null,
  txn_ts               timestamp     not null,
  txn_type             varchar2(12)  not null,
  channel              varchar2(8)   not null,
  amount               number(18,2)  not null,
  currency             varchar2(3)   not null,
  status               varchar2(10)  not null,
  counterparty_account varchar2(12),
  description          varchar2(60),
  constraint transactions_pk primary key (txn_id),
  constraint transactions_account_fk foreign key (account_id) references bank.accounts
);

-- Luhn check digit for the fake card numbers
create or replace function bank.luhn_check_digit(p_digits varchar2) return varchar2
  deterministic
is
  l_sum  pls_integer := 0;
  l_d    pls_integer;
  l_dbl  boolean := true;   -- rightmost payload digit is doubled
begin
  for i in reverse 1 .. length(p_digits) loop
    l_d := to_number(substr(p_digits, i, 1));
    if l_dbl then
      l_d := l_d * 2;
      if l_d > 9 then l_d := l_d - 9; end if;
    end if;
    l_sum := l_sum + l_d;
    l_dbl := not l_dbl;
  end loop;
  return to_char(mod(10 - mod(l_sum, 10), 10));
end;
/

exit
