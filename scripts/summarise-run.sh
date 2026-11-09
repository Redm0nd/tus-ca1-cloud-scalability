#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
LABEL="${1:?label}"; FROM="${2:-3}"; TO="${3:-12}"
EV="$ROOT/evidence/raw/$LABEL"
K6=""; for d in loadgen local; do [ -f "$ROOT/evidence/raw/$d/$LABEL/summary.json" ] && K6="$ROOT/evidence/raw/$d/$LABEL"; done
[ -d "$EV" ] || die "No evidence at $EV - run: make evidence LABEL=$LABEL"

START="$(cat "$K6/start-utc.txt" 2>/dev/null || true)"
[ -n "$START" ] || die "No start-utc.txt for $LABEL"
iso() { date -u -j -v+"$1"M -f %Y-%m-%dT%H:%M:%SZ "$START" +%Y-%m-%dT%H:%M 2>/dev/null || date -u -d "$START + $1 min" +%Y-%m-%dT%H:%M; }
W0="$(iso "$FROM")"; W1="$(iso "$TO")"

echo "== $LABEL  window $W0 .. $W1 UTC"
if [ -n "$K6" ]; then
  jq -r '.metrics as $m | "k6: reqs=\($m.http_reqs.count) rate=\($m.http_reqs.rate*100|round/100)/s failed=\(($m.http_req_failed.value // $m.http_req_failed.rate)*10000|round/100)% p50=\($m.http_req_duration.med|round)ms p95=\($m.http_req_duration["p(95)"]|round)ms max=\($m.http_req_duration.max|round)ms"' "$K6/summary.json"
fi
for f in "$EV"/*.json; do
  n="$(basename "$f" .json)"
  jq -r --arg a "$W0" --arg b "$W1" --arg n "$n" '
    if type=="array" and (.[0]|type)=="object" and (.[0]|has("t")) then
      [ .[] | select(.t >= $a and .t < $b) | .v ] as $v
      | if ($v|length)>0 then "\($n): mean=\(($v|add/length)*100|round/100) max=\(($v|max)*100|round/100) n=\($v|length)" else empty end
    else empty end' "$f" 2>/dev/null
done
