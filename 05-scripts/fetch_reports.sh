#!/bin/bash
# Copy one run's evidence from the lab VM into this repo.
# usage: 05-scripts/fetch_reports.sh <case> <tag> [host]
# (scp -r into a directory that does not exist yet copies the *contents* one level up — mkdir first)
set -eu
case=$1 tag=$2 host=${3:-prm3}
H=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$H/04-reports/$case/$tag"
scp -q "oracle@$host:perflab/04-reports/$case/$tag/*" "$H/04-reports/$case/$tag/"
ls "$H/04-reports/$case/$tag"
