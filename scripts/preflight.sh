#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ok=1
check() { if command -v "$1" >/dev/null 2>&1; then printf '  \033[32mOK\033[0m   %-10s %s\n' "$1" "$(command -v "$1")"; else printf '  \033[31mMISS\033[0m %-10s (required: %s)\n' "$1" "$2"; ok=0; fi; }

say "Tooling:"
check aws   "AWS CLI v2"
check mvn   "Maven (build JARs)"
check jq    "jq (JSON parsing in scripts)"
check cfn-lint "optional - template linting"

say "AWS identity (profile=$PROFILE, region=$REGION):"
if $AWS sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output table 2>/dev/null; then
  :
else
  warn "Profile '$PROFILE' not usable. Run:  aws configure --profile $PROFILE   (region $REGION)"
  ok=0
fi

[ "$ok" = "1" ] && say "Preflight passed." || die "Preflight found problems (see above)."
