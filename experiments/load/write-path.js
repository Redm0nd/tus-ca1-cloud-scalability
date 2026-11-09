import http from 'k6/http';
import { sleep } from 'k6';
import { Rate } from 'k6/metrics';
import {
  PRODUCTS_URL,
  buildProductPayload,
  jsonParams,
  standardThresholds,
  checkCreated,
} from './lib/common.js';

const RATE = Number(__ENV.RATE) || 50;
const DURATION = __ENV.DURATION || '15m';
const PREALLOC_VUS = Number(__ENV.PREALLOC_VUS) || 100;
const MAX_VUS = Number(__ENV.MAX_VUS) || 400;
const THINK_MS = Number(__ENV.THINK_MS) || 0;

const createErrors = new Rate('create_errors');

export const options = {
  scenarios: {
    write_path: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: PREALLOC_VUS,
      maxVUs: MAX_VUS,
      tags: { endpoint: 'create' },
    },
  },
  thresholds: standardThresholds({
    'http_req_duration{endpoint:create}': [`p(95)<${Number(__ENV.P95_MS) || 2000}`],
    create_errors: [`rate<${Number(__ENV.ERROR_RATE) || 0.01}`],
  }),
};

export default function () {
  const payload = buildProductPayload(); // random valid coupon
  const res = http.post(
    PRODUCTS_URL,
    JSON.stringify(payload),
    jsonParams({ endpoint: 'create' })
  );

  const ok = checkCreated(res, 'create');
  createErrors.add(!ok);

  if (THINK_MS > 0) {
    sleep(THINK_MS / 1000);
  }
}
