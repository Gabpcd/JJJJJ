import { get } from 'node:http';

// Only the CI runner's local Metro probes use this transport. Node 24.22.1's
// bundled fetch can crash outside its promise on a reset macOS socket:
// https://github.com/nodejs/undici/issues/6075
// node:http surfaces connection failures normally; no global error suppression,
// retry, external request, redirect or application networking is involved here.
export async function readMetroResponse(input, { timeoutMs, maxBytes, headers = {} }) {
  const url = new URL(input);
  if (url.protocol !== 'http:' || !['127.0.0.1', 'localhost'].includes(url.hostname)
    || url.port !== '8090' || url.username || url.password || url.hash) {
    throw new Error('METRO_LOCAL_ORIGIN_REQUIRED');
  }
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 180_000
    || !Number.isSafeInteger(maxBytes) || maxBytes < 1 || maxBytes > 128 * 1024 * 1024) {
    throw new Error('METRO_REQUEST_LIMITS_REQUIRED');
  }
  // Avoid DNS and an IPv6/IPv4 mismatch for the manifest's localhost URL.
  url.hostname = '127.0.0.1';
  return new Promise((resolve, reject) => {
    let request, response, timer, settled = false;
    const fail = error => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      response?.destroy();
      request?.destroy();
      reject(error);
    };
    // A wall-clock deadline includes connection, headers and the complete body.
    timer = setTimeout(() => fail(new Error('METRO_REQUEST_TIMEOUT')), timeoutMs);
    try {
      request = get(url, { agent: false, headers }, incoming => {
        response = incoming;
        const chunks = [];
        let size = 0;
        incoming.on('error', fail);
        incoming.on('aborted', () => fail(new Error('METRO_RESPONSE_INCOMPLETE')));
        incoming.on('close', () => {
          if (!incoming.complete) fail(new Error('METRO_RESPONSE_INCOMPLETE'));
        });
        const declared = Number(incoming.headers['content-length']);
        if (Number.isFinite(declared) && declared > maxBytes) {
          fail(new Error('METRO_RESPONSE_TOO_LARGE'));
          return;
        }
        incoming.on('data', chunk => {
          size += chunk.length;
          if (size > maxBytes) fail(new Error('METRO_RESPONSE_TOO_LARGE'));
          else if (!settled) chunks.push(chunk);
        });
        incoming.on('end', () => {
          if (settled) return;
          if (!incoming.complete) { fail(new Error('METRO_RESPONSE_INCOMPLETE')); return; }
          settled = true;
          clearTimeout(timer);
          const status = incoming.statusCode;
          resolve({ status, ok: status >= 200 && status < 300, body: Buffer.concat(chunks, size) });
        });
      });
      request.on('error', fail);
    } catch (error) { fail(error); }
  });
}
