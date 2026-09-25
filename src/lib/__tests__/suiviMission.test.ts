import { describe, expect, it } from 'vitest';
import { construireSuiviMission, type LecturesSuivi, type MissionSuivie } from '../suiviMission';

const mission: MissionSuivie = { id: 'mission', etablissement_id: 'etab', soignant_assigne_id: 'soignant', statut: 'TERMINEE', type_contrat_applique: 'LIBERAL' };
function vide(): LecturesSuivi {
  return { contrat: { etat: 'disponible', lignes: [] }, presences: { etat: 'disponible', lignes: [] }, documents: { etat: 'disponible', lignes: [] }, paiements: { etat: 'disponible', lignes: [] } };
}
const presence = { pointage_arrivee_le: '2026-09-25T08:00:00Z', pointage_depart_le: '2026-09-25T16:00:00Z', valide_par_etablissement: true };
describe('suivi commun : seuls les états canoniques confirment une étape', () => {
  it('une mission terminée ne prouve ni signatures, heures, document ni règlement', () => {
    const etapes = construireSuiviMission(mission, vide());
    expect(etapes.filter(e => e.etat === 'confirme').map(e => e.id)).toEqual(['attribution', 'mission']);
  });
  it('une candidature envoyée ne vaut pas attribution', () => {
    const [etape] = construireSuiviMission({ ...mission, soignant_assigne_id: null, statut: 'OUVERTE' }, vide(), { candidatureEnvoyee: true });
    expect(etape).toMatchObject({ etat: 'en_cours', statut: 'Candidature envoyée' });
  });
  it.each([
    ['SIGNE_COMPLET', true, true, 'confirme'],
    ['SIGNE_COMPLET', true, false, 'a_verifier'],
    ['EN_ATTENTE_SIGNATURES', false, false, 'en_cours'],
    ['ANNULE', true, true, 'a_verifier'],
  ])('contrat %s, signatures %s/%s → %s', (statut, signature_soignant, signature_etablissement, attendu) => {
    const lectures = vide(); lectures.contrat = { etat: 'disponible', lignes: [{ id: 'c', statut: String(statut), signature_soignant: Boolean(signature_soignant), signature_etablissement: Boolean(signature_etablissement) }] };
    expect(construireSuiviMission(mission, lectures)[1].etat).toBe(attendu);
  });
  it('une présence incomplète ou non validée reste en attente', () => {
    for (const ligne of [{ ...presence, pointage_depart_le: null }, { ...presence, valide_par_etablissement: false }]) {
      const lectures = vide(); lectures.presences = { etat: 'disponible', lignes: [ligne] };
      expect(construireSuiviMission(mission, lectures)[3].etat).toBe('en_cours');
    }
  });
  it('un litige actif empêche de présenter les heures comme définitives', () => {
    const lectures = vide(); lectures.presences = { etat: 'disponible', lignes: [presence] };
    expect(construireSuiviMission(mission, lectures)[3].etat).toBe('confirme');
    expect(construireSuiviMission(mission, lectures, { litigeActif: true })[3].etat).toBe('a_verifier');
  });
  it.each(['BROUILLON', 'ERREUR_GENERATION', 'REMPLACEE', 'ANNULEE'])('une facture %s ne prouve pas un document actif', statut => {
    const lectures = vide(); lectures.documents = { etat: 'disponible', lignes: [{ type_document: 'FACTURE', statut }] };
    expect(construireSuiviMission(mission, lectures)[4].etat).toBe('a_verifier');
  });
  it('une facture payée ne prouve pas à elle seule la réception du règlement', () => {
    const lectures = vide(); lectures.documents = { etat: 'disponible', lignes: [{ type_document: 'FACTURE', statut: 'PAYEE' }] };
    const etapes = construireSuiviMission(mission, lectures);
    expect(etapes[4].etat).toBe('confirme'); expect(etapes[5].etat).toBe('inconnu');
  });
  it('un avoir ne devient pas une facture', () => {
    const lectures = vide(); lectures.documents = { etat: 'disponible', lignes: [{ type_document: 'AVOIR', statut: 'EMISE' }] };
    expect(construireSuiviMission(mission, lectures)[4].etat).toBe('a_verifier');
  });
  it('le régime absent ne devient pas salarié ou libéral', () => {
    const etape = construireSuiviMission({ ...mission, type_contrat_applique: null }, vide())[4];
    expect(etape).toMatchObject({ titre: 'Document financier', statut: 'Régime à confirmer', etat: 'inconnu' });
  });
  it('un bulletin requiert un PDF et un statut canonique émis ou payé', () => {
    for (const [statut, pdf_s3_key, etat] of [['EMIS', 'bulletin.pdf', 'confirme'], ['EMIS', null, 'a_verifier'], ['INCONNU', 'bulletin.pdf', 'a_verifier']]) {
      const lectures = vide(); lectures.documents = { etat: 'disponible', lignes: [{ statut, pdf_s3_key }] };
      expect(construireSuiviMission({ ...mission, type_contrat_applique: 'SALARIE' }, lectures)[4]).toMatchObject({ titre: 'Bulletin de paie', etat });
    }
  });
  it.each([
    ['DECLARE', false, false, 'en_cours'], ['CONFIRME', false, false, 'a_verifier'],
    ['CONFIRME', true, false, 'confirme'], ['CONFIRME', true, true, 'a_verifier'],
    ['CONTESTE', true, false, 'a_verifier'], ['RESOLU', false, false, 'a_verifier'],
  ])('règlement %s, réception %s, contestation %s → %s', (statut, confirme_par_soignant, conteste, etat) => {
    const lectures = vide(); lectures.paiements = { etat: 'disponible', lignes: [{ statut: String(statut), confirme_par_soignant: Boolean(confirme_par_soignant), conteste: Boolean(conteste) }] };
    expect(construireSuiviMission(mission, lectures)[5].etat).toBe(etat);
  });
  it('une panne et un accès limité ne deviennent pas des collections vides réussies', () => {
    const lectures = vide(); lectures.documents = { etat: 'indisponible' }; lectures.paiements = { etat: 'restreint' };
    const etapes = construireSuiviMission(mission, lectures);
    expect(etapes[4].statut).toBe('Information indisponible'); expect(etapes[5].statut).toBe('Accès limité');
  });
  it('l’annulation reste visible et ne valide pas l’exécution', () => {
    const etapes = construireSuiviMission({ ...mission, statut: 'ANNULEE_PAR_ETABLISSEMENT' }, vide());
    expect(etapes[2]).toMatchObject({ etat: 'a_verifier', statut: 'Annulée' });
  });
});
