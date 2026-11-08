import Foundation

// Ports backend du lot 2 (blueprint `docs/mobile-swift/LOT2_PLAN.md` §2.3, tranche T1). Tous `Sendable`
// (concurrence stricte), bornés par l'appelant (`bounded(timeout: SessionController.resolutionTimeout)`).
// Chaque méthode reçoit le `MissionReadContext` de l'epoch courant : la gateway vérifie la cohérence session
// ↔ profil et le monde démo refuse tout autre utilisateur (`.demoOnly`). Une mutation n'annonce un succès
// qu'après relecture serveur (PRINCIPES §3) ; refus métier = issues de `Models/Lot2Results.swift`, erreurs
// de transport = `JoleneError`. Aucune file, aucun renvoi automatique (décision 2, PRINCIPES §4).

// MARK: - Contrats

/// Présences et pointage rotatif (`fn_scanner_code_pointage`, `fn_etat_pointage_mission`, `scans_pointage`,
/// `fn_consentir_gps`, `fn_presences_detail_mission`, `fn_relancer_validation_presence`) — tranche T3.
/// Le système de pointage ① n'est jamais appelé (décision 1).
public protocol PointagePort: Sendable {
    func presences(context: MissionReadContext) async throws -> InstantanePresences
    func etat(missionId: String, context: MissionReadContext) async throws -> EtatPointage
    /// `soignants.consentement_gps` : nil tant que le soignant n'a pas répondu.
    func consentementGps(context: MissionReadContext) async throws -> Bool?
    /// `fn_consentir_gps(p_accepte)` puis relecture : rend la valeur relue, jamais une hypothèse locale.
    func enregistrerConsentementGps(_ accepte: Bool, context: MissionReadContext) async throws -> Bool
    /// Une seule requête `fn_scanner_code_pointage` ; `recu` est en phase `started` et déjà journalisé.
    /// Succès annoncé seulement après relecture de l'état et de `scans_pointage` (preuve hors baseline).
    func scanner(code: String, metadonnees: MetadonneesScan, recu: RecuScan, context: MissionReadContext) async throws -> IssueScan
    /// Relecture de `scans_pointage` pour un reçu `started` (`RecuScan.reconcilier(scans:relueLe:)`), verdict
    /// traduit par `IssueScan(reconciliation:)` : `.enregistre`, `.incertain` (relire), `.nonRecu`, `.horlogeIncoherente`.
    func reconcilier(recu: RecuScan, context: MissionReadContext) async throws -> IssueScan
    func detail(missionId: String, context: MissionReadContext) async throws -> DetailPresences
    func relancerValidation(missionId: String, context: MissionReadContext) async throws -> IssueRelance
}

/// Litige depuis une présence (`litiges`, `fn_fenetre_contestation_ouverte`, `fn_ouvrir_litige_rate_limited`
/// par trois clés exactes) — tranche T5b (HARD STOP, décision 9 : aucun texte de délai).
public protocol ContestationPort: Sendable {
    func litige(presenceId: String, context: MissionReadContext) async throws -> LitigePresence?
    /// Fenêtre décidée par le serveur (`'DESACCORD_HEURES_POINTAGE'`) ; erreur → bouton masqué (fail-closed).
    func fenetreOuverte(missionId: String, context: MissionReadContext) async throws -> Bool
    func contester(missionId: String, presenceId: String, motif: String, context: MissionReadContext) async throws -> IssueContestation
}

/// Notation rapide (`fn_creer_notation_mission`, écriture seule) — tranche T5a. `criteres` nil : note
/// globale répliquée sur les quatre critères (`CriteresNotation.repliques(note:)`).
public protocol NotationPort: Sendable {
    func noter(missionId: String, note: Int, criteres: CriteresNotation?, context: MissionReadContext) async throws -> IssueNotation
}

