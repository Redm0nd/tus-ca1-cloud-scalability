#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_profile

NAME="CA1-evidence"
ASG="$(stack_output AsgName)"
ALB="$($AWS elbv2 describe-load-balancers --names cda-product-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text | sed -E 's#.*:loadbalancer/##')"
TG="$($AWS elbv2 describe-target-groups --names cda-product-tg --query 'TargetGroups[0].TargetGroupArn' --output text | sed -E 's#.*:(targetgroup/.*)#\1#')"
COUPON="$(stack_output CouponInstanceId)"

w() {
  jq -n --argjson x "$1" --argjson y "$2" --arg t "$3" --arg s "$4" --argjson m "$5" --arg r "$REGION" \
    '{type:"metric",x:$x,y:$y,width:12,height:6,properties:{title:$t,region:$r,stat:$s,period:60,view:"timeSeries",stacked:false,metrics:$m}}'
}
BODY="$(jq -n --argjson w "[
  $(w 0 0  'Requests per target / min (ALB)' Sum "[[\"AWS/ApplicationELB\",\"RequestCountPerTarget\",\"TargetGroup\",\"$TG\",\"LoadBalancer\",\"$ALB\"]]"),
  $(w 12 0 'Product CPU % (ASG average)' Average "[[\"AWS/EC2\",\"CPUUtilization\",\"AutoScalingGroupName\",\"$ASG\"]]"),
  $(w 0 6  'Healthy vs unhealthy Product targets' Average "[[\"AWS/ApplicationELB\",\"HealthyHostCount\",\"TargetGroup\",\"$TG\",\"LoadBalancer\",\"$ALB\"],[\".\",\"UnHealthyHostCount\",\".\",\".\",\".\",\".\"]]"),
  $(w 12 6 'ASG in-service vs desired instances' Average "[[\"AWS/AutoScaling\",\"GroupInServiceInstances\",\"AutoScalingGroupName\",\"$ASG\"],[\".\",\"GroupDesiredCapacity\",\".\",\".\"]]"),
  $(w 0 12 '5xx: ALB-generated vs Product' Sum "[[\"AWS/ApplicationELB\",\"HTTPCode_ELB_5XX_Count\",\"LoadBalancer\",\"$ALB\"],[\".\",\"HTTPCode_Target_5XX_Count\",\".\",\".\"]]"),
  $(w 12 12 'Target response time (s)' Average "[[\"AWS/ApplicationELB\",\"TargetResponseTime\",\"LoadBalancer\",\"$ALB\"]]"),
  $(w 0 24 'Coupon CPU % (single instance)' Average "[[\"AWS/EC2\",\"CPUUtilization\",\"InstanceId\",\"$COUPON\"]]"),
  $(w 12 24 'Product vs Coupon CPU %' Average "[[\"AWS/EC2\",\"CPUUtilization\",\"AutoScalingGroupName\",\"$ASG\"],[\"AWS/EC2\",\"CPUUtilization\",\"InstanceId\",\"$COUPON\"]]"),
  $(w 0 18 'RDS CPU %' Average "[[\"AWS/RDS\",\"CPUUtilization\",\"DBInstanceIdentifier\",\"cda-mysql\"]]"),
  $(w 12 18 'RDS connections (max_connections = 61)' Average "[[\"AWS/RDS\",\"DatabaseConnections\",\"DBInstanceIdentifier\",\"cda-mysql\"]]")
]" '{widgets:$w}')"
$AWS cloudwatch put-dashboard --dashboard-name "$NAME" --dashboard-body "$BODY" --query 'DashboardValidationMessages' --output text
say "Dashboard '$NAME' updated (Coupon instance: $COUPON)."

link() { echo "https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=${NAME};start=$2;end=$3   <- $1"; }
link "Exp 1 baseline (1 instance)"             2026-11-02T17:30:00Z 2026-11-02T17:48:00Z
link "Exp 2 fixed x3 (20, 60 VU, Mac mini)"     2026-11-02T17:30:00Z 2026-11-02T18:27:00Z
link "Exp 3 elasticity - CPU policy, min 1"     2026-11-02T18:26:00Z 2026-11-02T19:03:00Z
link "Exp 4 elasticity - request policy, min 1" 2026-11-02T19:06:00Z 2026-11-02T19:50:00Z
link "Exp 7 failure - terminate 1 of 3"         2026-11-02T19:51:00Z 2026-11-02T20:05:00Z
link "Exp 8 Coupon dependency failure"          2026-11-02T20:05:00Z 2026-11-02T20:18:00Z
link "Exp 1/2 repeats"                          2026-11-02T20:58:00Z 2026-11-02T21:27:00Z
link "Exp 5 elasticity - CPU 40%, min 2"        2026-11-02T21:30:00Z 2026-11-02T22:06:00Z
link "Exp 9 DB connections - 6 Product"         2026-11-03T02:22:00Z 2026-11-03T02:38:00Z
link "Exp 6 scale-out and scale-in, min 2"      2026-11-03T22:15:00Z 2026-11-03T23:00:00Z
link "Exp 6 repeat (6 Nov)"                     2026-11-06T19:28:00Z 2026-11-06T20:15:00Z
