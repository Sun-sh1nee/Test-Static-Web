import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 50 },    // ramp-up to 50 users in 5 min
    { duration: '2m', target: 100 },   // ramp-up to 100 users in next 5 min
    { duration: '8m', target: 200 },  // stay at 200 users for 10 min
    { duration: '2m', target: 100 },   // ramp-down to 100 users
    { duration: '1m', target: 0 },     // ramp-down to 0
  ],
};
export default function () {
  let res = http.get('http://nipa.sudlor.me/');

  check(res, {
    'status is 200': (r) => r.status === 200,
  });

  sleep(0.5);
}
