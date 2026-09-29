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
export interface EscrowSuivi {
  statut: string;
  paye_le: string | null;
}
export interface LecturesSuivi {
  contrat: LectureSuivi<ContratSuivi>;
  presences: LectureSuivi<PresenceSuivie>;
  documents: LectureSuivi<DocumentSuivi>;
  paiements: LectureSuivi<PaiementSuivi>;
  escrow?: LectureSuivi<EscrowSuivi>;
}
export type PlanningSuivi =
  | { etat: 'chargement' | 'indisponible' | 'incomplet' }
  | { etat: 'exact'; nombreCreneaux: number };
export interface EtapeSuivi {
  id: 'attribution' | 'conformite' | 'contrat' | 'planning' | 'mission' | 'presence' | 'heures' | 'document' | 'reglement';
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
  { candidatureEnvoyee = false, litigeActif = false, planning }: { candidatureEnvoyee?: boolean; litigeActif?: boolean; planning?: PlanningSuivi } = {},
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

  // Aucun verdict global de conformité n'est déduit d'une attribution, d'une
  // signature ou du seul contrôle des horaires. Les sources restent dans le dossier.
  const conformite: EtapeSuivi = { id: 'conformite', titre: 'Dossier et conformité',
    etat: 'inconnu', statut: 'Contrôles à consulter',
    detail: 'Consultez les pièces et les contrôles associés à cette mission dans le dossier du professionnel.' };
  const planification: EtapeSuivi = { id: 'planning', titre: 'Planification',
    etat: 'inconnu', statut: 'Planning à confirmer', detail: 'Consultez les dates et les créneaux prévus pour cette mission.' };
  if (planning?.etat === 'chargement') Object.assign(planification, { statut: 'Chargement du planning', detail: 'Les créneaux prévus sont en cours de lecture.' });
  else if (planning?.etat === 'indisponible') Object.assign(planification, { statut: 'Planning indisponible', detail: 'La lecture du planning a échoué. Actualisez le suivi pour réessayer.' });
  else if (planning?.etat === 'incomplet') Object.assign(planification, { etat: 'a_verifier', statut: 'Planning à compléter', detail: 'Les créneaux prévus ne permettent pas de confirmer le planning exact.' });
  else if (planning?.etat === 'exact' && Number.isInteger(planning.nombreCreneaux) && planning.nombreCreneaux > 0) Object.assign(planification, {
    etat: 'confirme', statut: 'Créneaux prévus disponibles',
    detail: `${planning.nombreCreneaux} créneau${planning.nombreCreneaux > 1 ? 'x' : ''} prévu${planning.nombreCreneaux > 1 ? 's' : ''}. Le planning ne prouve ni la présence ni la validation des heures.`,
  });

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
  else if (mission.statut === 'LITIGE') Object.assign(execution, { etat: 'a_verifier', statut: 'Mission marquée en litige', detail: 'Consultez le litige et sa décision. Le règlement est suivi séparément.' });
  else if (mission.statut === 'EXPIREE') Object.assign(execution, { etat: 'a_verifier', statut: 'Expirée', detail: 'La mission a expiré sans être déclarée terminée.' });
  else if (mission.statut === 'ABSENCE') Object.assign(execution, { etat: 'a_verifier', statut: 'Absence signalée', detail: 'Une absence est enregistrée sur cette mission. Consultez son détail.' });
  else if (mission.statut === 'TERMINEE') Object.assign(execution, { etat: 'confirme', statut: 'Terminée', detail: 'La mission est clôturée. La validation des heures est suivie séparément.' });
  else if (mission.statut === 'EN_COURS') Object.assign(execution, { etat: 'en_cours', statut: 'En cours', detail: 'La mission a commencé.' });
  else if (['OUVERTE', 'ASSIGNEE'].includes(mission.statut)) Object.assign(execution, { etat: 'en_cours', statut: 'À venir', detail: 'La mission n’est pas encore déclarée en cours.' });

  const presence: EtapeSuivi = { id: 'presence', titre: 'Présence', etat: 'inconnu', statut: 'Aucune présence disponible', detail: 'Aucun pointage ne peut encore être confirmé.' };
  const heures: EtapeSuivi = { id: 'heures', titre: 'Validation des heures', etat: 'inconnu', statut: 'Aucune validation disponible', detail: 'La présence et la validation des heures sont suivies séparément.' };
  const manqueHeures = lectureManquante(lectures.presences);
  if (manqueHeures) { Object.assign(presence, manqueHeures); Object.assign(heures, manqueHeures); }
  else if (lectures.presences.etat === 'disponible' && lectures.presences.lignes.length) {
    const fermees = lectures.presences.lignes.every(p => p.pointage_arrivee_le && p.pointage_depart_le);
    const validees = fermees && lectures.presences.lignes.every(p => p.valide_par_etablissement === true);
    Object.assign(presence, fermees
      ? { etat: 'confirme', statut: 'Pointages enregistrés', detail: 'Toutes les présences consultées ont une arrivée et un départ. Leur validation reste distincte.' }
      : { etat: 'en_cours', statut: 'Pointages à compléter', detail: 'Une arrivée ou un départ manque parmi les présences consultées.' });
    Object.assign(heures, validees
      ? { etat: 'confirme', statut: 'Présences enregistrées validées', detail: 'Toutes les présences consultées ont leurs pointages et une validation.' }
      : { etat: 'en_cours', statut: fermees ? 'Validation attendue' : 'Pointages attendus', detail: 'La validation reste à confirmer pour les présences consultées.' });
    if (litigeActif) Object.assign(heures, { etat: 'a_verifier', statut: 'À vérifier — litige en cours', detail: 'Consultez le litige et les présences avant de considérer les heures comme définitives.' });
  }

