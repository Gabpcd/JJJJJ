import { describe, expect, it } from 'vitest';
import { configurationDebitEmail, creerBudgetEnvoi, transportInterrompu } from '../../../supabase/functions/_shared/email-cron-budget';

describe('budget borné du drain email', () => {
  it('sépare une interruption indéterminée des erreurs HTTP et réseau explicites', () => {
    expect(transportInterrompu({name:'AbortError'})).toBe(true);
    expect(transportInterrompu({name:'TimeoutError'})).toBe(true);
    expect(transportInterrompu({name:'FunctionsFetchError',context:{name:'AbortError'}})).toBe(true);
    expect(transportInterrompu({name:'FunctionsFetchError',context:{name:'TimeoutError'}})).toBe(true);
    expect(transportInterrompu({name:'FunctionsHttpError',context:{status:503}})).toBe(false);
    expect(transportInterrompu({name:'FunctionsFetchError',context:new TypeError('Network')})).toBe(false);
    expect(transportInterrompu(null)).toBe(false);
  });
  it('répartit au plus 25 transports sous le plafond Edge de 30', async () => {
    let now = 0;
    const b = creerBudgetEnvoi(0, 40_000, () => now, async ms => { now += ms; });
    const resultats = [];
    for (let i = 0; i < 26; i++) resultats.push(await b.reserver());
    expect(resultats.slice(0, 25)).toEqual(Array(25).fill(8_000));
    expect(resultats[25]).toBeNull();
    expect(b.appels).toBe(25);
    expect(now).toBe(14_400);
  });
  it('arrête sans appel supplémentaire quand la fenêtre est consommée', async () => {
    let now = 0;
    const b = creerBudgetEnvoi(0, 40_000, () => now, async ms => { now += ms; });
    expect(await b.reserver()).toBe(8_000);
    now = 39_001;
    expect(b.peutCommencer()).toBe(false);
    expect(await b.reserver()).toBeNull();
    expect(b.appels).toBe(1);
  });
  it('réduit le timeout au temps restant et respecte la marge de stockage', async () => {
    let now = 37_000;
    const b = creerBudgetEnvoi(0, 40_000, () => now, async ms => { now += ms; });
    expect(await b.reserver()).toBe(3_000);
    now = 40_000;
    expect(await b.reserver()).toBeNull();
  });
  it('ne transforme pas un réveil tardif en autorisation d’envoi', async () => {
    let now = 0;
    const b = creerBudgetEnvoi(0, 5_000, () => now, async () => { now = 5_000; });
    expect(await b.reserver()).toBe(5_000);
    expect(await b.reserver()).toBeNull();
    expect(b.appels).toBe(1);
  });
  it('un nouveau tour peut reprendre les éléments restants', async () => {
    let now = 0;
    const b = creerBudgetEnvoi(0, 40_000, () => now, async ms => { now += ms; });
    for (let i = 0; i < 25; i++) await b.reserver();
    now = 60_000;
    const suivant = creerBudgetEnvoi(now, 40_000, () => now);
    expect(await suivant.reserver()).toBe(8_000);
    expect(suivant.appels).toBe(1);
  });
  it('accepte une réduction explicite des lots', () => {
    const env: Record<string, string> = { EMAIL_CRON_QUEUE_BATCH_SIZE: '12', EMAIL_CRON_ONBOARDING_BATCH_SIZE: '2', EMAIL_CRON_BUDGET_MS: '20000' };
    expect(configurationDebitEmail(cle => env[cle])).toEqual({queue:12,onboarding:2,budgetMs:20_000});
  });
  it.each(['', 'abc', 'Infinity', '1.5'])('utilise les valeurs sûres pour %s', value => {
    expect(configurationDebitEmail(() => value)).toEqual({queue:20,onboarding:5,budgetMs:40_000});
  });
  it('borne une configuration excessive ou négative', () => {
    expect(configurationDebitEmail(() => '999999')).toEqual({queue:20,onboarding:5,budgetMs:40_000});
    expect(configurationDebitEmail(() => '-1')).toEqual({queue:1,onboarding:1,budgetMs:5_000});
  });
});
