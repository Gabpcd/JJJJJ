import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { request } from '@playwright/test';
import { chargerHtmlLocal } from '../../e2e/helpers/recette-complete-mission.ts';

// APIRequestContext only: no browser, provider, credentials or application server.
// The real Playwright transport receives the same options as Route.fetch.
async function local(t, respond, method = 'GET') {
  let calls = 0;
  const server = createServer((req, res) => { calls++; respond(req, res, calls); });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const context = await request.newContext();
  t.after(async () => {
    await context.dispose();
    await new Promise(resolve => server.close(resolve));
  });
  const url = `http://127.0.0.1:${server.address().port}/document`;
  return { calls: () => calls, route: {
    request: () => ({ method: () => method }),
    fetch: options => context.fetch(url, { method, ...options }),
  } };
}

test('historical direct fetch reproduces the first TCP reset without retry', async t => {
  const h = await local(t, req => req.socket.destroy());
  await assert.rejects(h.route.fetch({ maxRedirects: 0 }), /socket hang up|ECONNRESET/);
  assert.equal(h.calls(), 1);
});

test('one local HTML GET reset is retried once by the real Playwright transport', async t => {
  const h = await local(t, (req, res, count) => {
    if (count === 1) req.socket.destroy();
    else res.end('<!doctype html><title>Fixture</title>');
  });
  const response = await chargerHtmlLocal(h.route, 0);
  assert.equal(response.status(), 200);
  assert.match(await response.text(), /<title>Fixture<\/title>/);
  assert.equal(h.calls(), 2);
});

test('a second TCP reset still fails, without a third attempt', async t => {
  const h = await local(t, req => req.socket.destroy());
  await assert.rejects(chargerHtmlLocal(h.route, 0), /Failed after 2 attempt/);
  assert.equal(h.calls(), 2);
});

test('POST is never retried after a TCP reset', async t => {
  const h = await local(t, req => req.socket.destroy(), 'POST');
  await assert.rejects(chargerHtmlLocal(h.route, 0), /socket hang up|ECONNRESET/);
  assert.equal(h.calls(), 1);
});

test('HTTP failure is returned unchanged once, so F1 still requires status 200', async t => {
  const h = await local(t, (_req, res) => { res.writeHead(503); res.end('fixture unavailable'); });
  const response = await chargerHtmlLocal(h.route, 0);
  assert.equal(response.status(), 503);
  assert.equal(h.calls(), 1);
});

test('F1 zero-redirect policy remains effective', async t => {
  const h = await local(t, (_req, res) => { res.writeHead(302, { location: '/target' }); res.end(); });
  const response = await chargerHtmlLocal(h.route, 0);
  assert.equal(response.status(), 302);
  assert.equal(h.calls(), 1);
});

test('the shared mission helper preserves its existing default redirect behavior', async t => {
  const h = await local(t, (_req, res, count) => {
    if (count === 1) res.writeHead(302, { location: '/target' });
    res.end(count === 1 ? '' : 'fixture reached');
  });
  const response = await chargerHtmlLocal(h.route);
  assert.equal(response.status(), 200);
  assert.equal(await response.text(), 'fixture reached');
  assert.equal(h.calls(), 2);
});
