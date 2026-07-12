import { describe, expect, it } from 'vitest';
import { extraireRecoveryCredentials, normaliserLienJolene, urlCallbackPublique } from './nativeLinks';

describe('normaliserLienJolene', () => {
  it('conserve query et hash pour un recovery Universal Link', () => {
    expect(normaliserLienJolene('https://jolene.app/reset-password?code=abc#type=recovery'))
      .toBe('/reset-password?code=abc#type=recovery');
  });

  it('accepte les liens invitation, PSC et mission', () => {
    expect(normaliserLienJolene('https://jolene.app/etab/invitation/token?source=email'))
      .toBe('/etab/invitation/token?source=email');
    expect(normaliserLienJolene('https://www.jolene.app/auth/psc/callback?status=success&token_hash=x'))
      .toBe('/auth/psc/callback?status=success&token_hash=x');
    expect(normaliserLienJolene('https://app.jolene.app/contrat/contrat-id'))
      .toBe('/contrat/contrat-id');
    expect(normaliserLienJolene('/soignant/missions/mission-id')).toBe('/soignant/missions/mission-id');
  });

  it('rejette les origines, ports et chemins protocol-relative non fiables', () => {
    expect(normaliserLienJolene('https://evil.example/reset-password#access_token=x')).toBeNull();
    expect(normaliserLienJolene('https://jolene.app:444/reset-password')).toBeNull();
    expect(normaliserLienJolene('//evil.example/path')).toBeNull();
    expect(normaliserLienJolene('/\\evil.example/path')).toBeNull();
    expect(normaliserLienJolene('soignant/missions')).toBeNull();
    expect(normaliserLienJolene('javascript:alert(1)')).toBeNull();
  });

  it('conserve l’origine localhost sur le web pour les tests de recovery', () => {
    expect(urlCallbackPublique('/reset-password'))
      .toBe(new URL('/reset-password', window.location.origin).toString());
  });
});

describe('extraireRecoveryCredentials', () => {
  it('extrait le flux implicit depuis le fragment', () => {
    expect(extraireRecoveryCredentials({
      search: '',
      hash: '#access_token=access&refresh_token=refresh&type=recovery',
    } as Location)).toEqual({ kind: 'implicit', accessToken: 'access', refreshToken: 'refresh' });
  });

  it('extrait PKCE et token_hash depuis la query string', () => {
    expect(extraireRecoveryCredentials({ search: '?code=pkce&type=recovery', hash: '' } as Location))
      .toEqual({ kind: 'pkce', code: 'pkce' });
    expect(extraireRecoveryCredentials({ search: '?token_hash=hash&type=recovery', hash: '' } as Location))
      .toEqual({ kind: 'token_hash', tokenHash: 'hash' });
  });
});
