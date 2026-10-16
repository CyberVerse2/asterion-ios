import assert from 'node:assert/strict';
import test from 'node:test';

import { normalizeProxyUrl } from '../src/config.js';

test('proxy URLs with a scheme pass through', () => {
  assert.equal(normalizeProxyUrl('http://u:p@proxy.example.com:9000'), 'http://u:p@proxy.example.com:9000');
});

test('host:port:user:pass becomes an http URL with encoded credentials', () => {
  assert.equal(
    normalizeProxyUrl('proxy.example.com:9000:user-type-residential:p@ss:word'),
    'http://user-type-residential:p%40ss%3Aword@proxy.example.com:9000',
  );
});

test('scheme-less user:pass@host:port and host:port get http://', () => {
  assert.equal(normalizeProxyUrl('u:p@proxy.example.com:9000'), 'http://u:p@proxy.example.com:9000');
  assert.equal(normalizeProxyUrl('proxy.example.com:9000'), 'http://proxy.example.com:9000');
});

test('a value without a numeric port is rejected', () => {
  assert.throws(() => normalizeProxyUrl('proxy.example.com'));
  assert.equal(normalizeProxyUrl(null), null);
});
