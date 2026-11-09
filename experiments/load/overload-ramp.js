import http from 'k6/http';
import { Rate, Trend } from 'k6/metrics';
import { PRODUCTS_URL, HEALTH_URL } from './lib/common.js';

const STEPS = (__ENV.STEPS || '10,20,30,40,50,60,80').split(',').map(Number);
const HOLD = __ENV.HOLD || '3m';

const listErrors = new Rate('list_errors');
const probeLatency = new Trend('probe_latency_ms', true);
const probeSlow = new Rate('probe_over_5s');

const stages = [];
for (const v of STEPS) {
  stages.push({ duration: '10s', target: v });
  stages.push({ duration: HOLD, target: v });
}
const totalSecs = stages.reduce((s, st) => s + parseInt(st.duration, 10) * (st.duration.endsWith('m') ? 60 : 1), 0);

export const options = {
  scenarios: {
    overload: { executor: 'ramping-vus', startVUs: STEPS[0], stages, gracefulRampDown: '30s', exec: 'list' },
    probe: {
      executor: 'constant-arrival-rate', rate: 1, timeUnit: '1s', duration: `${totalSecs}s`,
      preAllocatedVUs: 20, maxVUs: 60, exec: 'probe',
    },
  },
  thresholds: { list_errors: [{ threshold: 'rate<0.5', abortOnFail: false }] },
};

export function list() {
  const res = http.get(PRODUCTS_URL, { tags: { endpoint: 'list' }, timeout: '60s' });
  listErrors.add(res.status !== 200);
}

export function probe() {
  const res = http.get(HEALTH_URL, { tags: { endpoint: 'probe' }, timeout: '30s' });
  probeLatency.add(res.timings.duration);
  probeSlow.add(res.timings.duration > 5000 || res.status !== 200);
  console.log(`PROBE ${new Date().toISOString()} ${Math.round(res.timings.duration)} ${res.status}`);
}
