#!/bin/bash
# Go deeper (optional): make a Glue 6.0 copy of tutorial 2's job, rides-month-g6, and leave rides-month as it is.
#   curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/b3-t2-glue-rides/main/rerun_glue6.sh && bash rerun_glue6.sh
# The copy uses the same script, role, workers and arguments as rides-month. Only the Glue version changes.
set -euo pipefail
export AWS_DEFAULT_REGION=ca-central-1
SRC=rides-month
NEW=rides-month-g6
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

aws glue get-job --job-name "$SRC" --output json > "$TMP/src.json" 2>/dev/null \
  || { echo "STOP: the job $SRC is not in this account. Run setup_t2.sh first (README section 2)."; exit 1; }
python3 - "$TMP/src.json" "$NEW" > "$TMP/new.json" <<'PY'
import json, sys
job = json.load(open(sys.argv[1]))["Job"]
copy = {k: job[k] for k in ("Role", "Command", "DefaultArguments", "WorkerType", "NumberOfWorkers", "Timeout",
                            "MaxRetries") if k in job}
copy["Name"] = sys.argv[2]
copy["GlueVersion"] = "6.0"
print(json.dumps(copy))
PY
if aws glue get-job --job-name "$NEW" >/dev/null 2>&1; then
  aws glue delete-job --job-name "$NEW" >/dev/null
fi
aws glue create-job --cli-input-json "file://$TMP/new.json" >/dev/null
echo "job     $NEW created: Glue 6.0, with the same script, role, workers and arguments as $SRC"
echo
echo "Next, as the README's Explore on your own exercise says:"
echo "  1. In Athena:      DROP TABLE tutorial.rides_month;"
echo "  2. In CloudShell:  aws glue start-job-run --job-name $NEW"
