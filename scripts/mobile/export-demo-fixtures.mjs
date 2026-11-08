#!/usr/bin/env node
/**
 * Export déterministe du monde démo de l'app iOS native (plan §4.6).
 *
 * Reproduit à l'identique l'algorithme de `mobile-native/src/data/demoGateway.ts`
 * (30 missions, 3 établissements fictifs, profil DEMO_CONTEXT) avec une horloge
 * fixée, puis écrit les fichiers JSON à clés snake_case (contrat PostgREST),
 * lus par `JoleneCore` (DemoMissionsGateway, DemoDashboardGateway) et par les XCUITest.
 *
 * Horloge fixée : 2026-11-02T00:00:00Z. Les missions démarrent donc du
 * 2026-11-03 au 2026-12-02 (07:00 UTC, ou 20:00 UTC une mission sur quatre).
 * Toute l'arithmétique est en UTC, comme dans le pilote : le résultat ne
 * dépend ni du fuseau ni de la date de la machine qui exécute le script.
 *
 * Usage :
 *   node scripts/mobile/export-demo-fixtures.mjs          # écrit les fichiers
 *   node scripts/mobile/export-demo-fixtures.mjs --check  # échoue si un fichier diffère
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const FIXED_NOW = '2026-11-02T00:00:00.000Z';
export const MISSION_COUNT = 30;

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const FIXTURES_DIR = join(
  ROOT, 'ios-native', 'Packages', 'JoleneCore', 'Sources', 'JoleneCore', 'Resources', 'fixtures',
);

/** Copie de DEMO_CONTEXT (demoGateway.ts). */
export const DEMO_PROFILE = {
  user_id: 'demo-soignant',
  email: 'demonstration@example.invalid',
  profile: {
    id: 'demo-soignant',
    profession: 'IDE',
    adresse_lat: 48.8566,
    adresse_lng: 2.3522,
    rayon_deplacement_km: 50,
    tous_documents_valides: false,
    type_contrat: 'CDD',
    types_contrat_acceptes: '["CDD","LIBERAL"]',
    type_exercice: 'MIXTE',
    taux_horaire_minimum: 0,
  },
};

/** Copie de ESTABLISHMENTS (demoGateway.ts). */
export const DEMO_ETABLISSEMENTS = [
  { id: 'demo-etab-1', nom: 'Établissement fictif République', adresse_ville: 'Paris', adresse_code_postal: '75011', adresse_lat: 48.867, adresse_lng: 2.363, type: 'CLINIQUE' },
  { id: 'demo-etab-2', nom: 'Établissement fictif des Lilas', adresse_ville: 'Les Lilas', adresse_code_postal: '93260', adresse_lat: 48.879, adresse_lng: 2.421, type: 'EHPAD' },
  { id: 'demo-etab-3', nom: 'Cabinet fictif du Parc', adresse_ville: 'Vincennes', adresse_code_postal: '94300', adresse_lat: 48.848, adresse_lng: 2.439, type: 'CABINET' },
];

/**
 * Même boucle que le constructeur de DemoGateway. Chaque mission porte ses
 * créneaux sous la clé `creneaux` (la table `mission_creneaux` du pilote).
 */
