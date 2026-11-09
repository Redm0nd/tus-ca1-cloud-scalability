#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_profile

LABEL="${1:?usage: fetch-evidence.sh <label> [minutes_back] [period]}"
MINS="${2:-30}"; PERIOD="${3:-60}"
OUT="$ROOT/evidence/raw/$LABEL"; mkdir -p "$OUT"
END="${END:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
START="$(date -u -j -v-"${MINS}"M -f %Y-%m-%dT%H:%M:%SZ "$END" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$END - ${MINS} minutes" +%Y-%m-%dT%H:%M:%SZ)"
say "Window $START .. $END (period ${PERIOD}s) -> $OUT"

ASG="$(stack_output AsgName)"
ALB_ARN="$($AWS elbv2 describe-load-balancers --names cda-product-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text)"
TG_ARN="$($AWS elbv2 describe-target-groups --names cda-product-tg --query 'TargetGroups[0].TargetGroupArn' --output text)"
ALB_DIM="$(echo "$ALB_ARN" | sed -E 's#.*:loadbalancer/##')"
TG_DIM="$(echo "$TG_ARN"  | sed -E 's#.*:(targetgroup/.*)#\1#')"

cw() {
  local ns="$1" m="$2" st="$3" of="$4"; shift 4
  $AWS cloudwatch get-metric-statistics --namespace "$ns" --metric-name "$m" \
    --start-time "$START" --end-time "$END" --period "$PERIOD" --statistics "$st" \
    "$@" --query 'sort_by(Datapoints,&Timestamp)[].{t:Timestamp,v:'"$st"'}' --output json > "$of"
}

say "CloudWatch: Product CPU, ALB rate/latency/5xx/healthy, RDS cpu/connections"
cw AWS/EC2 CPUUtilization Average "$OUT/product_cpu.json" --dimensions Name=AutoScalingGroupName,Value="$ASG"
cw AWS/ApplicationELB RequestCountPerTarget Sum "$OUT/alb_req_per_target.json" --dimensions Name=TargetGroup,Value="$TG_DIM" Name=LoadBalancer,Value="$ALB_DIM"
cw AWS/ApplicationELB TargetResponseTime Average "$OUT/alb_latency.json" --dimensions Name=LoadBalancer,Value="$ALB_DIM"
cw AWS/ApplicationELB HTTPCode_Target_5XX_Count Sum "$OUT/alb_target_5xx.json" --dimensions Name=LoadBalancer,Value="$ALB_DIM"
cw AWS/ApplicationELB HTTPCode_ELB_5XX_Count Sum "$OUT/alb_5xx.json" --dimensions Name=LoadBalancer,Value="$ALB_DIM"
cw AWS/ApplicationELB HealthyHostCount Average "$OUT/alb_healthy_hosts.json" --dimensions Name=TargetGroup,Value="$TG_DIM" Name=LoadBalancer,Value="$ALB_DIM"
cw AWS/EC2 CPUUtilization Average "$OUT/coupon_cpu.json" --dimensions Name=InstanceId,Value="$(stack_output CouponInstanceId)"
cw AWS/RDS CPUUtilization Average "$OUT/rds_cpu.json" --dimensions Name=DBInstanceIdentifier,Value=cda-mysql
cw AWS/RDS DatabaseConnections Average "$OUT/rds_connections.json" --dimensions Name=DBInstanceIdentifier,Value=cda-mysql
cw AWS/RDS DatabaseConnections Maximum "$OUT/rds_connections_max.json" --dimensions Name=DBInstanceIdentifier,Value=cda-mysql
cw AWS/RDS FreeableMemory Average "$OUT/rds_freeable_memory.json" --dimensions Name=DBInstanceIdentifier,Value=cda-mysql

say "ASG scaling activities + target health"
$AWS autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG" \
  --query 'Activities[].{Start:StartTime,End:EndTime,Status:StatusCode,Desc:Description,Cause:Cause}' --output json > "$OUT/asg_activities.json"
$AWS elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}' --output json > "$OUT/target_health.json"

say "CloudTrail scaling/instance events"
$AWS cloudtrail lookup-events --start-time "$START" --end-time "$END" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --query 'Events[].{Time:EventTime,Name:EventName,User:Username}' --output json > "$OUT/cloudtrail_runinstances.json" 2>/dev/null || true
$AWS cloudtrail lookup-events --start-time "$START" --end-time "$END" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=TerminateInstances \
  --query 'Events[].{Time:EventTime,Name:EventName,User:Username}' --output json > "$OUT/cloudtrail_terminateinstances.json" 2>/dev/null || true

say "Evidence saved under $OUT"
