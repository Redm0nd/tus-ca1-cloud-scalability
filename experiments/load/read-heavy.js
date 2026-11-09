import http from 'k6/http';
import {
  PRODUCTS_URL,
  standardThresholds,
  recordListBodySize,
  checkOk,
} from './lib/common.js';

const VUS_PEAK = Number(__ENV.VUS_PEAK) || 50;
const RAMP_UP = __ENV.RAMP_UP || '3m';
const HOLD = __ENV.HOLD || '9m';
const RAMP_DOWN = __ENV.RAMP_DOWN || '3m';

export const options = {
  scenarios: {
    read_heavy: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: RAMP_UP, target: VUS_PEAK }, // ramp up to peak
        { duration: HOLD, target: VUS_PEAK },
        { duration: RAMP_DOWN, target: 0 },
      ],
      gracefulRampDown: '30s',
      tags: { endpoint: 'list' },
    },
  },
  thresholds: standardThresholds({
    'http_req_duration{endpoint:list}': [`p(95)<${Number(__ENV.P95_MS) || 2000}`],
  }),
};

export default function () {
  const res = http.get(PRODUCTS_URL, { tags: { endpoint: 'list' } });

  checkOk(res, 'list');
  recordListBodySize(res);

}
