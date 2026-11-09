import Foundation
import Combine

/// Complétion du profil soignant (lot 3, T8) : port de `src/pages/InscriptionSoignant.tsx` en mode `parcours`
/// (`/inscription/completer`) et de `finaliserProfil` (`src/lib/inscriptionProgressive.ts` l.169-238).
///
/// Règles :
/// - saisie initialisée depuis le brouillon serveur (`parcours.donnees`, liste blanche) ; profession **figée** du
///   parcours (principe « État dérivé ») ; jamais de brouillon local ;
/// - modes proposés : `fn_types_exercice_autorises` (table paramétrée, aucune règle en dur) ; `LIBERAL` retiré quand le
///   référentiel ne le propose pas, conservé tant qu'il est inconnu (jamais ajoutable sans confirmation) ;
/// - « Enregistrer et continuer plus tard » : brouillon relu par le serveur (`fn_enregistrer_parcours_inscription`),
///   puis la vue relit le parcours (le web navigue vers `/inscription/reprendre`) ;
/// - « Enregistrer mon profil » : garde du formulaire web (l.354-357), puis `InscriptionPort.finaliser` (brouillon,
///   `register-soignant`, `refreshSession()`), borné, un seul envoi à la fois, aucun renvoi automatique :
///   - profil créé → rôle relu (`fn_get_my_role`) ; SOIGNANT → `SessionStore.ouvrirIdentiteInscription()` (navigateur
///     intégré vidé, intégration T7 × T3b, puis `start()` : seul `.ready` relu prouve l'espace) ; sinon message web
///     « Votre profil est enregistré. Reconnectez-vous… » ;
///   - refus serveur → message serveur verbatim, saisie conservée, aucune relecture ;
///   - 503 `ACCOUNT_FINALIZATION_PENDING` (ou session non rafraîchie) → message annoncé à la connexion, puis
///     déconnexion locale (`SessionStore.signOutLocally`) ;
///   - issue inconnue (délai, réseau, réponse illisible) → relecture du rôle : un profil créé ouvre l'espace, sinon le
///     texte réseau du web ou « Votre saisie est conservée. Réessayez. » ;
/// - epoch : capturé au premier appel ; une réponse arrivée pour une identité partie est ignorée ; une annulation
///   n'est jamais une erreur. Rien n'est journalisé (identité, téléphone, date de naissance, RPPS).
@MainActor
public final class CompletionProfilModel: ObservableObject {
    public enum Modes: Equatable, Sendable {
        case inactif
        case chargement
        case disponibles([String])
        case indisponible
    }

    /// Issue d'une finalisation, pour la vue.
    public enum Issue: Equatable, Sendable {
        /// Profil créé, rôle soignant relu : l'identité est relue par `SessionStore` (`.ready` = preuve).
        case espaceOuvert
        /// Déconnexion locale faite ; `message` (verbatim serveur ou web) est affiché sur l'écran de connexion.
        case deconnecte(message: String)
    }

    @Published public var prenom: String
    @Published public var nom: String
    @Published public var telephone: String
    /// `AAAA-MM-JJ` ; nil tant que l'utilisateur n'a rien choisi (jamais un défaut écrit en silence).
    @Published public var dateNaissance: String?
    /// Toujours filtré (11 chiffres au plus) ; vide et non transmis quand le champ n'est pas proposé.
    @Published public var rpps: String {
        didSet {
            let filtre = CompletionRules.filtrerRpps(rpps)
            if filtre != rpps { rpps = filtre }
        }
    }
    @Published public private(set) var typesContrat: [String]
    /// Réponse « Êtes-vous actuellement salarié(e)… ? » : affichage seul (avertissement d'exclusivité), jamais transmise
    /// (correction 21).
    @Published public var estSalarieEtablissement: Bool?
    @Published public private(set) var modes: Modes = .inactif
    @Published public private(set) var erreur: String?
    @Published public private(set) var enCours = false
    @Published public private(set) var enregistrementEnCours = false
    /// Un envoi a été tenté (le web n'affiche « La date de naissance est obligatoire » qu'après une tentative, l.555).
    @Published public private(set) var tentative = false
    /// Jeton d'annonce VoiceOver de l'encart d'erreur (`InlineNotice.announcementID`).
    @Published public private(set) var annonces = 0

    public let parcours: ParcoursInscription
    /// Profession du parcours (`parcours.donnees.profession`), lecture seule.
    public let profession: String
    /// Rayon du brouillon (web), retransmis tel quel ; jamais un défaut de l'app (le serveur applique ses 30 km).
    private let rayon: Int?
    private let session: SessionStore
    private let maintenant: @Sendable () -> Date
    private let annoncerDeconnexion: (String) -> Void
    private var epoch: Int?
    private var generationModes = 0

