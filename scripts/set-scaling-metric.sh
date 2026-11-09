#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
METRIC="${1:-}"
case "$METRIC" in
  None|CPU|RequestCount) ;;
  *) die "Usage: set-scaling-metric.sh None|CPU|RequestCount" ;;
esac
say "Switching scaling metric -> $METRIC (redeploying scaling policy only changes; fast update)"
SCALING_METRIC="$METRIC" "$HERE/deploy.sh"
