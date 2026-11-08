import Foundation
import Combine

// Modèles des écrans d'inscription (lot 3, T7) : compte rapide, lien de confirmation, aiguillage d'onboarding.
// Le port d'inscription est pris dans les gateways de l'epoch courant (`controller.gateways(for:)`) ; chaque appel
// est borné à `SessionController.resolutionTimeout` ; une réponse arrivée après un changement d'identité est
// ignorée ; une annulation (vue qui disparaît) n'est jamais une erreur. Aucune mutation n'est renvoyée d'office :
// une création de compte dont l'issue est inconnue (délai, réseau) affiche le texte réseau du web et attend un
// nouvel appui (PRINCIPES §3-§4). Le mot de passe ne quitte le modèle que vers le port ou `SessionStore.signIn`,
// sans être conservé ni journalisé.

// MARK: - Compte rapide

/// « Créer un compte » soignant : port de `src/pages/InscriptionRapide.tsx` (submit l.55-115) et de
/// `creerCompteRapide` (`src/lib/inscriptionProgressive.ts` l.41-99).
@MainActor
public final class InscriptionRapideModel: ObservableObject {
    public enum Mode: Equatable, Sendable {
        /// Depuis l'écran de connexion : création du compte GoTrue (`signUp`).
        case nouveauCompte
        /// Depuis l'aiguillage d'onboarding (« Je suis soignant ») : la session est ouverte, seul le parcours est
        /// démarré (`creerCompteRapide` l.56-62 : session existante de même email → `demarrerParcours`).
        case sessionOuverte(email: String?)
    }

    /// Étape du bouton principal (l.346-352).
    public enum Etape: Equatable, Sendable {
        case saisie
        /// Lien de confirmation envoyé : le bouton devient « J’ai confirmé mon email » (connexion par mot de passe).
        case confirmationEnvoyee
        /// Compte existant : « Se connecter et continuer » (connexion par mot de passe).
        case connexionRequise
    }

    /// Suite à donner par la racine de session.
    public enum Issue: Equatable, Sendable {
        /// Connexion par mot de passe (l.63-68) : `SessionStore.signIn`, puis aiguillage selon l'espace relu.
        case connexion(email: String, motDePasse: String)
        /// Session ouverte et parcours démarré (`fn_demarrer_inscription`) : `SessionStore.start()`.
        case parcoursDemarre
    }

    public let mode: Mode
    /// Changer l'email efface l'étape (web l.165-169 : `setConfirmation(false)`, `setConnexionCompte(false)`).
    @Published public var email: String {
        didSet { if email != oldValue { etape = .saisie } }
    }
    @Published public var motDePasse = ""
    @Published public var profession: String
    @Published public var cgu = false
    @Published public private(set) var erreurs: [ChampInscription: String] = [:]
    @Published public private(set) var erreurService: String?
    /// Le refus est un refus captcha (D25) : la vue propose l'inscription web si le présentateur `.safari` existe.
    @Published public private(set) var refusCaptcha = false
    @Published public private(set) var etape: Etape = .saisie
    @Published public private(set) var enCours = false
    /// Premier champ en erreur après une validation refusée (focus, web l.76), remis à nil par la vue.
    @Published public var champAFocaliser: ChampInscription?

    private let controller: SessionController

    public init(controller: SessionController, mode: Mode = .nouveauCompte, profession: String = "") {
        self.controller = controller
        self.mode = mode
        self.profession = profession
        if case .sessionOuverte(let email) = mode { self.email = email ?? "" } else { self.email = "" }
    }

    public var saisitIdentifiants: Bool { mode == .nouveauCompte }

    /// Libellé du bouton principal, verbatim l.346-352.
    public var libelleBouton: String {
        if enCours { return InscriptionTextes.creationEnCours }
        switch etape {
        case .connexionRequise: return InscriptionTextes.seConnecterEtContinuer
        case .confirmationEnvoyee: return InscriptionTextes.jaiConfirme
        case .saisie: return InscriptionTextes.creerMonCompte
        }
    }

    /// Envoi du formulaire : validation (l.58-78), puis création, démarrage ou connexion. Un seul envoi à la fois.
    public func soumettre() async -> Issue? {
        guard !enCours else { return nil }
        let refusSaisie = InscriptionRules.erreurs(email: email, motDePasse: motDePasse, profession: profession, cgu: cgu,
                                                   avecIdentifiants: saisitIdentifiants)
        erreurs = refusSaisie
        erreurService = nil
        refusCaptcha = false
        if let premier = InscriptionRules.premierChampEnErreur(refusSaisie) {
            champAFocaliser = premier
            return nil
        }
        let emailEnvoye = InscriptionRules.emailNormalise(email)
        if saisitIdentifiants, etape != .saisie {
            // `confirmation || connexionCompte` (l.83) : jamais un second `signUp`, une connexion par mot de passe.
            return .connexion(email: emailEnvoye, motDePasse: motDePasse)
        }
        enCours = true
        defer { enCours = false }
        let epoch = await controller.epoch
        guard let gateways = await controller.gateways(for: epoch) else { return nil }
        let port = gateways.inscription
        let delai = controller.resolutionTimeout
        let intention = InscriptionRules.intention(profession: profession, cgu: cgu)
        do {
            if !saisitIdentifiants {
                _ = try await bounded(timeout: delai) { try await port.demarrer(intention: intention) }
                return await controller.epoch == epoch ? .parcoursDemarre : nil
            }
            let secret = motDePasse
            let resultat = try await bounded(timeout: delai) {
                try await port.creerCompte(email: emailEnvoye, motDePasse: secret, intention: intention)
            }
            guard await controller.epoch == epoch else { return nil }
            switch resultat {
            case .confirmationEnvoyee:
                etape = .confirmationEnvoyee
                return nil
            case .connexionRequise:
                etape = .connexionRequise
                erreurService = InscriptionTextes.compteExistant
                return nil
            case .sessionOuverte:
                _ = try await bounded(timeout: delai) { try await port.demarrer(intention: intention) }
                guard await controller.epoch == epoch else { return nil }
                motDePasse = ""
                return .parcoursDemarre
            }
        } catch {
            if error is CancellationError || (error as? JoleneError)?.kind == .cancelled || Task.isCancelled { return nil }
            guard await controller.epoch == epoch else { return nil }
            refusCaptcha = (error as? RefusInscription)?.estCaptcha == true
            erreurService = InscriptionRules.messageErreur(error)
            return nil
        }
    }
}