export function buildDemoMissions(now = new Date(FIXED_NOW)) {
  const missions = [];
  for (let index = 0; index < MISSION_COUNT; index += 1) {
    const day = new Date(now);
    day.setUTCDate(day.getUTCDate() + index + 1);
    day.setUTCHours(index % 4 === 3 ? 20 : 7, 0, 0, 0);
    const start = day.toISOString();
    const finish = new Date(day.getTime() + 8 * 3_600_000).toISOString();
    const id = `demo-mission-${String(index + 1).padStart(3, '0')}`;
    const multi = index % 6 === 5;
    const laterStart = new Date(day.getTime() + 2 * 86_400_000).toISOString();
    const laterFinish = new Date(day.getTime() + 2 * 86_400_000 + 8 * 3_600_000).toISOString();
    const hourly = 23 + (index % 8);
    const creneaux = [
      { id: `${id}-slot-1`, mission_id: id, debut: start, fin: finish, est_pause: false, type_creneau: 'PREVISIONNEL' },
    ];
    if (multi) {
      creneaux.push({ id: `${id}-slot-2`, mission_id: id, debut: laterStart, fin: laterFinish, est_pause: false, type_creneau: 'PREVISIONNEL' });
    }
    missions.push({
      id,
      intitule: `Démonstration · ${index % 2 ? 'Soins de suite' : 'Médecine polyvalente'} ${index + 1}`,
      description: 'Mission entièrement fictive pour découvrir la navigation native. Aucun remplacement, contrat ou paiement ne peut être engagé dans ce pilote.',
      service: index % 2 ? 'Soins de suite' : 'Médecine polyvalente',
      profession_requise: 'IDE',
      specialite_medicale_requise: null,
      accepte_non_specialises: null,
      debut_le: start,
      fin_le: multi ? laterFinish : finish,
      duree_heures: multi ? 16 : 8,
      nb_creneaux: multi ? 2 : 1,
      taux_horaire_base: hourly,
      taux_rist_plafonne: index === 0 ? hourly : null,
      rist_plafond_applique: index === 0,
      total_brut: null,
      net_a_payer: null,
      est_urgente: index % 5 === 0,
      niveau_urgence: index % 5 === 0 ? 1 : 0,
      statut: 'OUVERTE',
      etablissement_id: DEMO_ETABLISSEMENTS[index % DEMO_ETABLISSEMENTS.length].id,
      type_contrat_recherche: index % 3 === 2 ? 'LIBERAL' : 'SALARIE',
      boostee_le: null,
      mode_remuneration: 'HORAIRE',
      retrocession_pct: null,
      creneaux,
    });
  }
  return missions;
}

/** Instant UTC `jours` jours après `now`, à `heure`:00 (même arithmétique que buildDemoMissions). */
function instantDemo(now, jours, heure) {
  const day = new Date(now);
  day.setUTCDate(day.getUTCDate() + jours);
  day.setUTCHours(heure, 0, 0, 0);
  return day;
}

/**
 * Tableau de bord démo (lot 1, T3) : corps de `fn_dashboard_soignant_complet` (clés et ordre
 * des colonnes du dump `supabase/schema/public.sql` l.27920) pour le profil fictif, plus :
 *   - `missions_assignees` : fiches et créneaux des deux missions ASSIGNEE de `mes_missions`,
 *     lisibles en détail (DemoMissionsGateway.mission) mais jamais listées dans Explorer ;
 *   - `gains_missions` : missions TERMINEE du mois relues comme le web (décision 10).
 * `missions_ouvertes` = les trois premières missions démo (ORDER BY debut_le LIMIT 3) ; la
 * proposition PROPOSEE vise demo-mission-011 et date de 30 minutes avant l'horloge fixée.
 * `gains_mois.net_total` reste présent dans le corps (contrat serveur) mais n'est jamais affiché.
 */
