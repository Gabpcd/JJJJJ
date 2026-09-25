/** Synthèse en lecture seule : aucun état ultérieur ne prouve une étape antérieure. */
export type LectureSuivi<T> =
  | { etat: 'disponible'; lignes: T[] }
  | { etat: 'chargement' | 'indisponible' | 'restreint' | 'non_concerne' };

export interface MissionSuivie {
  id: string;
  etablissement_id: string;
  soignant_assigne_id: string | null;
  statut: string;
  type_contrat_applique?: string | null;
}
export interface ContratSuivi {
  id: string;
  statut: string;
  signature_soignant: boolean | null;
  signature_etablissement: boolean | null;
}
export interface PresenceSuivie {
  pointage_arrivee_le: string | null;
  pointage_depart_le: string | null;
  valide_par_etablissement: boolean | null;
}
export interface DocumentSuivi {
  statut: string | null;
  type_document?: string | null;
  pdf_s3_key?: string | null;
}
export interface PaiementSuivi {
  statut: string;
  confirme_par_soignant: boolean | null;
  conteste: boolean | null;
}
export interface LecturesSuivi {
  contrat: LectureSuivi<ContratSuivi>;
  presences: LectureSuivi<PresenceSuivie>;
  documents: LectureSuivi<DocumentSuivi>;
  paiements: LectureSuivi<PaiementSuivi>;
}
export interface EtapeSuivi {
  id: 'attribution' | 'contrat' | 'mission' | 'heures' | 'document' | 'reglement';
  titre: string;
  etat: 'confirme' | 'en_cours' | 'a_verifier' | 'inconnu';
  statut: string;
  detail: string;
}

function lectureManquante<T>(lecture: LectureSuivi<T>): Pick<EtapeSuivi, 'etat' | 'statut' | 'detail'> | null {
  switch (lecture.etat) {
    case 'chargement': return { etat: 'inconnu', statut: 'Vérification en cours', detail: 'Chargement des informations de cette étape.' };
    case 'indisponible': return { etat: 'inconnu', statut: 'Information indisponible', detail: 'La lecture a échoué. Actualisez le suivi pour réessayer.' };
    case 'restreint': return { etat: 'inconnu', statut: 'Accès limité', detail: 'Votre accès à cette mission ne permet pas de consulter cette information.' };
    case 'non_concerne': return { etat: 'inconnu', statut: 'À confirmer', detail: 'Cette information sera disponible après l’attribution de la mission.' };
    default: return null;
  }
}

