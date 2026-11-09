#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/config.env"

AWS="aws --profile $PROFILE --region $REGION"

say()  { printf '\033[1;36m[cda]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[cda] WARN:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[cda] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

require_profile() {
  $AWS sts get-caller-identity >/dev/null 2>&1 || die \
    "AWS profile '$PROFILE' is not usable. Run: aws configure --profile $PROFILE  (region $REGION)."
}

account_id() { $AWS sts get-caller-identity --query Account --output text; }

deploy_bucket() { echo "cda-deploy-$(account_id)-$REGION"; }

stack_output() {
  $AWS cloudformation describe-stacks --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text 2>/dev/null
}

stack_tags() {
  echo "Project=$TAG_PROJECT Module=$TAG_MODULE Owner=$TAG_OWNER \
Environment=$TAG_ENVIRONMENT ManagedBy=$TAG_MANAGEDBY CostCenter=$TAG_COSTCENTER"
}
