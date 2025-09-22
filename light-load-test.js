import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  vus: 2, // 10 virtual users
  duration: '15s', // Run for 5 minutes
};

export default function () {
  const baseUrl = 'http://localhost:8080';
  const headers = {
    'Host': 'api.demo.local',
  };

  // Test service-a hello endpoint
  let response1 = http.get(`${baseUrl}/api/service-a/hello`, { headers });
  check(response1, {
    'service-a hello status is 200': (r) => r.status === 200,
  });

   // Test service-a slow endpoint
  let slowResponse = http.get(`${baseUrl}/api/service-a/slow`, { headers });
  check(slowResponse, {
    'service-a slow status is 200': (r) => r.status === 200,
  });

  // Test service-b hello endpoint
  let response2 = http.get(`${baseUrl}/api/service-b/hello`, { headers });
  check(response2, {
    'service-b hello status is 200': (r) => r.status === 200,
  });

  // Test service-a chain endpoint
  let response3 = http.get(`${baseUrl}/api/service-a/chain`, { headers });
  check(response3, {
    'service-a chain status is 200': (r) => r.status === 200,
  });

  // Test service-a canary endpoint
  let response4 = http.get(`${baseUrl}/api/service-a/hello`, {
    headers: { ...headers, 'X-Canary': 'true' }
  });
  check(response4, {
    'service-a canary status is 200': (r) => r.status === 200,
  });

  // Wait 10 seconds before next iteration
  sleep(5);
}