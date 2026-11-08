import Foundation
@testable import JoleneCore

/// Témoin des cinq ports du lot 2 : ni stub `Unwired*`, ni gateway réelle. Posé dans chaque champ du lot 2 avant
/// `câblerLot2`, il prouve que la fonction écrit chaque champ (revue fraîche de T1 : sans lui, le test resterait
/// vert avec un `câblerLot2` vide, les défauts de `Gateways` étant déjà des stubs). Ne répond jamais.
struct PortTemoinLot2: PointagePort, ContestationPort, NotationPort, DocumentsPort, ContratsPort {
    private var erreur: JoleneError { JoleneError(.contract, "témoin de test") }

    func presences(context: MissionReadContext) async throws -> InstantanePresences { throw erreur }
    func etat(missionId: String, context: MissionReadContext) async throws -> EtatPointage { throw erreur }
    func consentementGps(context: MissionReadContext) async throws -> Bool? { throw erreur }
    func enregistrerConsentementGps(_ accepte: Bool, context: MissionReadContext) async throws -> Bool { throw erreur }
    func scanner(code: String, metadonnees: MetadonneesScan, recu: RecuScan, context: MissionReadContext) async throws -> IssueScan {
        throw erreur
    }
    func reconcilier(recu: RecuScan, context: MissionReadContext) async throws -> IssueScan { throw erreur }
    func detail(missionId: String, context: MissionReadContext) async throws -> DetailPresences { throw erreur }
    func relancerValidation(missionId: String, context: MissionReadContext) async throws -> IssueRelance { throw erreur }

    func litige(presenceId: String, context: MissionReadContext) async throws -> LitigePresence? { throw erreur }
    func fenetreOuverte(missionId: String, context: MissionReadContext) async throws -> Bool { throw erreur }
    func contester(missionId: String, presenceId: String, motif: String,
                   context: MissionReadContext) async throws -> IssueContestation { throw erreur }

    func noter(missionId: String, note: Int, criteres: CriteresNotation?,
               context: MissionReadContext) async throws -> IssueNotation { throw erreur }

    func dossier(context: MissionReadContext) async throws -> DossierDocuments { throw erreur }
    func preparerEnvoi(type: String, fichier: FichierChoisi, libelle: String?,
                       context: MissionReadContext) async throws -> RecuDocument { throw erreur }
    func envoyer(recu: RecuDocument, octets: Data, context: MissionReadContext) async throws -> IssueEnvoiDocument { throw erreur }
    func reconcilier(recu: RecuDocument, context: MissionReadContext) async throws -> IssueEnvoiDocument { throw erreur }
    func reverifier(documentId: String, context: MissionReadContext) async throws -> VerdictDocument { throw erreur }
    func demanderRevue(documentId: String, context: MissionReadContext) async throws { throw erreur }
    func consulter(document: DocumentSoignant, context: MissionReadContext) async throws -> URL { throw erreur }
    func signerAttestationSante(context: MissionReadContext) async throws -> Date { throw erreur }
    func coherence(context: MissionReadContext) async throws -> CoherenceDocuments? { throw erreur }

    func contrats(context: MissionReadContext) async throws -> [ContratResume] { throw erreur }
    func contrat(id: String, context: MissionReadContext) async throws -> ContratDetail { throw erreur }
    func original(contrat: ContratDetail, context: MissionReadContext) async throws -> OriginalContrat { throw erreur }
    func admissionRecette(contratId: String, context: MissionReadContext) async throws -> AdmissionSignatureRecette? { throw erreur }
    func envoyerOtp(contratId: String, empreinte: String, context: MissionReadContext) async throws -> IssueEnvoiOtp { throw erreur }
    func signer(contratId: String, code: String, empreinte: String,
                context: MissionReadContext) async throws -> IssueSignature { throw erreur }
    func certificat(contratId: String, context: MissionReadContext) async throws -> [SignatureCertificat] { throw erreur }
    func fichierOriginal(contrat: OriginalContrat, context: MissionReadContext) async throws -> URL { throw erreur }
}
