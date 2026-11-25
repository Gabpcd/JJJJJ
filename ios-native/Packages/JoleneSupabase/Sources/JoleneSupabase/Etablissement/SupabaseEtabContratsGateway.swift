import Foundation
import JoleneCore
import Supabase

/// `ContratsPort` de l'espace établissement sur Supabase (lot 5, T10 ; `LOT5_PLAN.md` §3 T10, D18 ; fiches
/// `fn_envoyer_otp_signature` et `fn_signer_contrat_otp` de `CONTRATS_RPC_SOIGNANT.md` et
/// `CONTRATS_RPC_ETABLISSEMENT.md`). Extension additive du gateway du lot 2 : mêmes RPC, mêmes clés, même triple
/// contrôle de l'original, sous le JWT du membre et l'établissement **confirmé** du contexte (jamais `user.id`).
///
/// - Aucun appel sans contexte cohérent et permission `contrats` servie (`ContratsEtablissement.verifier`, fail-closed) ;
///   le serveur reste l'autorité (`NON_AUTORISE` de `fn_envoyer_otp_signature` / `fn_signer_contrat_otp`).
/// - Liste : `contrats_mission` `eq('etablissement_id', etab)` (`ListeContrats.tsx` l.65-71), sous RLS
///   `lecture_contrats` ; une ligne d'un autre établissement est écartée (défense en profondeur).
/// - Détail : ligne de l'établissement seulement ; compte TEST relu sur `etablissements.est_compte_test`
///   (`ContratMission.tsx` l.233-237, l.257-266 ; fail-closed) ; ni mission (montants, D15) ni nom relus.
/// - OTP : le SMS part au `telephone_contact` de l'établissement (serveur, l.33584-33587) ; seul le numéro masqué
///   servi revient (`telephone_masked`). Aucun SMS ni signature si la révision affichée n'est plus celle du serveur.
/// - Signature : annoncée seulement après relecture du contrat (`signature_etablissement` vrai,
///   `signature_etablissement_le` non nul, même `hash_document`) **et** de la preuve `signatures_contrats` du membre
///   (`signataire_role = 'etablissement'`, `statut_signature = 'signe'`, même empreinte).
extension SupabaseContratsGateway {
    static let tableEtablissements = "etablissements"

