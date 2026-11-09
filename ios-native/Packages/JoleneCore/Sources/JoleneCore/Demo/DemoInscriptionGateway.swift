import Foundation

/// Refus d'inscription simulés en démo (DEBUG) : `-JOLENE_DEMO_INSCRIPTION_REFUS <code>` (blueprint §2.7), codes de
/// `CodeErreurInscription` (`src/lib/erreurs.ts`). T7 : compte existant et captcha (création du compte) ; T8 : codes de
/// `register-soignant` (finalisation) et référentiel des modes indisponible.
public enum RefusInscriptionDemo: String, CaseIterable, Sendable {
    /// GoTrue « User already registered » : la connexion est proposée (`ResultatCompte.connexionRequise`).
    case compteExistant = "USER_ALREADY_REGISTERED"
    /// GoTrue « captcha protection: request disallowed » : message générique, renvoi web (D25).
    case captcha = "CAPTCHA_FAILED"
    /// T8 — `register-soignant` 400 `UNDERAGE` (message serveur verbatim).
    case mineur = "UNDERAGE"
    /// T8 — `register-soignant` 409 `RPPS_ALREADY_REGISTERED` (message serveur verbatim).
    case rppsDejaEnregistre = "RPPS_ALREADY_REGISTERED"
    /// T8 — `register-soignant` 503 `ACCOUNT_FINALIZATION_PENDING` : déconnexion locale puis message serveur.
    case finalisationEnAttente = "ACCOUNT_FINALIZATION_PENDING"
    /// T8 — `fn_types_exercice_autorises` en échec : état « indisponible » du web (aucun référentiel supposé).
    case referentielIndisponible = "TYPES_EXERCICE_INDISPONIBLE"
    /// T8 (revue B8, M1) — `register-soignant` 409 `ACCOUNT_ALREADY_REGISTERED` : le profil existe déjà (créé par une
    /// tentative précédente, ou sur le web) ; issue inconnue, l'espace s'ouvre après relecture du rôle.
    case compteDejaFinalise = "ACCOUNT_ALREADY_REGISTERED"

    public static let argument = "-JOLENE_DEMO_INSCRIPTION_REFUS"

    /// Valeur qui suit l'argument, nil si absente ou inconnue.
    public init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: Self.argument), arguments.indices.contains(index + 1),
              let refus = RefusInscriptionDemo(rawValue: arguments[index + 1]) else { return nil }
        self = refus
    }
}

/// Brouillon serveur simulé au démarrage du parcours démo (DEBUG, `JOLENE_DEMO_BROUILLON=<variante>`, lu par
/// `AppContainer`) : reprise d'une complétion commencée ailleurs (web) pour la recette de T8 sans piloter le sélecteur
/// de date. `complet` : identité du profil démo (Camille Démo, née le 14/05/1990) et un numéro de téléphone fictif ;
/// aucun mode d'exercice coché. `etudiant` (revue B8 de T8, B1) : le même brouillon, déclaré étudiant sur le web
/// (« Je suis étudiant(e) en santé », `estEtudiant: true`) puis « Enregistrer et continuer plus tard ».
public enum VarianteBrouillonDemo: String, Sendable, CaseIterable {
    case complet
    case etudiant

    public static let variableEnvironnement = "JOLENE_DEMO_BROUILLON"

