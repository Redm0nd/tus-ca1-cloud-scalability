#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_profile

LABEL="${1:-}"
COUPON="$(stack_output CouponInstanceId)"; DB="$(stack_output DbEndpoint)"; SECRET="$(stack_output DbSecretArn)"
ASG="$(stack_output AsgName)"

run_ssm() {
  local ids=(); while [ "$1" != "--" ]; do ids+=("$1"); shift; done; shift
  local id cmd_id st
  cmd_id="$($AWS ssm send-command --instance-ids "${ids[@]}" --document-name AWS-RunShellScript \
    --parameters "$(jq -n --arg c "$1" '{commands: [$c]}')" --query Command.CommandId --output text)"
  for id in "${ids[@]}"; do
    while :; do
      st="$($AWS ssm get-command-invocation --command-id "$cmd_id" --instance-id "$id" --query Status --output text 2>/dev/null || echo Pending)"
      case "$st" in Pending|InProgress|Delayed) sleep 3 ;; *) break ;; esac
    done
    printf '%s ' "$id"; $AWS ssm get-command-invocation --command-id "$cmd_id" --instance-id "$id" --query StandardOutputContent --output text
  done
}

SQL="SELECT @@max_connections AS max_connections;
SHOW GLOBAL STATUS WHERE Variable_name IN ('Threads_connected','Max_used_connections','Connection_errors_max_connections','Aborted_connects');"
OUT="$(
  echo "== $(date -u +%Y-%m-%dT%H:%M:%SZ)  RDS class: $($AWS rds describe-db-instances --db-instance-identifier cda-mysql --query 'DBInstances[0].DBInstanceClass' --output text)"
  echo "== MySQL (via Coupon $COUPON)"
  run_ssm "$COUPON" -- "SEC=\$(aws secretsmanager get-secret-value --secret-id '$SECRET' --query SecretString --output text --region $REGION); export MYSQL_PWD=\$(echo \"\$SEC\" | jq -r .password); mysql -h $DB -u \$(echo \"\$SEC\" | jq -r .username) -t -e \"$SQL\" 2>&1"
  echo "== Product instances: 'Too many connections' log lines / Hikari pool errors"
  IDS="$($AWS autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' --output text)"
  [ -n "$IDS" ] && run_ssm $IDS -- "echo \"too_many=\$(journalctl -u productservice --no-pager | grep -c 'Too many connections') hikari_timeout=\$(journalctl -u productservice --no-pager | grep -c 'Connection is not available')\""
)"
echo "$OUT"
if [ -n "$LABEL" ]; then
  mkdir -p "$ROOT/evidence/raw/$LABEL"
  echo "$OUT" > "$ROOT/evidence/raw/$LABEL/db-status-$(date -u +%H%M%S).txt"
fi
