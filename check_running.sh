#!/bin/bash
# List what may still be running, or billing, in this AWS account. Reads only: it changes and deletes nothing.
#   bash check_running.sh               ca-central-1 and account-wide checks first, then every other region
#   ONLY_CA=1 bash check_running.sh     ca-central-1 and account-wide checks only
# !! bills while it exists or runs, or starts runs on its own: look at these first
# -- listed for information: bills only when used, or only for what it stores
# ?? this account has no permission to check it, so nothing is known about it
# !? the check failed for another reason (the message is shown)
set -uo pipefail
export AWS_PAGER=""
ACCOUNT=$(aws sts get-caller-identity --query Account --output text) || { echo "STOP: no AWS credentials in this shell"; exit 1; }
TMP=$(mktemp -d)
MARK='!!'

# chk <label> <why> <aws command ...>: prints the command's output if it is not empty
chk() {
  local label=$1 why=$2; shift 2
  local out err rc n ef="$TMP/err.$BASHPID"
  out=$("$@" --region "$R" --output text 2>"$ef" </dev/null); rc=$?
  if [ $rc -ne 0 ]; then
    err=$(cat "$ef")
    case "$err" in
      *AccessDenied*|*UnauthorizedOperation*|*not\ authorized*|*AuthorizationError*|*UnrecognizedClient*|*InvalidClientTokenId*)
        echo "  ?? $label" ;;
      *) echo "  !? $label: $(echo "$err" | grep . | tail -1 | cut -c1-140)" ;;
    esac
    return
  fi
  out=$(echo "$out" | grep -v '^None$' | sed '/^\s*$/d')
  [ -z "$out" ] && return
  n=$(echo "$out" | wc -l)
  if [ "$n" -gt 1 ]; then echo "  $MARK $label ($why; $n):"; else echo "  $MARK $label ($why):"; fi
  echo "$out" | head -20 | sed 's/^/       /'
  [ "$n" -gt 20 ] && echo "       ... and $((n-20)) more"
  return 0
}
info() { MARK='--' chk "$@"; }