    /// - Parameters:
    ///   - maintenant: horloge de la garde de majorité (tests).
    ///   - annoncerDeconnexion: appelé avec le message AVANT la déconnexion locale (la racine l'affiche à la connexion).
    public init(session: SessionStore, parcours: ParcoursInscription, maintenant: @escaping @Sendable () -> Date = { Date() },
                annoncerDeconnexion: @escaping (String) -> Void = { _ in }) {
        self.session = session
        self.parcours = parcours
        self.maintenant = maintenant
        self.annoncerDeconnexion = annoncerDeconnexion
        let brouillon = parcours.brouillon
        let profession = brouillon.profession ?? ""
        self.profession = profession
        self.prenom = brouillon.prenom ?? ""
        self.nom = brouillon.nom ?? ""
        self.telephone = brouillon.telephone ?? ""
        self.dateNaissance = brouillon.dateNaissance.flatMap { CompletionRules.date($0) == nil ? nil : $0 }
        // `PROFESSIONS_SANS_RPPS` hors AS : numéro vidé (l.203-208).
        self.rpps = CompletionRules.afficheRpps(profession: profession) ? CompletionRules.filtrerRpps(brouillon.rpps ?? "") : ""
        self.typesContrat = brouillon.typesContrat
        self.rayon = brouillon.rayon
    }

    // MARK: - Présentation

    /// La profession du parcours est connue du catalogue : sinon la complétion ne peut pas aboutir (contrat rompu,
    /// `fn_demarrer_inscription` exige une profession soignant).
    public var professionValide: Bool { InscriptionRules.professionConnue(profession) }

    public var typesAutorises: [String]? {
        if case let .disponibles(types) = modes { return types }
        return nil
    }

    public var choixModes: ChoixModesExercice {
        ChoixModesExercice.presenter(valeur: typesContrat, typesAutorises: typesAutorises,
                                     chargement: modes == .chargement, indisponible: modes == .indisponible)
    }

    /// « Réessayer la vérification » (le référentiel peut répondre à une nouvelle lecture).
    public var reessaiModesPossible: Bool { modes == .indisponible }

    /// `uniqueType` : phrase automatique à la place de la question « salarié(e) ».
    public var phraseTypeUnique: String? {
        CompletionRules.typeUnique(typesAutorises).map { CompletionRules.phraseTypeUnique(profession: profession, type: $0) }
    }

    public var afficheRpps: Bool { CompletionRules.afficheRpps(profession: profession) }
    public var rppsObligatoire: Bool { CompletionRules.rppsObligatoire(profession: profession) }

    /// Message sous le téléphone (l.551) : saisie non vide et invalide.
    public var erreurTelephone: String? {
        !telephone.isEmpty && !CompletionRules.telephoneValide(telephone) ? CompletionTextes.telephoneInvalide : nil
    }

    /// Message sous la date (l.555-556).
    public var erreurDateNaissance: String? {
        guard let dateNaissance else { return tentative ? CompletionTextes.dateNaissanceObligatoire : nil }
        return CompletionRules.majeur(dateNaissance: dateNaissance, maintenant: maintenant())
            ? nil : CompletionTextes.dateNaissanceMineur
    }

    /// Saisie transmise : brouillon et `register-soignant` (clés de la liste blanche seulement).
    public var formulaire: FormulaireInscription {
        FormulaireInscription(prenom: prenom, nom: nom, telephone: telephone, dateNaissance: dateNaissance ?? "",
                              profession: profession, typesContrat: typesContrat, rpps: afficheRpps ? rpps : "", rayon: rayon)
    }

    public func basculerMode(_ mode: PreferenceModeExercice, selectionne: Bool) {
        // Inscription : la liste peut être vidée (« Sélectionnez au moins un mode d’exercice. », garde à l'envoi).
        typesContrat = ModesExercice.modifier(typesContrat, mode: mode, selectionne: selectionne)
    }

    // MARK: - Référentiel des modes

    /// Lecture de `fn_types_exercice_autorises` (premier affichage et « Réessayer la vérification »).
    public func verifierModes() async {
        guard !profession.isEmpty else {
            modes = .inactif
            return
        }
        generationModes += 1
        let courant = generationModes
        guard let (gateways, epoch) = await gatewaysCourantes() else { return }
        let port = gateways.inscription
        let profession = self.profession
        modes = .chargement
        do {
            let types = try await bounded(timeout: session.controller.resolutionTimeout) {
                try await port.typesExercice(profession: profession)
            }
            guard await session.controller.epoch == epoch, courant == generationModes else { return }
            modes = types.map(Modes.disponibles) ?? .indisponible
            typesContrat = CompletionRules.contratsApresReferentiel(typesContrat, typesAutorises: types)
        } catch {
            if Self.estAnnulation(error) { return }
            guard await session.controller.epoch == epoch, courant == generationModes else { return }
            modes = .indisponible
        }
    }