/// Justificatifs (`documents_requis_par_profession`, `documents_soignants`, bucket `jolene-documents`,
/// `fn_remplacer_document_soignant`, edge `verify-document`, `fn_demander_revue_document`,
/// `fn_signer_attestation_sante`, `fn_verifier_coherence_documents`) — tranche T6.
public protocol DocumentsPort: Sendable {
    func dossier(context: MissionReadContext) async throws -> DossierDocuments
    /// Reçu `prepared` à la clé déterministe, à journaliser AVANT l'envoi (`RecuDocument.preparer`).
    func preparerEnvoi(type: String, fichier: FichierChoisi, libelle: String?, context: MissionReadContext) async throws -> RecuDocument
    /// Upload (`upsert: false`), enregistrement idempotent, `verify-document` une seule fois. Les octets ne
    /// sont jamais conservés.
    func envoyer(recu: RecuDocument, octets: Data, context: MissionReadContext) async throws -> IssueEnvoiDocument
    /// Relecture par `s3_cle` (ligne, puis objet Storage) ; seule `fn_remplacer_document_soignant` peut être
    /// rejouée, après preuve de l'absence de ligne (décision 14).
    func reconcilier(recu: RecuDocument, context: MissionReadContext) async throws -> IssueEnvoiDocument
    /// Revérification demandée par l'utilisateur, jamais automatique.
    func reverifier(documentId: String, context: MissionReadContext) async throws -> VerdictDocument
    func demanderRevue(documentId: String, context: MissionReadContext) async throws
    /// Fichier temporaire protégé (`NSFileProtectionComplete`, exclu de la sauvegarde) ; jamais l'URL signée.
    func consulter(document: DocumentSoignant, context: MissionReadContext) async throws -> URL
    /// `fn_signer_attestation_sante()` puis relecture de `soignants.attestation_sante_signee_le`.
    func signerAttestationSante(context: MissionReadContext) async throws -> Date
    /// Lecture best-effort : nil sans bannière (le web avale l'erreur).
    func coherence(context: MissionReadContext) async throws -> CoherenceDocuments?
}

/// Contrats signés par OTP SMS (`contrats_mission`, bucket `contrats-signes`, edge
/// `generate-contrat-mission-pdf`, `fn_envoyer_otp_signature`, `fn_signer_contrat_otp`,
/// `signatures_contrats`, `fn_admission_otp_signature_recette` sur STAGING seulement) — tranche T8.
public protocol ContratsPort: Sendable {
    func contrats(context: MissionReadContext) async throws -> [ContratResume]
    func contrat(id: String, context: MissionReadContext) async throws -> ContratDetail
    /// Triple contrôle de l'empreinte (§2.5) ; sinon refus, jamais un original supposé.
    func original(contrat: ContratDetail, context: MissionReadContext) async throws -> OriginalContrat
    /// Admission de recette (STAGING et URL `mejpriaetwgtcstbgfid` seulement ; `AdmissionRecette`, T2) ;
    /// nil partout ailleurs, jamais une erreur de contrat.
    func admissionRecette(contratId: String, context: MissionReadContext) async throws -> AdmissionSignatureRecette?
    func envoyerOtp(contratId: String, empreinte: String, context: MissionReadContext) async throws -> IssueEnvoiOtp
    /// `fn_signer_contrat_otp(p_contrat_id, p_otp_code, p_hash_document, p_signature_image: null)` puis relecture.
    func signer(contratId: String, code: String, empreinte: String, context: MissionReadContext) async throws -> IssueSignature
    /// Projection `SignatureCertificat.colonnes`, jamais `select=*` (correction 22).
    func certificat(contratId: String, context: MissionReadContext) async throws -> [SignatureCertificat]
    /// Fichier HTML original contrôlé, à partager ou imprimer (dossier temporaire protégé).
    func fichierOriginal(contrat: OriginalContrat, context: MissionReadContext) async throws -> URL
}

// MARK: - Ports « non câblés »

// Même règle que le lot 1 (`Lot1Ports.swift`) : un stub ne rend jamais un état vide plausible, il lève
// `.contract` en citant la tranche ET le lot 2 (`UnwiredPorts.erreur(port:tranche:lot:)`, surcharge
// partagée avec le lot 3).

