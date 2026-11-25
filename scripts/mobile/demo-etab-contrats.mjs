/**
 * Lot 5, T10 — contrats de l'établissement démo (`docs/mobile-swift/LOT5_PLAN.md` §2.10, §3 T10, fixture
 * `demo-etab-contrats.json`), écrits par `export-demo-fixtures.mjs` (job « Cœur » : sortie diffée).
 *
 * Deux contrats de l'établissement démo (`demo-etab-1`), **dérivés** des missions de `demo-etab-missions.json`
 * (mission, soignant assigné, horaires : jamais ressaisis) et cohérents avec `demo-etab-pointage.json` :
 *   - `demo-etab-contrat-m05` : mission M5 « Contrat à signer », CDD `EN_ATTENTE_SIGNATURES`, créé 8 h avant
 *     l'horloge (64 h restantes), original figé : c'est le contrat que l'établissement signe par OTP en démo ;
 *   - `demo-etab-contrat-m04` : mission M4 (code de pointage affiché : contrat signé), CDD `SIGNE_COMPLET`,
 *     deux lignes de certificat (établissement puis soignant).
 * Les originaux sont rendus par le moteur serveur, comme ceux du lot 2 (`rendreOriginalDemo` de
 * `export-demo-fixtures.mjs` : `rendreCddEmployeur` puis `wrapInDocument`) : aucun texte de contrat n'est écrit
 * ici ; l'empreinte est le SHA-256 des octets UTF-8 du document complet. Même forme que `demo-contrats.json`
 * (lignes à la projection `ContratDetail.selection`, signatures à `SignatureCertificat.colonnes`) ; missions
 * réduites à l'embed de la liste (`intitule, debut_le, fin_le`), sans aucun montant (D15).
 * Le CDD « à préparer » (sans original) n'est pas une ligne de la fixture : la gateway démo sert M5 sans original
 * sous `-JOLENE_DEMO_SCENARIO cdd-a-preparer`. Aucune donnée réelle.
 */

const HEURE = 3_600_000;
/** Taux fictif du rendu de l'original (le document le porte, comme un vrai contrat) ; jamais écrit dans le JSON. */
const TAUX_FICTIF = 26;

/**
 * @param {{ now: Date, missions: { missions: object[], creneaux: object[], soignants: object[] },
 *   etablissement: object, utilisateurEtablissement: string,
 *   rendreOriginal: (entree: object) => { html: string, empreinte: string } }} entree
 *   `missions` : la fixture `demo-etab-missions.json` ; `rendreOriginal` : `rendreOriginalDemo` lié au moteur serveur.
 */
export function buildDemoEtabContrats({ now, missions, etablissement, utilisateurEtablissement, rendreOriginal }) {
  const iso = ms => new Date(ms).toISOString();
  const mission = (id) => {
    const ligne = missions.missions.find(m => m.id === id);
    if (!ligne) throw new Error(`Mission ${id} absente de demo-etab-missions.json`);
    if (!ligne.soignant_assigne_id) throw new Error(`Mission ${id} sans soignant assigné : aucun contrat`);
    return ligne;
  };
  const soignant = (id) => {
    const ligne = missions.soignants.find(s => s.id === id);
    if (!ligne) throw new Error(`Soignant ${id} absent de demo-etab-missions.json`);
    return ligne;
  };
  const dureeHeures = (missionId) => missions.creneaux
    .filter(c => c.mission_id === missionId && c.type_creneau === 'PREVISIONNEL' && !c.est_pause)
    .reduce((total, c) => total + (new Date(c.fin).getTime() - new Date(c.debut).getTime()) / HEURE, 0);

  const contrat = ({ rang, numero, statut, creeLe, signeEtabLe = null, signeSoignantLe = null }) => {
    const m = mission(`demo-etab-m${rang}`);
    const s = soignant(m.soignant_assigne_id);
    const id = `demo-etab-contrat-m${rang}`;
    const renduLe = iso(new Date(creeLe).getTime() + 5 * 60_000);
    const original = rendreOriginal({
      numero,
      mission: { intitule: m.intitule, debut_le: m.debut_le, fin_le: m.fin_le, duree_heures: dureeHeures(m.id),
        taux_horaire_base: TAUX_FICTIF },
      etablissement,
      prepareLe: renduLe,
      soignant: { prenom: s.prenom, nom: s.nom },
    });
    return {
      ligne: {
        id, mission_id: m.id, soignant_id: s.id, etablissement_id: etablissement.id,
        numero_contrat: numero, type_contrat: 'CDD', statut, mode_signature: 'JOLENE_OTP',
        contenu_html: original.html, hash_document: original.empreinte,
        storage_path: `${id}/original-m${rang}.html`, contenu_html_rendu_le: renduLe,
        signature_soignant: signeSoignantLe != null, signature_soignant_le: signeSoignantLe,
        signature_etablissement: signeEtabLe != null, signature_etablissement_le: signeEtabLe,
        cree_le: creeLe,
      },
      mission: { id: m.id, intitule: m.intitule, service: m.service, debut_le: m.debut_le, fin_le: m.fin_le },
      original,
      fichier: `${id}.html`,
      soignantId: s.id,
    };
  };

  const creeLe04 = iso(now.getTime() - 120 * HEURE);
  const signeEtab04 = iso(now.getTime() - 119 * HEURE);
  const signeSoignant04 = iso(now.getTime() - 118 * HEURE);
  const aSigner = contrat({ rang: '05', numero: 'DEMO-E-0005', statut: 'EN_ATTENTE_SIGNATURES', creeLe: iso(now.getTime() - 8 * HEURE) });
  const signe = contrat({ rang: '04', numero: 'DEMO-E-0004', statut: 'SIGNE_COMPLET', creeLe: creeLe04,
    signeEtabLe: signeEtab04, signeSoignantLe: signeSoignant04 });
  const contrats = [aSigner, signe];

  const signature = (id, role, userId, signeA) => ({
    id, contrat_id: signe.ligne.id, signataire_user_id: userId, signataire_role: role, signe_a: signeA,
    ip_signature: null, user_agent: null, hash_document: signe.original.empreinte, otp_valide_a: signeA,
    psc_session_active: false, rpps_verifie: false, traits_identite_verifies: false, statut_signature: 'signe', cree_le: signeA,
  });

  return {
    json: {
      fixed_now: now.toISOString(),
      contrats: contrats.map(c => c.ligne),
      missions: contrats.map(c => c.mission),
      originaux: contrats.map(c => ({ contrat_id: c.ligne.id, storage_path: c.ligne.storage_path, fichier: c.fichier })),
      signatures: [
        signature('demo-etab-signature-m04-etab', 'etablissement', utilisateurEtablissement, signeEtab04),
        signature('demo-etab-signature-m04-soignant', 'soignant', signe.soignantId, signeSoignant04),
      ],
    },
    fichiers: Object.fromEntries(contrats.map(c => [c.fichier, c.original.html])),
  };
}
