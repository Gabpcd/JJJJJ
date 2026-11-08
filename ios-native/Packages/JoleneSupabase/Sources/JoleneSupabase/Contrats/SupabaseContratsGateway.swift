import Foundation
import JoleneCore
import Supabase

/// `ContratsPort` sur Supabase (lot 2, T8 ; `docs/mobile-swift/LOT2_PLAN.md` §2.3-§2.5, fiches
/// `fn_envoyer_otp_signature`, `fn_signer_contrat_otp`, `fn_admission_otp_signature_recette`, « Edge
/// `generate-contrat-mission-pdf` » et « Storage du lot 2 » de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`).
///
/// - Lectures PostgREST à projection explicite (jamais `select=*`, correction 22) : liste (`ListeContrats.tsx`
///   l.69), détail (`ContratDetail.colonnes`, sans images ni IP de signature), mission (l.218-222), nom
///   d'établissement par `fn_etablissements_safe` seulement (jamais l'embed `etablissements`), compte TEST
///   (`soignants.est_compte_test`, fail-closed), certificat (`SignatureCertificat.colonnes`, colonnes accordées). Une
///   ligne d'un autre soignant est écartée (défense en profondeur de la RLS).
/// - Original : triple contrôle `VerificationOriginal` sur les octets `contrats-signes/<storage_path>` ; rendu
///   serveur demandé une seule fois et seulement si `ContratRules.renduServeurADemander` (jamais un CDD, jamais
///   `donnees_cdd`), puis contrat relu ; un refus de l'edge est restitué verbatim, jamais rejoué.
/// - OTP : `fn_envoyer_otp_signature` et `fn_signer_contrat_otp` par leurs clés exactes, une seule requête
///   (`RPCResponse.appelerMutation`, jamais rejouée), session du compte affiché exigée ; aucun SMS si la révision
///   affichée n'est plus celle du serveur ; `p_signature_image` toujours NULL (décision 18) ; un succès de
///   signature n'est annoncé qu'après relecture du contrat ET de la preuve `signatures_contrats` ; une réponse
///   perdue est réconciliée par la même relecture. Messages : `MESSAGES_ERREUR` du web (TL), sinon `error`
///   serveur verbatim.
/// - Admission de recette : `fn_admission_otp_signature_recette` seulement si l'origine du projet est STAGING
///   (`AdmissionRecette`), nil partout ailleurs, jamais une erreur de contrat.
public struct SupabaseContratsGateway: ContratsPort {
    public static let table = "contrats_mission"
    public static let tableSignatures = "signatures_contrats"
    public static let bucket = "contrats-signes"
    public static let edgeRendu = "generate-contrat-mission-pdf"
    public static let rpcEnvoyer = "fn_envoyer_otp_signature"
    public static let rpcSigner = "fn_signer_contrat_otp"
    public static let rpcAdmission = "fn_admission_otp_signature_recette"
    /// Relecture de la révision avant un envoi de code.
    public static let selectionEmpreinte = "id,hash_document"
    /// Succès annoncé par le serveur mais preuve non relue : texte du pilote, repris tel quel
    /// (`mobile-native/src/workflows/contracts/supabaseGateway.ts` l.263).
    public static let messageSignatureNonConfirmee =
        "La signature ne peut pas être confirmée. Rechargez son état ; ne renvoyez pas automatiquement le code."
    /// Exception déclarée de `fn_signer_contrat_otp` (`public.sql` l.56600 : « Rôle de signature invalide »).
    static let exceptionsSignature: Set<String> = ["23514"]
    static let codeHashChange = "HASH_DOCUMENT_CHANGE"

    private let client: SupabaseClient
    private let clock: any ClockPort
    private let projet: URL

    /// - Parameter projet: URL du projet (défaut : celle du stockage du client, `https://<ref>.supabase.co/storage/v1`),
    ///   seule source de la garde STAGING de l'admission de recette.
    public init(client: SupabaseClient, clock: any ClockPort = SystemClock(), projet: URL? = nil) {
        self.client = client
        self.clock = clock
        self.projet = projet ?? client.storage.configuration.url
    }

    // MARK: - Lectures

