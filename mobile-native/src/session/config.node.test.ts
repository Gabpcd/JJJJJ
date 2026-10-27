import assert from 'node:assert/strict';
import test from 'node:test';
import { readNativeConfig } from './config';

const ref = 'abcdefghijklmnopqrst';
const publicKey = 'sb_publishable_example_for_config_test_only';
test('demo is explicit by default, without a network configuration', () => {
  assert.deepEqual(readNativeConfig({}, []), { mode: 'demo' });
});
test('staging only accepts the independently allowlisted HTTPS project', () => {
  assert.equal(readNativeConfig({ mode: 'staging', url: `https://${ref}.supabase.co`, publishableKey: publicKey }, [ref]).mode, 'staging');
  for (const url of [`http://${ref}.supabase.co`, `https://${ref}.supabase.co.attacker.com`, `https://${ref}.supabase.co/path`, `https://user@${ref}.supabase.co`, `https://${ref}.supabase.co?x=1`]) {
    assert.throws(() => readNativeConfig({ mode: 'staging', url, publishableKey: publicKey }, [ref]));
  }
  assert.throws(() => readNativeConfig({ mode: 'staging', url: `https://${ref}.supabase.co`, publishableKey: publicKey }, []));
});
test('invalid configuration never silently falls back to demo, secret keys and legacy JWTs are rejected', () => {
  for (const mode of ['production', 'prod', 'invalid']) assert.throws(() => readNativeConfig({ mode }, [ref]));
  for (const publishableKey of ['', 'sb_secret_example_only', 'eyJhbGciOiJIUzI1NiJ9.example.invalid']) {
    assert.throws(() => readNativeConfig({ mode: 'staging', url: `https://${ref}.supabase.co`, publishableKey }, [ref]));
  }
});
