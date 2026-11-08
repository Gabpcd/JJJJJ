import Foundation
import JoleneCore
import Supabase

/// `DocumentsPort` sur Supabase (lot 2 T6 ; blueprint `docs/mobile-swift/LOT2_PLAN.md` §2.3-§2.5, décision 14 ; fiches
/// `fn_remplacer_document_soignant`, `fn_demander_revue_document`, `fn_verifier_coherence_documents`,
/// `fn_signer_attestation_sante`, « Edge `verify-document` » et « Storage du lot 2 » de
/// `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`). Parité `src/pages/DocumentsSoignant.tsx`.
///
/// Envoi (reçu `started` journalisé par l'appelant) : upload Storage `upload(_:data:options:)` avec `upsert: false`
/// (jamais `upload(path:file:options:)`, déprécié, correction 18) sous la clé du reçu, construite comme le web (l.372) ;
/// `fn_remplacer_document_soignant` (idempotente sur la clé) ; refus → `cleanup_orphan` une fois ; succès →
/// `verify-document {document_id}` UNE fois, quel qu'en soit le résultat, puis relecture de la ligne par `s3_cle`.
/// Réconciliation : ligne relue par `s3_cle` (jamais de vérification automatique si elle existe), sinon objet relu
/// par `exists(path:)` (HEAD) → enregistrement rejoué sous la même clé, sinon « non envoyé ». Aucun octet conservé,
/// aucune URL signée, aucun chemin ni nom de fichier journalisé côté client.
public struct SupabaseDocumentsGateway: DocumentsPort {
    public static let bucket = "jolene-documents"
    public static let fonctionVerification = "verify-document"
    public static let remplacerRPC = "fn_remplacer_document_soignant"
    public static let revueRPC = "fn_demander_revue_document"
    public static let coherenceRPC = "fn_verifier_coherence_documents"
    public static let attestationRPC = "fn_signer_attestation_sante"
    public static let auditRPC = "fn_ecrire_audit_safe"
    /// `DocumentsSoignant.tsx` l.181 (sans `prenom`, `nom`, non lus par la page) + l.36 (attestation santé).
    public static let selectionProfil = "profession,type_exercice,rpps_verifie,adeli_verifie,attestation_sante_signee_le"
    /// l.201, telle quelle.
    public static let selectionExigences = "id,profession,type_document,description,a_expiration,duree_validite_mois,est_critique,type_exercice_requis"
    /// l.199, sans `soignant_id` ni `s3_bucket` (filtrés), plus `verification_attempt_id` ; de `resultat_ia`, seule la
    /// profession certifiée.
    public static let selectionDocuments = "id,type_document,nom_fichier,statut_verification,valide_depuis,valide_jusqua,televerse_le,"
        + "motif_rejet,est_critique,s3_cle,type_mime,taille_octets,libelle,verification_attempt_id,"
        + "profession_certifiee:resultat_ia->>profession_certifiee"
    /// Code de refus d'un upload refusé par Storage (`STOCKAGE_<statut HTTP>`).
    public static let prefixeRefusStockage = "STOCKAGE_"
    /// Refus d'enregistrement sans `error_code` (web : `'Enregistrement impossible'`, l.403).
    public static let codeEnregistrementImpossible = "ENREGISTREMENT_IMPOSSIBLE"

    private let client: SupabaseClient
    private let clock: any ClockPort

    public init(client: SupabaseClient, clock: any ClockPort = SystemClock()) {
        self.client = client
        self.clock = clock
    }

    // MARK: - Dossier

