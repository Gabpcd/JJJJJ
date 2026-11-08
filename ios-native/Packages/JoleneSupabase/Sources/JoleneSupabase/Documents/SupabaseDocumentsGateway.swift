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
/// `verify-document {document_id}` lancé UNE fois sans être attendu, comme le web (l.410-426 ; revue fraîche de T6, M2) :
/// le verdict est relu dans la ligne par le suivi du modèle, et l'issue de l'appel (erreur ou réponse) est observable par
/// `verificationEchouee(documentId:)` sans jamais le relancer (m-d). Réconciliation : ligne relue par `s3_cle` (jamais de
/// vérification automatique si elle existe), sinon objet relu par `exists(path:)` (HEAD) → enregistrement rejoué sous la
/// même clé, sinon « non envoyé » et `cleanup_orphan` best-effort juste après le HEAD (m7, portée limitée : m-e). Jeton
/// refusé (PostgREST `PGRST301`-`PGRST303`,
/// `NON_AUTHENTIFIE`, Storage `InvalidJWT`, HTTP 401) → session expirée, jamais un refus ordinaire (m5). Aucun octet
/// conservé, aucune URL signée, aucun chemin ni nom de fichier journalisé côté client.
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
    /// l.199, sans `soignant_id` (filtré), plus `verification_attempt_id` ; de `resultat_ia`, seule la profession
    /// certifiée ; `s3_bucket` lu pour la consultation (`doc.s3_bucket || 'jolene-documents'`, l.438 ; revue fraîche m1).
    public static let selectionDocuments = "id,type_document,nom_fichier,statut_verification,valide_depuis,valide_jusqua,televerse_le,"
        + "motif_rejet,est_critique,s3_cle,s3_bucket,type_mime,taille_octets,libelle,verification_attempt_id,"
        + "profession_certifiee:resultat_ia->>profession_certifiee"
    /// Code de refus d'un upload refusé par Storage (`STOCKAGE_<statut HTTP>`).
    public static let prefixeRefusStockage = "STOCKAGE_"
    /// Refus d'enregistrement sans `error_code` (web : `'Enregistrement impossible'`, l.403).
    public static let codeEnregistrementImpossible = "ENREGISTREMENT_IMPOSSIBLE"
    /// Codes PostgREST d'un jeton refusé (expiré, absent, revendications invalides) : session expirée.
    static let codesJetonRefuse: Set<String> = ["PGRST301", "PGRST302", "PGRST303"]

    private let client: SupabaseClient
    private let clock: any ClockPort
    /// Vérifications lancées par ce port (partagées par ses copies : `Gateways` est une valeur).
    private let verifications = VerificationsLancees()
    /// Tests seulement : appelé juste avant la garde d'annulation qui précède `verify-document` (correctif 4c84aa0e).
    var avantVerification: (@Sendable () -> Void)?

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
            case .sessionExpiree: throw Self.sessionExpireeErreur
            }
        }
        return try await enregistrerPuisVerifier(recu)
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
            if Self.sessionExpiree(error) { throw Self.sessionExpireeErreur }
            return .incertain
        }
        if let preuve { return preuve.issue }
        // Un reçu `registered` sans ligne relue ne se rejoue pas : nouvelle sélection.
        guard recu.phase != .registered, recu.phase != .verificationDemandee else { return .nonEnvoye }
        let objetPresent: Bool
        do {
            objetPresent = try await client.storage.from(Self.bucket).exists(path: recu.s3Cle)
        } catch {
            if Self.sessionExpiree(error) { throw Self.sessionExpireeErreur }
            return .incertain
        }
        guard objetPresent else {
            // m7, portée corrigée (m-e) : `cleanup_orphan` part juste après le HEAD, une fois, best-effort ; il ne rattrape
            // qu'un objet devenu visible entre les deux appels, jamais un objet arrivé plus tard (qui reste non
            // référencé). Un objet absent ou déjà référencé n'est pas touché (`verify-document/index.ts` l.333-387).
            // Aucun envoi de ce processus n'est en vol pour la clé (registre `EssaisDocumentsEnVol`, M1-bis).
            await nettoyerOrphelin(recu.s3Cle)
            return .nonEnvoye
        }
        return try await enregistrerPuisVerifier(recu)
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
        } catch FunctionsError.httpError(let statut, let corps) {
            if statut == 401 { throw Self.sessionExpireeErreur }
            throw JoleneError(.unknown, Self.messageEdge(corps) ?? MessagesDocuments.verificationImpossible)
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
    /// Garde (revue fraîche m1) : celle de la politique Storage (`fn_peut_gerer_objet_jolene` : premier segment = uid),
    /// sans `..` ni segment vide, et le bucket de la ligne (`doc.s3_bucket || 'jolene-documents'`, l.438) : une pièce
    /// envoyée avant 02e957ea (clé `<uid>/<TYPE>/<ms>_<nom>`) reste consultable.
    public func consulter(document: DocumentSoignant, context: MissionReadContext) async throws -> URL {
        try MissionQuery.validate(context: context)
        guard let cle = document.s3Cle, Self.cleConsultable(cle, userId: context.userId),
              let bucket = Self.bucketConsultable(document.s3Bucket) else {
            throw JoleneError(.contract, MessagesDocuments.consultationImpossible)
        }
        let octets: Data
        do {
            octets = try await client.storage.from(bucket).download(path: cle)
        } catch {
            if Self.sessionExpiree(error) { throw Self.sessionExpireeErreur }
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
    /// l.385-391), puis `verify-document` lancé une seule fois, sans l'attendre : la preuve d'enregistrement est le
    /// `document_id` rendu par CETTE requête ; le verdict est relu par le suivi.
    private func enregistrerPuisVerifier(_ recu: RecuDocument) async throws -> IssueEnvoiDocument {
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
            // m5 : jeton refusé par PostgREST, rien n'est enregistré : session expirée, sans nettoyage (l'objet sera
            // rattaché après reconnexion par la réconciliation du reçu `started`).
            if Self.codesJetonRefuse.contains(code) { throw Self.sessionExpireeErreur }
            await nettoyerOrphelin(recu.s3Cle)
            return .refuse(code: RecuScan.sqlstateValide(code) ? RPCResponse.prefixeSQLState + code : code)
        case let .reponse(reponse):
            // m5 : `NON_AUTHENTIFIE` (`public.sql` l.53089-53091) est rendu avant toute écriture : même traitement.
            if reponse.codeErreur == "NON_AUTHENTIFIE" { throw Self.sessionExpireeErreur }
            guard reponse.success == true, let id = reponse.string("document_id").flatMap(SupabaseAuditGateway.uuid) else {
                await nettoyerOrphelin(recu.s3Cle)
                return .refuse(code: reponse.codeErreur ?? Self.codeEnregistrementImpossible)
            }
            documentId = id
        }
        // Envoi annulé (délai `bounded` de l'appelant, qui réconcilie aussitôt) : aucune vérification ne part après
        // coup ; la ligne relue donnera « Revérifier ». « Une seule fois » reste vrai même en concurrence.
        avantVerification?()
        guard !Task.isCancelled else { return .incertain }
        await lancerVerification(documentId)
        return .verificationDemandee(documentId: documentId)
    }

    /// `verify-document {document_id}` : un seul appel, lancé dans une tâche non structurée que ni le délai ni
    /// l'annulation de l'appelant n'interrompent (l'edge sonde 10 s puis appelle l'IA 20 s, `index.ts` l.286-287 et
    /// l.625-626 ; le web ne l'attend pas non plus, l.410-426). Jamais relancé. Son issue — erreur (HTTP hors 2xx,
    /// transport) ou réponse — est gardée pour `verificationEchouee(documentId:)` ; le verdict, ou la revue manuelle d'un
    /// 503, est relu dans la ligne par le suivi du modèle.
    private func lancerVerification(_ documentId: String) async {
        let client = self.client
        let options = FunctionInvokeOptions(method: .post, body: ["document_id": documentId])
        let tache = Task { () -> Bool in
            do {
                _ = try await client.functions.invoke(Self.fonctionVerification, options: options) { donnees, _ in donnees }
                return false
            } catch {
                return true
            }
        }
        await verifications.poser(tache, pour: documentId)
    }

    /// Revue fraîche de T6, m-d : issue de la vérification lancée par ce port pour `documentId`, attendue sans relance
    /// (vrai : erreur, comme le `.then` du web l.413-425 ; faux : réponse) ; nil si ce port n'en a lancé aucune (ou plus de
    /// `VerificationsLancees.capacite` depuis).
    public func verificationEchouee(documentId: String) async -> Bool? {
        guard let tache = await verifications.tache(pour: documentId) else { return nil }
        return await tache.value
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
            // Échecs de la résolution ou de la connexion seulement : `.notConnectedToInternet` (-1009) peut survenir en
            // cours de transfert sur iOS, il reste incertain et le HEAD de la réconciliation tranche (revue fraîche, m-g).
            let jamaisPartie: Set<URLError.Code> = [.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed]
            return jamaisPartie.contains(url.code) ? .nonEnvoye : .incertain
        }
        if let storage = error as? StorageError, jetonRefuseParStorage(storage) { return .sessionExpiree }
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

    // MARK: - Session, consultation, messages de l'edge

    static let sessionExpireeErreur = JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)

    /// Jeton refusé (revue fraîche m5) : PostgREST `PGRST301`-`PGRST303`, Storage `InvalidJWT` ou 401, HTTP 401 d'une
    /// passerelle ou d'une edge function.
    static func sessionExpiree(_ error: any Error) -> Bool {
        if let jolene = error as? JoleneError { return jolene.kind == .unauthorized }
        if let postgrest = error as? PostgrestError { return postgrest.code.map(codesJetonRefuse.contains) ?? false }
        if let storage = error as? StorageError { return storage.statusCode == "401" || jetonRefuseParStorage(storage) }
        if let http = error as? HTTPError { return http.response.statusCode == 401 }
        if let edge = error as? FunctionsError, case let .httpError(statut, _) = edge { return statut == 401 }
        return false
    }

    /// Storage rend un jeton expiré ou invalide en HTTP 400 (`{"statusCode":"400","error":"InvalidJWT",…}`).
    static func jetonRefuseParStorage(_ erreur: StorageError) -> Bool {
        erreur.error?.caseInsensitiveCompare("InvalidJWT") == .orderedSame
    }

    /// Clé consultable : celle que la politique Storage accorde (`fn_peut_gerer_objet_jolene`, premier segment = uid),
    /// au moins deux segments non vides, sans `..` ni `\`.
    static func cleConsultable(_ cle: String, userId: String) -> Bool {
        let segments = cle.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count >= 2, segments.allSatisfy({ !$0.isEmpty }), String(segments[0]) == userId.lowercased() else {
            return false
        }
        return !cle.contains("..") && !cle.contains("\\") && cle.count <= 1_024
    }

    /// Bucket de la ligne, `jolene-documents` à défaut (`doc.s3_bucket || 'jolene-documents'`) ; nil s'il n'a pas la forme
    /// d'un nom de bucket.
    static func bucketConsultable(_ bucket: String?) -> String? {
        guard let bucket, !bucket.isEmpty else { return Self.bucket }
        let autorises = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        guard !bucket.contains(".."), bucket.allSatisfy(autorises.contains) else { return nil }
        return bucket
    }

    /// Message d'erreur d'une edge function, comme `messageErreurEdgeFn` (`body.error || body.message || body.motif`,
    /// `src/lib/erreurs.ts` l.573-575) ; nil sans texte.
    static func messageEdge(_ corps: Data) -> String? {
        let reponse = RPCResponse(SupabaseAccountGateway.lire(corps))
        for cle in ["error", "message", "motif"] {
            if let texte = reponse.string(cle), !texte.isEmpty { return texte }
        }
        return nil
    }
}

/// Tâches `verify-document` lancées par un `SupabaseDocumentsGateway`, par document (les `capacite` plus récentes) :
/// leur issue est attendue par `verificationEchouee(documentId:)`, jamais relancée.
actor VerificationsLancees {
    static let capacite = 32

    private var taches: [String: Task<Bool, Never>] = [:]
    private var ordre: [String] = []

    func poser(_ tache: Task<Bool, Never>, pour documentId: String) {
        if taches.updateValue(tache, forKey: documentId) == nil { ordre.append(documentId) }
        while ordre.count > Self.capacite { taches[ordre.removeFirst()] = nil }
    }

    func tache(pour documentId: String) -> Task<Bool, Never>? { taches[documentId] }
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