  const regime = mission.type_contrat_applique;
  const document: EtapeSuivi = { id: 'document', titre: regime === 'SALARIE' ? 'Copie du bulletin officiel' : regime === 'LIBERAL' ? 'Facture d’honoraires' : 'Document financier',
    etat: 'inconnu', statut: regime === 'SALARIE' ? 'Aucune copie disponible' : 'Aucun document disponible', detail: regime === 'SALARIE' ? 'Aucune copie officielle publiée n’est disponible pour cette mission. Une simulation ne constitue pas le bulletin de l’employeur.' : 'L’émission d’un document financier n’est pas encore confirmée.' };
  const manqueDocument = lectureManquante(lectures.documents);
  if (manqueDocument) Object.assign(document, manqueDocument);
  if (regime !== 'SALARIE' && regime !== 'LIBERAL') Object.assign(document, { etat: 'inconnu', statut: 'Régime à confirmer', detail: 'Le régime appliqué à cette mission n’est pas encore enregistré.' });
  else if (lectures.documents.etat === 'disponible') {
    const lignes = lectures.documents.lignes;
    const emis = lignes.some(d => regime === 'SALARIE'
      ? d.type_document === 'COPIE_BULLETIN_OFFICIEL' && d.statut === 'PUBLIEE'
      : d.type_document === 'FACTURE' && ['EMISE', 'EN_ATTENTE_PAIEMENT', 'EN_RETARD', 'PAYEE', 'FACTORISEE'].includes(d.statut ?? ''));
    if (emis) Object.assign(document, { etat: 'confirme', statut: regime === 'SALARIE' ? 'Copie disponible' : 'Document disponible', detail: regime === 'SALARIE' ? 'Une copie du bulletin officiel est publiée pour cette mission. Sa disponibilité ne confirme pas le paiement du salaire.' : 'Une facture d’honoraires émise est enregistrée pour cette mission.' });
    else if (lignes.length) Object.assign(document, { etat: 'a_verifier', statut: regime === 'SALARIE' ? 'Copie à vérifier' : 'Document à vérifier', detail: 'Les documents enregistrés ne permettent pas de confirmer une pièce définitive active.' });
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
  // Le circuit sécurisé ne crée pas nécessairement de paiement déclaré à la
  // main. Son état doit être lu directement, sans déduire un versement d'un
  // prélèvement ni une réception bancaire d'un remboursement.
  if (regime === 'LIBERAL' && lectures.escrow && lectures.escrow.etat !== 'non_concerne') {
    const manqueEscrow = lectureManquante(lectures.escrow);
    if (manqueEscrow) Object.assign(reglement, manqueEscrow);
    else if (lectures.escrow.etat === 'disponible' && lectures.escrow.lignes.length) {
      const [escrow] = lectures.escrow.lignes;
      const etats: Record<string, Pick<EtapeSuivi, 'etat' | 'statut' | 'detail'>> = {
        INITIE: { etat: 'en_cours', statut: 'Prélèvement en cours', detail: 'Le paiement sécurisé est engagé. Aucun versement au soignant n’est encore confirmé.' },
        DEBITE: { etat: 'en_cours', statut: 'Fonds prélevés', detail: 'Le prélèvement de l’établissement est confirmé. Le versement au soignant reste une étape distincte.' },
        DISPONIBLE: { etat: 'en_cours', statut: 'Fonds disponibles', detail: 'Les fonds du paiement sécurisé sont disponibles. Le versement au soignant reste à confirmer.' },
        RELEASE_PLANIFIE: { etat: 'en_cours', statut: 'Versement planifié', detail: 'Le versement au soignant est planifié, mais son exécution n’est pas encore confirmée.' },
        PAYE: { etat: 'confirme', statut: 'Versement confirmé par le prestataire', detail: 'Le prestataire confirme le versement. Ce statut ne constitue pas une confirmation de réception saisie par le soignant.' },
        ECHOUE: { etat: 'a_verifier', statut: 'Paiement sécurisé à vérifier', detail: 'Une erreur est enregistrée sur le paiement sécurisé. Consultez les finances pour connaître la suite.' },
        DISPUTE: { etat: 'a_verifier', statut: 'Paiement sécurisé en litige', detail: 'Le règlement est suspendu ou contesté. Consultez le litige avant de considérer le paiement comme définitif.' },
        REMBOURSE_EN_COURS: { etat: 'en_cours', statut: 'Remboursement en cours', detail: 'Le remboursement à l’établissement a été demandé. Sa réalisation reste à confirmer.' },
        REMBOURSE: escrow.paye_le
          ? { etat: 'a_verifier', statut: 'Remboursement après versement', detail: 'Un remboursement à l’établissement est enregistré après un versement au soignant. Consultez les finances pour les montants concernés.' }
          : { etat: 'confirme', statut: 'Remboursement confirmé', detail: 'Les fonds du paiement sécurisé ont été remboursés à l’établissement. Ce remboursement n’est pas un versement au soignant.' },
      };
      Object.assign(reglement, lectures.escrow.lignes.length === 1 && etats[escrow.statut]
        ? etats[escrow.statut]
        : { etat: 'a_verifier', statut: 'État du paiement sécurisé à vérifier', detail: 'Les informations disponibles ne permettent pas de confirmer le règlement. Consultez les finances.' });
    }
  }
  return [attribution, conformite, contrat, planification, execution, presence, heures, document, reglement];
}
