import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { Socket } from 'node:net';
import test from 'node:test';
import { readMetroResponse } from './metro-http.mjs';

const origin = 'http://127.0.0.1:8090';
const limits = { timeoutMs: 2000, maxBytes: 1024 };
async function server(t, handler, connection) {
  const instance = createServer(handler);
  if (connection) instance.on('connection', connection);
  await new Promise((resolve, reject) => {
    instance.once('error', reject);
    instance.listen(8090, '127.0.0.1', resolve);
  });
  t.after(() => new Promise((resolve, reject) => {
    instance.closeAllConnections();
    instance.close(error => error ? reject(error) : resolve());
  }));
}

test('Metro returns the actual complete body, status and platform header without Undici/QoS', async t => {
  t.mock.method(globalThis, 'fetch', () => { throw new Error('Unexpected fetch'); });
  const original = Object.getOwnPropertyDescriptor(Socket.prototype, 'setTypeOfService');
  Object.defineProperty(Socket.prototype, 'setTypeOfService', { configurable: true,
    value() { throw Object.assign(new Error('setTypeOfService EINVAL'), { code: 'EINVAL' }); } });
  t.after(() => original
    ? Object.defineProperty(Socket.prototype, 'setTypeOfService', original)
    : delete Socket.prototype.setTypeOfService);
  await server(t, (request, response) => {
    assert.equal(request.headers['expo-platform'], 'ios');
    response.writeHead(200, { 'Content-Type': 'application/expo+json' });
    response.write('{"sdkVersion":');
    response.end('"57.0.0"}');
  });
  const response = await readMetroResponse('http://localhost:8090/', {
    ...limits, headers: { 'expo-platform': 'ios', accept: 'application/expo+json' },
  });
  assert.equal(response.status, 200);
  assert.equal(response.ok, true);
  assert.deepEqual(JSON.parse(response.body.toString('utf8')), { sdkVersion: '57.0.0' });
});

test('connection resets before the first write reject normally and never retry', async t => {
  let connections = 0;
  await server(t, () => assert.fail('Reset server must not receive a request'), socket => {
    connections += 1;
    socket.resetAndDestroy();
  });
  for (let index = 0; index < 20; index++) {
    await assert.rejects(readMetroResponse(`${origin}/status`, limits), /ECONNRESET|socket hang up|EPIPE/);
  }
  assert.equal(connections, 20);
});

test('a refused connection rejects rather than being marked ready', async () => {
  await assert.rejects(readMetroResponse(`${origin}/status`, limits), { code: 'ECONNREFUSED' });
});

test('non-success status is preserved and redirects are not followed', async t => {
  let requests = 0;
  await server(t, (request, response) => {
    requests += 1;
    if (request.url === '/redirect') response.writeHead(302, { Location: `${origin}/target` }).end('redirect');
    else response.writeHead(503).end('not ready');
  });
  for (const [path, status, body] of [['/redirect', 302, 'redirect'], ['/status', 503, 'not ready']]) {
    const response = await readMetroResponse(`${origin}${path}`, limits);
    assert.equal(response.status, status);
    assert.equal(response.ok, false);
    assert.equal(response.body.toString(), body);
  }
  assert.equal(requests, 2);
});

test('the deadline includes waiting for headers', async t => {
  await server(t, () => {});
  await assert.rejects(readMetroResponse(origin, { ...limits, timeoutMs: 60 }), /METRO_REQUEST_TIMEOUT/);
});

test('a continuously streaming body cannot extend the total deadline', async t => {
  await server(t, (_request, response) => {
    response.writeHead(200);
    response.write('a');
    const interval = setInterval(() => response.write('b'), 5);
    response.on('close', () => clearInterval(interval));
  });
  await assert.rejects(readMetroResponse(origin, { ...limits, timeoutMs: 60 }), /METRO_REQUEST_TIMEOUT/);
});

test('a truncated body cannot be accepted as a ready bundle', async t => {
  await server(t, (_request, response) => {
    response.writeHead(200, { 'Content-Length': 100 });
    response.write('partial');
    setTimeout(() => response.destroy(), 10);
  });
  await assert.rejects(readMetroResponse(origin, limits), /METRO_RESPONSE_INCOMPLETE|aborted/);
});

test('both declared and chunked bodies obey the byte ceiling', async t => {
  await server(t, (request, response) => {
    if (request.url === '/declared') response.writeHead(200, { 'Content-Length': 200 });
    else response.writeHead(200);
    response.write('x'.repeat(20));
    response.end('y'.repeat(20));
  });
  for (const path of ['/declared', '/chunked']) {
    await assert.rejects(readMetroResponse(`${origin}${path}`, { ...limits, maxBytes: 30 }), /METRO_RESPONSE_TOO_LARGE/);
  }
});

test('external destinations, credentials and alternate ports are refused before a request', async () => {
  for (const url of ['https://127.0.0.1:8090/', 'http://example.com:8090/', 'http://127.0.0.1:8081/',
    'http://user:password@127.0.0.1:8090/', 'http://127.0.0.1:8090/#fragment']) {
    await assert.rejects(readMetroResponse(url, limits), /METRO_LOCAL_ORIGIN_REQUIRED/);
  }
});

test('a caller cannot remove the time or memory ceiling', async () => {
  for (const options of [{}, { ...limits, timeoutMs: Infinity }, { ...limits, maxBytes: 0 },
    { ...limits, maxBytes: 129 * 1024 * 1024 }, { ...limits, timeoutMs: 180001 }]) {
    await assert.rejects(readMetroResponse(origin, options), /METRO_REQUEST_LIMITS_REQUIRED/);
  }
});