export function buildDemoDashboard(now = new Date(FIXED_NOW), missions = buildDemoMissions(now)) {
  const nomEtab = (id) => DEMO_ETABLISSEMENTS.find((e) => e.id === id).nom;
  const assignee = (rang, service, etablissementId, taux, contrat, jours) => {
    const id = `demo-assignee-${String(rang).padStart(3, '0')}`;
    const creneaux = jours.map((jour, index) => {
      const debut = instantDemo(now, jour, 7);
      const fin = new Date(debut.getTime() + 8 * 3_600_000);
      return { id: `${id}-slot-${index + 1}`, mission_id: id, debut: debut.toISOString(), fin: fin.toISOString(), est_pause: false, type_creneau: 'PREVISIONNEL' };
    });
    return {
      id,
      intitule: `Démonstration · Mission assignée ${rang}`,
      description: 'Mission entièrement fictive pour découvrir la navigation native. Aucun remplacement, contrat ou paiement ne peut être engagé dans ce pilote.',
      service,
      profession_requise: 'IDE',
      specialite_medicale_requise: null,
      accepte_non_specialises: null,
      debut_le: creneaux[0].debut,
      fin_le: creneaux[creneaux.length - 1].fin,
      duree_heures: 8 * creneaux.length,
      nb_creneaux: creneaux.length,
      taux_horaire_base: taux,
      taux_rist_plafonne: null,
      rist_plafond_applique: false,
      total_brut: null,
      net_a_payer: null,
      est_urgente: false,
      niveau_urgence: 0,
      statut: 'ASSIGNEE',
      etablissement_id: etablissementId,
      type_contrat_recherche: contrat,
      boostee_le: null,
      mode_remuneration: 'HORAIRE',
      retrocession_pct: null,
      soignant_assigne_id: DEMO_PROFILE.user_id,
      presence_confirmee_le: null,
      creneaux,
    };
  };
  const missionsAssignees = [
    assignee(1, 'Médecine polyvalente', 'demo-etab-1', 27, 'SALARIE', [3]),
    assignee(2, 'Soins de suite', 'demo-etab-2', 30, 'LIBERAL', [7, 8]),
  ];
  const ouvertes = missions.slice(0, 3);
  const proposee = missions.find((m) => m.id === 'demo-mission-011');
  const termineeDebut = instantDemo(now, -1, 7);
  const lundi = instantDemo(now, 0, 0); // 2026-11-02 est un lundi
  const semaine = missionsAssignees.filter((m) => {
    const debut = new Date(m.debut_le).getTime();
    return debut >= lundi.getTime() && debut < lundi.getTime() + 7 * 86_400_000;
  });
  const dashboard = {
    profil: {
      prenom: 'Camille', nom: 'Démo', telephone: null, date_naissance: null,
      profession: DEMO_PROFILE.profile.profession, type_contrat: DEMO_PROFILE.profile.type_contrat,
      numero_rpps: null, numero_adeli: null, rpps_verifie: false,
      adresse_lat: DEMO_PROFILE.profile.adresse_lat, adresse_lng: DEMO_PROFILE.profile.adresse_lng,
      tous_documents_valides: DEMO_PROFILE.profile.tous_documents_valides, identite_verifiee: false,
      score_fiabilite: null, total_missions_terminees: 1, heures_cumulees: 8, eligible_conversion_3200h: false,
      type_exercice: DEMO_PROFILE.profile.type_exercice, mandat_facturation_signe: false,
    },
    missions_ouvertes: ouvertes.map((m) => ({
      id: m.id, intitule: m.intitule, service: m.service, debut_le: m.debut_le, fin_le: m.fin_le,
      duree_heures: m.duree_heures, nb_creneaux: m.nb_creneaux, taux_horaire_base: m.taux_horaire_base,
      total_brut: m.total_brut, net_a_payer: m.net_a_payer, net_estime: null,
      est_urgente: m.est_urgente, etablissement_id: m.etablissement_id, profession_requise: m.profession_requise,
      type_contrat_recherche: m.type_contrat_recherche, accepte_non_specialises: m.accepte_non_specialises,
      specialite_medicale_requise: m.specialite_medicale_requise, etab_nom: nomEtab(m.etablissement_id),
    })),
    mes_missions: missionsAssignees.map((m) => ({
      id: m.id, intitule: m.intitule, debut_le: m.debut_le, fin_le: m.fin_le, duree_heures: m.duree_heures,
      statut: m.statut, etablissement_id: m.etablissement_id, etab_nom: nomEtab(m.etablissement_id),
    })),
    documents: [
      { id: 'demo-document-001', type_document: 'CARTE_IDENTITE', valide_jusqua: '2030-06-30', statut_verification: 'VERIFIE' },
    ],
    heures_semaine: semaine.reduce((total, m) => total + m.duree_heures, 0),
    gains_mois: { net_total: 224.6, brut_total: 208, nb_missions: 1 },
    gains_6mois: [{ mois: termineeDebut.toISOString().slice(0, 7), net: 224.6 }],
    missions_semaine_cal: semaine.map((m) => ({ debut_le: m.debut_le, statut: m.statut })),
    propositions: [{
      id: 'demo-proposition-001',
      mission_id: proposee.id,
      cree_le: new Date(now.getTime() - 30 * 60_000).toISOString(),
      type_contrat_choisi: null,
      missions: {
        id: proposee.id, intitule: proposee.intitule, debut_le: proposee.debut_le, fin_le: proposee.fin_le,
        duree_heures: proposee.duree_heures, taux_horaire_base: proposee.taux_horaire_base, net_estime: null,
        type_contrat_recherche: proposee.type_contrat_recherche, etablissement_id: proposee.etablissement_id,
        est_urgente: proposee.est_urgente, etab_nom: nomEtab(proposee.etablissement_id),
      },
    }],
    heures_totales_terminees: 8,
    missions_oubliees_count: 0,
    notifs_non_lues: 2,
  };
  return {
    fixed_now: now.toISOString(),
    dashboard,
    missions_assignees: missionsAssignees,
    gains_missions: [
      { id: 'demo-terminee-001', type_contrat_applique: 'SALARIE', type_contrat_recherche: 'SALARIE', total_brut: 208, net_a_payer: 224.6, net_estime: 162.4 },
    ],
  };
}

