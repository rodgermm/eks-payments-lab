// Run IN-CLUSTER with `make loadtest` (a port-forward pins traffic to one pod,
// which hides the scaling you want to show).
// Ramps to 500 req/s; watch KEDA scale pods and Karpenter add nodes:
//   kubectl get pods -n payments -w     kubectl get nodeclaims -w
import http from 'k6/http';
import { check } from 'k6';
import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';

export const options = {
  scenarios: {
    ramp: {
      executor: 'ramping-arrival-rate',
      startRate: 20,
      timeUnit: '1s',
      preAllocatedVUs: 100,
      maxVUs: 1000,
      stages: [
        { target: 100, duration: '2m' },
        { target: 500, duration: '5m' },
        { target: 500, duration: '3m' },
        { target: 0, duration: '1m' },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],   // SLO: <1% errors
    http_req_duration: ['p(95)<300'], // SLO: p95 < 300ms
  },
};

export default function () {
  const key = uuidv4();
  const params = { headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key } };
  const body = JSON.stringify({ amount_cents: 1999, currency: 'EUR', merchant_id: 'm-123' });

  const first = http.post(`${BASE}/payments`, body, params);
  check(first, { 'created 201': (r) => r.status === 201 });

  // 10% of clients "retry" — must get the same payment back, not a double charge
  if (Math.random() < 0.1) {
    const retry = http.post(`${BASE}/payments`, body, params);
    check(retry, {
      'replay 200': (r) => r.status === 200,
      'same payment id': (r) => first.status === 201 && r.json('id') === first.json('id'),
    });
  }
}
