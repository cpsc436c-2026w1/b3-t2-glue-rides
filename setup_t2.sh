#!/bin/bash
# B3T2 setup: run in CloudShell (Region ca-central-1) after L7's setup_glue.sh (github.com/cpsc436c-2026w1/l7-spark-glue).
#   bash setup_t2.sh
# 1. lets your Glue role 436c-glue-notebook read the course lake (rides), 2. copies the job script to your bucket,
# 3. creates the Glue job rides-month (Glue 5.0, 2 G.1X workers). Running it again is safe.
set -euo pipefail
export AWS_DEFAULT_REGION=ca-central-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
# If any command below fails, print a STOP line naming it before the script exits.
trap 'echo "STOP: a setup step failed: $BASH_COMMAND (the AWS error is above). Send your account number ($ACCOUNT) and that error to your TA."' ERR
ROLE=436c-glue-notebook
BUCKET=${BUCKET:-436c-glue-$ACCOUNT}
JOB=rides-month
SCRIPT_SRC=${SCRIPT_SRC:-load_rides_month.py}

aws iam get-role --role-name "$ROLE" >/dev/null 2>&1 || { echo "STOP: role $ROLE not found; run L7's setup_glue.sh first"; exit 1; }
aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1 || { echo "STOP: bucket $BUCKET not found; run L7's setup_glue.sh first or set BUCKET=<your bucket>"; exit 1; }

# SKIP_ROLE_POLICY is a hook for staff tests. Students do not set it.
if [ -z "${SKIP_ROLE_POLICY:-}" ]; then
aws iam put-role-policy --role-name "$ROLE" --policy-name course-lake-read --policy-document '{
  "Version": "2012-10-17", "Statement": [
    {"Effect": "Allow", "Action": "s3:GetObject", "Resource": "arn:aws:s3:::436c-l6-bench-940482406111/lake/*"},
    {"Effect": "Allow", "Action": "s3:ListBucket", "Resource": "arn:aws:s3:::436c-l6-bench-940482406111",
     "Condition": {"StringLike": {"s3:prefix": "lake/*"}}}]}'
echo "role    $ROLE can read the course lake"
fi

aws s3 cp "$SCRIPT_SRC" "s3://$BUCKET/tutorial2/load_rides_month.py" --only-show-errors
echo "script  s3://$BUCKET/tutorial2/load_rides_month.py"

CONF="spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions --conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO --conf spark.sql.catalog.glue_catalog.warehouse=s3://$BUCKET/tutorial2/warehouse/"
ARGS=$(python3 -c 'import json,sys; print(json.dumps({"--datalake-formats":"iceberg","--conf":sys.argv[1],"--MONTH":"2024-03","--DATABASE":"tutorial"}))' "$CONF")
JOBDEF=$(python3 -c 'import json,sys; print(json.dumps({"Role":sys.argv[1],"GlueVersion":"5.0","WorkerType":"G.1X","NumberOfWorkers":2,"Timeout":15,"MaxRetries":0,"Command":{"Name":"glueetl","ScriptLocation":sys.argv[2],"PythonVersion":"3"},"DefaultArguments":json.loads(sys.argv[3])}))' \
  "arn:aws:iam::$ACCOUNT:role/$ROLE" "s3://$BUCKET/tutorial2/load_rides_month.py" "$ARGS")
if aws glue get-job --job-name "$JOB" >/dev/null 2>&1; then
  aws glue update-job --job-name "$JOB" --job-update "$JOBDEF" >/dev/null; echo "job     $JOB updated"
else
  aws glue create-job --name "$JOB" --cli-input-json "$JOBDEF" >/dev/null; echo "job     $JOB created"
fi
echo
echo "Start it:  aws glue start-job-run --job-name $JOB"
echo "Watch it:  Glue console > ETL jobs > $JOB > Runs (about 2.5 minutes)"
