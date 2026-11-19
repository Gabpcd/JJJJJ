/**
 * Lot 5, T7 — pointage terrain de l'établissement démo (`docs/mobile-swift/LOT5_PLAN.md` §3 T7, fixture
 * `demo-etab-pointage.json`), écrit par `export-demo-fixtures.mjs` (job « Cœur » : sortie diffée).
 *
 * Réponses de `fn_etat_pointage_mission` rejouées par la gateway démo, dans l'ordre, pour les missions assignées ou en
 * cours de `demo-etab-missions.json` (créneaux et horaires **dérivés** de cette fixture, jamais ressaisis) :
 *   M4 (nuit en cours, contrat signé) : code `123456` servi deux lectures, puis l'état relu après le scan d'arrivée du
 *     soignant (segment ouvert, prochain pointage FERMETURE, code `100002`) — le code suivant n'est jamais calculé par
 *     l'app : c'est une réponse serveur enregistrée, comme la rotation de `fn_scanner_code_pointage` ;
 *   M5 (contrat à signer) : aucune réponse enregistrée, la gateway sert l'état neutre de la mission → code masqué ;
 *   M6 (deux créneaux, contrat signé) : premier créneau pointé (segment fermé), second créneau à venir → code masqué
 *     hors créneau.
 * `contrats_signes` : réponse de `fn_contrat_signe_pour_pointage` (contrat `SIGNE_COMPLET` des deux parties). Les
 * codes sont fictifs (six chiffres) ; aucune clé de la réponse du scanner n'est reprise.
 */

/** Instant ISO décalé de `minutes` minutes. */
function decaler(iso, minutes) {
  return new Date(new Date(iso).getTime() + minutes * 60_000).toISOString();
}

/**
 * @param {{ now: Date, missions: { missions: object[], creneaux: object[] } }} entree
 *   `missions` : la fixture `demo-etab-missions.json` (source des créneaux et des statuts).
 */
export function buildDemoEtabPointage({ now, missions }) {
  const creneau = (missionId, rang) => {
    const ligne = missions.creneaux.find(c => c.id === `${missionId}-slot-${rang}`);
    if (!ligne) throw new Error(`Créneau ${rang} de ${missionId} absent de demo-etab-missions.json`);
    return ligne;
  };
  const statut = (missionId) => {
    const mission = missions.missions.find(m => m.id === missionId);
    if (!mission) throw new Error(`Mission ${missionId} absente de demo-etab-missions.json`);
    return mission.statut;
  };
  const etat = (missionId, champs) => ({
    statut: champs.statut ?? statut(missionId),
    prochain_type_scan: champs.prochain ?? 'OUVERTURE',
    segment_ouvert: (champs.segments ?? []).some(s => s.fin === null),
    segments: champs.segments ?? [],
    code_pointage_actif: champs.code ?? null,
  });
  const m4 = 'demo-etab-m04';
  const m6 = 'demo-etab-m06';
  const nuit = creneau(m4, 1);
  const veille = creneau(m6, 1);
  if (!(new Date(nuit.debut) <= now && now < new Date(nuit.fin))) {
    throw new Error('M4 doit être en cours à l’horloge fixée du monde démo');
  }
  return {
    fixed_now: now.toISOString(),
    contrats_signes: [m4, m6],
    scenarios: [
      {
        mission_id: m4,
        etats: [
          { lectures: 2, etat: etat(m4, { code: '123456' }) },
          {
            lectures: null,
            etat: etat(m4, {
              statut: 'EN_COURS',
              prochain: 'FERMETURE',
              segments: [{ id: `${m4}-seg-1`, debut: decaler(now.toISOString(), -2), fin: null }],
              code: '100002',
            }),
          },
        ],
      },
      {
        mission_id: m6,
        etats: [
          {
            lectures: null,
            etat: etat(m6, {
              segments: [{ id: `${m6}-seg-1`, debut: decaler(veille.debut, 2), fin: decaler(veille.fin, 1) }],
              code: '654321',
            }),
          },
        ],
      },
    ],
  };
}
