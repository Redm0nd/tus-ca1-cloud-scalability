import http from 'k6/http';
import { Rate, Trend } from 'k6/metrics';
import {
  PRODUCTS_URL,
  HEALTH_URL,
  buildProductPayload,
  jsonParams,
  checkCreated,
} from './lib/common.js';

const RATE = Number(__ENV.RATE) || 20;
const DURATION = __ENV.DURATION || '10m';
const PREALLOC_VUS = Number(__ENV.PREALLOC_VUS) || 50;
const MAX_VUS = Number(__ENV.MAX_VUS) || 500;

const createErrors = new Rate('create_errors');
const productHealthy = new Rate('product_health_ok');
const createLatency = new Trend('create_latency_ms', true);

export const options = {
  scenarios: {
    coupling_writes: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: PREALLOC_VUS,
      maxVUs: MAX_VUS,
      exec: 'writes',
      tags: { endpoint: 'create' },
    },
    health_probe: {
      executor: 'constant-vus',
      vus: 1,
      duration: DURATION,
      exec: 'healthProbe',
      tags: { endpoint: 'health' },
    },
  },
  thresholds: {
    'http_req_duration{endpoint:health}': ['p(95)<1000'],
  },
};

export function writes() {
  const payload = buildProductPayload(); // random valid coupon
  const res = http.post(
    PRODUCTS_URL,
    JSON.stringify(payload),
    jsonParams({ endpoint: 'create' })
  );

  const ok = checkCreated(res, 'create');
  createErrors.add(!ok);
  createLatency.add(res.timings.duration);
}

export function healthProbe() {
  const res = http.get(HEALTH_URL, { tags: { endpoint: 'health' } });
  productHealthy.add(res.status === 200);
}