    public func contrats(context: MissionReadContext) async throws -> [ContratResume] {
        try MissionQuery.validate(context: context)
        let lignes: [ContratResume]
        do {
            lignes = try await client.from(Self.table)
                .select(ContratResume.selection)
                .eq("soignant_id", value: context.userId)
                .order("cree_le", ascending: false, nullsFirst: true) // `order('cree_le', {ascending:false})` du web
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesContrats.indisponible)
        }
        return lignes.filter { Self.meme($0.soignantId, context.userId) }
    }

    public func contrat(id: String, context: MissionReadContext) async throws -> ContratDetail {
        try MissionQuery.validate(context: context)
        var detail = try await lireLigne(id: id, context: context)
        let missionId = detail.missionId
        let etablissementId = detail.etablissementId
        async let mission = lireMission(missionId)
        async let nom = lireNomEtablissement(etablissementId)
        async let compteTest = lireCompteTest(context)
        detail.estCompteTest = try await compteTest
        detail.mission = try await mission
        detail.etablissementNom = try await nom
        return detail
    }

    public func original(contrat: ContratDetail, context: MissionReadContext) async throws -> OriginalContrat {
        try MissionQuery.validate(context: context)
        guard ContratRules.identifiantValide(contrat.id), Self.meme(contrat.soignantId, context.userId) else {
            throw JoleneError(.unknown, MessagesContrats.indisponible)
        }
        if ContratRules.cddSansOriginal(contrat) { throw ContratOriginalIndisponible(motif: .cddAPreparer) }
        var courant = contrat
        if ContratRules.renduServeurADemander(contrat) {
            try await demanderRendu(contratId: contrat.id)
            courant = try await lireLigne(id: contrat.id, context: context)
        }
        if let motif = VerificationOriginal.motifAvantStorage(courant) { throw ContratOriginalIndisponible(motif: motif) }
        let octets = try await telecharger(courant.storagePath ?? "")
        let signatures = try await certificat(contratId: courant.id, context: context)
        return try VerificationOriginal.verifier(courant, octetsStorage: octets, signatures: signatures)
    }

    public func certificat(contratId: String, context: MissionReadContext) async throws -> [SignatureCertificat] {
        try MissionQuery.validate(context: context)
        guard ContratRules.identifiantValide(contratId) else { throw JoleneError(.unknown, MessagesContrats.indisponible) }
        let lignes: [SignatureCertificat]
        do {
            lignes = try await client.from(Self.tableSignatures)
                .select(SignatureCertificat.selection)
                .eq("contrat_id", value: contratId)
                .order("cree_le", ascending: true) // `order('cree_le')` du web (l.52)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesContrats.indisponible)
        }
        return lignes.filter { $0.contratId == contratId }
    }

    public func fichierOriginal(contrat: OriginalContrat, context: MissionReadContext) async throws -> URL {
        try MissionQuery.validate(context: context)
        return try FichierContratTemporaire.ecrire(contrat)
    }

    public func admissionRecette(contratId: String, context: MissionReadContext) async throws -> AdmissionSignatureRecette? {
        try MissionQuery.validate(context: context)
        let client = client
        return await AdmissionRecette.lire(projet: projet, contratId: contratId, maintenant: clock.now()) { id in
            try await client.rpc(Self.rpcAdmission, params: ["p_contrat_id": id]).execute().value
        }
    }

    // MARK: - OTP

    public func envoyerOtp(contratId: String, empreinte: String, context: MissionReadContext) async throws -> IssueEnvoiOtp {
        try MissionQuery.validate(context: context)
        guard ContratRules.identifiantValide(contratId) else { throw JoleneError(.unknown, MessagesContrats.indisponible) }
        try await verifierSession(context)
        // Aucun SMS pour une révision qui n'est plus celle affichée (le serveur refuserait la signature).
        let actuelle = try await empreinteActuelle(contratId: contratId)
        guard VerificationOriginal.estEmpreinte(empreinte), actuelle == empreinte else {
            return .refuse(code: Self.codeHashChange, message: TextesWeb.SignatureOtp.hashDocumentChange, bloquant: true)
        }
        switch await RPCResponse.appelerMutation(client, Self.rpcEnvoyer, params: ["p_contrat_id": .string(contratId)],
                                                 fallback: MessagesContrats.indisponible, exceptionsMetier: []) {
        case .reponse(let reponse):
            if reponse.success == true, reponse.erreur == nil {
                return .envoye(OtpEnvoye(role: reponse.string("role"), telephoneMasque: reponse.string("telephone_masked"),
                                         expireDansMinutes: reponse.int("expire_dans_minutes"), smsEnvoyes: reponse.int("sms_envoyes"),
                                         smsRestants: reponse.int("sms_restants")))
            }
            let code = reponse.codeErreur
            return .refuse(code: code, message: TextesWeb.SignatureOtp.message(code: code, erreurServeur: reponse.erreur,
                                                                              repli: LibellesWeb.SignatureOtp.repliEnvoi),
                           bloquant: code.map { TextesWeb.SignatureOtp.codesBloquants.contains($0) } ?? false)
        case .refusDefinitif(_, let erreur), .incertain(let erreur):
            // Rollback prouvé ou réponse perdue : affiché, jamais renvoyé ; un nouvel envoi reste un geste explicite.
            throw erreur
        }
    }

    public func signer(contratId: String, code: String, empreinte: String, context: MissionReadContext) async throws -> IssueSignature {
        try MissionQuery.validate(context: context)
        guard ContratRules.identifiantValide(contratId) else { throw JoleneError(.unknown, MessagesContrats.indisponible) }
        // `/^[0-9]{6}$/` (SignerContratOtp.tsx l.166) : refus local, aucune requête.
        guard code.unicodeScalars.count == 6, code.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) else {
            return .refuse(code: nil, message: LibellesWeb.SignatureOtp.codeSixChiffresRequis, tentativesRestantes: nil)
        }
        guard VerificationOriginal.estEmpreinte(empreinte) else {
            return .refuse(code: Self.codeHashChange, message: TextesWeb.SignatureOtp.hashDocumentChange, tentativesRestantes: nil)
        }
        try await verifierSession(context)
        let params: JSONObject = [
            "p_contrat_id": .string(contratId),
            "p_otp_code": .string(code),
            "p_hash_document": .string(empreinte),
            "p_signature_image": .null,
        ]
        switch await RPCResponse.appelerMutation(client, Self.rpcSigner, params: params, fallback: MessagesContrats.indisponible,
                                                 exceptionsMetier: Self.exceptionsSignature) {
        case .reponse(let reponse):
            if reponse.success == true, reponse.erreur == nil {
                guard let complet = try await signatureRelue(contratId: contratId, empreinte: empreinte, context: context) else {
                    throw JoleneError(.unknown, Self.messageSignatureNonConfirmee)
                }
                return .signee(contratComplet: reponse.bool("contrat_complet") ?? complet)
            }
            if reponse.sqlstate != nil {
                return .refuse(code: reponse.code, message: reponse.erreur ?? MessagesContrats.indisponible, tentativesRestantes: nil)
            }
            let codeErreur = reponse.codeErreur
            return .refuse(code: codeErreur, message: TextesWeb.SignatureOtp.message(code: codeErreur, erreurServeur: reponse.erreur,
                                                                                    repli: LibellesWeb.SignatureOtp.repliSignature),
                           tentativesRestantes: reponse.int("tentatives_restantes"))
        case .refusDefinitif(_, let erreur):
            throw erreur
        case .incertain(let erreur):
            // Réponse perdue : la signature a pu être appliquée. Relue, jamais renvoyée. `try?` aplatit `Bool??` :
            // relecture en échec et preuve non confirmée donnent toutes deux `nil` → l'incertain d'origine est restitué.
            if let complet = try? await signatureRelue(contratId: contratId, empreinte: empreinte, context: context) {
                return .signee(contratComplet: complet)
            }
            throw erreur
        }
    }

    // MARK: - Requêtes

    private func lireLigne(id: String, context: MissionReadContext) async throws -> ContratDetail {
        guard ContratRules.identifiantValide(id) else { throw JoleneError(.unknown, MessagesContrats.indisponible) }
        let lignes: [ContratDetail]
        do {
            lignes = try await client.from(Self.table)
                .select(ContratDetail.selection)
                .eq("id", value: id)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesContrats.indisponible)
        }
        guard let ligne = lignes.first(where: { Self.meme($0.id, id) }), Self.meme(ligne.soignantId, context.userId) else {
            throw JoleneError(.unknown, MessagesContrats.indisponible)
        }
        return ligne
    }

    /// Mission du contrat, best-effort (le web l'accepte nulle) ; une session expirée reste propagée.
    private func lireMission(_ missionId: String) async throws -> MissionContrat? {
        do {
            let lignes: [MissionContrat] = try await client.from("missions")
                .select(MissionContrat.selection)
                .eq("id", value: missionId)
                .execute()
                .value
            return lignes.first { $0.id == missionId }
        } catch {
            return try Self.complementIndisponible(error)
        }
    }

    /// Nom par `fn_etablissements_safe` seulement, best-effort.
    private func lireNomEtablissement(_ etablissementId: String?) async throws -> String? {
        guard let etablissementId, !etablissementId.isEmpty else { return nil }
        do {
            return try await SupabaseMissionsGateway(client: client).etablissements(ids: [etablissementId])[etablissementId]?.nom
        } catch {
            return try Self.complementIndisponible(error)
        }
    }

    private struct LigneCompteTest: Decodable {
        let estCompteTest: Bool?
        enum CodingKeys: String, CodingKey { case estCompteTest = "est_compte_test" }
    }

    /// `soignants.est_compte_test` du soignant (`ContratMission.tsx` l.225, l.257-266) : sans relecture, aucun compte
    /// n'est supposé réel (fail-closed : l'écran ne peut pas choisir entre OTP et renvoi web).
    private func lireCompteTest(_ context: MissionReadContext) async throws -> Bool {
        let lignes: [LigneCompteTest]
        do {
            lignes = try await client.from("soignants")
                .select("est_compte_test")
                .eq("id", value: context.userId)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesContrats.indisponible)
        }
        guard let ligne = lignes.first else { throw JoleneError(.unknown, MessagesContrats.indisponible) }
        return ligne.estCompteTest == true
    }

    private struct LigneEmpreinte: Decodable {
        let id: String
        let hashDocument: String?
        enum CodingKeys: String, CodingKey { case id, hashDocument = "hash_document" }
    }

    private func empreinteActuelle(contratId: String) async throws -> String? {
        let lignes: [LigneEmpreinte]
        do {
            lignes = try await client.from(Self.table)
                .select(Self.selectionEmpreinte)
                .eq("id", value: contratId)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesContrats.indisponible)
        }
        guard let ligne = lignes.first(where: { Self.meme($0.id, contratId) }) else {
            throw JoleneError(.unknown, MessagesContrats.indisponible)
        }
        return ligne.hashDocument
    }

    /// Rendu serveur de l'original (corps `{contrat_id}` seulement) : un appel, refus restitué verbatim.
    private func demanderRendu(contratId: String) async throws {
        let options = FunctionInvokeOptions(method: .post, body: ["contrat_id": contratId])
        let reponse: RPCResponse
        do {
            reponse = try await client.functions.invoke(Self.edgeRendu, options: options) { corps, _ in RPCResponse(Self.lire(corps)) }
        } catch FunctionsError.httpError(_, let corps) {
            throw ContratOriginalIndisponible(motif: .renduRefuse(messageServeur: RPCResponse(Self.lire(corps)).erreur))
        } catch FunctionsError.relayError {
            throw ContratOriginalIndisponible(motif: .renduRefuse(messageServeur: nil))
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesContrats.indisponible)
        }
        guard reponse.success == true, reponse.erreur == nil else {
            throw ContratOriginalIndisponible(motif: .renduRefuse(messageServeur: reponse.erreur))
        }
    }

    /// Octets de l'original Storage. Objet absent ou refusé (400/404) : motif d'intégrité ; transport : erreur.
    private func telecharger(_ chemin: String) async throws -> Data {
        do {
            return try await client.storage.from(Self.bucket).download(path: chemin)
        } catch let erreur as StorageError {
            switch erreur.statusCode {
            case "400", "404": throw ContratOriginalIndisponible(motif: .storageMismatch)
            case "401", "403": throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
            default: throw JoleneError(.unknown, MessagesContrats.indisponible)
            }
        } catch let http as HTTPError where [400, 404].contains(http.response.statusCode) {
            throw ContratOriginalIndisponible(motif: .storageMismatch)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesContrats.indisponible)
        }
    }

    /// Preuve relue d'une signature soignant sur `empreinte` : contrat (`signature_soignant`, même `hash_document`) et
    /// ligne `signatures_contrats` du compte (`statut_signature = 'signe'`, même empreinte). `nil` : non confirmée ;
    /// sinon le contrat est-il complet.
    private func signatureRelue(contratId: String, empreinte: String, context: MissionReadContext) async throws -> Bool? {
        let relu = try await lireLigne(id: contratId, context: context)
        guard relu.signatureSoignant == true, relu.hashDocument == empreinte else { return nil }
        let lignes = try await certificat(contratId: contratId, context: context)
        guard lignes.contains(where: {
            $0.signataireRole == "soignant" && Self.meme($0.signataireUserId, context.userId)
                && $0.statutSignature == "signe" && $0.hashDocument == empreinte
        }) else { return nil }
        return relu.statut == "SIGNE_COMPLET" || relu.signatureEtablissement == true
    }

    private func verifierSession(_ context: MissionReadContext) async throws {
        let session: Session
        do {
            session = try await client.auth.session
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: SupabaseErrorMapping.unauthorizedMessage)
        }
        guard Self.meme(session.user.id.uuidString, context.userId) else {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
    }

    // MARK: - Outils

    /// Lecture complémentaire en échec : `nil`, sauf session expirée et annulation, propagées.
    private static func complementIndisponible<T>(_ error: Error) throws -> T? {
        if error is CancellationError { throw error }
        let erreur = SupabaseErrorMapping.map(error, fallback: MessagesContrats.indisponible)
        if erreur.kind == .unauthorized || erreur.kind == .cancelled { throw erreur }
        return nil
    }

    /// Identifiants UUID comparés sans casse (Postgres les rend en minuscules, `UUID.uuidString` en majuscules).
    private static func meme(_ a: String?, _ b: String) -> Bool {
        guard let a else { return false }
        return a.lowercased() == b.lowercased()
    }

    /// Corps JSON tolérant : vide, non JSON (page de passerelle) ou scalaire → `null`.
    static func lire(_ corps: Data) -> AnyJSON {
        (try? JSONDecoder().decode(AnyJSON.self, from: corps)) ?? .null
    }
}
