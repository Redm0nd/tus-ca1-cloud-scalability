#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_profile

BUCKET="$(deploy_bucket)"
say "Ensuring deploy bucket s3://$BUCKET"
if ! $AWS s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  if [ "$REGION" = "us-east-1" ]; then
    $AWS s3api create-bucket --bucket "$BUCKET" >/dev/null
  else
    $AWS s3api create-bucket --bucket "$BUCKET" \
      --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
  fi
  $AWS s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
fi

for svc in productservice couponservice; do
  say "Building $svc ..."
  ( cd "$ROOT/$svc" && mvn -q -DskipTests package )
  JAR="$(ls "$ROOT/$svc/target/"*.jar | grep -v 'original' | head -1)"
  [ -f "$JAR" ] || die "No JAR produced for $svc"
  say "Uploading $svc JAR -> s3://$BUCKET/artifacts/$svc.jar"
  $AWS s3 cp "$JAR" "s3://$BUCKET/artifacts/$svc.jar"
done

say "Uploading seed SQL -> s3://$BUCKET/seed/"
$AWS s3 cp "$ROOT/experiments/seed/schema.sql"      "s3://$BUCKET/seed/schema.sql"
$AWS s3 cp "$ROOT/experiments/seed/seed.sql.tmpl"   "s3://$BUCKET/seed/seed.sql.tmpl"
say "Artifacts ready."
