-- Load BANKDB for a given scale (1 = 500k transactions, 16 = 8M).
-- usage: sqlplus / as sysdba @02_load.sql <pdb_name> <scale>
--
-- Every value comes from ORA_HASH(row number, max, salt), so a given scale always
-- produces exactly the same data (checksums in 03_verify.sql can be compared).
whenever sqlerror exit failure
set echo on timing on
alter session set container = &1;
define scale = &2

alter session enable parallel dml;

-- BRANCHES (fixed 100 rows)
insert /*+ append */ into bank.branches
select n,
       'BR' || lpad(n, 3, '0'),
       'Branch ' || n,
       regexp_substr('Ha Noi,Ho Chi Minh,Da Nang,Hai Phong,Can Tho,Hue,Nha Trang,Vung Tau,Bien Hoa,Quy Nhon',
                     '[^,]+', 1, mod(n - 1, 10) + 1),
       case mod(n - 1, 10) when 0 then 'NORTH' when 3 then 'NORTH' when 1 then 'SOUTH'
                           when 4 then 'SOUTH' when 7 then 'SOUTH' when 8 then 'SOUTH'
                           else 'CENTRAL' end,
       date '2005-01-01' + ora_hash(n, 5000, 1)
from (select level n from dual connect by level <= 100);
commit;

-- CUSTOMERS (20,000 per scale unit)
insert /*+ append */ into bank.customers
select n,
       mod(ora_hash(n, 99, 15), 100) + 1,
       regexp_substr('Nguyen,Tran,Le,Pham,Hoang,Phan,Vu,Dang,Bui,Do', '[^,]+', 1, mod(ora_hash(n, 9, 21), 10) + 1)
         || ' ' || regexp_substr('Van,Thi,Minh,Thanh,Ngoc', '[^,]+', 1, mod(ora_hash(n, 4, 22), 5) + 1)
         || ' ' || regexp_substr('An,Binh,Chau,Dung,Giang,Hai,Hanh,Hung,Khanh,Lan,Linh,Long,Mai,Nam,Phuong,Quang,Son,Tam,Thao,Trung,Tuan,Vy',
                                 '[^,]+', 1, mod(ora_hash(n, 21, 23), 22) + 1),
       '079' || lpad(n, 9, '0'),
       date '1960-01-01' + ora_hash(n, 15000, 11),
       '09' || lpad(ora_hash(n, 99999999, 12), 8, '0'),
       'cust' || n || '@example.com',
       case when mod(ora_hash(n, 99, 13), 100) < 85 then 'RETAIL'
            when mod(ora_hash(n, 99, 13), 100) < 97 then 'SME' else 'VIP' end,
       case when mod(ora_hash(n, 99, 14), 100) < 95 then 'VERIFIED' else 'PENDING' end,
       date '2018-01-01' + ora_hash(n, 2000, 16)
from (select level n from dual connect by level <= 20000 * &scale);
commit;

-- ACCOUNTS (30,000 per scale unit; account_id multiple of 100 = "hot" payroll/merchant account)
insert /*+ append */ into bank.accounts
select n,
       mod(n - 1, 20000 * &scale) + 1,
       '1' || lpad(n, 11, '0'),
       case mod(ora_hash(n, 2, 31), 3) when 0 then 'SAVINGS' when 1 then 'CURRENT' else 'TERM' end,
       case when mod(n, 33) = 0 then 'USD' else 'VND' end,
       case when mod(ora_hash(n, 99, 32), 100) < 96 then 'ACTIVE'
            when mod(ora_hash(n, 99, 32), 100) < 99 then 'DORMANT' else 'CLOSED' end,
       round(ora_hash(n, 999999, 33) * 1000, -3),
       date '2018-01-01' + ora_hash(n, 2500, 34)
from (select level n from dual connect by level <= 30000 * &scale);
commit;

-- CARDS (24,000 per scale unit; fake PAN: 900001 + 9 digits + Luhn check digit)
insert /*+ append */ into bank.cards
select n,
       n,
       p || bank.luhn_check_digit(p),
       lpad(mod(ora_hash(n, 11, 41), 12) + 1, 2, '0') || '/' || to_char(26 + mod(ora_hash(n, 4, 42), 5)),
       case when mod(ora_hash(n, 99, 43), 100) < 92 then 'ACTIVE'
            when mod(ora_hash(n, 99, 43), 100) < 97 then 'BLOCKED' else 'EXPIRED' end,
       date '2019-01-01' + ora_hash(n, 2000, 44)
from (select level n, '900001' || lpad(level, 9, '0') p from dual connect by level <= 24000 * &scale);
commit;

-- TRANSACTIONS (500,000 per scale unit, 2 years; ~30% go to the 1% hot accounts)
insert /*+ append */ into bank.transactions
select n,
       case when mod(ora_hash(n, 99, 51), 100) < 30
            then (mod(ora_hash(n, 300 * &scale - 1, 52), 300 * &scale) + 1) * 100
            else mod(ora_hash(n, 30000 * &scale - 1, 53), 30000 * &scale) + 1 end,
       cast(date '2024-01-01' as timestamp) + numtodsinterval(ora_hash(n, 63071999, 54), 'SECOND'),
       t,
       c,
       case t when 'FEE' then 11000
              else round((ora_hash(n, 99999, 57) + 1) * case when mod(n, 50) = 0 then 5000 else 100 end, -2) end,
       'VND',
       case when mod(ora_hash(n, 99, 58), 100) < 97 then 'POSTED'
            when mod(ora_hash(n, 99, 58), 100) < 99 then 'PENDING' else 'REVERSED' end,
       case when t like 'TRANSFER%' then lpad(ora_hash(n, 99999999, 59), 12, '0') end,
       t || ' via ' || c
from (
  select n,
         case when mod(ora_hash(n, 99, 55), 100) < 35 then 'CARD_PAYMENT'
              when mod(ora_hash(n, 99, 55), 100) < 55 then 'TRANSFER_OUT'
              when mod(ora_hash(n, 99, 55), 100) < 72 then 'TRANSFER_IN'
              when mod(ora_hash(n, 99, 55), 100) < 85 then 'WITHDRAW'
              when mod(ora_hash(n, 99, 55), 100) < 97 then 'DEPOSIT' else 'FEE' end t,
         regexp_substr('ATM,MOBILE,BRANCH,POS,INTERNET', '[^,]+', 1, mod(ora_hash(n, 4, 56), 5) + 1) c
  from (select (a.n - 1) * 10000 + b.n n
        from (select level n from dual connect by level <= ceil(500000 * &scale / 10000)) a,
             (select level n from dual connect by level <= 10000) b)
  where n <= 500000 * &scale
);
commit;

exec dbms_stats.gather_schema_stats('BANK', degree => 2)

select table_name, num_rows, blocks from dba_tables where owner = 'BANK' order by table_name;
exit