    public func contratsEtablissement(context: EtablissementReadContext) async throws -> [ContratResume] {
        try ContratsEtablissement.verifier(context)
        let lignes: [ContratResume]
        do {
            lignes = try await client.from(Self.table)
                .select(ContratResume.selection)
                .eq("etablissement_id", value: context.etablissementId)
                .order("cree_le", ascending: false, nullsFirst: true)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesContrats.indisponible)
        }
        return lignes.filter { Self.meme($0.etablissementId, context.etablissementId) }
    }

    public func contrat(id: String, etab: EtablissementReadContext) async throws -> ContratDetail {
        try ContratsEtablissement.verifier(etab)
        var detail = try await lireLigneEtablissement(id: id, context: etab)
        detail.estCompteTest = try await lireCompteTestEtablissement(etab)
        return detail
    }

    public func original(contrat: ContratDetail, etab: EtablissementReadContext) async throws -> OriginalContrat {
        try ContratsEtablissement.verifier(etab)
        guard ContratRules.identifiantValide(contrat.id), Self.meme(contrat.etablissementId, etab.etablissementId) else {
            throw JoleneError(.unknown, MessagesContrats.indisponible)
        }
        if ContratRules.cddSansOriginal(contrat) { throw ContratOriginalIndisponible(motif: .cddAPreparer) }
        var courant = contrat
        if ContratRules.renduServeurADemander(contrat) {
            try await demanderRendu(contratId: contrat.id)
            courant = try await lireLigneEtablissement(id: contrat.id, context: etab)
        }
        if let motif = VerificationOriginal.motifAvantStorage(courant) { throw ContratOriginalIndisponible(motif: motif) }
        let octets = try await telecharger(courant.storagePath ?? "")
        let signatures = try await certificat(contratId: courant.id, etab: etab)
        return try VerificationOriginal.verifier(courant, octetsStorage: octets, signatures: signatures)
    }

    public func certificat(contratId: String, etab: EtablissementReadContext) async throws -> [SignatureCertificat] {
        try ContratsEtablissement.verifier(etab)
        guard ContratRules.identifiantValide(contratId) else { throw JoleneError(.unknown, MessagesContrats.indisponible) }
        let lignes: [SignatureCertificat]
        do {
            lignes = try await client.from(Self.tableSignatures)
                .select(SignatureCertificat.selection)
                .eq("contrat_id", value: contratId)
                .order("cree_le", ascending: true)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesContrats.indisponible)
        }
        return lignes.filter { Self.meme($0.contratId, contratId) }
    }

    public func fichierOriginal(contrat: OriginalContrat, etab: EtablissementReadContext) async throws -> URL {
        try ContratsEtablissement.verifier(etab)
        return try FichierContratTemporaire.ecrire(contrat)
    }

    public func admissionRecette(contratId: String, etab: EtablissementReadContext) async throws -> AdmissionSignatureRecette? {
        try ContratsEtablissement.verifier(etab)
        let client = client
        return await AdmissionRecette.lire(projet: projet, contratId: contratId, maintenant: clock.now()) { id in
            try await client.rpc(Self.rpcAdmission, params: ["p_contrat_id": id]).execute().value
        }
    }

    // MARK: - OTP

    public func envoyerOtp(contratId: String, empreinte: String, etab: EtablissementReadContext) async throws -> IssueEnvoiOtp {
        try ContratsEtablissement.verifier(etab)
        guard ContratRules.identifiantValide(contratId) else { throw JoleneError(.unknown, MessagesContrats.indisponible) }
        try await verifierSession(userId: etab.userId)
        let actuelle = try await empreinteActuelle(contratId: contratId)
        guard VerificationOriginal.estEmpreinte(empreinte), actuelle == empreinte else {
            return ContratsEtablissement.refusEnvoiOriginalChange
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
            throw erreur
        }
    }

    public func signer(contratId: String, code: String, empreinte: String,
                       etab: EtablissementReadContext) async throws -> IssueSignature {
        try ContratsEtablissement.verifier(etab)
        guard ContratRules.identifiantValide(contratId) else { throw JoleneError(.unknown, MessagesContrats.indisponible) }
        guard code.unicodeScalars.count == 6, code.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) else {
            return .refuse(code: nil, message: LibellesWeb.SignatureOtp.codeSixChiffresRequis, tentativesRestantes: nil)
        }
        guard VerificationOriginal.estEmpreinte(empreinte) else { return ContratsEtablissement.refusSignatureOriginalChange }
        try await verifierSession(userId: etab.userId)
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
                guard let complet = try await signatureEtablissementRelue(contratId: contratId, empreinte: empreinte, context: etab) else {
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
            // Réponse perdue : relue, jamais renvoyée.
            if let complet = try? await signatureEtablissementRelue(contratId: contratId, empreinte: empreinte, context: etab) {
                return .signee(contratComplet: complet)
            }
            throw erreur
        }
    }

    // MARK: - Requêtes

    private func lireLigneEtablissement(id: String, context: EtablissementReadContext) async throws -> ContratDetail {
        guard ContratRules.identifiantValide(id) else { throw JoleneError(.unknown, MessagesContrats.indisponible) }
        let lignes: [ContratDetail]
        do {
            lignes = try await client.from(Self.table)
                .select(ContratDetail.selection)
                .eq("id", value: id)
                .eq("etablissement_id", value: context.etablissementId)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesContrats.indisponible)
        }
        guard let ligne = lignes.first(where: { Self.meme($0.id, id) }),
              Self.meme(ligne.etablissementId, context.etablissementId) else {
            throw JoleneError(.unknown, MessagesContrats.indisponible)
        }
        return ligne
    }

    private struct LigneCompteTestEtablissement: Decodable {
        let id: String
        let estCompteTest: Bool?
        enum CodingKeys: String, CodingKey { case id, estCompteTest = "est_compte_test" }
    }

    /// `etablissements.est_compte_test` de l'établissement confirmé (web l.233-237) : sans relecture, aucun compte n'est
    /// supposé réel (fail-closed).
    private func lireCompteTestEtablissement(_ context: EtablissementReadContext) async throws -> Bool {
        let lignes: [LigneCompteTestEtablissement]
        do {
            lignes = try await client.from(Self.tableEtablissements)
                .select("id,est_compte_test")
                .eq("id", value: context.etablissementId)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MessagesContrats.indisponible)
        }
        guard let ligne = lignes.first(where: { Self.meme($0.id, context.etablissementId) }) else {
            throw JoleneError(.unknown, MessagesContrats.indisponible)
        }
        return ligne.estCompteTest == true
    }

    /// Preuve relue d'une signature de l'établissement sur `empreinte`. `nil` : non confirmée ; sinon contrat complet.
    private func signatureEtablissementRelue(contratId: String, empreinte: String,
                                             context: EtablissementReadContext) async throws -> Bool? {
        let relu = try await lireLigneEtablissement(id: contratId, context: context)
        guard relu.signatureEtablissement == true, !(relu.signatureEtablissementLe ?? "").isEmpty,
              relu.hashDocument == empreinte else { return nil }
        let lignes = try await certificat(contratId: contratId, etab: context)
        guard lignes.contains(where: {
            $0.signataireRole == PartieContrat.etablissement.rawValue && Self.meme($0.signataireUserId, context.userId)
                && $0.statutSignature == "signe" && $0.hashDocument == empreinte
        }) else { return nil }
        return relu.statut == "SIGNE_COMPLET" || relu.signatureSoignant == true
    }
}
