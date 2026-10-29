#!/bin/bash
# Run SQLT XTRACT for one SQL_ID (memory or AWR) as BANK in PERF, copy the result to 06-sqlt/runs/<tag>/.
# usage (from the host): 06-sqlt/xtract.sh <sql_id> <tag>
# sqltxtract.sql reads the SQLTXPLAIN password with ACCEPT ... HIDE, which gets an empty value without a
# terminal (ORA-20104 over ssh). A batch copy reads it as parameter 2 instead, as older SQLT versions did;
# the parameter is sent on stdin, so the password is not visible in ps.
set -eu
sql_id=$1 tag=$2
H=$(cd "$(dirname "$0")/.." && pwd)
. "$H/lab.env"
P="ssh -o BatchMode=yes oracle@prm3"
$P "cd ~/sqlt/run && sed -e \"104s/.*/DEF enter_tool_password = '^2';/\" sqltxtract.sql > sqltxtract_batch.sql"
$P ". ~/.bash_profile >/dev/null; rm -rf ~/sqlt-runs/$tag; mkdir -p ~/sqlt-runs/$tag; cd ~/sqlt-runs/$tag; sqlplus -s /nolog" <<EOF | grep -E "SQLTXTRACT completed|^ORA-" || true
connect bank/"$BANK_PASSWORD"@//prm3.rac:1521/perf.rac
@/home/oracle/sqlt/run/sqltxtract_batch.sql $sql_id $SQLT_PASSWORD
exit
EOF
mkdir -p "$H/06-sqlt/runs/$tag"
# only the reports: the full output (test case, exports, 10053 trace, AWR/ASH/ADDM copies) is ~46 MB
$P "cd ~/sqlt-runs/$tag && tar czf - *_main.html *_lite.html *_readme.txt" | tar xzf - -C "$H/06-sqlt/runs/$tag"
ls -la "$H/06-sqlt/runs/$tag"
