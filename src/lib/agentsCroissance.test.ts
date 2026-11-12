import { describe, expect, it } from 'vitest';
import {
  actionsPossibles,
  etapesEtablissements,
  etapesSoignants,
  goulot,
  groupesSuggeres,
  lienGmail,
  raisonsCible,
  type EntonnoirCroissance,
} from './agentsCroissance';

const entonnoir = (s: Record<string, number>, p: Record<string, number>, e: Record<string, number>): EntonnoirCroissance => ({
  periode: { debut: '2026-11-01T00:00:00Z', fin: '2026-11-08T00:00:00Z' },
  soignants: s,
  etablissements: e,
  missions: {},
  prospection: p,
  agents: {},
  sources_inscriptions_periode: {},
  exclus_cohorte_test: {},
});

describe('agents de croissance — règles pures', () => {
  it('ne propose aucune action sur un brouillon traité', () => {
    expect(actionsPossibles('BROUILLON')).toEqual(['MODIFIER', 'VALIDER', 'REJETER']);
    expect(actionsPossibles('VALIDE')).toEqual(['MODIFIER', 'MARQUER_ENVOYE', 'REJETER']);
    expect(actionsPossibles('ENVOYE')).toEqual([]);
    expect(actionsPossibles('REJETE')).toEqual([]);
    expect(actionsPossibles('EXPIRE')).toEqual([]);
  });

  it('encode destinataire, objet et corps dans le lien Gmail', () => {
    const url = lienGmail('contact@ehpad.fr', 'Renforts & remplacements', 'Bonjour,\n\n15 % HT');
    expect(url.startsWith('https://mail.google.com/mail/?view=cm&fs=1&to=contact%40ehpad.fr')).toBe(true);
    expect(url).toContain('&su=Renforts%20%26%20remplacements');
    expect(url).toContain('&body=Bonjour%2C%0A%0A15%20%25%20HT');
    expect(lienGmail('a@b.fr', null, 'x')).toContain('&su=&body=x');
  });

  it('ne garde que les groupes nommés et les URL http(s)', () => {
    const groupes = groupesSuggeres({
      groupes_suggeres: [
        { nom: 'Infirmiers IDF', url: 'https://facebook.com/groups/1', membres: 1200 },
        { nom: 'Lien piégé', url: 'javascript:alert(1)', membres: null },
        { nom: '', url: 'https://x.y' },
        'texte',
      ],
    });
    expect(groupes).toEqual([
      { nom: 'Infirmiers IDF', url: 'https://facebook.com/groups/1', membres: 1200 },
      { nom: 'Lien piégé', url: null, membres: null },
    ]);
    expect(groupesSuggeres({})).toEqual([]);
  });

  it('explique pourquoi un établissement est ciblé', () => {
    const raisons = raisonsCible({
      agent: 'PROSPECTION_ETABLISSEMENT',
      departement: '56',
      contexte: {
        type_etablissement: 'EHPAD',
        ville: 'Lorient',
        score: { signal_boamp_90j: 20 },
        bmo_as: { difficulte_pct: 74 },
      },
    });
    expect(raisons).toEqual(['EHPAD', 'Lorient', 'dépt 56', 'avis BOAMP récent', 'recrutement AS jugé difficile à 74 % (BMO)']);
    expect(raisonsCible({ agent: 'REACTIVATION', departement: null, contexte: { blocage: 'DOCUMENTS' } })).toEqual(['aucun document déposé']);
  });

  it('calcule les conversions et désigne le premier zéro comme goulot', () => {
    const e = entonnoir(
      { inscrits_total: 2, avec_document: 1, documents_valides: 1, ayant_candidate: 0, ayant_realise_mission: 0 },
      { prospects_avec_email: 30633, prospects_contactes_total: 0 },
      { inscrits_total: 0, peuvent_publier: 0, ayant_publie: 0 },
    );
    const s = etapesSoignants(e);
    expect(s.map((x) => x.conversionPct)).toEqual([null, 50, 100, 0, null]);
    expect(goulot(s)?.cle).toBe('ayant_candidate');
    const et = etapesEtablissements(e);
    expect(et[0]).toMatchObject({ cle: 'prospects_avec_email', valeur: 30633, conversionPct: null });
    expect(goulot(et)?.cle).toBe('prospects_contactes_total');
  });

  it('désigne la plus faible conversion quand aucune étape n’est vide', () => {
    const e = entonnoir(
      { inscrits_total: 100, avec_document: 40, documents_valides: 30, ayant_candidate: 25, ayant_realise_mission: 20 },
      {},
      {},
    );
    expect(goulot(etapesSoignants(e))?.cle).toBe('avec_document');
  });
});
