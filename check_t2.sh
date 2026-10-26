#!/bin/bash
# Tutorial 2 check: run in CloudShell (Region ca-central-1) before the tutorial, or whenever a step fails.
#   curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/b3-t2-glue-rides/main/check_t2.sh && bash check_t2.sh
# It only reads your account and changes nothing. Each line says ✔ or ✗, and each ✗ says what to run.
# CloudShell sets AWS_REGION to the console's Region, and AWS_REGION wins over AWS_DEFAULT_REGION, so set both.
export AWS_REGION=ca-central-1 AWS_DEFAULT_REGION=ca-central-1
FAIL=0
NEED_GLUE=0; NEED_ATHENA=0
ERR=$(mktemp); trap 'rm -f "$ERR"' EXIT
ok()  { echo "✔ $1"; }
bad() { echo "✗ $1"; [ -s "$ERR" ] && echo "    AWS said: $(grep -m1 . "$ERR" | cut -c1-200)"; echo "    fix: $2"; FAIL=$((FAIL + 1)); }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$ACCOUNT" ]; then
  echo "✗ CloudShell cannot read your account. Reopen CloudShell from the AWS console and run this again."; exit 1
fi
ok "account $ACCOUNT, Region ca-central-1"

T1="curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/b3-t1-athena-rides/main/setup_athena.sh && bash setup_athena.sh"
L7="curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/l7-spark-glue/main/setup_glue.sh && bash setup_glue.sh"
T2="run the three lines under '2. Set up the job (once)' in the README (they run setup_t2.sh)"

aws iam get-role --role-name 436c-glue-notebook >/dev/null 2>"$ERR" \
  && ok "Glue role 436c-glue-notebook (Glue tutorial setup)" || { bad "no Glue role 436c-glue-notebook" "$L7"; NEED_GLUE=1; }
aws s3api head-bucket --bucket "436c-glue-$ACCOUNT" >/dev/null 2>"$ERR" \
  && ok "bucket 436c-glue-$ACCOUNT (Glue tutorial setup)" || { bad "no bucket 436c-glue-$ACCOUNT" "$L7"; NEED_GLUE=1; }
aws athena get-data-catalog --name course >/dev/null 2>"$ERR" \
  && ok "Athena data source course (Athena tutorial setup)" || { bad "no Athena data source course" "$T1"; NEED_ATHENA=1; }
LOC=$(aws athena get-work-group --work-group primary --query 'WorkGroup.Configuration.ResultConfiguration.OutputLocation' --output text 2>/dev/null)
case "$LOC" in s3://*) ok "Athena saves results to $LOC (Athena tutorial setup)";; *) bad "Athena has no result location" "$T1"; NEED_ATHENA=1;; esac
LIMIT=$(aws athena get-work-group --work-group primary --query 'WorkGroup.Configuration.BytesScannedCutoffPerQuery' --output text 2>/dev/null)
case "$LIMIT" in ""|None) bad "no Data scanned limit on the workgroup primary" "$T1"; NEED_ATHENA=1;;
  *) ok "Data scanned limit $((LIMIT / 1000000000)) GB a query";; esac

aws iam get-role-policy --role-name 436c-glue-notebook --policy-name course-lake-read >/dev/null 2>"$ERR" \
  && ok "Glue role can read the course lakehouse (setup_t2.sh)" || bad "the Glue role cannot read the course lakehouse yet" "$T2"
aws s3api head-object --bucket "436c-glue-$ACCOUNT" --key tutorial2/load_rides_month.py >/dev/null 2>"$ERR" \
  && ok "job script in your bucket (setup_t2.sh)" || bad "the job script is not in your bucket" "$T2"
if aws glue get-job --job-name rides-month >/dev/null 2>"$ERR"; then
  ok "Glue job rides-month (setup_t2.sh)"
  RUN=$(aws glue get-job-runs --job-name rides-month --max-items 1 --query 'JobRuns[0].[JobRunState,ErrorMessage]' --output text 2>/dev/null | head -1)
  case "$RUN" in
    ""|None*) echo "· the job has not run yet. Step 1 starts it." ;;
    SUCCEEDED*) ok "last run of rides-month succeeded" ;;
    RUNNING*|STARTING*|WAITING*) echo "· the job is still running. Wait for Succeeded before you query the table." ;;
    *) bad "last run of rides-month: $RUN" "read the error in the Glue console (ETL jobs, rides-month, Runs), then start the job again" ;;
  esac
else
  bad "no Glue job rides-month" "$T2"
fi

echo
if [ "$NEED_GLUE" -eq 1 ] || [ "$NEED_ATHENA" -eq 1 ]; then
  echo "An earlier tutorial's setup is missing. Run these in CloudShell, in this order, then run this check again:"
  N=1
  [ "$NEED_GLUE" -eq 1 ] && { echo "  $N. Glue tutorial setup:   $L7"; N=$((N + 1)); }
  [ "$NEED_ATHENA" -eq 1 ] && { echo "  $N. Athena tutorial setup: $T1"; N=$((N + 1)); }
  echo "  $N. This tutorial's setup: the three lines under '2. Set up the job (once)' in the README"
  echo
fi
if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; else echo "$FAIL check(s) failed. Run each fix above, then run this check again."; fi
