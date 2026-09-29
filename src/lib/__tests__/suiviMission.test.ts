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
    expect(construireSuiviMission(mission, lectures).find(e => e.id === 'contrat')!.etat).toBe(attendu);
  });
  it('une présence incomplète ou non validée reste en attente', () => {
    for (const ligne of [{ ...presence, pointage_depart_le: null }, { ...presence, valide_par_etablissement: false }]) {
      const lectures = vide(); lectures.presences = { etat: 'disponible', lignes: [ligne] };
      expect(construireSuiviMission(mission, lectures).find(e => e.id === 'heures')!.etat).toBe('en_cours');
    }
  });
  it('un litige actif empêche de présenter les heures comme définitives', () => {
    const lectures = vide(); lectures.presences = { etat: 'disponible', lignes: [presence] };
    expect(construireSuiviMission(mission, lectures).find(e => e.id === 'heures')!.etat).toBe('confirme');
    expect(construireSuiviMission(mission, lectures, { litigeActif: true }).find(e => e.id === 'heures')!.etat).toBe('a_verifier');
  });
  it.each(['BROUILLON', 'ERREUR_GENERATION', 'REMPLACEE', 'ANNULEE'])('une facture %s ne prouve pas un document actif', statut => {
    const lectures = vide(); lectures.documents = { etat: 'disponible', lignes: [{ type_document: 'FACTURE', statut }] };
    expect(construireSuiviMission(mission, lectures).find(e => e.id === 'document')!.etat).toBe('a_verifier');
  });
  it('une facture payée ne prouve pas à elle seule la réception du règlement', () => {
    const lectures = vide(); lectures.documents = { etat: 'disponible', lignes: [{ type_document: 'FACTURE', statut: 'PAYEE' }] };
    const etapes = construireSuiviMission(mission, lectures);
    expect(etapes.find(e => e.id === 'document')!.etat).toBe('confirme'); expect(etapes.find(e => e.id === 'reglement')!.etat).toBe('inconnu');
  });
  it('un avoir ne devient pas une facture', () => {
    const lectures = vide(); lectures.documents = { etat: 'disponible', lignes: [{ type_document: 'AVOIR', statut: 'EMISE' }] };
    expect(construireSuiviMission(mission, lectures).find(e => e.id === 'document')!.etat).toBe('a_verifier');
  });
  it('le régime absent ne devient pas salarié ou libéral', () => {
    const etape = construireSuiviMission({ ...mission, type_contrat_applique: null }, vide()).find(e => e.id === 'document')!;
    expect(etape).toMatchObject({ titre: 'Document financier', statut: 'Régime à confirmer', etat: 'inconnu' });
  });
  it('un PDF de simulation ne prouve jamais une copie officielle, même marqué payé', () => {
    for (const [statut, pdf_s3_key] of [['EMIS', 'bulletin.pdf'], ['PAYE', 'bulletin.pdf'], ['EMIS', null]]) {
      const lectures = vide(); lectures.documents = { etat: 'disponible', lignes: [{ statut, pdf_s3_key }] };
      expect(construireSuiviMission({ ...mission, type_contrat_applique: 'SALARIE' }, lectures).find(e => e.id === 'document')!).toMatchObject({ titre: 'Copie du bulletin officiel', etat: 'a_verifier' });
    }
  });
  it('seule une copie officielle publiée confirme le document, jamais le règlement', () => {
    for (const statut of ['PUBLIEE', 'REMPLACEE', 'RETIREE']) {
      const lectures = vide(); lectures.documents = { etat: 'disponible', lignes: [{ statut, type_document: 'COPIE_BULLETIN_OFFICIEL' }] };
      const etapes = construireSuiviMission({ ...mission, type_contrat_applique: 'SALARIE' }, lectures);
      expect(etapes.find(e => e.id === 'document')!.etat).toBe(statut === 'PUBLIEE' ? 'confirme' : 'a_verifier');
      expect(etapes.find(e => e.id === 'reglement')!.etat).toBe('inconnu');
    }
  });
  it.each([
    ['DECLARE', false, false, 'en_cours'], ['CONFIRME', false, false, 'a_verifier'],
    ['CONFIRME', true, false, 'confirme'], ['CONFIRME', true, true, 'a_verifier'],
    ['CONTESTE', true, false, 'a_verifier'], ['RESOLU', false, false, 'a_verifier'],
  ])('règlement %s, réception %s, contestation %s → %s', (statut, confirme_par_soignant, conteste, etat) => {
    const lectures = vide(); lectures.paiements = { etat: 'disponible', lignes: [{ statut: String(statut), confirme_par_soignant: Boolean(confirme_par_soignant), conteste: Boolean(conteste) }] };
    expect(construireSuiviMission(mission, lectures).find(e => e.id === 'reglement')!.etat).toBe(etat);
  });
  it('une panne et un accès limité ne deviennent pas des collections vides réussies', () => {
    const lectures = vide(); lectures.documents = { etat: 'indisponible' }; lectures.paiements = { etat: 'restreint' };
    const etapes = construireSuiviMission(mission, lectures);
    expect(etapes.find(e => e.id === 'document')!.statut).toBe('Information indisponible'); expect(etapes.find(e => e.id === 'reglement')!.statut).toBe('Accès limité');
  });
  it('des pointages complets ne valent pas validation, et le litige n’efface pas leur existence', () => {
    const lectures = vide(); lectures.presences = { etat: 'disponible', lignes: [{ ...presence, valide_par_etablissement: false }] };
    const etapes = construireSuiviMission(mission, lectures);
    expect(etapes.find(e => e.id === 'presence')).toMatchObject({ etat: 'confirme', statut: 'Pointages enregistrés' });
    expect(etapes.find(e => e.id === 'heures')).toMatchObject({ etat: 'en_cours', statut: 'Validation attendue' });
    const contestees = construireSuiviMission(mission, lectures, { litigeActif: true });
    expect(contestees.find(e => e.id === 'presence')?.etat).toBe('confirme');
    expect(contestees.find(e => e.id === 'heures')?.etat).toBe('a_verifier');
  });
  it('une validation déclarée avec un départ manquant ne confirme ni présence complète ni heures', () => {
    const lectures = vide(); lectures.presences = { etat: 'disponible', lignes: [{ ...presence, pointage_depart_le: null }] };
    const etapes = construireSuiviMission(mission, lectures);
    expect(etapes.find(e => e.id === 'presence')).toMatchObject({ etat: 'en_cours', statut: 'Pointages à compléter' });
    expect(etapes.find(e => e.id === 'heures')).toMatchObject({ etat: 'en_cours', statut: 'Pointages attendus' });
  });
  it('un planning exact prouve les créneaux prévus, jamais la présence ou la conformité globale', () => {
    const lectures = vide(); lectures.contrat = { etat: 'disponible', lignes: [{ id: 'c', statut: 'SIGNE_COMPLET', signature_soignant: true, signature_etablissement: true }] };
    const etapes = construireSuiviMission(mission, lectures, { planning: { etat: 'exact', nombreCreneaux: 3 } });
    expect(etapes.find(e => e.id === 'planning')).toMatchObject({ etat: 'confirme', statut: 'Créneaux prévus disponibles' });
    expect(etapes.find(e => e.id === 'planning')?.detail).toContain('3 créneaux prévus');
    expect(etapes.find(e => e.id === 'presence')?.etat).toBe('inconnu');
    expect(etapes.find(e => e.id === 'conformite')).toMatchObject({ etat: 'inconnu', statut: 'Contrôles à consulter' });
  });
  it.each([
    [{ etat: 'chargement' as const }, 'Chargement du planning', 'inconnu'],
    [{ etat: 'indisponible' as const }, 'Planning indisponible', 'inconnu'],
    [{ etat: 'incomplet' as const }, 'Planning à compléter', 'a_verifier'],
    [{ etat: 'exact' as const, nombreCreneaux: 0 }, 'Planning à confirmer', 'inconnu'],
  ])('un planning absent, en panne ou incomplet ne devient pas validé (%j)', (planning, statut, etat) => {
    expect(construireSuiviMission(mission, vide(), { planning }).find(e => e.id === 'planning')).toMatchObject({ statut, etat });
  });
  it('l’annulation reste visible et ne valide pas l’exécution', () => {
    const etapes = construireSuiviMission({ ...mission, statut: 'ANNULEE_PAR_ETABLISSEMENT' }, vide());
    expect(etapes.find(e => e.id === 'mission')!).toMatchObject({ etat: 'a_verifier', statut: 'Annulée' });
  });
  it.each([['LITIGE', 'Mission marquée en litige'], ['EXPIREE', 'Expirée'], ['ABSENCE', 'Absence signalée']])('reconnaît le statut opérationnel %s sans inventer une mission terminée', (statut, libelle) => {
    expect(construireSuiviMission({ ...mission, statut }, vide()).find(e => e.id === 'mission')).toMatchObject({ etat: 'a_verifier', statut: libelle });
  });
  it('un remboursement sécurisé prime sur un ancien règlement déclaré sans inventer un versement au soignant', () => {
    const lectures = vide();
    lectures.paiements = { etat: 'disponible', lignes: [{ statut: 'CONFIRME', confirme_par_soignant: true, conteste: false }] };
    lectures.escrow = { etat: 'disponible', lignes: [{ statut: 'REMBOURSE', paye_le: null }] };
    const etape = construireSuiviMission(mission, lectures).find(e => e.id === 'reglement')!;
    expect(etape).toMatchObject({ etat: 'confirme', statut: 'Remboursement confirmé' });
    expect(etape.detail).toContain('n’est pas un versement au soignant');
    lectures.escrow.lignes[0].paye_le = '2026-09-25T08:00:00Z';
    expect(construireSuiviMission(mission, lectures).find(e => e.id === 'reglement')).toMatchObject({ etat: 'a_verifier', statut: 'Remboursement après versement' });
  });
  it.each([
    ['DEBITE', 'Fonds prélevés', 'en_cours'],
    ['REMBOURSE_EN_COURS', 'Remboursement en cours', 'en_cours'],
    ['PAYE', 'Versement confirmé par le prestataire', 'confirme'],
    ['DISPUTE', 'Paiement sécurisé en litige', 'a_verifier'],
    ['STATUT_INCONNU', 'État du paiement sécurisé à vérifier', 'a_verifier'],
  ])('distingue %s d’une réception déclarée par le soignant', (statutSource, statut, etat) => {
    const lectures = vide(); lectures.escrow = { etat: 'disponible', lignes: [{ statut: statutSource, paye_le: null }] };
    expect(construireSuiviMission(mission, lectures).find(e => e.id === 'reglement')).toMatchObject({ statut, etat });
  });
  it('une lecture escrow en panne ne devient pas un remboursement confirmé et ne modifie pas le circuit salarié', () => {
    const lectures = vide(); lectures.escrow = { etat: 'indisponible' };
    expect(construireSuiviMission(mission, lectures).find(e => e.id === 'reglement')?.statut).toBe('Information indisponible');
    expect(construireSuiviMission({ ...mission, type_contrat_applique: 'SALARIE' }, lectures).find(e => e.id === 'reglement')?.statut).toBe('Règlement non confirmé');
  });
});