export function construireSuiviMission(
  mission: MissionSuivie,
  lectures: LecturesSuivi,
  { candidatureEnvoyee = false, litigeActif = false }: { candidatureEnvoyee?: boolean; litigeActif?: boolean } = {},
): EtapeSuivi[] {
  const annulee = mission.statut.startsWith('ANNULEE');
  const attribution: EtapeSuivi = {
    id: 'attribution', titre: 'Attribution',
    ...(mission.soignant_assigne_id
      ? { etat: 'confirme' as const, statut: 'Soignant attribué', detail: 'Un soignant est affecté à cette mission.' }
      : candidatureEnvoyee
        ? { etat: 'en_cours' as const, statut: 'Candidature envoyée', detail: 'Votre candidature est enregistrée. L’attribution est suivie séparément.' }
        : { etat: 'en_cours' as const, statut: annulee ? 'Mission annulée' : 'En attente d’attribution', detail: 'Aucun soignant n’est actuellement affecté à cette mission.' }),
  };

  const contrat: EtapeSuivi = { id: 'contrat', titre: 'Contrat Jolene',
    etat: 'inconnu', statut: 'Aucun contrat disponible', detail: 'Les signatures ne sont pas encore confirmées.' };
  const manqueContrat = lectureManquante(lectures.contrat);
  if (manqueContrat) Object.assign(contrat, manqueContrat);
  else if (lectures.contrat.etat === 'disponible' && lectures.contrat.lignes[0]) {
    const ligne = lectures.contrat.lignes[0];
    if (ligne.statut === 'SIGNE_COMPLET' && ligne.signature_soignant === true && ligne.signature_etablissement === true) {
      Object.assign(contrat, { etat: 'confirme', statut: 'Deux signatures enregistrées', detail: 'Le soignant et l’établissement ont signé le contrat Jolene.' });
    } else if (['BROUILLON', 'EN_ATTENTE_SIGNATURES', 'SIGNE_SOIGNANT', 'SIGNE_ETABLISSEMENT'].includes(ligne.statut)) {
      Object.assign(contrat, { etat: 'en_cours', statut: 'Signatures à compléter',
        detail: ligne.signature_soignant ? 'Signature de l’établissement attendue.' : ligne.signature_etablissement ? 'Signature du soignant attendue.' : 'Les deux signatures restent à enregistrer.' });
    } else Object.assign(contrat, { etat: 'a_verifier', statut: 'Signature à vérifier', detail: 'Consultez le contrat pour connaître son état actuel.' });
  }
  if (mission.type_contrat_applique === 'SALARIE') contrat.detail += ' Le contrat de travail de l’employeur se consulte séparément dans les documents de la mission.';

  const execution: EtapeSuivi = { id: 'mission', titre: 'Mission', etat: 'inconnu', statut: 'État à confirmer', detail: 'Le statut de la mission n’est pas reconnu.' };
  if (annulee) Object.assign(execution, { etat: 'a_verifier', statut: 'Annulée', detail: 'La mission est annulée. Les documents déjà enregistrés restent consultables.' });
  else if (mission.statut === 'TERMINEE') Object.assign(execution, { etat: 'confirme', statut: 'Terminée', detail: 'La mission est clôturée. La validation des heures est suivie séparément.' });
  else if (mission.statut === 'EN_COURS') Object.assign(execution, { etat: 'en_cours', statut: 'En cours', detail: 'La mission a commencé.' });
  else if (['OUVERTE', 'ASSIGNEE'].includes(mission.statut)) Object.assign(execution, { etat: 'en_cours', statut: 'À venir', detail: 'La mission n’est pas encore déclarée en cours.' });

  const heures: EtapeSuivi = { id: 'heures', titre: 'Heures', etat: 'inconnu', statut: 'Aucune présence disponible', detail: 'Aucune validation d’heures ne peut encore être confirmée.' };
  const manqueHeures = lectureManquante(lectures.presences);
  if (manqueHeures) Object.assign(heures, manqueHeures);
  else if (lectures.presences.etat === 'disponible' && lectures.presences.lignes.length) {
    const fermees = lectures.presences.lignes.every(p => p.pointage_arrivee_le && p.pointage_depart_le);
    const validees = fermees && lectures.presences.lignes.every(p => p.valide_par_etablissement === true);
    Object.assign(heures, validees
      ? { etat: 'confirme', statut: 'Présences enregistrées validées', detail: 'Toutes les présences consultées ont leurs pointages et une validation.' }
      : { etat: 'en_cours', statut: fermees ? 'Validation attendue' : 'Pointages à compléter', detail: 'Consultez les présences pour vérifier les heures et les pauses.' });
    if (litigeActif) Object.assign(heures, { etat: 'a_verifier', statut: 'À vérifier — litige en cours', detail: 'Consultez le litige et les présences avant de considérer les heures comme définitives.' });
  }

  const regime = mission.type_contrat_applique;
  const document: EtapeSuivi = { id: 'document', titre: regime === 'SALARIE' ? 'Bulletin de paie' : regime === 'LIBERAL' ? 'Facture d’honoraires' : 'Document financier',
    etat: 'inconnu', statut: 'Aucun document disponible', detail: 'L’émission d’un document financier n’est pas encore confirmée.' };
  const manqueDocument = lectureManquante(lectures.documents);
  if (manqueDocument) Object.assign(document, manqueDocument);
  if (regime !== 'SALARIE' && regime !== 'LIBERAL') Object.assign(document, { etat: 'inconnu', statut: 'Régime à confirmer', detail: 'Le régime appliqué à cette mission n’est pas encore enregistré.' });
  else if (lectures.documents.etat === 'disponible') {
    const lignes = lectures.documents.lignes;
    const emis = lignes.some(d => regime === 'SALARIE'
      ? Boolean(d.pdf_s3_key) && ['EMIS', 'PAYE'].includes(d.statut ?? '')
      : d.type_document === 'FACTURE' && ['EMISE', 'EN_ATTENTE_PAIEMENT', 'EN_RETARD', 'PAYEE', 'FACTORISEE'].includes(d.statut ?? ''));
    if (emis) Object.assign(document, { etat: 'confirme', statut: 'Document disponible', detail: regime === 'SALARIE' ? 'Un bulletin avec son PDF est enregistré pour cette mission.' : 'Une facture d’honoraires émise est enregistrée pour cette mission.' });
    else if (lignes.length) Object.assign(document, { etat: 'a_verifier', statut: 'Document à vérifier', detail: 'Les documents enregistrés ne permettent pas de confirmer une pièce définitive active.' });
  }

  const reglement: EtapeSuivi = { id: 'reglement', titre: 'Règlement', etat: 'inconnu', statut: 'Règlement non confirmé', detail: 'Aucune confirmation de règlement n’est disponible ici. Consultez les finances pour le détail des versements.' };
  const manquePaiement = lectureManquante(lectures.paiements);
  if (manquePaiement) Object.assign(reglement, manquePaiement);
  else if (lectures.paiements.etat === 'disponible') {
    const lignes = lectures.paiements.lignes;
    if (lignes.some(p => p.conteste === true || p.statut === 'CONTESTE')) Object.assign(reglement, { etat: 'a_verifier', statut: 'Règlement contesté', detail: 'Une contestation est enregistrée. Consultez les finances et le litige.' });
    else if (lignes.some(p => p.statut === 'DECLARE')) Object.assign(reglement, { etat: 'en_cours', statut: 'Déclaré, à confirmer', detail: 'Un règlement a été déclaré. Sa réception doit encore être confirmée par le soignant.' });
    else if (lignes.length && lignes.every(p => p.statut === 'CONFIRME' && p.confirme_par_soignant === true)) Object.assign(reglement, { etat: 'confirme', statut: 'Réception enregistrée', detail: 'Le soignant a confirmé les règlements affichés dans les finances. Ce suivi ne calcule pas le solde restant.' });
    else if (lignes.length) Object.assign(reglement, { etat: 'a_verifier', statut: 'Confirmation à vérifier', detail: 'La résolution d’un litige ou un statut seul ne confirme pas la réception du règlement.' });
  }
  return [attribution, contrat, execution, heures, document, reglement];
}