    public func dossier(context: MissionReadContext) async throws -> DossierDocuments {
        try MissionQuery.validate(context: context)
        do {
            let profil: ProfilDocuments? = try await client.from("soignants")
                .select(Self.selectionProfil)
                .eq("id", value: context.userId)
                .maybeSingle()
                .execute()
                .value
            guard let profil else { return DossierDocuments() }
            var regles: [ExigenceDocument] = []
            if let profession = profil.profession, !profession.isEmpty {
                regles = try await client.from("documents_requis_par_profession")
                    .select(Self.selectionExigences)
                    .eq("profession", value: profession)
                    .execute()
                    .value
            }
            let documents: [DocumentSoignant] = try await client.from("documents_soignants")
                .select(Self.selectionDocuments)
                .eq("soignant_id", value: context.userId)
                .is("supprime_le", value: nil)
                .is("revoque_le", value: nil)
                // supabase-js n'ajoute aucun suffixe : NULLS FIRST, défaut PostgreSQL d'un DESC (même règle qu'au lot 1).
                .order("televerse_le", ascending: false, nullsFirst: true)
                .execute()
                .value
            return DossierDocuments.assembler(profil: profil.exigences, regles: regles, documents: documents,
                                              attestationSanteSigneeLe: profil.attestationSanteSigneeLe)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesDocuments.chargementImpossible)
        }
    }

    // MARK: - Envoi

    public func preparerEnvoi(type: String, fichier: FichierChoisi, libelle: String?, context: MissionReadContext) async throws -> RecuDocument {
        try MissionQuery.validate(context: context)
        guard !ExigencesDocuments.typesDocumentsExclusUpload.contains(type) else { throw RecuErreur.champInvalide("typeDocument") }
        // `Date.now()` du web, en millisecondes ; l'epoch est posé par le modèle (`DocumentsModel`).
        let horodatage = Int64((clock.now().timeIntervalSince1970 * 1_000).rounded(.down))
        return try RecuDocument.preparer(userId: context.userId, epoch: 0, typeDocument: type, fichier: fichier, libelle: libelle,
                                         horodatageMs: horodatage)
    }

    public func envoyer(recu: RecuDocument, octets: Data, context: MissionReadContext) async throws -> IssueEnvoiDocument {
        try MissionQuery.validate(context: context)
        guard recu.userId == context.userId else { throw RecuErreur.utilisateurDifferent }
        guard recu.phase == .started else {
            throw RecuErreur.transitionInterdite(de: recu.phase.rawValue, vers: RecuDocument.Phase.stored.rawValue)
        }
        guard octets.count == recu.tailleOctets else { throw RecuErreur.champInvalide("tailleOctets") }
        do {
            try await client.storage.from(Self.bucket)
                .upload(recu.s3Cle, data: octets, options: FileOptions(contentType: recu.mime.rawValue, upsert: false))
        } catch {
            switch Self.classerEchecUpload(error) {
            case .nonEnvoye: return .nonEnvoye
            case .incertain: return .incertain
            case let .refuse(code): return .refuse(code: code)
            case .sessionExpiree: throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
            }
        }
        return await enregistrerPuisVerifier(recu)
    }

    public func reconcilier(recu: RecuDocument, context: MissionReadContext) async throws -> IssueEnvoiDocument {
        try MissionQuery.validate(context: context)
        guard recu.userId == context.userId else { throw RecuErreur.utilisateurDifferent }
        // `prepared` : journalisé avant toute requête, rien n'est parti.
        guard recu.phase != .prepared else { return .nonEnvoye }
        let preuve: PreuveDocument?
        do {
            preuve = try await lirePreuve(recu)
        } catch {
            return .incertain
        }
        if let preuve { return preuve.issue }
        // Un reçu `registered` sans ligne relue ne se rejoue pas : nouvelle sélection.
        guard recu.phase != .registered, recu.phase != .verificationDemandee else { return .nonEnvoye }
        let objetPresent: Bool
        do {
            objetPresent = try await client.storage.from(Self.bucket).exists(path: recu.s3Cle)
        } catch {
            return .incertain
        }
        guard objetPresent else { return .nonEnvoye }
        return await enregistrerPuisVerifier(recu)
    }

    // MARK: - Actions sur une pièce

    public func reverifier(documentId: String, context: MissionReadContext) async throws -> VerdictDocument {
        try MissionQuery.validate(context: context)
        guard let id = SupabaseAuditGateway.uuid(documentId) else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        let options = FunctionInvokeOptions(method: .post, body: ["document_id": id])
        do {
            let corps = try await client.functions.invoke(Self.fonctionVerification, options: options) { donnees, _ in donnees }
            let verdict = RPCResponse(SupabaseAccountGateway.lire(corps)).string("verdict").flatMap(VerdictDocument.init(rawValue:))
            return verdict ?? .enAttente // web : « Vérification en attente… » pour tout autre verdict
        } catch FunctionsError.httpError(_, let corps) {
            throw JoleneError(.unknown, RPCResponse(SupabaseAccountGateway.lire(corps)).erreur ?? MessagesDocuments.verificationImpossible)
        } catch FunctionsError.relayError {
            throw JoleneError(.unknown, MessagesDocuments.verificationImpossible)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesDocuments.reverificationErreur)
        }
    }

    public func demanderRevue(documentId: String, context: MissionReadContext) async throws {
        try MissionQuery.validate(context: context)
        guard let id = SupabaseAuditGateway.uuid(documentId) else { throw JoleneError(.unknown, MessagesDocuments.revueDocumentIntrouvable) }
        let reponse = try await RPCResponse.appeler(client, Self.revueRPC,
                                                    params: ["p_document_id": .string(id), "p_motif": .string(MessagesDocuments.motifRevue)],
                                                    fallback: MessagesDocuments.erreurGenerique)
        if reponse.success == true, reponse.erreur == nil { return }
        switch reponse.codeErreur {
        case "DOCUMENT_INTROUVABLE": throw JoleneError(.unknown, MessagesDocuments.revueDocumentIntrouvable)
        case "MOTIF_INVALIDE": throw JoleneError(.unknown, MessagesDocuments.revueMotifInvalide)
        case "NON_AUTHENTIFIE": throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        default:
            try reponse.leverSiErreur(fallback: MessagesDocuments.erreurGenerique)
            throw JoleneError(.unknown, reponse.erreur ?? MessagesDocuments.erreurGenerique)
        }
    }

    /// Téléchargement de l'objet sous le JWT du soignant (politique `pol_storage_jolene_select`), copie temporaire
    /// protégée, puis audit `DOCUMENT_CONSULTATION` best-effort (parité l.445-448). Écart assumé au web : aucune URL
    /// signée n'est créée (`createSignedUrl(…, 3600)`, l.437-439) — l'app affiche une copie locale, pas un lien.
    public func consulter(document: DocumentSoignant, context: MissionReadContext) async throws -> URL {
        try MissionQuery.validate(context: context)
        guard let cle = document.s3Cle, cle.hasPrefix("\(context.userId)/documents/"), !cle.contains("..") else {
            throw JoleneError(.contract, MessagesDocuments.consultationImpossible)
        }
        let octets: Data
        do {
            octets = try await client.storage.from(Self.bucket).download(path: cle)
        } catch {
            if Self.statutHTTP(error) == 401 { throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage) }
            throw JoleneError(.unknown, MessagesDocuments.consultationImpossible)
        }
        let fichier = try ConsultationDocuments.ecrire(octets, nomFichier: document.nomFichier)
        await auditerConsultation(document, cle: cle, context: context)
        return fichier
    }

    /// `fn_signer_attestation_sante()` (le serveur horodate et journalise `ATTESTATION_SANTE_SIGNEE`, l.56335-56352 : le
    /// natif n'ajoute pas l'audit client du web, doublon) puis relecture de `soignants.attestation_sante_signee_le`.
    public func signerAttestationSante(context: MissionReadContext) async throws -> Date {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.attestationRPC, fallback: MessagesDocuments.signatureAttestationErreur)
        if let erreur = reponse.erreur, RPCResponse.estNonAuthentifie(erreur) {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        guard reponse.success == true, reponse.erreur == nil else {
            throw JoleneError(.unknown, MessagesDocuments.signatureAttestationErreur)
        }
        let relue: AttestationRelue?
        do {
            relue = try await client.from("soignants")
                .select("attestation_sante_signee_le")
                .eq("id", value: context.userId)
                .maybeSingle()
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesDocuments.signatureAttestationErreur)
        }
        guard let valeur = relue?.attestationSanteSigneeLe, let date = try? DateHeureParis.instantJolene(valeur) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return date
    }

    /// Lecture best-effort, appel SANS `p_soignant_id` (l.304) : toute erreur rend nil (aucune bannière), `42501`
    /// compris (compte inactif), jamais « session expirée ».
    public func coherence(context: MissionReadContext) async throws -> CoherenceDocuments? {
        try MissionQuery.validate(context: context)
        do {
            let reponse = try await RPCResponse.appeler(client, Self.coherenceRPC, fallback: MessagesDocuments.erreurGenerique,
                                                        exceptionsMetier: ExceptionsMetierLot2.verifierCoherenceDocuments)
            guard !reponse.estRefus, reponse.erreur == nil, reponse.bool("coherent") != nil else { return nil }
            let donnees = try JSONEncoder().encode(reponse.raw)
            return try? JSONDecoder().decode(CoherenceDocuments.self, from: donnees)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    // MARK: - Enregistrement et vérification

    /// `fn_remplacer_document_soignant` sous la clé du reçu (`p_libelle: libelle || ''`, `p_nom_fichier: fichier.name`,
    /// l.385-391), puis `verify-document` une seule fois et relecture de la ligne.
    private func enregistrerPuisVerifier(_ recu: RecuDocument) async -> IssueEnvoiDocument {
        let params: JSONObject = [
            "p_type_document": .string(recu.typeDocument),
            "p_libelle": .string(recu.libelle ?? ""),
            "p_s3_cle": .string(recu.s3Cle),
            "p_nom_fichier": .string(recu.nomFichier),
            "p_type_mime": .string(recu.mime.rawValue),
            "p_taille_octets": .integer(recu.tailleOctets),
        ]
        // Aucune exception déclarée : le trigger des pièces de santé (`P0001`, texte juridique) n'est jamais affiché.
        let issue = await RPCResponse.appelerMutation(client, Self.remplacerRPC, params: params,
                                                      fallback: MessagesDocuments.enregistrementImpossible, exceptionsMetier: [])
        let documentId: String
        switch issue {
        case .incertain:
            return .incertain
        case let .refusDefinitif(code, _):
            await nettoyerOrphelin(recu.s3Cle)
            return .refuse(code: RecuScan.sqlstateValide(code) ? RPCResponse.prefixeSQLState + code : code)
        case let .reponse(reponse):
            guard reponse.success == true, let id = reponse.string("document_id").flatMap(SupabaseAuditGateway.uuid) else {
                await nettoyerOrphelin(recu.s3Cle)
                return .refuse(code: reponse.codeErreur ?? Self.codeEnregistrementImpossible)
            }
            documentId = id
        }
        await demanderVerification(documentId)
        let preuve: PreuveDocument?
        do {
            preuve = try await lirePreuve(recu)
        } catch {
            return .incertain
        }
        guard let preuve, preuve.id.lowercased() == documentId else { return .incertain }
        return preuve.issue
    }

    /// `verify-document {document_id}` : un seul appel, résultat ignoré (le verdict est relu dans la ligne ; un 429 ou un
    /// 503 laisse la pièce en vérification manuelle, l.416-426). Jamais relancé.
    private func demanderVerification(_ documentId: String) async {
        let options = FunctionInvokeOptions(method: .post, body: ["document_id": documentId])
        _ = try? await client.functions.invoke(Self.fonctionVerification, options: options) { donnees, _ in donnees }
    }

    /// `cleanup_orphan` après un refus d'enregistrement (l.395-397), une fois, best-effort.
    private func nettoyerOrphelin(_ cle: String) async {
        let options = FunctionInvokeOptions(method: .post, body: ["action": "cleanup_orphan", "s3_cle": cle])
        _ = try? await client.functions.invoke(Self.fonctionVerification, options: options) { donnees, _ in donnees }
    }

    /// Ligne `documents_soignants` relue par `s3_cle` (actives ou non : une ligne existante interdit tout rejeu).
    private func lirePreuve(_ recu: RecuDocument) async throws -> PreuveDocument? {
        let lignes: [PreuveDocument] = try await client.from("documents_soignants")
            .select(PreuveDocument.selection)
            .eq("soignant_id", value: recu.userId)
            .eq("s3_bucket", value: Self.bucket)
            .eq("s3_cle", value: recu.s3Cle)
            .order("televerse_le", ascending: false, nullsFirst: true)
            .limit(1)
            .execute()
            .value
        return lignes.first { $0.s3Cle == recu.s3Cle }
    }

    private func auditerConsultation(_ document: DocumentSoignant, cle: String, context: MissionReadContext) async {
        guard let acteur = SupabaseAuditGateway.uuid(context.userId), let ressource = SupabaseAuditGateway.uuid(document.id) else { return }
        let params: JSONObject = [
            "p_acteur_id": .string(acteur),
            "p_type_acteur": .string(SupabaseAuditGateway.typeActeur),
            "p_action": .string("DOCUMENT_CONSULTATION"),
            "p_type_ressource": .string("document"),
            "p_id_ressource": .string(ressource),
            "p_cle_s3": .string(cle),
            "p_details": .object(["type_document": .string(document.typeDocument)]),
            "p_navigateur": .string(SupabaseAuditGateway.navigateur),
        ]
        _ = try? await RPCResponse.appeler(client, Self.auditRPC, params: params, fallback: SupabaseAuditGateway.fallbackMessage)
    }

    // MARK: - Classement des échecs d'upload

    enum EchecUpload: Equatable {
        /// La requête n'est jamais partie (pas de réseau, hôte injoignable).
        case nonEnvoye
        /// Réponse perdue ou ambiguë : réconciliation par `exists(path:)`.
        case incertain
        /// Refus définitif de Storage (aucun objet écrit).
        case refuse(String)
        case sessionExpiree
    }

    static func classerEchecUpload(_ error: any Error) -> EchecUpload {
        if let url = error as? URLError {
            let jamaisPartie: Set<URLError.Code> = [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed]
            return jamaisPartie.contains(url.code) ? .nonEnvoye : .incertain
        }
        guard let statut = statutHTTP(error) else { return .incertain }
        switch statut {
        case 401: return .sessionExpiree
        // 409 « déjà existant » : seul cet essai écrit sous cette clé → objet présent, réconciliation.
        case 409: return .incertain
        case 400..<500: return .refuse(prefixeRefusStockage + String(statut))
        default: return .incertain
        }
    }

    static func statutHTTP(_ error: any Error) -> Int? {
        if let storage = error as? StorageError { return storage.statusCode.flatMap { Int($0) } }
        if let http = error as? HTTPError { return http.response.statusCode }
        return nil
    }
}

/// Profil documentaire lu dans `soignants`.
private struct ProfilDocuments: Decodable {
    let profession: String?
    let typeExercice: String?
    let rppsVerifie: Bool?
    let adeliVerifie: Bool?
    let attestationSanteSigneeLe: String?

    enum CodingKeys: String, CodingKey {
        case profession
        case typeExercice = "type_exercice"
        case rppsVerifie = "rpps_verifie"
        case adeliVerifie = "adeli_verifie"
        case attestationSanteSigneeLe = "attestation_sante_signee_le"
    }

    var exigences: SoignantExigencesDocuments {
        SoignantExigencesDocuments(profession: profession, typeExercice: typeExercice, rppsVerifie: rppsVerifie, adeliVerifie: adeliVerifie)
    }
}

private struct AttestationRelue: Decodable {
    let attestationSanteSigneeLe: String?
    enum CodingKeys: String, CodingKey { case attestationSanteSigneeLe = "attestation_sante_signee_le" }
}
