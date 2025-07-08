import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 20 },   // ไต่ขึ้นเป็น 20 users ใน 2 นาทีแรก
    { duration: '3m', target: 50 },   // ไต่ขึ้นเป็น 50 users ใน 3 นาทีถัดไป
    { duration: '5m', target: 100 },  // ไต่ขึ้นเป็น 100 users ใน 5 นาทีสุดท้าย
  ],
};


export default function () {
  let res = http.get('http://nipa.sudlor.me/');

  check(res, {
    'status is 200': (r) => r.status === 200,
  });

  sleep(0.5);
}