// MARK: - Lien de confirmation

/// Lien `/inscription/confirmer` (`token_hash`, implicit ou `code`, D10) : port de `ConfirmationInscription.tsx`
/// l.36-84. L'échange n'est tenté **qu'une fois** par lien (code à usage unique) ; tout échec rend le texte web
/// verbatim et « Se connecter » (le compte est confirmé par `/verify` avant la redirection, correction 10).
@MainActor
public final class ConfirmationInscriptionModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case verification
        /// Session ouverte : la racine relit la session (`SessionStore.start()`), puis l'aiguillage d'onboarding.
        case confirme
        case refuse(String)
    }

    @Published public private(set) var etat: Etat = .verification
    private let controller: SessionController
    private let credentials: AuthCallbackCredentials?
    private var tentee = false

    public init(controller: SessionController, credentials: AuthCallbackCredentials?) {
        self.controller = controller
        self.credentials = credentials
    }

    public func confirmer() async {
        guard !tentee else { return }
        tentee = true
        guard let credentials else {
            etat = .refuse(InscriptionTextes.lienNonValide)
            return
        }
        guard let gateways = await controller.gateways(for: await controller.epoch) else {
            etat = .refuse(InscriptionTextes.lienNonValide)
            return
        }
        let port = gateways.inscription
        do {
            let resultat = try await bounded(timeout: controller.resolutionTimeout) { try await port.confirmer(credentials) }
            switch resultat {
            case .sessionOuverte: etat = .confirme
            case .lienRefuse(let message): etat = .refuse(message)
            }
        } catch {
            if error is CancellationError || (error as? JoleneError)?.kind == .cancelled || Task.isCancelled { return }
            etat = .refuse(InscriptionTextes.lienNonValide)
        }
    }
}

// MARK: - Aiguillage d'onboarding

/// Écran « Reprendre votre inscription » d'une identité sans espace soignant (`OnboardingResolution.concerne`) :
/// port de `src/pages/ParcoursInscription.tsx` l.33-130. Lecture du contexte Auth et du parcours serveur ; sans
/// parcours, une intention soignant valide démarre le parcours (`fn_demarrer_inscription`) ; tout échec rend le
/// texte web l.80 et « Réessayer » (le web ne distingue aucune cause).
@MainActor
public final class OnboardingModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        /// Parcours soignant réservé : complétion (T8).
        case completerSoignant(ParcoursInscription)
        /// Parcours ou intention établissement : renvoi web.
        case espaceEtablissement
        /// « Choisissez votre espace… » ; `email` = compte Auth courant (formulaire « Je suis soignant »).
        case choixEspace(email: String?)
        case erreur
    }

    @Published public private(set) var etat: Etat = .chargement
    private let controller: SessionController
    /// Numéro du dernier chargement lancé : seul ce chargement publie.
    private var generation = 0

    public init(controller: SessionController) {
        self.controller = controller
    }

    public func charger() async {
        generation += 1
        let courant = generation
        etat = .chargement
        let epoch = await controller.epoch
        guard let gateways = await controller.gateways(for: epoch), generation == courant else { return }
        let port = gateways.inscription
        let delai = controller.resolutionTimeout
        do {
            guard let contexte = try await bounded(timeout: delai, { try await port.contexte() }) else {
                throw JoleneError(.unauthorized, InscriptionTextes.espaceIndisponible)
            }
            guard await controller.epoch == epoch, generation == courant else { return }
            let userId = contexte.userId
            var parcours = try await bounded(timeout: delai) { try await port.parcours(userId: userId) }
            guard await controller.epoch == epoch, generation == courant else { return }
            var etape = OnboardingResolution.etape(parcours: parcours, intention: contexte.intention)
            if case .demarrer(let intention) = etape {
                parcours = try await bounded(timeout: delai) { try await port.demarrer(intention: intention) }
                etape = OnboardingResolution.etape(parcours: parcours, intention: nil)
            }
            guard await controller.epoch == epoch, generation == courant else { return }
            switch etape {
            case .completerSoignant(let lu): etat = .completerSoignant(lu)
            case .espaceEtablissement: etat = .espaceEtablissement
            case .choixEspace: etat = .choixEspace(email: contexte.email)
            case .demarrer: etat = .erreur // inatteignable : un parcours démarré est toujours relu
            }
        } catch {
            if error is CancellationError || (error as? JoleneError)?.kind == .cancelled || Task.isCancelled { return }
            guard await controller.epoch == epoch, generation == courant else { return }
            etat = .erreur
        }
    }

    /// Apparition de l'écran : premier chargement seulement (un échec attend « Réessayer »).
    public func chargerSiNecessaire() async {
        guard case .chargement = etat else { return }
        await charger()
    }
}
