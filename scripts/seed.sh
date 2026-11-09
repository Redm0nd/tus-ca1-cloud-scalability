#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_profile

BUCKET="$(deploy_bucket)"
INSTANCE="$(stack_output CouponInstanceId)"
DB_ENDPOINT="$(stack_output DbEndpoint)"
DB_SECRET="$(stack_output DbSecretArn)"
[ -n "$INSTANCE" ] && [ -n "$DB_ENDPOINT" ] || die "Stack not deployed or outputs missing."
say "Seeding $SEED_ROWS rows into $DB_ENDPOINT via instance $INSTANCE (SSM)"

read -r -d '' REMOTE <<REMOTE || true
set -xe
dnf install -y mariadb105 jq awscli >/dev/null 2>&1 || dnf install -y mariadb105 jq
aws s3 cp s3://$BUCKET/seed/schema.sql    /tmp/schema.sql    --region $REGION
aws s3 cp s3://$BUCKET/seed/seed.sql.tmpl /tmp/seed.sql.tmpl --region $REGION
SEC=\$(aws secretsmanager get-secret-value --secret-id $DB_SECRET --query SecretString --output text --region $REGION)
U=\$(echo "\$SEC" | jq -r .username); P=\$(echo "\$SEC" | jq -r .password)
export MYSQL_PWD="\$P"
echo "Applying schema ..."
mysql -h $DB_ENDPOINT -u "\$U" servicedb < /tmp/schema.sql
echo "Generating rows ..."
( echo "SET @rows=$SEED_ROWS;"; cat /tmp/seed.sql.tmpl ) | mysql -h $DB_ENDPOINT -u "\$U" servicedb
REMOTE

CMD_ID="$($AWS ssm send-command \
  --instance-ids "$INSTANCE" \
  --document-name AWS-RunShellScript \
  --comment "CA1 seed $SEED_ROWS rows" \
  --parameters "$(printf '%s\n' "$REMOTE" | jq -Rn '{commands: [inputs]}')" \
  --query Command.CommandId --output text)"
say "SSM command $CMD_ID dispatched; waiting ..."
while :; do
  STATUS="$($AWS ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE" --query Status --output text 2>/dev/null || echo Pending)"
  case "$STATUS" in Pending|InProgress|Delayed) sleep 10 ;; *) break ;; esac
done
say "Seed status: $STATUS"
$AWS ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE" \
  --query StandardOutputContent --output text | tail -5
[ "$STATUS" = "Success" ] || die "Seed failed - inspect: aws ssm get-command-invocation --command-id $CMD_ID --instance-id $INSTANCE"