/**
 * Présences et pointage démo (lot 2, T3 ; blueprint `docs/mobile-swift/LOT2_PLAN.md` §2.8), lus par
 * `DemoPointageGateway`. Colonnes des requêtes de `src/pages/PresencesSoignant.tsx` réduites à celles que lit l'app
 * (`MissionPresenceLue`, `PresenceLue`, `MissionDePresence`) : aucun montant, aucune colonne `code_pointage_*`,
 * jamais l'embed `etablissements` (noms par `demo-etablissements.json`, comme `fn_etablissements_safe`).
 *   - demo-presence-a : ASSIGNEE, créneau 00:05Z → 08:05Z le 02/11, contrat SIGNE_COMPLET, code affiché 123456
 *     (onglet Aujourd'hui, pointage ouvert car dans les 15 min) ;
 *   - demo-presence-b : EN_COURS, segment EFFECTIF ouvert depuis 2026-11-01T22:00Z, code affiché 654321 ;
 *   - demo-presence-c : ASSIGNEE ce jour, contrat SIGNE_SOIGNANT (motif CONTRAT), aucun code ;
 *   - demo-presence-d : ASSIGNEE, créneau le 03/11 (À venir) ;
 *   - demo-presence-e : ASSIGNEE sur plusieurs jours sans créneau (« Planning détaillé à confirmer ») ;
 *   - historique : h1 validée il y a 10 h, h2 non validée, h3 sans présence reconstruite depuis deux EFFECTIF.
 * `codes_affiches` simule le code affiché par l'écran établissement fictif (`AffichageCodeRotatifEtab`) : il n'est
 * jamais renvoyé par le monde démo, qui le fait tourner après chaque scan. `consentement_gps` nul : le soignant n'a
 * pas encore répondu.
 */
