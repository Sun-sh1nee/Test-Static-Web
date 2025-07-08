import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 50 },    // ramp-up to 50 users in 5 min
  ],
};
export default function () {
  let res = http.get('http://nipa.sudlor.me/');

  check(res, {
    'status is 200': (r) => r.status === 200,
  });

  sleep(0.5);
}
