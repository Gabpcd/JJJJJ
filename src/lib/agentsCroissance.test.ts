import { describe, expect, it } from 'vitest';
import {
  AGENTS,
  LIBELLE_CANAL,
  RESULTATS_APPEL,
  actionsPossibles,
  alerteCibles,
  estAppel,
  estEmail,
  etapesEtablissements,
  etapesSoignants,
  goulot,
  groupesSuggeres,
  libelleResultatAppel,
  libelleStatut,
  lienGmail,
  lienTel,
  lireCibles,
  lirePassage,
  raisonsCible,
  resumeAppels,
  resumeCibles,
  sourceAdresse,
  resumeSansMention,
  sourceFiche,
  telephoneFiche,
  telephoneNational,
  type EntonnoirCroissance,
} from './agentsCroissance';

/** Les séparateurs de milliers français sont des espaces insécables fines : on compare le texte lu. */
const lisible = (texte: string | undefined) => (texte ?? '').replace(/[\u00a0\u202f]/g, ' ');

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

describe('agents de croissance — fiches d’appel', () => {
  it('déclare l’agent et le canal téléphone', () => {
    expect(Object.keys(AGENTS)).toEqual([
      'PROSPECTION_ETABLISSEMENT', 'APPEL_ETABLISSEMENT', 'POST_SOCIAL', 'MISSION_A_POURVOIR', 'REACTIVATION',
    ]);
    expect(LIBELLE_CANAL.TELEPHONE).toBe('Téléphone');
    expect(estAppel({ canal: 'TELEPHONE' })).toBe(true);
    expect(estAppel({ canal: 'EMAIL' })).toBe(false);
    expect(estEmail({ canal: 'TELEPHONE' })).toBe(false);
  });

  it('ne dit jamais qu’une fiche d’appel est « envoyée »', () => {
    expect(libelleStatut({ canal: 'TELEPHONE', statut: 'BROUILLON' })).toBe('À valider');
    expect(libelleStatut({ canal: 'TELEPHONE', statut: 'VALIDE' })).toBe('Validée, à appeler');
    expect(libelleStatut({ canal: 'TELEPHONE', statut: 'ENVOYE' })).toBe('Appel noté');
    expect(libelleStatut({ canal: 'TELEPHONE', statut: 'REJETE' })).toBe('Rejeté');
    expect(libelleStatut({ canal: 'EMAIL', statut: 'VALIDE' })).toBe('Validé, à envoyer');
    expect(libelleStatut({ canal: 'EMAIL', statut: 'ENVOYE' })).toBe('Envoyé');
  });

  it('construit un lien tel: seulement pour un numéro français complet, sous sa forme nationale', () => {
    expect(telephoneFiche({ telephone: ' 01 00 00 10 01 ' })).toBe('01 00 00 10 01');
    expect(telephoneFiche({ telephone: '' })).toBeNull();
    expect(telephoneFiche({})).toBeNull();
    // Mêmes cas que private.fn_growth_telephone_national (suite SQL, section 11.a).
    for (const saisi of ['01 00 00 10 01', '01.00.00.10.01', '+33 1 00 00 10 01', '0033 1 00 00 10 01', '33100001001', '+33 (0)1 00 00 10 01', '0033 (0) 1 00 00 10 01']) {
      expect(telephoneNational(saisi)).toBe('0100001001');
      expect(lienTel(saisi)).toBe('tel:0100001001');
    }
    for (const saisi of ['100001001', '12345', '01 00 00 10 01 / 01 00 00 10 02', '+262 262 00 10 01', '', null, undefined]) {
      expect(telephoneNational(saisi)).toBeNull();
      expect(lienTel(saisi)).toBeNull();
    }
  });

  it('donne l’origine du numéro quand la fiche la porte', () => {
    expect(sourceFiche({ source: ' Annuaires publics (FINESS) ' })).toBe('Annuaires publics (FINESS)');
    expect(sourceFiche({ source: '' })).toBeNull();
    expect(sourceFiche({})).toBeNull();
  });

  it('explique le dernier passage de l’agent d’appels, liste épuisée comprise', () => {
    expect(resumeAppels({ places_de_la_semaine: 30, quota_semaine: 30, exclus_stop: 2, numeros_deja_en_file: 1, places_non_pourvues: 25 })).toEqual({
      texte: '30 places restaient sur 30 cette semaine · 2 cibles écartées pour opposition · 1 numéro déjà proposé · 25 places sans cible appelable',
      epuisee: true,
    });
    expect(resumeAppels({ places_de_la_semaine: 0, quota_semaine: 30, exclus_stop: 0, numeros_deja_en_file: 0, places_non_pourvues: 0 })).toEqual({
      texte: 'Liste de la semaine complète (30 fiches) : la prochaine arrive lundi',
      epuisee: false,
    });
    expect(resumeAppels({ places_de_la_semaine: 1, quota_semaine: 30, exclus_stop: 1, places_non_pourvues: 0 })).toEqual({
      texte: '1 place restait sur 30 cette semaine · 1 cible écartée pour opposition',
      epuisee: false,
    });
    // Aucune place : le quota de la semaine, ou le plafond de fiches en attente.
    expect(resumeAppels({ places_de_la_semaine: 0, quota_semaine: 30, fiches_de_la_semaine: 30, fiches_en_file: 12, file_max: 60 })?.texte)
      .toBe('Liste de la semaine complète (30 fiches) : la prochaine arrive lundi');
    expect(resumeAppels({ places_de_la_semaine: 0, quota_semaine: 30, fiches_de_la_semaine: 10, fiches_en_file: 60, file_max: 60 })?.texte)
      .toBe('File pleine (60 fiches en attente) : traitez des fiches pour en recevoir d’autres');
    expect(resumeAppels({ fiches_appel: 3 })).toBeNull();
    expect(resumeAppels(null)).toBeNull();
  });

  it('propose les résultats du CRM, dont deux définitifs', () => {
    expect(RESULTATS_APPEL.map((r) => r.code)).toEqual([
      'APPEL_REPONDU', 'SANS_REPONSE', 'INTERESSE', 'A_RAPPELER', 'PAS_INTERESSE', 'STOP',
    ]);
    expect(RESULTATS_APPEL.filter((r) => r.definitif).map((r) => r.code)).toEqual(['PAS_INTERESSE', 'STOP']);
    expect(libelleResultatAppel('SANS_REPONSE')).toBe('Sans réponse');
    expect(libelleResultatAppel('INSCRIT')).toBeNull();
    expect(libelleResultatAppel(undefined)).toBeNull();
  });

  it('explique le classement d’une fiche d’appel sans chiffre BMO', () => {
    expect(raisonsCible({
      agent: 'APPEL_ETABLISSEMENT',
      departement: '75',
      contexte: { type_etablissement: 'CENTRE_SANTE', ville: 'Paris', score: { type: 20, signal_boamp_90j: 20, tension_bmo_as: 3 } },
    })).toEqual(['CENTRE SANTE', 'Paris', 'dépt 75', 'avis BOAMP récent']);
  });
});

