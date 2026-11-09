import Foundation

/// Refus d'inscription simulés en démo (DEBUG) : `-JOLENE_DEMO_INSCRIPTION_REFUS <code>` (blueprint §2.7), codes de
/// `CodeErreurInscription` (`src/lib/erreurs.ts`). T7 : compte existant et captcha ; T8 ajoute les codes de
/// `register-soignant` (`UNDERAGE`, 409…).
public enum RefusInscriptionDemo: String, CaseIterable, Sendable {
    /// GoTrue « User already registered » : la connexion est proposée (`ResultatCompte.connexionRequise`).
    case compteExistant = "USER_ALREADY_REGISTERED"
    /// GoTrue « captcha protection: request disallowed » : message générique, renvoi web (D25).
    case captcha = "CAPTCHA_FAILED"

    public static let argument = "-JOLENE_DEMO_INSCRIPTION_REFUS"

    /// Valeur qui suit l'argument, nil si absente ou inconnue.
    public init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: Self.argument), arguments.indices.contains(index + 1),
              let refus = RefusInscriptionDemo(rawValue: arguments[index + 1]) else { return nil }
        self = refus
    }
}

/// Comptes créés pendant un lancement démo (mémoire vive, jamais persistés), partagés entre
/// `DemoInscriptionGateway` (création, confirmation, parcours) et `DemoAuthGateway` (connexion par mot de passe).
actor DemoComptesInscription {
    /// Compte créé ou confirmé pendant ce lancement ; `intention` nil : compte confirmé sans intention d'inscription
    /// (`DemoInscriptionGateway.tokenHashSansIntention`).
    private var compte: (email: String, intention: IntentionInscription?)?
    private var parcours: ParcoursInscription?

    func creer(email: String, intention: IntentionInscription) {
        compte = (email, intention)
        parcours = nil
    }

    /// Utilisateur du compte créé, si `email` est le sien. En démo, aucun e-mail n'est envoyé : la confirmation
    /// est réputée faite (`email_confirmed_at` posé), pour que « J’ai confirmé mon email » mène à l'aiguillage.
    func utilisateur(email: String) -> AuthenticatedUser? {
        guard let compte, compte.email == InscriptionRules.emailNormalise(email) else { return nil }
        return DemoInscriptionGateway.utilisateur(email: compte.email)
    }

    /// Lien de confirmation démo : le compte créé, ou un compte par défaut (IDE, CGU acceptées) si aucun ne l'est.
    func utilisateurConfirme() -> AuthenticatedUser {
        if compte == nil {
            compte = (DemoInscriptionGateway.emailParDefaut, InscriptionRules.intention(profession: "IDE", cgu: true))
        }
        return DemoInscriptionGateway.utilisateur(email: compte?.email ?? DemoInscriptionGateway.emailParDefaut)
    }

    /// Lien de confirmation démo « sans intention » : compte par défaut confirmé **sans** `inscription_progressive`
    /// valide ni parcours (compte créé hors de l'inscription progressive). L'aiguillage propose alors « Choisissez votre
    /// espace… » (`OnboardingResolution.Etape.choixEspace`), puis « Je suis soignant » en session ouverte (revue
    /// fraîche B8 de L3-TJ : cas de la décision TJ3 couvert par `DemoInscriptionTests`).
    func utilisateurConfirmeSansIntention() -> AuthenticatedUser {
        compte = (DemoInscriptionGateway.emailParDefaut, nil)
        parcours = nil
        return DemoInscriptionGateway.utilisateur(email: DemoInscriptionGateway.emailParDefaut)
    }

    func intention() -> IntentionInscription? { compte?.intention ?? nil }

    func parcoursCourant() -> ParcoursInscription? { parcours }

    /// `INSERT … ON CONFLICT (user_id) DO NOTHING` puis relecture de la ligne (`public.sql` l.30178-30187).
    func demarrer(_ intention: IntentionInscription) -> ParcoursInscription {
        if let parcours { return parcours }
        let ligne = ParcoursInscription(userId: DemoInscriptionGateway.nouveauSoignantId, typeCompte: intention.typeCompte,
                                        brouillon: FormulaireInscription(profession: intention.profession),
                                        consentementCguLe: DemoInscriptionGateway.horodatage,
                                        modifieLe: DemoInscriptionGateway.horodatage)
        parcours = ligne
        return ligne
    }
}

/// Inscription du monde démo (lot 3, T7 ; blueprint §2.7), sans réseau : « Créer un compte » envoie un lien de
/// confirmation fictif ; `token_hash=demo` (`-JOLENE_OPEN_URL https://jolene.app/inscription/confirmer?token_hash=demo&type=signup`,
/// coordinateur de L1-T10) ou « J’ai confirmé mon email » ouvrent l'identité `demo-nouveau-soignant`, sans profil
/// soignant (aiguillage d'onboarding) ; `token_hash=demo-sans-intention` ouvre la même identité sans intention
/// d'inscription (« Choisissez votre espace… »). Les refus du serveur sont rejoués avec ses messages verbatim ; l'adresse du
/// compte démo existant (`demonstration@example.invalid`) est un compte existant. La complétion et
/// `register-soignant` (brouillon, modes d'exercice, finalisation) sont livrés par T8 : ces méthodes refusent
/// explicitement (`.contract`, « …livré par la tranche T8 du lot 3 »), comme le stub non câblé.
public struct DemoInscriptionGateway: InscriptionPort {
    public static let nouveauSoignantId = "demo-nouveau-soignant"
    /// `token_hash` du lien de confirmation démo.
    public static let tokenHashDemo = "demo"
    /// `token_hash` du lien de confirmation démo d'un compte sans intention d'inscription ni parcours (revue fraîche B8
    /// de L3-TJ) : aiguillage « Choisissez votre espace… », formulaire « Je suis soignant » en session ouverte.
    public static let tokenHashSansIntention = "demo-sans-intention"
    static let emailParDefaut = "nouveau-soignant@example.invalid"
    /// Horloge du monde démo (`fixed_now` des fixtures).
    static let horodatage = "2026-11-02T00:00:00+00:00"

