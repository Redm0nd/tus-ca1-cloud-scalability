import http from 'k6/http';
import { Rate, Trend } from 'k6/metrics';
import { PRODUCTS_URL, randomCoupon } from './lib/common.js';

const STEPS = (__ENV.STEPS || '25,50,100,200,400').split(',').map(Number);
const HOLD = __ENV.HOLD || '2m';
const MAX_VUS = Number(__ENV.MAX_VUS) || 600;

const createErrors = new Rate('create_errors');
const createLatency = new Trend('create_latency_ms', true);

const stages = [];
for (const r of STEPS) {
  stages.push({ duration: '10s', target: r });
  stages.push({ duration: HOLD, target: r });
}

export const options = {
  scenarios: {
    write_ramp: {
      executor: 'ramping-arrival-rate',
      startRate: STEPS[0],
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: MAX_VUS,
      stages,
      tags: { endpoint: 'create' },
    },
  },
  thresholds: { create_errors: [{ threshold: 'rate<0.5', abortOnFail: false }] },
};

export default function () {
  const res = http.post(
    PRODUCTS_URL,
    JSON.stringify({ name: `ramp-${__VU}-${__ITER}`, description: 'write-ramp', price: 100, couponCode: randomCoupon() }),
    { headers: { 'Content-Type': 'application/json' }, tags: { endpoint: 'create' }, timeout: '30s' },
  );
  createErrors.add(res.status !== 200);
  createLatency.add(res.timings.duration);
}
