import http from 'k6/http';
import { check } from 'k6';
import { Trend } from 'k6/metrics';

export const BASE_URL = __ENV.BASE_URL || 'http://localhost:9090';

export const PRODUCTS_URL = `${BASE_URL}/productapi/products`;
export const HEALTH_URL = `${BASE_URL}/actuator/health`;

export const VALID_COUPONS = ['SAVE10', 'SAVE20', 'BLACKFRIDAY'];

export function randomCoupon() {
  return VALID_COUPONS[Math.floor(Math.random() * VALID_COUPONS.length)];
}

export function buildProductPayload(coupon) {
  const n = Math.floor(Math.random() * 1e9);
  return {
    name: `load-test-product-${n}`,
    description: `Created by k6 load test at ${new Date().toISOString()}`,
    price: Number((Math.random() * 500 + 1).toFixed(2)),
    couponCode: coupon || randomCoupon(),
  };
}

export function jsonParams(tags) {
  return {
    headers: { 'Content-Type': 'application/json' },
    tags: tags || {},
  };
}

export const listBodySize = new Trend('list_body_size_bytes');

export function recordListBodySize(res) {
  const len = Number(res.headers['Content-Length']) || (res.body ? res.body.length : 0);
  listBodySize.add(len);
  return len;
}

export const P95_MS = Number(__ENV.P95_MS) || 2000;
export const ERROR_RATE = Number(__ENV.ERROR_RATE) || 0.01;

export function standardThresholds(extra) {
  const base = {
    http_req_duration: [`p(95)<${P95_MS}`],
    http_req_failed: [`rate<${ERROR_RATE}`],
  };
  return Object.assign(base, extra || {});
}

export function checkOk(res, name) {
  return check(res, {
    [`${name}: status is 200`]: (r) => r.status === 200,
    [`${name}: has body`]: (r) => !!r.body && r.body.length > 0,
  });
}

export function checkCreated(res, name) {
  return check(res, {
    [`${name}: status is 2xx`]: (r) => r.status === 200 || r.status === 201,
  });
}
