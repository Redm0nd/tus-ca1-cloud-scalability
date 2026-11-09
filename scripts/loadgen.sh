#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_profile

BUCKET="$(deploy_bucket)"

loadgen_output() {
  $AWS cloudformation describe-stacks --stack-name "$LOADGEN_STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text 2>/dev/null
}

case "${1:-}" in
  up)
    ALB_URL="$(stack_output AlbUrl)"
    [ -n "$ALB_URL" ] && [ "$ALB_URL" != "None" ] || die "Root stack '$STACK_NAME' has no AlbUrl - run 'make up' first."
    VPC_ID="$($AWS ec2 describe-vpcs --filters Name=tag:Name,Values=cda-vpc --query 'Vpcs[0].VpcId' --output text)"
    SUBNET_ID="$($AWS ec2 describe-subnets --filters Name=tag:Name,Values=cda-public-a --query 'Subnets[0].SubnetId' --output text)"

    say "Uploading k6 scripts -> s3://$BUCKET/loadgen/scripts/"
    $AWS s3 sync "$ROOT/experiments/load/" "s3://$BUCKET/loadgen/scripts/" --delete --exclude '*.md'

    say "Deploying '$LOADGEN_STACK' ($LOADGEN_INSTANCE_TYPE) -> $ALB_URL"
    $AWS cloudformation deploy \
      --template-file "$ROOT/infra/loadgen.yaml" \
      --stack-name "$LOADGEN_STACK" \
      --capabilities CAPABILITY_IAM \
      --tags $(stack_tags) Component=loadgen \
      --parameter-overrides \
        VpcId="$VPC_ID" SubnetId="$SUBNET_ID" \
        ArtifactBucket="$BUCKET" BaseUrl="$ALB_URL" \
        InstanceType="$LOADGEN_INSTANCE_TYPE"
    say "Load-gen up: $(loadgen_output InstanceId). k6 installs at boot (~1-2 min); then: make loadgen-shell"
    ;;
  shell)
    ID="$(loadgen_output InstanceId)"
    [ -n "$ID" ] && [ "$ID" != "None" ] || die "Load-gen stack not found - run 'make loadgen-up'."
    say "SSM session to $ID. Try:  sudo -i; cda-run baseline read-heavy.js"
    $AWS ssm start-session --target "$ID"
    ;;
  run)
    shift; LABEL="${1:?label}"; SCRIPT="${2:?script.js}"; shift 2
    ID="$(loadgen_output InstanceId)"
    [ -n "$ID" ] && [ "$ID" != "None" ] || die "Load-gen stack not found - run 'make loadgen-up'."
    CMD="cda-run $LABEL $SCRIPT $*"
    say "[$LABEL] $CMD  (start $(date -u +%H:%M:%SZ))"
    CMD_ID="$($AWS ssm send-command --instance-ids "$ID" --document-name AWS-RunShellScript \
      --comment "CA1 k6 $LABEL" \
      --parameters "$(jq -n --arg c "$CMD" '{commands: [$c], executionTimeout: ["7200"]}')" \
      --query Command.CommandId --output text)"
    while :; do
      STATUS="$($AWS ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$ID" --query Status --output text 2>/dev/null || echo Pending)"
      case "$STATUS" in Pending|InProgress|Delayed) sleep 15 ;; *) break ;; esac
    done
    say "[$LABEL] $STATUS (end $(date -u +%H:%M:%SZ))"
    $AWS s3 sync "s3://$BUCKET/loadgen/results/$LABEL/" "$ROOT/evidence/raw/loadgen/$LABEL/" --quiet
    tail -40 "$ROOT/evidence/raw/loadgen/$LABEL/console.log" 2>/dev/null || true
    ;;
  results)
    DEST="$ROOT/evidence/raw/loadgen"
    mkdir -p "$DEST"
    $AWS s3 sync "s3://$BUCKET/loadgen/results/" "$DEST/"
    say "Results in $DEST"
    ;;
  down)
    say "Deleting '$LOADGEN_STACK' ..."
    $AWS cloudformation delete-stack --stack-name "$LOADGEN_STACK"
    $AWS cloudformation wait stack-delete-complete --stack-name "$LOADGEN_STACK" && say "Load-gen deleted."
    ;;
  *) die "Usage: $0 up|run|shell|results|down" ;;
esac
