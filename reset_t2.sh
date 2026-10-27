#!/bin/bash
# Start tutorial 2 again from Step 1: removes the table the rides-month job made, and its files.
#   bash reset_t2.sh            asks before deleting anything
#   bash reset_t2.sh --yes      deletes without asking
#   bash reset_t2.sh --run      deletes, then starts the job again (Step 1) and waits for it to finish
#   DRY=1 bash reset_t2.sh      prints what it would do and changes nothing
# Keeps the role, the bucket, the database and the job, so setup_t2.sh does not need to run again.
set -euo pipefail
export AWS_REGION=ca-central-1 AWS_DEFAULT_REGION=ca-central-1 AWS_PAGER=""
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET=436c-glue-$ACCOUNT   # the same bucket setup_t2.sh uses; ignores a BUCKET set by A2 in ~/.bashrc
DB=tutorial
TABLE=rides_month
JOB=rides-month
PREFIX=s3://$BUCKET/tutorial2/warehouse/$DB.db/$TABLE/
YES=""; RUN=""
for a in "$@"; do
  case "$a" in --yes) YES=1 ;; --run) YES=1; RUN=1 ;; *) echo "unknown option $a"; exit 2 ;; esac
done
do_() { if [ -n "${DRY:-}" ]; then echo "would run: $*"; else "$@"; fi; }

# 1. A job run that is still going would write the table again, so stop here if there is one.
RUNNING=$(aws glue get-job-runs --job-name "$JOB" --max-items 5 \
  --query "JobRuns[?JobRunState=='RUNNING' || JobRunState=='STARTING' || JobRunState=='STOPPING'].Id" --output text 2>/dev/null || true)
if [ -n "$RUNNING" ] && [ "$RUNNING" != "None" ]; then
  echo "STOP: job $JOB is still running ($RUNNING). Wait until it ends (Glue console > ETL jobs > $JOB > Runs), then run this again."
  exit 1
fi

# 2. Say what will go, and ask.
HAS_TABLE=$(aws glue get-table --database-name "$DB" --name "$TABLE" --query Table.Name --output text 2>/dev/null || true)
NFILES=$( { aws s3 ls "$PREFIX" --recursive 2>/dev/null || true; } | wc -l)
echo "account $ACCOUNT"
if [ -n "$HAS_TABLE" ]; then echo "table   $DB.$TABLE exists"; else echo "table   $DB.$TABLE not there"; fi
echo "files   $NFILES under $PREFIX"
if [ -z "$HAS_TABLE" ] && [ "$NFILES" -eq 0 ]; then
  echo "Nothing to remove."
else
  if [ -z "$YES" ] && [ -z "${DRY:-}" ]; then
    read -r -p "Delete the table and its $NFILES files? Type yes: " ans
    [ "$ans" = "yes" ] || { echo "Nothing deleted."; exit 0; }
  fi
  # 3. The table leaves the Glue catalog first, so no reader sees a table without its files.
  [ -n "$HAS_TABLE" ] && do_ aws glue delete-table --database-name "$DB" --name "$TABLE" && echo "table   $DB.$TABLE removed from the catalog"
  # 4. Then its data, delete and metadata files (Glue's delete-table leaves them in S3).
  [ "$NFILES" -gt 0 ] && do_ aws s3 rm "$PREFIX" --recursive --only-show-errors && echo "files   $NFILES removed from S3"
fi

# 5. Optionally Step 1 again: start the job and wait.
if [ -n "$RUN" ]; then
  if [ -n "${DRY:-}" ]; then echo "would run: aws glue start-job-run --job-name $JOB"; exit 0; fi
  ID=$(aws glue start-job-run --job-name "$JOB" --query JobRunId --output text)
  echo "job     $JOB started ($ID), about 2.5 minutes"
  while :; do
    S=$(aws glue get-job-run --job-name "$JOB" --run-id "$ID" --query JobRun.JobRunState --output text)
    case "$S" in
      SUCCEEDED) echo "job     $JOB succeeded: the table is back as after Step 1"; break ;;
      FAILED|ERROR|TIMEOUT|STOPPED) echo "STOP: job ended $S; see Glue console > ETL jobs > $JOB > Runs"; exit 1 ;;
    esac
    sleep 15
  done
else
  echo
  echo "Done. Start again from Step 1:  aws glue start-job-run --job-name $JOB"
fi
