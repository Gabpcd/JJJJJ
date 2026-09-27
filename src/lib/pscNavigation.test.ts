import { describe, expect, it } from 'vitest';
import { estUrlPscAutorisee } from './pscNavigation';

describe('estUrlPscAutorisee', () => {
  it('accepte uniquement les endpoints PSC production et bac à sable', () => {
    expect(estUrlPscAutorisee('https://wallet.esw.esante.gouv.fr/auth?state=x')).toBe(true);
    expect(estUrlPscAutorisee('https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/logout')).toBe(true);
    expect(estUrlPscAutorisee('https://wallet.bas.psc.esante.gouv.fr/auth?state=x')).toBe(true);
    expect(estUrlPscAutorisee('https://auth.bas.psc.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/logout')).toBe(true);
  });

  it('refuse les redirections externes et les variations d’autorité', () => {
    expect(estUrlPscAutorisee('https://evil.example/auth')).toBe(false);
    expect(estUrlPscAutorisee('https://wallet.esw.esante.gouv.fr.evil.example/auth')).toBe(false);
    expect(estUrlPscAutorisee('https://wallet.esw.esante.gouv.fr:444/auth')).toBe(false);
    expect(estUrlPscAutorisee('https://user@wallet.esw.esante.gouv.fr/auth')).toBe(false);
    expect(estUrlPscAutorisee('https://wallet.bas.psc.esante.gouv.fr.evil.example/auth')).toBe(false);
    expect(estUrlPscAutorisee('https://wallet.bas.esw.esante.gouv.fr/auth')).toBe(false);
    expect(estUrlPscAutorisee('https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet')).toBe(false);
    expect(estUrlPscAutorisee('javascript:alert(1)')).toBe(false);
  });
});
