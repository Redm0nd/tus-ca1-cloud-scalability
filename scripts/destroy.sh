#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_profile

if $AWS cloudformation describe-stacks --stack-name "$LOADGEN_STACK" >/dev/null 2>&1; then
  bash "$HERE/loadgen.sh" down
fi

EVIDENCE="$(stack_output EvidenceBucket || true)"
if [ -n "${EVIDENCE:-}" ] && [ "$EVIDENCE" != "None" ]; then
  say "Emptying evidence bucket s3://$EVIDENCE"
  $AWS s3 rm "s3://$EVIDENCE" --recursive >/dev/null 2>&1 || true
fi

say "Deleting root stack '$STACK_NAME' (cascades to all nested stacks) ..."
$AWS cloudformation delete-stack --stack-name "$STACK_NAME"
$AWS cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" && say "Stack deleted."

if [ "${1:-}" = "--purge-deploy-bucket" ]; then
  BUCKET="$(deploy_bucket)"
  say "Purging deploy bucket s3://$BUCKET"
  $AWS s3 rb "s3://$BUCKET" --force >/dev/null 2>&1 || warn "Could not remove $BUCKET"
fi
say "Teardown complete. Nothing should be billing now."
$AWS cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1 \
  && warn "Stack still present - check the CloudFormation console." \
  || say "Confirmed: stack '$STACK_NAME' no longer exists."
