#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_profile

BASE="$(stack_output AlbUrl)"
[ -n "$BASE" ] || die "No ALB URL - is the stack deployed?"
say "ALB base: $BASE"

say "1) Health:"
curl -fsS "$BASE/actuator/health" && echo

say "2) Read path GET /productapi/products (row count):"
curl -fsS "$BASE/productapi/products" | jq 'length'

say "3) Write path POST /productapi/products (coupon SAVE10, price 100 -> expect 90):"
curl -fsS -X POST "$BASE/productapi/products" \
  -H 'Content-Type: application/json' \
  -d '{"name":"SmokeTest","description":"created by smoke-test","price":100.000,"couponCode":"SAVE10"}' \
  | jq '{name, price, couponCode}'
say "Smoke test complete."
