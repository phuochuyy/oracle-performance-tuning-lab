#!/bin/bash
# Case 9 — TDE on orcl3 (prm3, datafiles on a filesystem) and offline encryption of PERF.BANK_DATA.
#   keystore  WALLET_ROOT (static -> restart), TDE_CONFIGURATION, united keystore, master keys for every container,
#             auto-login keystore; off-host copy of ewallet.p12 only (cwallet.sso stays on the server)
#   encrypt   ALTER TABLESPACE bank_data ENCRYPTION OFFLINE ENCRYPT (in place: no second copy of the 3.3 GB file and
#             almost no redo — the host had ~3.7 GB free; online encryption writes a full new copy)
# usage (from the host): TDE_PW=... ./tde_setup.sh keystore | encrypt      (TDE_PW from the git-ignored lab.env)
# Every output passes through a mask: a failing ADMINISTER KEY MANAGEMENT statement echoes its password.
set -eu
: "${TDE_PW:?set TDE_PW}"
WR=/u01/app/oracle/admin/orcl3/wallet
mask() { sed -E "s/${TDE_PW//\//\\/}/********/g; s/(identified by )\"[^\"]*\"/\1\"********\"/Ig"; }
sql() { { echo "whenever sqlerror exit failure"; echo "set lines 200 pages 50 timing on"; cat; echo "exit"; } \
          | ssh -o BatchMode=yes oracle@prm3 '. ~/.bash_profile >/dev/null 2>&1; sqlplus -s / as sysdba' 2>&1 | mask; }

case ${1:?keystore|encrypt} in
keystore)
  ssh -o BatchMode=yes oracle@prm3 "mkdir -p $WR/tde && chmod 700 $WR $WR/tde"
  echo "alter system set wallet_root='$WR' scope=spfile;" | sql
  echo "== restart orcl3 (static WALLET_ROOT); GoldenGate GG_B is stopped and started around it"
  ssh -o BatchMode=yes root@prm3 'systemctl stop ogg-ha; systemctl restart oracle-db; systemctl start ogg-ha'
  sql <<SQL
alter system set tde_configuration='KEYSTORE_CONFIGURATION=FILE' scope=both;
administer key management create keystore identified by "$TDE_PW";
administer key management set keystore open identified by "$TDE_PW" container=all;
administer key management set key using tag 'orcl3_case09' force keystore identified by "$TDE_PW" with backup container=all;
administer key management create auto_login keystore from keystore identified by "$TDE_PW";
col wrl_parameter for a45
select con_id, status, wallet_type, keystore_mode from v\$encryption_wallet order by con_id;
select con_id, count(*) master_keys from v\$encryption_keys group by con_id order by con_id;
SQL
  mkdir -p ~/work/lab/keystore-backup/orcl3 && chmod 700 ~/work/lab/keystore-backup/orcl3
  scp -q oracle@prm3:$WR/tde/ewallet.p12 ~/work/lab/keystore-backup/orcl3/ewallet.p12 && chmod 600 ~/work/lab/keystore-backup/orcl3/ewallet.p12
  echo "off-host copy: $(md5sum ~/work/lab/keystore-backup/orcl3/ewallet.p12 | cut -c1-12) / server: $(ssh -o BatchMode=yes oracle@prm3 "md5sum $WR/tde/ewallet.p12" | cut -c1-12)"
  ;;
encrypt)
  sql <<'SQL'
alter session set container=PERF;
select count(*) sessions_on_perf from v$session where con_id = sys_context('userenv','con_id') and type = 'USER' and username = 'BANK';
alter tablespace bank_data offline normal;
alter tablespace bank_data encryption offline using 'AES256' encrypt;
alter tablespace bank_data online;
select tablespace_name, encrypted, status from dba_tablespaces where tablespace_name = 'BANK_DATA';
select t.name, e.encryptionalg from v$encrypted_tablespaces e join v$tablespace t on t.ts# = e.ts# and t.con_id = e.con_id;
SQL
  ;;
esac
