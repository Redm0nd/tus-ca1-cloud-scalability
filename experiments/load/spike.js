import http from 'k6/http';
import {
  PRODUCTS_URL,
  recordListBodySize,
  checkOk,
} from './lib/common.js';

const BASE_RATE = Number(__ENV.BASE_RATE) || 10;
const SPIKE_RATE = Number(__ENV.SPIKE_RATE) || 500;
const WARMUP = __ENV.WARMUP || '1m';
const SPIKE_RAMP = __ENV.SPIKE_RAMP || '10s';
const SPIKE_HOLD = __ENV.SPIKE_HOLD || '3m';
const RECOVER = __ENV.RECOVER || '2m';
const PREALLOC_VUS = Number(__ENV.PREALLOC_VUS) || 100;
const MAX_VUS = Number(__ENV.MAX_VUS) || 1000;

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: BASE_RATE,
      timeUnit: '1s',
      preAllocatedVUs: PREALLOC_VUS,
      maxVUs: MAX_VUS,
      stages: [
        { duration: WARMUP, target: BASE_RATE },
        { duration: SPIKE_RAMP, target: SPIKE_RATE }, // SHARP jump -> trigger ASG
        { duration: SPIKE_HOLD, target: SPIKE_RATE }, // hold -> let fleet scale out
        { duration: SPIKE_RAMP, target: BASE_RATE },
        { duration: RECOVER, target: BASE_RATE },
      ],
      tags: { endpoint: 'list' },
    },
  },
  thresholds: {
    'http_req_duration{endpoint:list}': ['p(95)<5000'],
  },
};

export default function () {
  const res = http.get(PRODUCTS_URL, { tags: { endpoint: 'list' } });
  checkOk(res, 'list');
  recordListBodySize(res);
}
