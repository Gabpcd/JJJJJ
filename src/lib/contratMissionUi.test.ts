import { describe, expect, it } from 'vitest';
import {
  choisirContenuContratAffiche,
  contientVariablesContratNonRendues,
} from './contratMissionUi';

describe('contratMissionUi', () => {
  it('détecte une variable juridique non rendue', () => {
    expect(contientVariablesContratNonRendues('<p>Né(e) le {{soignant_date_naissance}}</p>')).toBe(true);
    expect(contientVariablesContratNonRendues('<p>Né(e) le 1 janvier 1990</p>')).toBe(false);
  });

  it('n’affiche jamais le contenu serveur incomplet', () => {
    expect(choisirContenuContratAffiche('<p>{{motif_cdd}}</p>', '<p>Surcroît temporaire</p>'))
      .toBe('<p>Surcroît temporaire</p>');
    expect(choisirContenuContratAffiche('<p>Document figé</p>', '<p>Fallback</p>'))
      .toBe('<p>Document figé</p>');
  });
});