describe('agents de croissance — un zéro n’est plus muet', () => {
  const constat = {
    departements: ['56', '75', '92'], etablissements_cibles: 2318, adresses_fermees: 656,
    adresses_utilisables: 0, adresses_annuaire_public: 0, adresses_restantes: 0,
    telephones_utilisables: 2017, telephones_restants: 2017,
  };

  it('ne lit qu’un décompte complet', () => {
    expect(lireCibles(constat)).toEqual(constat);
    // Rapport figé avant la clé « annuaire public » : toujours lisible, à zéro.
    const { adresses_annuaire_public: _absente, ...ancien } = constat;
    expect(lireCibles(ancien)).toEqual(constat);
    expect(lireCibles({ ...constat, adresses_annuaire_public: 'beaucoup' })?.adresses_annuaire_public).toBe(0);
    expect(lireCibles({ ...constat, adresses_utilisables: 279, adresses_annuaire_public: 279 })?.adresses_annuaire_public).toBe(279);
    expect(lireCibles({ ...constat, adresses_utilisables: undefined })).toBeNull();
    expect(lireCibles({ ...constat, telephones_restants: '2017' })).toBeNull();
    expect(lireCibles(null)).toBeNull();
    expect(lireCibles(undefined)).toBeNull();
    expect(lireCibles({ ...constat, departements: 'ZZ' })?.departements).toEqual([]);
  });

  it('avertit quand aucune adresse n’est utilisable (constat du 20/11/2026)', () => {
    const a = alerteCibles(lireCibles(constat));
    expect(a?.niveau).toBe('alerte');
    expect(a?.titre).toBe('Prospection par email à l’arrêt');
    expect(lisible(a?.texte)).toBe(
      'Aucune adresse utilisable parmi les 2 318 établissements ciblés (56, 75, 92). '
      + '656 ont une adresse, toutes en messagerie de santé fermée (MSSanté, Apicrypt), où un email envoyé depuis Gmail est rejeté. '
      + '2 017 ont un téléphone : les fiches d’appel de la semaine sont dans « Appels établissements ».',
    );
  });

  it('accorde au singulier et dit quand il n’y a pas de téléphone non plus', () => {
    const a = alerteCibles({ ...constat, etablissements_cibles: 3, adresses_fermees: 1, telephones_utilisables: 0, telephones_restants: 0 });
    expect(lisible(a?.texte)).toBe(
      'Aucune adresse utilisable parmi les 3 établissements ciblés (56, 75, 92). '
      + '1 a une adresse, en messagerie de santé fermée (MSSanté, Apicrypt), où un email envoyé depuis Gmail est rejeté. '
      + 'Aucun n’a de téléphone non plus.',
    );
    const b = alerteCibles({ ...constat, adresses_fermees: 0, telephones_utilisables: 1 });
    expect(lisible(b?.texte)).toBe(
      'Aucune adresse utilisable parmi les 2 318 établissements ciblés (56, 75, 92). '
      + '1 a un téléphone : les fiches d’appel de la semaine sont dans « Appels établissements ».',
    );
  });

  it('informe quand toutes les adresses utilisables sont déjà traitées', () => {
    const a = alerteCibles({ ...constat, adresses_utilisables: 12, adresses_restantes: 0 });
    expect(a?.niveau).toBe('info');
    expect(a?.titre).toBe('Plus aucune adresse à contacter par email');
    expect(lisible(a?.texte)).toBe(
      'Les 12 adresses utilisables des 2 318 établissements ciblés (56, 75, 92) sont déjà contactées, au CRM ou en file. '
      + '2 017 ont un téléphone : les fiches d’appel de la semaine sont dans « Appels établissements ».',
    );
    expect(lisible(alerteCibles({ ...constat, adresses_utilisables: 1, adresses_restantes: 0 })?.texte))
      .toContain('La seule adresse utilisable des 2 318 établissements ciblés (56, 75, 92) est déjà contactée, au CRM ou en file.');
  });

  it('se tait tant qu’il reste une adresse à contacter, ou sans décompte', () => {
    expect(alerteCibles({ ...constat, adresses_utilisables: 12, adresses_restantes: 5 })).toBeNull();
    expect(alerteCibles({ ...constat, adresses_utilisables: 12, adresses_restantes: 5 }, { premiers_contacts: 3, places_non_pourvues: 17, sans_mention: 0 })).toBeNull();
    expect(alerteCibles({ ...constat, adresses_utilisables: 12, adresses_restantes: 5 }, { premiers_contacts: 0, places_non_pourvues: 0, sans_mention: 0 })).toBeNull();
    expect(alerteCibles(null)).toBeNull();
  });

  it('dit quand les adresses restantes ont toutes été écartées au dernier passage', () => {
    expect(lirePassage({ premiers_contacts: 0, places_non_pourvues: 20, places_du_jour: 20 })).toEqual({ premiers_contacts: 0, places_non_pourvues: 20, sans_mention: 0 });
    expect(lirePassage({ premiers_contacts: 2, places_non_pourvues: 0, exclus_sans_mention: 3 })?.sans_mention).toBe(3);
    expect(lirePassage({ premiers_contacts: 2, places_non_pourvues: 0, exclus_sans_mention: 'trois' })?.sans_mention).toBe(0);
    expect(lirePassage({ premiers_contacts: 0 })).toBeNull();
    expect(lirePassage(null)).toBeNull();
    const a = alerteCibles({ ...constat, adresses_utilisables: 12, adresses_restantes: 5 }, { premiers_contacts: 0, places_non_pourvues: 20, sans_mention: 0 });
    expect(a?.niveau).toBe('info');
    expect(a?.titre).toBe('Aucun nouvel email préparé');
    expect(lisible(a?.texte)).toBe(
      'Il reste 5 adresses utilisables non contactées, mais elles ont toutes été écartées au dernier passage (opposition, ou adresse déjà en séquence). '
      + '2 017 ont un téléphone : les fiches d’appel de la semaine sont dans « Appels établissements ».',
    );
  });

  it('signale un ciblage vide', () => {
    const a = alerteCibles({ ...constat, departements: ['ZZ'], etablissements_cibles: 0, adresses_fermees: 0, telephones_utilisables: 0, telephones_restants: 0 });
    expect(a).toEqual({
      niveau: 'alerte',
      titre: 'Prospection sans cible',
      texte: 'Aucun établissement ne correspond aux départements et aux types ciblés (ZZ). Les agents de prospection ne peuvent rien préparer.',
    });
  });

  it('résume le décompte sur la carte de l’agent', () => {
    expect(lisible(resumeCibles(constat))).toBe('2 318 établissements ciblés · 0 adresse utilisable · 656 en messagerie fermée · 2 017 téléphones');
    expect(lisible(resumeCibles({ ...constat, etablissements_cibles: 1, adresses_utilisables: 2, telephones_utilisables: 1 })))
      .toBe('1 établissement ciblé · 2 adresses utilisables · 656 en messagerie fermée · 1 téléphone');
    expect(lisible(resumeCibles({ ...constat, adresses_utilisables: 280, adresses_annuaire_public: 279, adresses_fermees: 506 })))
      .toBe('2 318 établissements ciblés · 280 adresses utilisables (dont 279 d’un annuaire public) · 506 en messagerie fermée · 2 017 téléphones');
  });
});

