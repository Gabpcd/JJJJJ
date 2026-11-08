import Foundation
import JoleneCore
import Supabase

/// Inscription soignant sur GoTrue et PostgREST (lot 3, T7 ; blueprint `LOT3_PLAN.md` §2.3-§2.5, fiches
/// `fn_demarrer_inscription` et « Inscription » de `CONTRATS_RPC_SOIGNANT.md`) :
/// - `creerCompte` : `signUp(email:password:data:redirectTo:captchaToken: nil)` (`inscriptionProgressive.ts` l.69-77),
///   intention dans `user_metadata.inscription_progressive`, lien de confirmation vers
///   `https://jolene.app/inscription/confirmer` ; compte existant détecté comme le web (message GoTrue ou
///   `identities` vide, l.78-94) ; refus GoTrue traduits par `InscriptionRules.refusCreation` (textes web verbatim) ;
///   une session déjà ouverte pour la même adresse évite un second `signUp` (l.56-62) ;
/// - `confirmer` : trois formats (D10) — `token_hash` → `verifyOTP(type: .signup|.email)`, implicit → `setSession`,
///   `code` → `exchangeCodeForSession` (une seule fois : le modèle ne rejoue jamais un lien) ; tout autre type
///   (`recovery`…) est refusé sans appel réseau ; tout échec rend le texte web de `ConfirmationInscription.tsx`
///   l.76-77 (jamais `supabase.auth.handle(url)`) ;
/// - `contexte` : utilisateur relu (`GET /auth/v1/user`), jamais déduit du seul cache ; `parcours` : ligne
///   `parcours_inscription` sous RLS (`parcours_inscription_proprietaire`, `public.sql` l.78274) ;
/// - `demarrer` : `fn_demarrer_inscription` avec `exceptionsMetier` 22023 / 23505 lues avant
///   `SupabaseErrorMapping` (correction 12) ; 42501 « Session invalide. » → session expirée (mapping inchangé) ;
///   la ligne rendue est relue en liste blanche (`OnboardingResolution.parcours`).
/// Complétion et `register-soignant` : tranche T8 ; ces méthodes refusent explicitement d'ici là.
public struct SupabaseInscriptionGateway: InscriptionPort {
    public static let demarrageRPC = "fn_demarrer_inscription"
    public static let tableParcours = "parcours_inscription"
    /// Colonnes du web (`chargerParcours`, `inscriptionProgressive.ts` l.110) plus la preuve du consentement.
    public static let colonnesParcours = "user_id,type_compte,donnees,consentement_cgu_le,modifie_le"
    /// SQLSTATE métier de `fn_demarrer_inscription` (`public.sql` l.30163, l.30167, l.30176).
    public static let exceptionsDemarrage: Set<String> = ["22023", "23505"]

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    private var completion: JoleneError {
        UnwiredPorts.erreur(port: "complétion de l'inscription", tranche: "T8", lot: 3)
    }

    // MARK: - Compte