    // MARK: - Brouillon

    /// « Enregistrer et continuer plus tard » : vrai quand le brouillon a été relu par le serveur.
    public func enregistrerPlusTard() async -> Bool {
        guard !enCours, !enregistrementEnCours else { return false }
        enregistrementEnCours = true
        defer { enregistrementEnCours = false }
        erreur = nil
        guard let (gateways, epoch) = await gatewaysCourantes() else { return false }
        let port = gateways.inscription
        let saisie = formulaire
        do {
            _ = try await bounded(timeout: session.controller.resolutionTimeout) { try await port.enregistrerBrouillon(saisie) }
            return await session.controller.epoch == epoch
        } catch {
            if Self.estAnnulation(error) { return false }
            guard await session.controller.epoch == epoch else { return false }
            afficher(InscriptionRules.messageErreur(error))
            return false
        }
    }

    // MARK: - Finalisation

    /// « Enregistrer mon profil ». Rend l'issue quand l'identité a été relue ou fermée, nil sinon (message affiché ou
    /// réponse ignorée).
    public func finaliser() async -> Issue? {
        guard !enCours, !enregistrementEnCours, professionValide else { return nil }
        tentative = true
        erreur = nil
        let manques = CompletionRules.manques(prenom: prenom, nom: nom, telephone: telephone, dateNaissance: dateNaissance,
                                              profession: profession, typesContrat: typesContrat,
                                              rpps: afficheRpps ? rpps : "", maintenant: maintenant())
        guard manques.isEmpty else {
            afficher(CompletionRules.messageManques(manques))
            return nil
        }
        enCours = true
        defer { enCours = false }
        guard let (gateways, epoch) = await gatewaysCourantes() else { return nil }
        let port = gateways.inscription
        let saisie = formulaire
        do {
            let resultat = try await bounded(timeout: Self.delaiFinalisation(session.controller.resolutionTimeout)) {
                try await port.finaliser(saisie)
            }
            guard await session.controller.epoch == epoch else { return nil }
            switch resultat {
            case .finalisee:
                return await ouvrirEspace(gateways, epoch: epoch, sinon: CompletionTextes.profilEnregistreReconnecter)
            case .refusee(_, let message):
                afficher(message)
                return nil
            case .finalisationEnAttente(let message):
                annoncerDeconnexion(message)
                await session.signOutLocally()
                return .deconnecte(message: message)
            }
        } catch {
            if Self.estAnnulation(error) { return nil }
            guard await session.controller.epoch == epoch else { return nil }
            if let refus = error as? RefusInscription {
                afficher(refus.message)
                return nil
            }
            if let jolene = error as? JoleneError, jolene.kind == .unauthorized || jolene.kind == .demoOnly {
                afficher(jolene.message)
                return nil
            }
            // Issue inconnue : le profil a pu être créé. Relecture du rôle, jamais un renvoi.
            let message = (error as? JoleneError)?.kind == .network ? InscriptionTextes.connexionInstable
                : CompletionTextes.saisieConservee
            return await ouvrirEspace(gateways, epoch: epoch, sinon: message)
        }
    }

    /// Délai de la finalisation : deux fois la borne d'un appel (brouillon, puis `register-soignant` qui peut interroger
    /// l'Annuaire Santé jusqu'à 10 s, puis `refreshSession`). Un dépassement n'est jamais un échec supposé : relecture.
    public nonisolated static func delaiFinalisation(_ resolutionTimeout: TimeInterval) -> TimeInterval {
        resolutionTimeout * 2
    }

    // MARK: - Interne

    /// Rôle relu : SOIGNANT → identité relue (`.ready` prouve l'espace) ; sinon `message`, saisie conservée.
    private func ouvrirEspace(_ gateways: Gateways, epoch: Int, sinon message: String) async -> Issue? {
        let role = gateways.role
        let relu = try? await bounded(timeout: session.controller.resolutionTimeout) { try await role.currentRole() }
        guard await session.controller.epoch == epoch else { return nil }
        guard relu?.role == UserRole.soignant.rawValue else {
            afficher(message)
            return nil
        }
        await session.ouvrirIdentiteInscription()
        return .espaceOuvert
    }

    private func gatewaysCourantes() async -> (Gateways, Int)? {
        let controller = session.controller
        let courant: Int
        if let epoch {
            courant = epoch
        } else {
            courant = await controller.epoch
            epoch = courant
        }
        guard let gateways = await controller.gateways(for: courant) else { return nil }
        return (gateways, courant)
    }

    private func afficher(_ message: String) {
        erreur = message
        annonces += 1
    }

    private static func estAnnulation(_ error: Error) -> Bool {
        error is CancellationError || (error as? JoleneError)?.kind == .cancelled || Task.isCancelled
    }
}
