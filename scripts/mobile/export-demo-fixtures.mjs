#!/usr/bin/env node
/**
 * Export déterministe du monde démo de l'app iOS native (plan §4.6).
 *
 * Reproduit à l'identique l'algorithme de `mobile-native/src/data/demoGateway.ts`
 * (30 missions, 3 établissements fictifs, profil DEMO_CONTEXT) avec une horloge
 * fixée, puis écrit les fichiers JSON à clés snake_case (contrat PostgREST),
 * lus par `JoleneCore` (DemoMissionsGateway, DemoDashboardGateway, DemoPreferencesGateway) et par les XCUITest.
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
 * Centre de notifications démo (lot 3, T5) : lignes `notifications` du profil fictif, colonnes lues par
 * l'app (`id, titre, corps, type, lien, lue, lue_le, cree_le`), types de `notifications_type_check`
 * (`supabase/schema/public.sql` l.70815). Deux non lues, comme `notifs_non_lues` du tableau de bord démo ;
 * liens : détail d'une mission ASSIGNEE démo, Mes missions, factures (renvoi web, lot 4), Stripe Connect
 * (renvoi web jusqu'à T14a), préférences (écran natif depuis T6), litiges (renvoi web), et une ligne sans lien.
 * Dates : quelques heures à six jours avant l'horloge fixée (après le changement d'heure du 25/10/2026).
 */
export function buildDemoNotifications(now = new Date(FIXED_NOW)) {
  const avant = (heures) => new Date(now.getTime() - heures * 3_600_000).toISOString();
  const ligne = (rang, type, titre, corps, lien, lue, heures) => ({
    id: `demo-notification-${String(rang).padStart(3, '0')}`,
    titre, corps, type, lien,
    lue,
    lue_le: lue ? avant(heures - 1) : null,
    cree_le: avant(heures),
  });
  return {
    fixed_now: now.toISOString(),
    notifications: [
      ligne(1, 'RAPPEL_MISSION', 'Démonstration · Rappel de mission',
        'Votre mission fictive « Démonstration · Mission assignée 1 » approche.', '/soignant/missions/demo-assignee-001', false, 2),
      ligne(2, 'CANDIDATURE_ACCEPTEE', 'Démonstration · Candidature acceptée',
        'Une candidature fictive a été retenue. Retrouvez-la dans Mes missions.', '/soignant/missions', false, 5),
      ligne(3, 'FACTURE_EMISE', 'Démonstration · Facture émise',
        'Une facture fictive est disponible.', '/soignant/mes-gains?tab=factures', true, 26),
      ligne(4, 'SYSTEM', 'Démonstration · Paiements',
        'Configurez vos paiements fictifs.', '/soignant/stripe-connect', true, 48),
      ligne(5, 'SYSTEM', 'Démonstration · Préférences',
        'Choisissez les notifications que vous recevez.', '/soignant/parametres/notifications', true, 72),
      ligne(6, 'LITIGE_OUVERT', 'Démonstration · Litige ouvert',
        'Un litige fictif a été ouvert sur une mission.', '/soignant/litiges', true, 120),
      ligne(7, 'MISSION_A_POURVOIR', 'Démonstration · Nouvelle mission',
        'Une mission fictive correspond à votre profil.', null, true, 144),
    ],
  };
}

/**
 * Lot 3, T6 : préférences de notifications du profil fictif. `preferences` = corps de
 * `fn_obtenir_mes_preferences_notifications()` (ligne `preferences_notifications` aux défauts serveur
 * — e-mail, push, in-app actifs, SMS coupé — et trois exceptions par événement du catalogue soignant) ;
 * `soignant` = `soignants.select('sms_alertes_actives, type_exercice')`, régime dérivé du profil démo.
 * Lu par `DemoPreferencesGateway` et par les XCUITest (`DemoPreferencesTests`).
 */
export function buildDemoPreferences() {
  return {
    fixed_now: FIXED_NOW,
    preferences: {
      global: {
        canal_email: true,
        canal_sms: false,
        canal_push: true,
        canal_in_app: true,
        cree_le: '2026-10-01T08:00:00+00:00',
        mis_a_jour_le: '2026-10-01T08:00:00+00:00',
      },
      par_evenement: [
        { type_evenement: 'NOUVELLE_MISSION_MATCHANT_FILTRE', canal: 'EMAIL', actif: false },
        { type_evenement: 'LITIGE_RESOLU', canal: 'PUSH', actif: false },
        { type_evenement: 'SERIE_ONBOARDING', canal: 'EMAIL', actif: false },
      ],
    },
    soignant: { sms_alertes_actives: true, type_exercice: DEMO_PROFILE.profile.type_exercice },
  };
}

/**
 * Profil complet démo (lot 3, T9) : réponse de `fn_mon_profil_soignant_complet` (colonnes du dump
 * `supabase/schema/public.sql` l.44667-44679) pour le profil fictif, RÉDUITE À LA LISTE BLANCHE du
 * décodeur Swift (`ProfilComplet.clesLues`) : aucune clé sensible (`numero_secu`, `siret_liberal`,
 * `iban_last4`…), garde `DemoProfilGatewayTests`. Identité alignée sur le tableau de bord démo.
 */
export function buildDemoProfilComplet(now = new Date(FIXED_NOW)) {
  const p = DEMO_PROFILE.profile;
  return {
    fixed_now: now.toISOString(),
    profil: {
      id: p.id, prenom: 'Camille', nom: 'Démo', email: DEMO_PROFILE.email, telephone: null,
      date_naissance: '1990-05-14', profession: p.profession, numero_rpps: null, rpps_verifie: false,
      type_contrat: p.type_contrat, type_exercice: p.type_exercice,
      adresse_lat: p.adresse_lat, adresse_lng: p.adresse_lng, rayon_deplacement_km: p.rayon_deplacement_km,
      bio: null, annees_experience: 4, specialites: [], types_contrat_acceptes: p.types_contrat_acceptes,
      avatar_url: null, taux_horaire_minimum: p.taux_horaire_minimum, ville_recherche: null,
    },
  };
}

export function buildFixtures() {
  return {
    'demo-missions.json': { fixed_now: FIXED_NOW, missions: buildDemoMissions() },
    'demo-etablissements.json': { fixed_now: FIXED_NOW, etablissements: DEMO_ETABLISSEMENTS },
    'demo-profile.json': { fixed_now: FIXED_NOW, ...DEMO_PROFILE },
    'demo-dashboard.json': buildDemoDashboard(),
    'demo-notifications.json': buildDemoNotifications(),
    'demo-preferences.json': buildDemoPreferences(), // lot 3, T6
    'demo-profil-complet.json': buildDemoProfilComplet(),
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