export function buildDemoPresences(now = new Date(FIXED_NOW)) {
  const minutes = (n) => new Date(now.getTime() + n * 60_000);
  const heures = (n) => minutes(n * 60);
  const iso = (date) => date.toISOString();
  const creneau = (id, missionId, debut, fin, type = 'PREVISIONNEL') => ({
    id, mission_id: missionId, debut: iso(debut), fin: fin ? iso(fin) : null, est_pause: false, type_creneau: type,
  });
  const mission = (id, intitule, statut, debut, fin, etablissementId, service) => ({
    id, intitule: `Démonstration · ${intitule}`, service, debut_le: iso(debut), fin_le: iso(fin),
    duree_heures: (fin.getTime() - debut.getTime()) / 3_600_000, statut, etablissement_id: etablissementId,
  });
  const missions = [
    mission('demo-presence-a', 'Pointage du jour', 'ASSIGNEE', minutes(5), minutes(8 * 60 + 5), 'demo-etab-1', 'Médecine polyvalente'),
    mission('demo-presence-b', 'Mission en cours', 'EN_COURS', heures(-2), heures(6), 'demo-etab-2', 'Soins de suite'),
    mission('demo-presence-c', 'Contrat à signer', 'ASSIGNEE', heures(6), heures(14), 'demo-etab-3', 'Consultations'),
    mission('demo-presence-d', 'Mission de demain', 'ASSIGNEE', heures(31), heures(39), 'demo-etab-1', 'Médecine polyvalente'),
    mission('demo-presence-e', 'Planning à confirmer', 'ASSIGNEE', heures(8 * 24 + 7), heures(12 * 24 + 15), 'demo-etab-2', 'Soins de suite'),
  ];
  const missionsHistorique = [
    mission('demo-presence-h1', 'Présence validée', 'TERMINEE', heures(-41), heures(-33), 'demo-etab-1', 'Médecine polyvalente'),
    mission('demo-presence-h2', 'Présence à valider', 'TERMINEE', heures(-65), heures(-57), 'demo-etab-2', 'Soins de suite'),
    mission('demo-presence-h3', 'Heures pointées sans présence', 'TERMINEE', heures(-113), heures(-105), 'demo-etab-3', 'Consultations'),
  ];
  const creneaux = [
    creneau('demo-presence-a-prevu', 'demo-presence-a', minutes(5), minutes(8 * 60 + 5)),
    creneau('demo-presence-b-prevu', 'demo-presence-b', heures(-2), heures(6)),
    creneau('demo-presence-b-effectif-1', 'demo-presence-b', heures(-2), null, 'EFFECTIF'),
    creneau('demo-presence-c-prevu', 'demo-presence-c', heures(6), heures(14)),
    creneau('demo-presence-d-prevu', 'demo-presence-d', heures(31), heures(39)),
    creneau('demo-presence-h1-prevu', 'demo-presence-h1', heures(-41), heures(-33)),
    creneau('demo-presence-h1-effectif-1', 'demo-presence-h1', heures(-41), heures(-33), 'EFFECTIF'),
    creneau('demo-presence-h2-prevu', 'demo-presence-h2', heures(-65), heures(-57)),
    creneau('demo-presence-h2-effectif-1', 'demo-presence-h2', heures(-65), heures(-57), 'EFFECTIF'),
    creneau('demo-presence-h3-prevu', 'demo-presence-h3', heures(-113), heures(-105)),
    creneau('demo-presence-h3-effectif-1', 'demo-presence-h3', heures(-113), heures(-108), 'EFFECTIF'),
    creneau('demo-presence-h3-effectif-2', 'demo-presence-h3', minutes(-108 * 60 + 30), heures(-105), 'EFFECTIF'),
  ].sort((a, b) => new Date(a.debut).getTime() - new Date(b.debut).getTime());
  const embed = (m, avecStatut) => ({
    id: m.id, intitule: m.intitule, etablissement_id: m.etablissement_id, debut_le: m.debut_le, fin_le: m.fin_le,
    ...(avecStatut ? { statut: m.statut } : {}),
  });
  const presence = (id, m, valideLe, avecStatut) => ({
    id, mission_id: m.id, soignant_id: DEMO_PROFILE.user_id, pointage_arrivee_le: m.debut_le, pointage_depart_le: m.fin_le,
    valide_par_etablissement: valideLe !== null, valide_le: valideLe,
    methode_pointage_arrivee: 'CODE', methode_pointage_depart: 'CODE', missions: embed(m, avecStatut),
  });
  const [h1, h2] = missionsHistorique;
  const contrat = (missionId, statut) => ({
    id: `demo-contrat-pointage-${missionId.slice('demo-presence-'.length)}`, mission_id: missionId, statut,
    cree_le: iso(heures(-72)),
  });
  return {
    fixed_now: now.toISOString(),
    consentement_gps: null,
    missions,
    presences_validees: [presence('demo-presence-h1-presence', h1, iso(heures(-10)), false)],
    historique: [
      presence('demo-presence-h1-presence', h1, iso(heures(-10)), true),
      presence('demo-presence-h2-presence', h2, null, true),
    ],
    missions_historique: missionsHistorique,
    creneaux,
    contrats: [
      contrat('demo-presence-a', 'SIGNE_COMPLET'), contrat('demo-presence-b', 'SIGNE_COMPLET'),
      contrat('demo-presence-c', 'SIGNE_SOIGNANT'), contrat('demo-presence-d', 'SIGNE_COMPLET'),
      contrat('demo-presence-e', 'SIGNE_COMPLET'),
    ],
    codes_affiches: { 'demo-presence-a': '123456', 'demo-presence-b': '654321' },
  };
}

/**
 * Lot 2 T6 (`docs/mobile-swift/LOT2_PLAN.md` §2.8) : justificatifs du profil fictif (IDE MIXTE, comme DEMO_PROFILE).
 * Exigences fictives marquées « Exigence de démonstration » : aucune règle réelle n'est reproduite, seule la forme des
 * lignes de `documents_requis_par_profession` ; VACCINATIONS y figure pour prouver le filtre des pièces de santé
 * (`TYPES_DOCUMENTS_EXCLUS_UPLOAD`). Pièces : diplôme vérifié ; pièce d'identité REJETE avec une date passée (doit
 * s'afficher Rejetée, pas Expirée) ; RCP vérifiée qui expire dans 12 jours ; RIB expiré. Les clés Storage suivent le
 * chemin du web (`<uid>/documents/<TYPE>/<ms>-<nom>`), sans aucun objet réel.
 */