    public func creerCompte(email: String, motDePasse: String, intention: IntentionInscription) async throws -> ResultatCompte {
        let adresse = InscriptionRules.emailNormalise(email)
        if let existante = client.auth.currentSession?.user.email, InscriptionRules.emailNormalise(existante) == adresse {
            return .sessionOuverte
        }
        let metadonnees = try Self.anyJSON(InscriptionRules.metadonnees(intention))
        do {
            let reponse = try await client.auth.signUp(email: adresse, password: motDePasse,
                                                       data: ["inscription_progressive": metadonnees],
                                                       redirectTo: InscriptionRules.redirectionConfirmation, captchaToken: nil)
            switch reponse {
            case .session:
                return .sessionOuverte
            case .user(let user):
                // Compte existant masqué par GoTrue : utilisateur sans identité (l.81-84).
                return user.identities?.isEmpty == true ? .connexionRequise : .confirmationEnvoyee
            }
        } catch let erreur as AuthError {
            switch erreur {
            case let .api(message, code, _, _):
                if InscriptionRules.estCompteExistant(messageServeur: message) { return .connexionRequise }
                throw InscriptionRules.refusCreation(messageServeur: message, codeServeur: code.rawValue)
            case let .weakPassword(message, _):
                throw InscriptionRules.refusCreation(messageServeur: message, codeServeur: "weak_password")
            default:
                throw SupabaseErrorMapping.map(erreur, fallback: InscriptionTextes.erreurInattendue)
            }
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: InscriptionTextes.erreurInattendue)
        }
    }

    public func confirmer(_ credentials: AuthCallbackCredentials) async throws -> ResultatConfirmation {
        let refus = ResultatConfirmation.lienRefuse(message: InscriptionTextes.lienNonValide)
        do {
            switch credentials {
            case let .tokenHash(tokenHash, otpType):
                guard let type = Self.typeOTP(otpType) else { return refus }
                let reponse = try await client.auth.verifyOTP(tokenHash: tokenHash, type: type)
                guard case .session = reponse else { return refus }
            case let .implicit(accessToken, refreshToken):
                _ = try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
            case let .pkce(code):
                _ = try await client.auth.exchangeCodeForSession(authCode: code)
            }
            return .sessionOuverte
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw JoleneError(.cancelled, SupabaseErrorMapping.cancelledMessage)
            }
            return refus
        }
    }

    /// `type` du lien (`ConfirmationInscription.tsx` l.27 : `signup`, sinon `email`) ; tout autre type est refusé.
    static func typeOTP(_ type: String) -> EmailOTPType? {
        switch type {
        case "signup": return .signup
        case "email": return .email
        default: return nil
        }
    }

    // MARK: - Aiguillage

    public func contexte() async throws -> ContexteOnboarding? {
        guard client.auth.currentSession != nil else { return nil }
        do {
            let user = try await client.auth.user()
            let intention = OnboardingResolution.intention(depuis: Self.valeur(user.userMetadata["inscription_progressive"]))
            return ContexteOnboarding(userId: user.id.uuidString.lowercased(), email: user.email,
                                      emailConfirme: user.emailConfirmedAt != nil, intention: intention)
        } catch AuthError.sessionMissing {
            return nil
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: InscriptionTextes.espaceIndisponible)
        }
    }

    public func parcours(userId: String) async throws -> ParcoursInscription? {
        let lignes: [ValeurJSON]
        do {
            lignes = try await client.from(Self.tableParcours).select(Self.colonnesParcours)
                .eq("user_id", value: userId).limit(1).execute().value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: InscriptionTextes.espaceIndisponible)
        }
        return try OnboardingResolution.parcours(depuis: lignes.first, userId: userId)
    }

    public func demarrer(intention: IntentionInscription) async throws -> ParcoursInscription {
        guard let session = client.auth.currentSession else {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        let texte: (String?) -> AnyJSON = { InscriptionRules.parametreTexte($0).map(AnyJSON.string) ?? .null }
        let params: JSONObject = [
            "p_type_compte": .string(intention.typeCompte),
            "p_profession": texte(intention.profession),
            "p_nom": texte(intention.nom),
            "p_cgu": .bool(intention.cgu),
            "p_cgv": .bool(intention.cgv),
        ]
        let reponse = try await RPCResponse.appeler(client, Self.demarrageRPC, params: params,
                                                    fallback: InscriptionTextes.erreurInattendue,
                                                    exceptionsMetier: Self.exceptionsDemarrage)
        if let sqlstate = reponse.sqlstate {
            throw InscriptionRules.refusDemarrage(sqlstate: sqlstate, messageServeur: reponse.erreur ?? "")
        }
        // La ligne rendue (`to_jsonb(v_parcours)`) est celle de l'utilisateur de la session ; sinon, contrat rompu.
        guard let parcours = try OnboardingResolution.parcours(depuis: Self.valeur(reponse.raw),
                                                               userId: session.user.id.uuidString.lowercased()) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return parcours
    }

    // MARK: - Complétion (T8)

    public func enregistrerBrouillon(_ brouillon: FormulaireInscription) async throws -> ParcoursInscription { throw completion }
    public func typesExercice(profession: String) async throws -> [String]? { throw completion }
    public func finaliser(_ formulaire: FormulaireInscription) async throws -> ResultatFinalisation { throw completion }

    // MARK: - JSON

    static func valeur(_ json: AnyJSON?) -> ValeurJSON? {
        guard let json, let data = try? JSONEncoder().encode(json) else { return nil }
        return try? JSONDecoder().decode(ValeurJSON.self, from: data)
    }

    static func anyJSON(_ valeur: ValeurJSON) throws -> AnyJSON {
        try JSONDecoder().decode(AnyJSON.self, from: JSONEncoder().encode(valeur))
    }
}
