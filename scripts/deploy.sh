#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_profile

BUCKET="$(deploy_bucket)"
$AWS s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1 || die \
  "Deploy bucket missing - run scripts/build-and-upload.sh first."

PACKAGED="$(mktemp -t cda-packaged-XXXX.yaml)"
say "Packaging nested templates -> s3://$BUCKET/templates/"
$AWS cloudformation package \
  --template-file "$ROOT/infra/root.yaml" \
  --s3-bucket "$BUCKET" --s3-prefix templates \
  --output-template-file "$PACKAGED"

say "Deploying stack '$STACK_NAME' (metric=$SCALING_METRIC, desired=$DESIRED, max=$MAX_SIZE) in $REGION"
$AWS cloudformation deploy \
  --template-file "$PACKAGED" \
  --stack-name "$STACK_NAME" \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --tags $(stack_tags) \
  --parameter-overrides \
    ArtifactBucket="$BUCKET" \
    ScalingMetric="$SCALING_METRIC" \
    CpuTargetValue="$CPU_TARGET" \
    RequestCountTargetValue="$REQUEST_TARGET" \
    MinSize="$MIN_SIZE" MaxSize="$MAX_SIZE" DesiredCapacity="$DESIRED" \
    ProductInstanceType="$PRODUCT_INSTANCE_TYPE" \
    DBInstanceClass="$DB_INSTANCE_CLASS" \
    ProductXmx="$PRODUCT_XMX" ProductMaxThreads="$PRODUCT_MAX_THREADS" \
    AllowedClientCidr="$ALLOWED_CLIENT_CIDR" \
    AdminCidr="$ADMIN_CIDR" \
    EnableAlbAccessLogs="$ENABLE_ALB_LOGS" \
    ScheduleEnabled="$SCHEDULE_ENABLED"

ASG="$(stack_output AsgName)"
$AWS autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" \
  --min-size "$MIN_SIZE" --max-size "$MAX_SIZE" --desired-capacity "$DESIRED"
say "ASG $ASG set to min=$MIN_SIZE desired=$DESIRED max=$MAX_SIZE"

say "Deploy complete. Key outputs:"
$AWS cloudformation describe-stacks --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='AlbUrl'|| OutputKey=='HealthCheck'|| OutputKey=='ActiveScalingMetric'|| OutputKey=='DbEndpoint'].{Key:OutputKey,Value:OutputValue}" \
  --output table
rm -f "$PACKAGED"