describe('agents de croissance — origine d’une adresse publique', () => {
  const origine = {
    email: 'contact@ehpad-exemple.test', source_code: 'ANNUAIRE_PERSONNES_AGEES_DATA_GOUV',
    source_url: 'https://www.data.gouv.fr/datasets/etablissements-ehpad-esld-residences-autonomie-accueils-de-jour',
    source_publie_le: '2020-11-11', source_maj_le: '2020-10-04', releve_le: '2026-11-24', classe: 'FONCTION',
  };

  it('dit d’où vient l’adresse, de quand elle date, et qu’elle n’est pas vérifiée', () => {
    expect(sourceAdresse({ email_source: origine })).toEqual({
      texte: 'annuaire public des établissements pour personnes âgées (pour-les-personnes-agees.gouv.fr), jeu ouvert de data.gouv.fr — fiche mise à jour le 04/10/2020, relevée le 24/11/2026. Adresse non vérifiée : elle a pu changer depuis.',
      url: origine.source_url,
    });
  });

  it('se rabat sur la date de publication, et n’affiche pas un lien qui n’est pas https', () => {
    const s = sourceAdresse({ email_source: { ...origine, source_maj_le: null, source_url: 'javascript:alert(1)' } });
    expect(s?.texte).toContain('fiche mise à jour le 11/11/2020');
    expect(s?.url).toBeNull();
    expect(sourceAdresse({ email_source: { ...origine, source_maj_le: 'hier', source_publie_le: undefined, releve_le: 20261124 } })?.texte)
      .toBe('annuaire public des établissements pour personnes âgées (pour-les-personnes-agees.gouv.fr), jeu ouvert de data.gouv.fr. Adresse non vérifiée : elle a pu changer depuis.');
  });

  it('nomme une source inconnue par son code, et ne dit rien d’une adresse historique', () => {
    expect(sourceAdresse({ email_source: { ...origine, source_code: 'AUTRE_ANNUAIRE' } })?.texte).toContain('source AUTRE_ANNUAIRE');
    expect(sourceAdresse({ email_source: null })).toBeNull();
    expect(sourceAdresse({ source: 'FINESS (établissement) + Annuaire Santé (email)' })).toBeNull();
    expect(sourceAdresse({ email_source: 'annuaire' })).toBeNull();
    expect(sourceAdresse({ email_source: { source_url: origine.source_url } })).toBeNull();
  });

  it('ne s’affiche que sous l’adresse qu’elle décrit', () => {
    expect(sourceAdresse({ email_source: origine }, ' Contact@EHPAD-Exemple.test ')?.url).toBe(origine.source_url);
    expect(sourceAdresse({ email_source: origine }, 'autre@ehpad-exemple.test')).toBeNull();
    // Sans adresse à comparer (ancien appel) ou sans adresse dans la source : affichée.
    expect(sourceAdresse({ email_source: origine }, null)).not.toBeNull();
    expect(sourceAdresse({ email_source: { ...origine, email: undefined } }, 'autre@ehpad-exemple.test')).not.toBeNull();
  });
});

describe('adresses laissées sans brouillon', () => {
  it('se tait à zéro, compte au singulier et au pluriel', () => {
    expect(resumeSansMention(null)).toBeNull();
    expect(resumeSansMention({ premiers_contacts: 3, places_non_pourvues: 0, sans_mention: 0 })).toBeNull();
    expect(lisible(resumeSansMention({ premiers_contacts: 3, places_non_pourvues: 0, sans_mention: 1 }) ?? undefined))
      .toBe('Au dernier passage, 1 adresse laissée sans brouillon : origine sans mention d’opposition (adresse modifiée depuis son import).');
    expect(lisible(resumeSansMention({ premiers_contacts: 3, places_non_pourvues: 0, sans_mention: 4 }) ?? undefined))
      .toContain('4 adresses laissées sans brouillon');
  });
});
