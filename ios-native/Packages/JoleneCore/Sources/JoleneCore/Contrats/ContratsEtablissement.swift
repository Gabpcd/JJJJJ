import Foundation

// Contrats de l'espace établissement (lot 5, T10 ; `docs/mobile-swift/LOT5_PLAN.md` §2.3, §2.7, §3 T10 ; D18 :
// réemploi strict du port du lot 2, aucun port partiel). Le `ContratsPort` reçoit des méthodes additives à
// contexte `EtablissementReadContext` (`Ports/Lot2Ports.swift`) ; les écrans et les modèles du lot 2
// (`ContratModel`, `ContratsListeModel`, `SessionSignatureOtp`) sont réemployés tels quels, aiguillés par la partie
// qui regarde (`PartieContrat`). Aucun texte juridique ici (garde `DOSSIERS_LOT2`).

/// Partie d'un contrat qui regarde l'écran : le soignant du contrat (lot 2), ou un membre habilité de l'établissement
/// (lot 5, T10). Valeur brute = `signataire_role` de `signatures_contrats` (`fn_envoyer_otp_signature`, `v_role`).
/// `ContratMission.tsx` l.533-534 : `isSoignant ? signature_soignant : signature_etablissement`.
public enum PartieContrat: String, Equatable, Sendable, CaseIterable {
    case soignant
    case etablissement
}

/// Refus et messages opérationnels des contrats de l'établissement (aucun texte juridique).
public enum ContratsEtablissement {
    /// Permission `contrats` absente des permissions servies (§2.7, fail-closed) : même message neutre que le refus
    /// RBAC du serveur (`RPCInterception.messageRoleInsuffisant`, égalité gardée par
    /// `SupabaseEtabContratsGatewayTests`). Le serveur reste l'autorité (`fn_envoyer_otp_signature` : `NON_AUTORISE`).
    public static let messageRoleInsuffisant = "Votre rôle dans cet établissement ne permet pas cette action."

    /// Contexte cohérent (identifiants, rôle connu) et permission `contrats` servie ; sinon aucun appel.
    public static func verifier(_ context: EtablissementReadContext) throws {
        try context.verifier()
        guard context.permissions.contrats else { throw RefusAccesEtablissement(message: messageRoleInsuffisant) }
    }

    /// Code du refus serveur d'un document modifié (`fn_signer_contrat_otp`), repris pour le refus local.
    public static let codeOriginalChange = "HASH_DOCUMENT_CHANGE"

    /// Original relu par le triple contrôle différent de celui affiché (ou plus contrôlable) : aucun SMS n'est demandé.
    /// Même code et même message que le refus serveur d'un document modifié (texte du web, `MESSAGES_ERREUR`), bloquant
    /// comme lui : l'écran doit être rechargé.
    public static var refusEnvoiOriginalChange: IssueEnvoiOtp {
        .refuse(code: codeOriginalChange, message: TextesWeb.SignatureOtp.hashDocumentChange, bloquant: true)
    }

    /// Même refus avant la signature : le code n'est jamais envoyé au serveur pour un autre document que l'affiché.
    public static var refusSignatureOriginalChange: IssueSignature {
        .refuse(code: codeOriginalChange, message: TextesWeb.SignatureOtp.hashDocumentChange, tentativesRestantes: nil)
    }

    /// Refus d'un port qui ne sert pas encore l'espace établissement (conformances antérieures, doubles de test).
    static var nonCable: JoleneError { UnwiredPorts.erreur(port: "contrats", tranche: "T10", lot: 5) }
}

// Défauts des conformances antérieures au lot 5 (doubles de test du lot 2) : refus « non câblé », jamais un état vide
// plausible (PRINCIPES §2). Les deux mondes (`DemoContratsGateway`, `SupabaseContratsGateway`) implémentent chaque
// méthode ; `DemoEtabContratsGatewayTests` et `SupabaseEtabContratsGatewayTests` le prouvent.
extension ContratsPort {
    public func contratsEtablissement(context: EtablissementReadContext) async throws -> [ContratResume] {
        throw ContratsEtablissement.nonCable
    }

    public func contrat(id: String, etab: EtablissementReadContext) async throws -> ContratDetail {
        throw ContratsEtablissement.nonCable
    }

    public func original(contrat: ContratDetail, etab: EtablissementReadContext) async throws -> OriginalContrat {
        throw ContratsEtablissement.nonCable
    }

    public func admissionRecette(contratId: String, etab: EtablissementReadContext) async throws -> AdmissionSignatureRecette? {
        throw ContratsEtablissement.nonCable
    }

    public func envoyerOtp(contratId: String, empreinte: String, etab: EtablissementReadContext) async throws -> IssueEnvoiOtp {
        throw ContratsEtablissement.nonCable
    }

