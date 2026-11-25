/**
 * Fixtures démo du domaine « serie » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T12.
 *
 * Module du domaine : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais
 * export-demo-fixtures.mjs ni les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier
 * (`demo-<nom>.json`) → valeur JSON, ou `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * `demo-serie.json`, lu par `DemoSerieGateway` : deux séries (« packs ») de missions du monde démo. Les missions ne
 * sont pas recopiées : une série liste des identifiants de `demo-missions.json` (ouvertes, attribution au premier
 * arrivé) ou de `demo-dashboard.json` (déjà attribuée au profil fictif), relus par le port des missions du monde, si
 * bien qu'une mission acceptée dans la série est servie attribuée partout. Identifiants de série à la forme que le web
 * écrit et relit (`src/components/CarteSerie.tsx` l.27, `SERIE_<horodatage>_<suffixe>`).
 *
 * `reponse` : corps que rendrait `fn_confirmer_action_planning_v1` pour cette mission (clés du jsonb du serveur),
 * rejoué tel quel par la gateway démo ; absent, la mission est acceptée par la candidature du monde démo. Les textes
 * sont au format du serveur (supabase/schema/public.sql), jamais reformulés — `Lot4WiringSerieTests` les confronte
 * au dump :
 *   - conflit de planning : `fn_conflit_planning_soignant` (« Tu es déjà confirmé(e) sur « … » le … . Ce créneau
 *     chevauche la mission. »), code `CONFLIT_PLANNING` posé par `fn_confirmer_action_planning_v1` ; la mission 013
 *     (15/11, 08 h-16 h à Paris) chevauche réellement la mission assignée 4 du tableau de bord démo ;
 *   - choix de contrat : `{choix_requis, error, options}` de `fn_resoudre_contrat_mission`, sans clé `success` ;
 *   - refus d'un trigger de conformité : exception `dec_verifier_repos_11h` telle que le transport la restitue
 *     (`RPCResponse.refusCodeDuTravail` : `{success:false, ok:false, code:'CODE_DU_TRAVAIL', error:<message>}`) ; la
 *     mission 008 (10/11, 21 h à Paris) commence 5 h après la fin de la mission assignée 2 (10/11, 16 h).
 *
 * Série 1 (plan §2.7 : cinq missions, une refusée pour conflit) : 001, 010, 013 (conflit), 025, 028.
 * Série 2 : 002 (choix de contrat requis), 005, 008 (refus de conformité : la boucle s'arrête), la mission assignée 4
 * (déjà pourvue, non sélectionnable) et 023 (jamais envoyée).
 */
export const SERIE_PACK = 'SERIE_1793577600000_demo01';
export const SERIE_ARRET = 'SERIE_1793577600000_demo02';

/** Options de `fn_resoudre_contrat_mission` (`supabase/schema/public.sql`), comme `DemoCandidatureGateway.Textes`. */
const CHOIX_CONTRAT = [
  { value: 'SALARIE', label: 'Salarié (CDD / bulletin de paie)' },
  { value: 'LIBERAL', label: "Libéral (note d'honoraires)" },
];

/** @param {Date} now horloge fixée du monde démo */
export function buildDemoSerie(now) {
  return {
    fixed_now: now.toISOString(),
    series: [
      {
        serie_id: SERIE_PACK,
        missions: [
          { mission_id: 'demo-mission-001' },
          { mission_id: 'demo-mission-010' },
          {
            mission_id: 'demo-mission-013',
            reponse: {
              success: false,
              ok: false,
              code: 'CONFLIT_PLANNING',
              error: 'Tu es déjà confirmé(e) sur « Démonstration · Mission assignée 4 » le 15/11 08h00–15/11 16h00. Ce créneau chevauche la mission.',
            },
          },
          { mission_id: 'demo-mission-025' },
          { mission_id: 'demo-mission-028' },
        ],
      },
      {
        serie_id: SERIE_ARRET,
        missions: [
          {
            mission_id: 'demo-mission-002',
            reponse: { choix_requis: true, error: 'Choisissez votre mode de contrat.', options: CHOIX_CONTRAT },
          },
          { mission_id: 'demo-mission-005' },
          {
            mission_id: 'demo-mission-008',
            reponse: {
              success: false,
              ok: false,
              code: 'CODE_DU_TRAVAIL',
              error: '[CODE DU TRAVAIL] Repos insuffisant avant mission : 5.0 heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée.',
            },
          },
          { mission_id: 'demo-assignee-004' },
          { mission_id: 'demo-mission-023' },
        ],
      },
    ],
  };
}

/**
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  return { 'demo-serie.json': buildDemoSerie(contexte.now) };
}