check_region() {
  R=$1
  chk "EC2 instances running" "per second while running" \
    aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running,stopping \
    --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`]|[0].Value]'
  chk "EC2 instances stopped" "the instance does not bill, its EBS volumes do" \
    aws ec2 describe-instances --filters Name=instance-state-name,Values=stopped \
    --query 'Reservations[].Instances[].[InstanceId,InstanceType]'
  chk "Auto Scaling groups with desired capacity above 0" "start instances again after you terminate them" \
    aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[?DesiredCapacity>`0`].[AutoScalingGroupName,DesiredCapacity]'
  chk "Spot requests open or active" "a persistent request starts instances again" \
    aws ec2 describe-spot-instance-requests --filters Name=state,Values=open,active \
    --query 'SpotInstanceRequests[].[SpotInstanceRequestId,State,Type]'
  chk "EBS volumes not attached" "per GB-month" \
    aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].[VolumeId,Size,VolumeType]'
  chk "EBS snapshots" "per GB-month stored; size shown is the source volume's" \
    aws ec2 describe-snapshots --owner-ids self --query 'Snapshots[].[SnapshotId,VolumeSize,StartTime]'
  chk "Elastic IP addresses" "every public IPv4 address bills per hour" \
    aws ec2 describe-addresses --query 'Addresses[].[PublicIp,AllocationId,InstanceId]'
  chk "NAT gateways" "per hour" \
    aws ec2 describe-nat-gateways --filter Name=state,Values=pending,available --query 'NatGateways[].[NatGatewayId,State]'
  chk "VPC interface endpoints" "per hour, per Availability Zone" \
    aws ec2 describe-vpc-endpoints --filters Name=vpc-endpoint-type,Values=Interface \
    --query 'VpcEndpoints[].[VpcEndpointId,ServiceName,State]'
  chk "Load balancers" "per hour" \
    aws elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,Type,State.Code]'
  chk "Classic load balancers" "per hour" \
    aws elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName'
  chk "RDS DB instances" "per hour while available; a stopped one starts again after 7 days" \
    aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus]'
  chk "RDS and Aurora DB clusters" "their instances bill per hour or per ACU-hour, storage per GB-month" \
    aws rds describe-db-clusters --query 'DBClusters[].[DBClusterIdentifier,Engine,Status]'
  chk "RDS manual snapshots" "per GB-month" \
    aws rds describe-db-snapshots --snapshot-type manual --query 'DBSnapshots[].[DBSnapshotIdentifier,AllocatedStorage]'
  chk "RDS retained automated backups" "per GB-month" \
    aws rds describe-db-instance-automated-backups --query 'DBInstanceAutomatedBackups[].[DBInstanceIdentifier,Status]'
  chk "Redshift clusters" "per hour unless paused; storage always" \
    aws redshift describe-clusters --query 'Clusters[].[ClusterIdentifier,NodeType,ClusterStatus]'
  chk "Redshift Serverless workgroups" "per RPU-hour while queries run; storage per GB-month" \
    aws redshift-serverless list-workgroups --query 'workgroups[].[workgroupName,status]'
  chk "EMR clusters" "per second while up, including WAITING" \
    aws emr list-clusters --active --query 'Clusters[].[Id,Name,Status.State]'
  chk "EMR Serverless applications started" "pre-initialized workers bill while started, even idle" \
    aws emr-serverless list-applications --states STARTING STARTED --query 'applications[].[id,name,state]'
  chk "Glue interactive sessions" "per DPU-hour until stopped or the idle timeout" \
    aws glue list-sessions --query 'Sessions[?Status==`READY`||Status==`PROVISIONING`].[Id,Status]'
  chk "Glue dev endpoints" "per DPU-hour" \
    aws glue get-dev-endpoints --query 'DevEndpoints[].[EndpointName,Status]'
  chk "Glue crawlers running" "per DPU-hour while running" \
    aws glue get-crawlers --query 'Crawlers[?State==`RUNNING`].[Name,State]'
  chk "Glue scheduled triggers turned on" "start a job run on a schedule" \
    aws glue get-triggers --query 'Triggers[?Type==`SCHEDULED`&&State==`ACTIVATED`].[Name,Schedule]'
  chk "Glue crawlers on a schedule" "start a crawl on a schedule" \
    aws glue get-crawlers --query 'Crawlers[?Schedule.State==`SCHEDULED`].[Name,Schedule.ScheduleExpression]'
  info "Glue jobs" "bill only while a run is going; runs are checked next" \
    aws glue list-jobs --query 'JobNames[]'
  local J
  while IFS= read -r J; do
    [ -z "$J" ] && continue
    chk "Glue job \"$J\" running" "per DPU-hour" \
      aws glue get-job-runs --job-name "$J" --max-items 10 \
      --query 'JobRuns[?JobRunState==`RUNNING`||JobRunState==`STARTING`||JobRunState==`STOPPING`||JobRunState==`WAITING`].[Id,JobRunState]'
  done < <(aws glue list-jobs --region "$R" --query 'JobNames[]' --output json 2>/dev/null \
           | python3 -c 'import json,sys; [print(j) for j in json.load(sys.stdin)]' 2>/dev/null)
  chk "Athena capacity reservations" "per DPU-hour while active" \
    aws athena list-capacity-reservations --query 'CapacityReservations[?Status==`ACTIVE`].[Name,TargetDpus]'
  chk "SageMaker notebook instances" "per hour while InService" \
    aws sagemaker list-notebook-instances --status-equals InService --query 'NotebookInstances[].[NotebookInstanceName,InstanceType]'
  chk "SageMaker endpoints" "real-time endpoints per instance-hour" \
    aws sagemaker list-endpoints --query 'Endpoints[].[EndpointName,EndpointStatus]'
  chk "SageMaker Studio apps running" "apps on an instance bill per hour while InService" \
    aws sagemaker list-apps --query 'Apps[?Status==`InService`].[AppName,AppType,Status]'
  chk "Kinesis data streams" "per shard-hour, or per stream-hour on demand" \
    aws kinesis list-streams --query 'StreamSummaries[].[StreamName,StreamModeDetails.StreamMode,StreamStatus]'
  chk "Managed Flink applications running" "per KPU-hour" \
    aws kinesisanalyticsv2 list-applications \
    --query 'ApplicationSummaries[?ApplicationStatus!=`READY`&&ApplicationStatus!=`DELETING`].[ApplicationName,ApplicationStatus]'
  chk "MSK clusters" "provisioned per broker-hour, serverless per cluster-hour" \
    aws kafka list-clusters-v2 --query 'ClusterInfoList[].[ClusterName,ClusterType,State]'
  chk "OpenSearch domains" "per instance-hour" \
    aws opensearch list-domain-names --query 'DomainNames[].DomainName'
  chk "OpenSearch Serverless collections" "per OCU-hour, with a minimum unless the group scales to zero" \
    aws opensearchserverless list-collections --query 'collectionSummaries[].[name,status]'
  chk "ElastiCache clusters" "per node-hour" \
    aws elasticache describe-cache-clusters --query 'CacheClusters[].[CacheClusterId,CacheNodeType,CacheClusterStatus]'
  chk "ElastiCache serverless caches" "per GB-hour stored, 1 GB minimum" \
    aws elasticache describe-serverless-caches --query 'ServerlessCaches[].[ServerlessCacheName,Status]'
  chk "EKS clusters" "per hour" \
    aws eks list-clusters --query 'clusters'
  info "ECS clusters" "free; Fargate tasks in them bill per second while running" \
    aws ecs list-clusters --query 'clusterArns'
  chk "MWAA (Airflow) environments" "per hour" \
    aws mwaa list-environments --query 'Environments'
  chk "DMS replication instances" "per hour" \
    aws dms describe-replication-instances --query 'ReplicationInstances[].[ReplicationInstanceIdentifier,ReplicationInstanceClass,ReplicationInstanceStatus]'
  info "DynamoDB tables" "storage per GB-month; on-demand reads and writes per request" \
    aws dynamodb list-tables --query 'TableNames'
  local T
  for T in $(aws dynamodb list-tables --region "$R" --query 'TableNames' --output text 2>/dev/null); do
    chk "DynamoDB table $T in provisioned mode" "per capacity-unit-hour, used or not" \
      aws dynamodb describe-table --table-name "$T" \
      --query '[Table]|[?BillingModeSummary.BillingMode!=`PAY_PER_REQUEST`].[TableName,ProvisionedThroughput.ReadCapacityUnits,ProvisionedThroughput.WriteCapacityUnits]'
  done
  chk "DynamoDB on-demand backups" "per GB-month" \
    aws dynamodb list-backups --backup-type USER --query 'BackupSummaries[].[TableName,BackupName]'
  info "Lambda functions" "bill per request and duration, only when invoked" \
    aws lambda list-functions --query 'Functions[].[FunctionName,Runtime]'
  chk "Lambda event source mappings turned on" "invoke a function on their own (queue, stream)" \
    aws lambda list-event-source-mappings --query 'EventSourceMappings[?State==`Enabled`].[FunctionArn,EventSourceArn]'
  chk "EventBridge schedule rules turned on" "start targets on a schedule" \
    aws events list-rules --query 'Rules[?State==`ENABLED`&&ScheduleExpression!=`null`].[Name,ScheduleExpression]'
  chk "EventBridge Scheduler schedules turned on" "start targets on a schedule" \
    aws scheduler list-schedules --state ENABLED --query 'Schedules[].[Name,GroupName]'
  chk "Secrets Manager secrets" "per secret-month" \
    aws secretsmanager list-secrets --query 'SecretList[].Name'
}

show() {   # show <file>: findings, then the checks without permission on one line
  grep -v '^  ?? ' "$1"
  local d; d=$(grep '^  ?? ' "$1" | sed 's/^  ?? //' | paste -sd'|' - | sed 's/|/; /g')
  [ -n "$d" ] && echo "  ?? no permission to check: $d"
  return 0
}
summary() {
  echo
  echo "$1: $(cat "$TMP"/*.txt | grep -c '^  !! ') to look at (!!), $(cat "$TMP"/*.txt | grep -c '^  ?? ') checks without permission (??), $(cat "$TMP"/*.txt | grep -c '^  !? ') failed (!?). Nothing was changed."
}

# 1. ca-central-1, the course's region, and the account-wide checks: reported first
echo "account $ACCOUNT"
echo "== ca-central-1 (about a minute)"
check_region ca-central-1 > "$TMP/ca-central-1.txt" 2>&1
show "$TMP/ca-central-1.txt"
echo "== whole account"
R=us-east-1
{
info "S3 buckets" "per GB-month of what they hold" aws s3api list-buckets --query 'Buckets[].Name'
chk "Route 53 hosted zones" "per zone-month" aws route53 list-hosted-zones --query 'HostedZones[].Name'
chk "Cost so far this month by service, USD" "from Cost Explorer; this one call bills USD 0.01" \
  aws ce get-cost-and-usage --time-period Start=$(date -u +%Y-%m-01),End=$(date -u -d tomorrow +%F) \
  --granularity MONTHLY --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[].Groups[?to_number(Metrics.UnblendedCost.Amount)>`0.01`][].[Keys[0],Metrics.UnblendedCost.Amount]'
} > "$TMP/global.txt" 2>&1
show "$TMP/global.txt" | awk -F'\t' 'NF==2 && $2 ~ /^[0-9.]+$/ {printf "%s\t%.2f\n",$1,$2; next} {print}'
summary "ca-central-1 and whole account"

# 2. every other region the account has turned on: one probe call each, full checks only where it is allowed
[ -n "${ONLY_CA:-}" ] && { rm -rf "$TMP"; exit 0; }
OTHER=$(aws ec2 describe-regions --region ca-central-1 --query 'Regions[].RegionName' --output text 2>/dev/null | tr '\t' '\n' | grep -vx ca-central-1)
[ -z "$OTHER" ] && OTHER="us-east-1 us-west-2"
echo
echo "== other regions (Ctrl-C stops here; the report above stands)"
ALLOWED=""; BLOCKED=""
for R in $OTHER; do
  if aws ec2 describe-instances --region "$R" --max-items 1 --output text >/dev/null 2>&1; then ALLOWED="$ALLOWED $R"; else BLOCKED="$BLOCKED $R"; fi
done
[ -n "$BLOCKED" ] && echo "not allowed in this account (skipped):$BLOCKED"
n=0
for R in $ALLOWED; do
  check_region "$R" > "$TMP/$R.txt" 2>&1 &
  n=$((n+1)); [ $((n % 4)) -eq 0 ] && wait
done
wait
for R in $ALLOWED; do
  if grep -q '^  !! ' "$TMP/$R.txt"; then echo "== $R"; show "$TMP/$R.txt"; fi
done
QUIET=$(for R in $ALLOWED; do grep -q '^  !! ' "$TMP/$R.txt" || echo "$R"; done | paste -sd' ' -)
[ -n "$QUIET" ] && echo "nothing billing found in: $QUIET"
summary "all regions"
rm -rf "$TMP"