    /// Brouillon de départ pour `profession` (profession de l'intention, figée).
    public func brouillon(profession: String?) -> FormulaireInscription {
        switch self {
        case .complet:
            return FormulaireInscription(prenom: "Camille", nom: "Démo", telephone: "01 99 00 00 01", dateNaissance: "1990-05-14",
                                         profession: profession)
        case .etudiant:
            var brouillon = VarianteBrouillonDemo.complet.brouillon(profession: profession)
            brouillon.estEtudiant = true
            return brouillon
        }
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

    /// `UPDATE parcours_inscription SET donnees = donnees || p_donnees` (fusion de premier niveau, `public.sql`
    /// l.32503-32505) : seules les clés transmises (`CompletionRules.donneesBrouillon`) remplacent les anciennes ; nil
    /// sans parcours (`P0002`). La déclaration étudiant n'est jamais transmise : elle est conservée.
    func enregistrer(_ formulaire: FormulaireInscription) -> ParcoursInscription? {
        guard var ligne = parcours else { return nil }
        var brouillon = ligne.brouillon
        if let prenom = formulaire.prenom { brouillon.prenom = prenom }
        if let nom = formulaire.nom { brouillon.nom = nom }
        if let telephone = formulaire.telephone { brouillon.telephone = telephone }
        if let dateNaissance = formulaire.dateNaissance { brouillon.dateNaissance = dateNaissance }
        if let rpps = formulaire.rpps { brouillon.rpps = rpps }
        if let rayon = formulaire.rayon { brouillon.rayon = rayon }
        if let estSalarie = formulaire.estSalarieEtablissement { brouillon.estSalarieEtablissement = estSalarie }
        brouillon.typesContrat = formulaire.typesContrat
        ligne.brouillon = brouillon
        ligne.modifieLe = DemoInscriptionGateway.horodatage
        parcours = ligne
        return ligne
    }

    /// Fin de l'inscription démo : le compte créé est remplacé par l'espace `demo-soignant` (blueprint §2.7).
    func finaliser() {
        compte = nil
        parcours = nil
    }

    /// `INSERT … ON CONFLICT (user_id) DO NOTHING` puis relecture de la ligne (`public.sql` l.30178-30187).
    func demarrer(_ intention: IntentionInscription, variante: VarianteBrouillonDemo? = nil) -> ParcoursInscription {
        if let parcours { return parcours }
        let brouillon = variante?.brouillon(profession: intention.profession) ?? FormulaireInscription(profession: intention.profession)
        let ligne = ParcoursInscription(userId: DemoInscriptionGateway.nouveauSoignantId, typeCompte: intention.typeCompte,
                                        brouillon: brouillon,
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
/// d'inscription (« Choisissez votre espace… », L3-TJ). Les refus du serveur sont rejoués avec ses messages verbatim ;
/// l'adresse du compte démo existant (`demonstration@example.invalid`) est un compte existant. Complétion (T8) : brouillon
/// fusionné en mémoire, modes d'exercice lus dans `demo-types-exercice.json` (seed versionné de
/// `regles_exercice_profession`), finalisation simulée avec les contrôles et les messages verbatim de
/// `register-soignant`, puis bascule vers l'espace `demo-soignant` (blueprint §2.7 : les autres gateways démo ne
/// servent que lui).
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

    /// Refus de `fn_enregistrer_parcours_inscription` (P0002) et de `register-soignant` (T8), verbatim serveur.
    // source: supabase/schema/public.sql:32505
    static let refusInscriptionIntrouvable = "Inscription introuvable."
    // source: supabase/functions/register-soignant/index.ts:237
    static let refusChampsManquants = "Champs obligatoires manquants (prénom, nom, profession)."
    // source: supabase/functions/register-soignant/index.ts:241
    static let refusDateNaissance = "Date de naissance requise."
    // source: supabase/functions/register-soignant/index.ts:252
    static let refusMineur = "Vous devez avoir au moins 18 ans pour vous inscrire."
    // source: supabase/functions/register-soignant/index.ts:266
    static let refusRppsFormat = "Numéro RPPS invalide (11 chiffres attendus)."
    // source: supabase/functions/register-soignant/index.ts:270
    static let refusRppsRequis = "Le numéro RPPS est obligatoire pour votre profession (11 chiffres)."
    // source: supabase/functions/register-soignant/index.ts:328
    static let refusRppsDejaEnregistre = "Ce numéro RPPS est déjà associé à un compte Jolene. Connectez-vous à ce compte, ou contactez le support si ce n'est pas vous."
    // source: supabase/functions/register-soignant/index.ts:367
    static let refusFinalisationEnAttente = "Votre profil est enregistré. Reconnectez-vous pour reprendre votre espace."
    /// 409 `ACCOUNT_ALREADY_REGISTERED` (revue B8 de T8, M1) : repli affiché seulement si l'espace n'est pas relu.
    // source: supabase/functions/register-soignant/index.ts:208
    static let refusCompteDejaFinalise = "Ce compte soignant existe déjà. Connectez-vous pour continuer."

    /// Défaut serveur d'une profession absente du référentiel (`COALESCE`, `fn_types_exercice_autorises`).
    static let typesParDefaut = ["SALARIE", "LIBERAL", "MIXTE"]

    private let session: DemoSessionStore
    private let comptes: DemoComptesInscription
    private let refus: RefusInscriptionDemo?
    private let variante: VarianteBrouillonDemo?

    /// Partage la session et les comptes de `auth` : la connexion par mot de passe retrouve le compte créé.
    /// `brouillon` (T8, DEBUG) : brouillon serveur simulé au démarrage du parcours.
    public init(auth: DemoAuthGateway, refus: RefusInscriptionDemo? = nil, brouillon: VarianteBrouillonDemo? = nil) {
        self.session = auth.store
        self.comptes = auth.comptes
        self.refus = refus
        self.variante = brouillon
    }

    static func utilisateur(email: String) -> AuthenticatedUser {
        AuthenticatedUser(id: nouveauSoignantId, email: email, emailConfirmedAt: DemoWorld.fixedNow)
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
        case .mineur?, .rppsDejaEnregistre?, .finalisationEnAttente?, .referentielIndisponible?, .compteDejaFinalise?, nil:
            break // refus de la complétion (T8), sans effet sur la création du compte
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
        return await comptes.demarrer(intention, variante: variante)
    }

    // MARK: - Complétion (T8)

    /// `fn_enregistrer_parcours_inscription` simulée : fusion des clés transmises, puis ligne relue.
    public func enregistrerBrouillon(_ brouillon: FormulaireInscription) async throws -> ParcoursInscription {
        try await verifierNouveauCompte(nil)
        guard let relu = await comptes.enregistrer(brouillon) else {
            throw RefusInscription(code: "SQLSTATE_P0002", message: Self.refusInscriptionIntrouvable)
        }
        return relu
    }

    /// Référentiel public (GRANT `anon`) : servi quelle que soit l'identité démo (édition du profil comprise).
    public func typesExercice(profession: String) async throws -> [String]? {
        if refus == .referentielIndisponible { throw JoleneError(.network, SessionController.timeoutMessage) }
        let fichier: DemoFixtures.TypesExerciceFile = try DemoFixtures.load("demo-types-exercice")
        return fichier.typesExercice[profession] ?? Self.typesParDefaut
    }

    /// `register-soignant` simulée : brouillon d'abord (comme `finaliserProfil`), verrou du parcours étudiant sur le
    /// brouillon relu (D11, comme `SupabaseInscriptionGateway`), refus scripté, contrôles serveur (l.235-271, messages
    /// verbatim), puis bascule relue vers l'espace `demo-soignant`.
    public func finaliser(_ formulaire: FormulaireInscription) async throws -> ResultatFinalisation {
        let relu = try await enregistrerBrouillon(formulaire)
        if CompletionRules.parcoursEtudiant(relu.brouillon) { return .parcoursEtudiant }
        switch refus {
        case .mineur?: return .refusee(code: "UNDERAGE", message: Self.refusMineur)
        case .rppsDejaEnregistre?: return .refusee(code: "RPPS_ALREADY_REGISTERED", message: Self.refusRppsDejaEnregistre)
        case .finalisationEnAttente?: return .finalisationEnAttente(message: Self.refusFinalisationEnAttente)
        case .compteDejaFinalise?:
            // Profil déjà créé par une tentative précédente : l'espace existe, la réponse est une issue inconnue.
            try await basculerVersLEspaceDemo()
            return .indeterminee(message: Self.refusCompteDejaFinalise)
        case .compteExistant?, .captcha?, .referentielIndisponible?, nil: break
        }
        let profession = formulaire.profession ?? ""
        let rpps = formulaire.rpps ?? ""
        if (formulaire.prenom ?? "").isEmpty || (formulaire.nom ?? "").isEmpty || profession.isEmpty {
            return .refusee(code: "MISSING_REQUIRED_FIELDS", message: Self.refusChampsManquants)
        }
        if (formulaire.dateNaissance ?? "").isEmpty {
            return .refusee(code: "MISSING_REQUIRED_FIELDS", message: Self.refusDateNaissance)
        }
        if !rpps.isEmpty && (rpps.count != 11 || CompletionRules.filtrerRpps(rpps) != rpps) {
            return .refusee(code: "RPPS_FORMAT_INVALID", message: Self.refusRppsFormat)
        }
        if ProfessionsRpps.exigeRpps(profession) && rpps.isEmpty {
            return .refusee(code: "RPPS_FORMAT_INVALID", message: Self.refusRppsRequis)
        }
        try await basculerVersLEspaceDemo()
        return .finalisee(soignantId: DemoWorld.context.userId)
    }

    /// Fin de l'inscription démo : le nouveau compte devient l'espace `demo-soignant`, session relue.
    private func basculerVersLEspaceDemo() async throws {
        await comptes.finaliser()
        await session.set(DemoWorld.user)
        // Relecture après mutation : aucune session supposée.
        guard await session.current() == DemoWorld.user else {
            throw JoleneError(.unknown, CompletionTextes.saisieConservee)
        }
    }

    /// La démo ne sert que son nouveau compte : tout autre identifiant est refusé (`.demoOnly`).
    private func verifierNouveauCompte(_ userId: String?) async throws {
        guard let user = await session.current(), user.id == Self.nouveauSoignantId,
              userId == nil || userId == user.id else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}