export function buildDemoDocuments(now = new Date(FIXED_NOW)) {
  const uid = DEMO_PROFILE.user_id;
  const jour = (decalage) => {
    const d = new Date(now);
    d.setUTCDate(d.getUTCDate() + decalage);
    return d.toISOString().slice(0, 10);
  };
  const instant = (decalage) => new Date(now.getTime() + decalage * 86_400_000).toISOString();
  const exigence = (type, critique, exercice) => ({
    id: `demo-exigence-${type.toLowerCase().replaceAll('_', '-')}`,
    profession: DEMO_PROFILE.profile.profession,
    type_document: type,
    description: 'Exigence de démonstration',
    a_expiration: type !== 'DIPLOME',
    duree_validite_mois: null,
    est_critique: critique,
    type_exercice_requis: exercice,
  });
  const piece = (id, type, nom, mime, televerseJours, extra) => {
    const ms = new Date(instant(televerseJours)).getTime();
    return {
      id,
      type_document: type,
      libelle: null,
      s3_cle: `${uid}/documents/${type}/${ms}-${nom}`,
      nom_fichier: nom,
      type_mime: mime,
      taille_octets: 2048,
      valide_depuis: null,
      valide_jusqua: null,
      statut_verification: 'VERIFIE',
      motif_rejet: null,
      televerse_le: instant(televerseJours),
      verification_attempt_id: null,
      est_critique: true,
      profession_certifiee: null,
      ...extra,
    };
  };
  return {
    fixed_now: now.toISOString(),
    profil: {
      profession: DEMO_PROFILE.profile.profession,
      type_exercice: DEMO_PROFILE.profile.type_exercice,
      rpps_verifie: false,
      adeli_verifie: false,
    },
    attestation_sante_signee_le: null,
    exigences: [
      exigence('CARTE_IDENTITE', true, 'TOUS'),
      exigence('DIPLOME', true, 'TOUS'),
      exigence('RCP_ASSURANCE', true, 'LIBERAL_ONLY'),
      exigence('RIB', false, 'LIBERAL_ONLY'),
      exigence('VACCINATIONS', true, 'TOUS'),
    ],
    // Les plus récentes d'abord (`order('televerse_le', { ascending: false })`).
    documents: [
      piece('demo-doc-carte-identite', 'CARTE_IDENTITE', 'piece-identite-demonstration.pdf', 'application/pdf', -3,
        { statut_verification: 'REJETE', valide_jusqua: jour(-32), motif_rejet: 'Pièce de démonstration illisible.' }),
      piece('demo-doc-rcp', 'RCP_ASSURANCE', 'rcp-demonstration.pdf', 'application/pdf', -5, { valide_jusqua: jour(12) }),
      piece('demo-doc-diplome', 'DIPLOME', 'diplome-demonstration.pdf', 'application/pdf', -12, { valide_depuis: '2020-07-01' }),
      piece('demo-doc-rib', 'RIB', 'rib-demonstration.pdf', 'application/pdf', -400,
        { statut_verification: 'EXPIRE', valide_jusqua: jour(-18), est_critique: false }),
    ],
  };
}

export function buildFixtures() {
  return {
    'demo-missions.json': { fixed_now: FIXED_NOW, missions: buildDemoMissions() },
    'demo-etablissements.json': { fixed_now: FIXED_NOW, etablissements: DEMO_ETABLISSEMENTS },
    'demo-profile.json': { fixed_now: FIXED_NOW, ...DEMO_PROFILE },
    'demo-dashboard.json': buildDemoDashboard(),
    'demo-presences.json': buildDemoPresences(),
    'demo-documents.json': buildDemoDocuments(),
  };
}

const serialize = (value) => `${JSON.stringify(value, null, 2)}\n`;

function main(argv) {
  const check = argv.includes('--check');
  const fixtures = buildFixtures();
  mkdirSync(FIXTURES_DIR, { recursive: true });
  let drift = 0;
  for (const [name, value] of Object.entries(fixtures)) {
    const path = join(FIXTURES_DIR, name);
    const expected = serialize(value);
    if (check) {
      let actual = null;
      try { actual = readFileSync(path, 'utf8'); } catch { actual = null; }
      if (actual !== expected) {
        drift += 1;
        console.error(`DIFF ${path}`);
      }
      continue;
    }
    writeFileSync(path, expected, 'utf8');
    console.log(`OK ${path}`);
  }
  if (check) {
    if (drift > 0) {
      console.error(`${drift} fichier(s) de fixtures démo divergent : relancer sans --check.`);
      process.exit(1);
    }
    console.log(`OK fixtures démo identiques (${Object.keys(fixtures).length} fichiers).`);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2));
}
