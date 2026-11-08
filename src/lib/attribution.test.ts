import { afterEach, describe, expect, it } from 'vitest';
import { captureAttribution, getAttribution } from './attribution';

afterEach(() => { localStorage.clear(); window.history.replaceState(null, '', '/'); });

describe('attribution : page d\'arrivée', () => {
  it('mémorise landing_path avec la première source significative', () => {
    window.history.replaceState(null, '', '/emploi-soignant/paris/aide-soignant?utm_source=newsletter&utm_campaign=test');
    captureAttribution();
    expect(getAttribution()).toMatchObject({ utm_source: 'newsletter', utm_campaign: 'test', landing_path: '/emploi-soignant/paris/aide-soignant' });
  });

  it('ne remplace pas la première source par une navigation ultérieure', () => {
    window.history.replaceState(null, '', '/emploi-soignant/lyon?utm_source=a');
    captureAttribution();
    window.history.replaceState(null, '', '/inscription/soignant?utm_source=seo&utm_content=paris-aide-soignant');
    captureAttribution();
    expect(getAttribution()).toMatchObject({ utm_source: 'a', landing_path: '/emploi-soignant/lyon' });
  });

  it('arrivée directe sans signal : rien n\'est verrouillé', () => {
    window.history.replaceState(null, '', '/emploi-soignant/paris');
    captureAttribution();
    expect(getAttribution()).toEqual({});
  });
});