    /// Refus de `fn_demarrer_inscription` (22023), verbatim serveur.
    // source: supabase/schema/public.sql:30163
    static let refusTypeOuConditions = "Vérifiez le type de compte et les conditions acceptées."
    // source: supabase/schema/public.sql:30167
    static let refusProfession = "Choisissez votre profession."

    private let session: DemoSessionStore
    private let comptes: DemoComptesInscription
    private let refus: RefusInscriptionDemo?

    /// Partage la session et les comptes de `auth` : la connexion par mot de passe retrouve le compte créé.
    public init(auth: DemoAuthGateway, refus: RefusInscriptionDemo? = nil) {
        self.session = auth.store
        self.comptes = auth.comptes
        self.refus = refus
    }

    static func utilisateur(email: String) -> AuthenticatedUser {
        AuthenticatedUser(id: nouveauSoignantId, email: email, emailConfirmedAt: DemoWorld.fixedNow)
    }

    private var completion: JoleneError {
        UnwiredPorts.erreur(port: "complétion de l'inscription", tranche: "T8", lot: 3)
    }

    public func creerCompte(email: String, motDePasse: String, intention: IntentionInscription) async throws -> ResultatCompte {
        let adresse = InscriptionRules.emailNormalise(email)
        guard !adresse.isEmpty, !motDePasse.isEmpty else {
            throw JoleneError(.invalidCredentials, "Saisissez votre email et votre mot de passe.")
        }
        if adresse == DemoWorld.context.email { return .connexionRequise }
        switch refus {
        case .compteExistant?:
            return .connexionRequise
        case .captcha?:
            throw InscriptionRules.refusCreation(messageServeur: "captcha protection: request disallowed (invalid-input-response)",
                                                 codeServeur: "captcha_failed")
        case nil:
            break
        }
        await comptes.creer(email: adresse, intention: intention)
        return .confirmationEnvoyee
    }

    public func confirmer(_ credentials: AuthCallbackCredentials) async throws -> ResultatConfirmation {
        guard case let .tokenHash(tokenHash, otpType) = credentials,
              tokenHash == Self.tokenHashDemo || tokenHash == Self.tokenHashSansIntention,
              otpType == "signup" || otpType == "email" else {
            return .lienRefuse(message: InscriptionTextes.lienNonValide)
        }
        let user = tokenHash == Self.tokenHashSansIntention
            ? await comptes.utilisateurConfirmeSansIntention() : await comptes.utilisateurConfirme()
        await session.set(user)
        // Relecture après mutation : aucune session supposée.
        guard await session.current() == user else { return .lienRefuse(message: InscriptionTextes.lienNonValide) }
        return .sessionOuverte
    }

    public func contexte() async throws -> ContexteOnboarding? {
        guard let user = await session.current() else { return nil }
        let intention = user.id == Self.nouveauSoignantId ? await comptes.intention() : nil
        return ContexteOnboarding(userId: user.id, email: user.email, emailConfirme: user.emailConfirmedAt != nil,
                                  intention: intention)
    }

    public func parcours(userId: String) async throws -> ParcoursInscription? {
        try await verifierNouveauCompte(userId)
        return await comptes.parcoursCourant()
    }

    public func demarrer(intention: IntentionInscription) async throws -> ParcoursInscription {
        try await verifierNouveauCompte(nil)
        guard OnboardingResolution.typesCompte.contains(intention.typeCompte), intention.cgu,
              intention.typeCompte != "ETABLISSEMENT" || intention.cgv else {
            throw RefusInscription(code: "SQLSTATE_22023", message: Self.refusTypeOuConditions)
        }
        if intention.typeCompte == UserRole.soignant.rawValue,
           !InscriptionRules.professionConnue(intention.profession ?? "") {
            throw RefusInscription(code: "SQLSTATE_22023", message: Self.refusProfession)
        }
        return await comptes.demarrer(intention)
    }

    public func enregistrerBrouillon(_ brouillon: FormulaireInscription) async throws -> ParcoursInscription { throw completion }
    public func typesExercice(profession: String) async throws -> [String]? { throw completion }
    public func finaliser(_ formulaire: FormulaireInscription) async throws -> ResultatFinalisation { throw completion }
    /// T8 passe à `true` avec les trois appels ci-dessus (intégration du lot 3, T7 × T9).
    public var completionLivree: Bool { false }

    /// La démo ne sert que son nouveau compte : tout autre identifiant est refusé (`.demoOnly`).
    private func verifierNouveauCompte(_ userId: String?) async throws {
        guard let user = await session.current(), user.id == Self.nouveauSoignantId,
              userId == nil || userId == user.id else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}
