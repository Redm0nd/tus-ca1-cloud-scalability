#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_profile
ACTION="${1:-}"

ASG="$(stack_output AsgName)"
DB="$(stack_output DbEndpoint)"; DB_ID="cda-mysql"
COUPON="$(stack_output CouponInstanceId)"
[ -n "$ASG" ] || die "Stack not deployed."

rds_state() { $AWS rds describe-db-instances --db-instance-identifier "$DB_ID" --query 'DBInstances[0].DBInstanceStatus' --output text; }
ec2_state() { $AWS ec2 describe-instances --instance-ids "$COUPON" --query 'Reservations[0].Instances[0].State.Name' --output text; }
settle() {
  local i
  for i in $(seq 1 90); do
    case "$(rds_state) $(ec2_state)" in *stopping*|*starting*|*pending*|*modifying*|*backing-up*) sleep 20 ;; *) return 0 ;; esac
  done
  die "RDS/Coupon still transitioning after 30 min: $(rds_state) $(ec2_state)"
}

case "$ACTION" in
  stop)
    say "Scaling Product ASG to 0 ..."
    $AWS autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --min-size 0 --desired-capacity 0
    say "Stopping Coupon instance $COUPON ..."
    $AWS ec2 stop-instances --instance-ids "$COUPON" >/dev/null
    say "Stopping RDS $DB_ID ..."
    $AWS rds stop-db-instance --db-instance-identifier "$DB_ID" >/dev/null 2>&1 || warn "RDS already stopped/transitioning"
    say "Waiting for RDS and Coupon to finish stopping ..."; settle
    say "Stopped: RDS $(rds_state), Coupon $(ec2_state). (RDS auto-starts after 7 days.)"
    ;;
  start)
    settle
    say "Starting RDS $DB_ID (slowest; starting first) ..."
    $AWS rds start-db-instance --db-instance-identifier "$DB_ID" >/dev/null 2>&1 || warn "RDS already starting/available"
    say "Starting Coupon instance $COUPON ..."
    $AWS ec2 start-instances --instance-ids "$COUPON" >/dev/null
    say "Restoring Product ASG (min=$MIN_SIZE desired=$DESIRED) ..."
    $AWS autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --min-size "$MIN_SIZE" --desired-capacity "$DESIRED"
    say "Start requested. RDS may take a few minutes; instances register when healthy."
    ;;
  *) die "Usage: power.sh stop | start" ;;
esac