public struct UnwiredPointagePort: PointagePort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { UnwiredPorts.erreur(port: "pointage", tranche: "T3", lot: 2) }
    public func presences(context: MissionReadContext) async throws -> InstantanePresences { throw erreur }
    public func etat(missionId: String, context: MissionReadContext) async throws -> EtatPointage { throw erreur }
    public func consentementGps(context: MissionReadContext) async throws -> Bool? { throw erreur }
    public func enregistrerConsentementGps(_ accepte: Bool, context: MissionReadContext) async throws -> Bool { throw erreur }
    public func scanner(code: String, metadonnees: MetadonneesScan, recu: RecuScan,
                        context: MissionReadContext) async throws -> IssueScan { throw erreur }
    public func reconcilier(recu: RecuScan, context: MissionReadContext) async throws -> IssueScan { throw erreur }
    public func detail(missionId: String, context: MissionReadContext) async throws -> DetailPresences { throw erreur }
    public func relancerValidation(missionId: String, context: MissionReadContext) async throws -> IssueRelance { throw erreur }
}

public struct UnwiredContestationPort: ContestationPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { UnwiredPorts.erreur(port: "contestation", tranche: "T5b", lot: 2) }
    public func litige(presenceId: String, context: MissionReadContext) async throws -> LitigePresence? { throw erreur }
    public func fenetreOuverte(missionId: String, context: MissionReadContext) async throws -> Bool { throw erreur }
    public func contester(missionId: String, presenceId: String, motif: String,
                          context: MissionReadContext) async throws -> IssueContestation { throw erreur }
}

public struct UnwiredNotationPort: NotationPort, UnwiredPort {
    public init() {}
    public func noter(missionId: String, note: Int, criteres: CriteresNotation?,
                      context: MissionReadContext) async throws -> IssueNotation {
        throw UnwiredPorts.erreur(port: "notation", tranche: "T5a", lot: 2)
    }
}

public struct UnwiredDocumentsPort: DocumentsPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { UnwiredPorts.erreur(port: "documents", tranche: "T6", lot: 2) }
    public func dossier(context: MissionReadContext) async throws -> DossierDocuments { throw erreur }
    public func preparerEnvoi(type: String, fichier: FichierChoisi, libelle: String?,
                              context: MissionReadContext) async throws -> RecuDocument { throw erreur }
    public func envoyer(recu: RecuDocument, octets: Data, context: MissionReadContext) async throws -> IssueEnvoiDocument { throw erreur }
    public func reconcilier(recu: RecuDocument, context: MissionReadContext) async throws -> IssueEnvoiDocument { throw erreur }
    public func reverifier(documentId: String, context: MissionReadContext) async throws -> VerdictDocument { throw erreur }
    public func demanderRevue(documentId: String, context: MissionReadContext) async throws { throw erreur }
    public func consulter(document: DocumentSoignant, context: MissionReadContext) async throws -> URL { throw erreur }
    public func signerAttestationSante(context: MissionReadContext) async throws -> Date { throw erreur }
    public func coherence(context: MissionReadContext) async throws -> CoherenceDocuments? { throw erreur }
}

public struct UnwiredContratsPort: ContratsPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { UnwiredPorts.erreur(port: "contrats", tranche: "T8", lot: 2) }
    public func contrats(context: MissionReadContext) async throws -> [ContratResume] { throw erreur }
    public func contrat(id: String, context: MissionReadContext) async throws -> ContratDetail { throw erreur }
    public func original(contrat: ContratDetail, context: MissionReadContext) async throws -> OriginalContrat { throw erreur }
    public func admissionRecette(contratId: String, context: MissionReadContext) async throws -> AdmissionSignatureRecette? {
        throw erreur
    }
    public func envoyerOtp(contratId: String, empreinte: String, context: MissionReadContext) async throws -> IssueEnvoiOtp {
        throw erreur
    }
    public func signer(contratId: String, code: String, empreinte: String,
                       context: MissionReadContext) async throws -> IssueSignature { throw erreur }
    public func certificat(contratId: String, context: MissionReadContext) async throws -> [SignatureCertificat] { throw erreur }
    public func fichierOriginal(contrat: OriginalContrat, context: MissionReadContext) async throws -> URL { throw erreur }
}