    public func signer(contratId: String, code: String, empreinte: String,
                       etab: EtablissementReadContext) async throws -> IssueSignature {
        throw ContratsEtablissement.nonCable
    }

    public func certificat(contratId: String, etab: EtablissementReadContext) async throws -> [SignatureCertificat] {
        throw ContratsEtablissement.nonCable
    }

    public func fichierOriginal(contrat: OriginalContrat, etab: EtablissementReadContext) async throws -> URL {
        throw ContratsEtablissement.nonCable
    }
}

/// Périmètre d'un écran de contrat : contexte du soignant (lot 2) ou contexte confirmé de l'établissement (lot 5).
enum PerimetreContrat: Equatable, Sendable {
    case soignant(MissionReadContext)
    case etablissement(EtablissementReadContext)

    var partie: PartieContrat {
        switch self {
        case .soignant: return .soignant
        case .etablissement: return .etablissement
        }
    }
}

/// Cadre d'un modèle de contrat : epoch de la session qui l'a ouvert et périmètre des appels du port.
struct CadreContrat: Sendable {
    let epoch: Int
    let perimetre: PerimetreContrat

    init(_ snapshot: SessionSnapshot) {
        epoch = snapshot.epoch
        perimetre = .soignant(snapshot.context)
    }

    init(_ snapshot: EtablissementSessionSnapshot) {
        epoch = snapshot.epoch
        perimetre = .etablissement(snapshot.context)
    }
}

/// Mode de signature annoncé à l'établissement (`ContratMission.tsx` l.742-745) : libellé et description du mode OTP,
/// seul mode porté en natif (D18). Textes verbatim de `TextesWeb.Contrat` (HARD STOP n°4), jamais réécrits ici.
public struct ModeSignatureOtp: Equatable, Sendable {
    public var libelle: String
    public var description: String

    public init() {
        libelle = TextesWeb.Contrat.otpLibelle
        description = TextesWeb.Contrat.otpDescription
    }
}

/// Appels du port des contrats pour un périmètre : simple aiguillage vers la variante du contexte, aucune règle.
/// Les modèles du lot 2 l'emploient pour servir les deux espaces sans dupliquer leur logique.
struct AccesContrats: Sendable {
    let port: any ContratsPort
    let perimetre: PerimetreContrat

    func contrats() async throws -> [ContratResume] {
        switch perimetre {
        case .soignant(let context): return try await port.contrats(context: context)
        case .etablissement(let context): return try await port.contratsEtablissement(context: context)
        }
    }

    func contrat(id: String) async throws -> ContratDetail {
        switch perimetre {
        case .soignant(let context): return try await port.contrat(id: id, context: context)
        case .etablissement(let context): return try await port.contrat(id: id, etab: context)
        }
    }

    func original(contrat: ContratDetail) async throws -> OriginalContrat {
        switch perimetre {
        case .soignant(let context): return try await port.original(contrat: contrat, context: context)
        case .etablissement(let context): return try await port.original(contrat: contrat, etab: context)
        }
    }

    func admissionRecette(contratId: String) async throws -> AdmissionSignatureRecette? {
        switch perimetre {
        case .soignant(let context): return try await port.admissionRecette(contratId: contratId, context: context)
        case .etablissement(let context): return try await port.admissionRecette(contratId: contratId, etab: context)
        }
    }

    func envoyerOtp(contratId: String, empreinte: String) async throws -> IssueEnvoiOtp {
        switch perimetre {
        case .soignant(let context): return try await port.envoyerOtp(contratId: contratId, empreinte: empreinte, context: context)
        case .etablissement(let context): return try await port.envoyerOtp(contratId: contratId, empreinte: empreinte, etab: context)
        }
    }

    func signer(contratId: String, code: String, empreinte: String) async throws -> IssueSignature {
        switch perimetre {
        case .soignant(let context):
            return try await port.signer(contratId: contratId, code: code, empreinte: empreinte, context: context)
        case .etablissement(let context):
            return try await port.signer(contratId: contratId, code: code, empreinte: empreinte, etab: context)
        }
    }

    func certificat(contratId: String) async throws -> [SignatureCertificat] {
        switch perimetre {
        case .soignant(let context): return try await port.certificat(contratId: contratId, context: context)
        case .etablissement(let context): return try await port.certificat(contratId: contratId, etab: context)
        }
    }

    func fichierOriginal(contrat: OriginalContrat) async throws -> URL {
        switch perimetre {
        case .soignant(let context): return try await port.fichierOriginal(contrat: contrat, context: context)
        case .etablissement(let context): return try await port.fichierOriginal(contrat: contrat, etab: context)
        }
    }
}
