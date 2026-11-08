import Foundation
import Combine

/// Écran « Mon profil » (lot 3, T9) : textes et modèle. Port de `src/pages/ProfilSoignant.tsx`
/// (lecture l.137-205, enregistrement l.246-297) restreint au périmètre natif (D12) : identité,
/// coordonnées, préférences de recherche, bio et expérience. Type d'exercice et attestation de cumul
/// (L1222-5, correction 8) : renvoi web libellé, jamais portés (HARD STOP n°4).
public enum ProfilEdition {
    /// Textes affichés. Verbatim web (source en commentaire, garde `ProfilVerbatimTests`) ; les textes
    /// tutoyés du web, non juridiques, passent au vouvoiement (décision 9 du lot 1, `vouvoiements`).
    public enum Textes {
        /// `ProfilSoignant.tsx` l.333 ; entrée du hub `MonCompteSoignant.tsx` l.59.
        public static let titre = "Mon profil"
        /// `SectionProfilPrincipal.tsx` l.790.
        public static let sectionInformations = "Informations personnelles"
        /// l.792-850 (libellés des champs « Informations personnelles »).
        public static let prenom = "Prénom"
        public static let nom = "Nom"
        public static let telephone = "Téléphone"
        public static let dateNaissance = "Date de naissance"
        public static let email = "Email"
        /// l.733.
        public static let profession = "Profession"
        /// l.733, l.780, l.797, l.812, l.837.
        public static let nonModifiableApresRpps = "(non modifiable après le contrôle RPPS)"
        /// l.780 (RPPS vérifié).
        public static let rpps = "RPPS"
        /// l.722.
        public static let rppsVerifie = "RPPS Vérifié"
        /// l.246 : `Numéro RPPS{optionnel ? ' (optionnel)' : ' *'}`.
        public static let numeroRpps = "Numéro RPPS"
        public static let suffixeOptionnel = " (optionnel)"
        public static let suffixeRequis = " *"
        /// l.251.
        public static let rppsPlaceholder = "11 chiffres"
        /// l.262.
        public static let rppsAide = "Identifiant à 11 chiffres. Les chiffres seuls ne suffisent pas : le contrôle compare l’identité, la profession et le statut actif auprès de la source de vérification disponible."
        /// l.258 : `{rpps.length}/11 chiffres`, affiché entre 1 et 10 chiffres.
        public static func rppsCompteur(_ chiffres: Int) -> String? {
            chiffres > 0 && chiffres < FormulaireProfil.longueurRpps ? "\(chiffres)/11 chiffres" : nil
        }
        /// l.879 (pictogramme décoratif « 🏙️ » retiré).
        public static let villeRecherche = "Ville de recherche"
        /// l.881, vouvoyé.
        public static let villeRechercheAide = "Indiquez la ville où vous cherchez des missions. Utile si vous êtes en déplacement ou en vacances."
        /// l.887.
        public static let villeRecherchePlaceholder = "Ex : Lyon, Paris..."
        /// `SectionBio.tsx` l.46 (déjà au vouvoiement).
        public static let presentation = "Votre présentation"
        /// l.51, l.56.
        public static let bio = "Bio"
        public static let bioPlaceholder = "Présentez-vous aux établissements : votre expérience, vos spécialités, vos préférences..."
        /// l.61 : `{bio.length}/500`.
        public static func bioCompteur(_ caracteres: Int) -> String { "\(caracteres)/500" }
        /// l.68 (+ astérisque `*` du champ requis).
        public static let anneesExperience = "Années d'expérience"
        /// `SectionPreferences.tsx` l.71 (pictogramme « 💰 » retiré).
        public static let tauxTitre = "Taux horaire minimum accepté"
        /// l.72, vouvoyé.
        public static let tauxAide = "Les missions en dessous de ce taux seront grisées dans vos résultats."
        /// l.76.
        public static let tauxNonDefini = "Non défini"
        public static func taux(_ valeur: Double) -> String { "\(MissionPresentation.nombreJavaScript(valeur)) €/h" }
        /// l.96.
        public static let tauxMinimum = "10 €/h"
        public static let tauxMaximum = "100 €/h"
        /// l.102 (pictogramme « 📍 » retiré).
        public static let rayonTitre = "Rayon de déplacement"
        /// l.103.
        public static let rayonAide = "Distance maximale jusqu'aux missions proposées."
        /// l.105 : `Rayon : {rayon} km`.
        public static func rayon(_ km: Int) -> String { "Rayon : \(km) km" }
        /// l.117.
        public static let rayonMinimum = "5 km"
        public static let rayonMaximum = "100 km"
        /// `SectionProfilPrincipal.tsx` l.897.
        public static let typeExercice = "Type d'exercice"
        /// Sans équivalent web (non juridique, à relire par Gabrielle, `DECISIONS_LOT3.md`) : renvoi
        /// libellé du type d'exercice et de l'attestation de cumul, servis par la page web (HARD STOP n°4).
        public static let typeExerciceWeb = "Le type d'exercice se modifie sur jolene.app."
        /// Sans équivalent web (non juridique, à relire par Gabrielle) : repli d'un refus d'enregistrement
        /// sans message serveur (le web passe par `extraireMessageErreur`, non porté) ; message de
        /// `SupabaseProfilGateway` et du modèle.
        public static let enregistrementEchec = "Votre profil n'a pas pu être enregistré. Réessayez."
        /// Libellé natif des renvois web du lot 1 (`AccueilScreen.swift`).
        public static let voirSurLeWeb = "Voir sur jolene.app"
        /// `ProfilSoignant.tsx` l.499.
        public static let enregistrer = "Enregistrer les modifications"
        public static let enregistrement = "Enregistrement…"
        /// l.293 (toast web, ici encart après relecture).
        public static let succes = "Profil mis à jour avec succès !"
        /// l.411, vouvoyé.
        public static let chargementEchec = "Votre profil n’a pas pu être chargé. Vous pouvez réessayer."
        /// l.412.
        public static let reessayer = "Réessayer"
    }

    /// Textes tutoyés du web et leur forme vouvoyée (décision 9 du lot 1 ; aucun n'est juridique).
    public static let vouvoiements: [(web: String, natif: String)] = [
        ("Indique la ville où tu cherches des missions. Utile si tu es en déplacement ou en vacances.",
         Textes.villeRechercheAide),
        ("Les missions en dessous de ce taux seront grisées dans tes résultats.", Textes.tauxAide),
        ("Ton profil n’a pas pu être chargé. Tu peux réessayer.", Textes.chargementEchec),
    ]

    /// Renvoi web du type d'exercice : la page profil du web (onglet principal, section « Type
    /// d'exercice »), servie par Safari. Construit hors `LinkRouter` : `/soignant/profil` est une route
    /// native (`.profil`), mais cette section ne l'est pas.
    public static let lienTypeExercice = "/soignant/profil?tab=principal"

    public static var renvoiTypeExercice: JoleneRoute? {
        guard let lien = JoleneLink.normalize(lienTypeExercice), let url = JoleneLink.canonicalURL(link: lien) else { return nil }
        return .safari(url)
    }

    /// La section web « Type d'exercice » n'existe que pour une profession connue
    /// (`{profession && …}`, `SectionProfilPrincipal.tsx` l.895-896) : le renvoi suit la même condition.
    public static func afficheRenvoiTypeExercice(_ profil: ProfilComplet) -> Bool {
        guard let profession = profil.profession else { return false }
        return !profession.isEmpty
    }

    /// Audit de consultation (web l.157-163) : `DONNEES_PERSO_CONSULTATION`, ressource `soignant`.
    public static let auditTypeRessource = "soignant"
    public static let auditDetails = ["page": "profil"]
}

/// Modèle de l'écran « Mon profil » (lot 3, T9). Règles :
/// - lecture `gateways.profil` bornée à `resolutionTimeout` pour l'epoch de l'écran ; échec → message
///   du web (vouvoyé) et « Réessayer », session expirée signalée à part ;
/// - audit `DONNEES_PERSO_CONSULTATION` une fois par ouverture (instance du modèle), après la
///   première lecture réussie, best-effort et jamais bloquant ;
/// - enregistrement : seuls les champs changés (`ModificationProfil.depuis`), une seule demande par
///   appui, succès annoncé seulement sur le profil RELU rendu par le port ; refus serveur verbatim ;
///   délai dépassé ou réseau : relecture du profil (la saisie est conservée, aucun renvoi
///   automatique) ; après un succès, la session est revalidée (silencieusement, sans démonter les
///   onglets) pour que le profil de la session (rayon, contrats, taux lus par Explorer) suive la base,
///   comme `invaliderProfilNavigation` du web ; le bouton n'attend pas cette revalidation ;
/// - modes d'exercice autorisés : `gateways.inscription.typesExercice` (`fn_types_exercice_autorises`,
///   câblé par T8, point d'extension) ; erreur ou réponse absente → état « indisponible » du web ; port
///   encore non câblé → même état, sans « Réessayer la vérification » (jamais un bouton sans effet).
@MainActor
public final class ProfilEditionModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case pret(ProfilComplet)
        case echec(String)
    }

    public enum Modes: Equatable, Sendable {
        case inactif
        case chargement
        case disponibles([String])
        case indisponible
        /// `InscriptionPort` encore non câblé (T8) : le référentiel ne peut pas être lu, présenté comme
        /// « indisponible » sans nouvelle tentative possible.
        case nonCable
    }

    @Published public private(set) var etat: Etat = .chargement
    /// Saisie de l'écran. Toute modification efface l'encart de succès.
    @Published public var formulaire: FormulaireProfil {
        didSet { if formulaire != oldValue { succes = nil } }
    }
    /// Formulaire tel que relu : base de la différence envoyée.
    @Published public private(set) var initial: FormulaireProfil?
    @Published public private(set) var enregistrementEnCours = false
    @Published public private(set) var succes: String?
    @Published public private(set) var erreur: String?
    @Published public private(set) var sessionExpiree = false
    @Published public private(set) var modes: Modes = .inactif
    /// Jeton d'annonce VoiceOver des encarts (`InlineNotice.announcementID`).
    @Published public private(set) var annonces = 0

    private let session: SessionStore
    private let snapshot: SessionSnapshot
    private var generation = 0
    private var auditTente = false

    public init(session: SessionStore, snapshot: SessionSnapshot) {
        self.session = session
        self.snapshot = snapshot
        self.formulaire = FormulaireProfil(profil: ProfilComplet(id: snapshot.user.id, prenom: "", nom: ""))
    }

    public var profil: ProfilComplet? {
        if case let .pret(profil) = etat { return profil }
        return nil
    }

    /// Champs à transmettre ; vide = bouton « Enregistrer » inactif.
    public var modification: ModificationProfil {
        guard let profil, let initial else { return ModificationProfil() }
        return ModificationProfil.depuis(initial: initial, saisi: formulaire, profil: profil)
    }

    public var peutEnregistrer: Bool { !enregistrementEnCours && !modification.estVide }

    public var choixModes: ChoixModesExercice {
        let types: [String]?
        if case let .disponibles(valeurs) = modes { types = valeurs } else { types = nil }
        return ChoixModesExercice.presenter(valeur: formulaire.typesContrat, typesAutorises: types,
                                            chargement: modes == .chargement,
                                            indisponible: modes == .indisponible || modes == .nonCable)
    }

    /// « Réessayer la vérification » n'est proposé que si une nouvelle lecture peut aboutir.
    public var reessaiModesPossible: Bool { modes == .indisponible }

    public func basculerMode(_ mode: PreferenceModeExercice, selectionne: Bool) {
        formulaire.typesContrat = ChoixModesExercice.basculer(formulaire.typesContrat, mode: mode, selectionne: selectionne)
    }

    // MARK: - Lecture

    /// Premier chargement ou « Réessayer ». Une lecture dépassée par une plus récente ne publie rien.
    public func charger() async {
        generation += 1
        let courant = generation
        if profil == nil { etat = .chargement }
        guard let gateways = await session.controller.gateways(for: snapshot.epoch), generation == courant else { return }
        do {
            let relu = try await lire(gateways)
            guard await memeEpoch(), generation == courant else { return }
            sessionExpiree = false
            appliquer(relu, conserverSaisie: false)
        } catch {
            guard await memeEpoch(), generation == courant, let message = Self.messageLecture(error) else { return }
            if (error as? JoleneError)?.kind == .unauthorized { sessionExpiree = true }
            etat = .echec(message)
            return
        }
        await auditerConsultation(gateways)
        if modes == .inactif || modes == .indisponible || modes == .nonCable { await verifierModes() }
    }

    /// « Réessayer la vérification » des modes d'exercice autorisés (`reessayer` du web).
    public func verifierModes() async {
        guard let profession = profil?.profession, !profession.isEmpty else {
            modes = .inactif
            return
        }
        guard let gateways = await session.controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.inscription
        guard !(port is UnwiredPort) else {
            modes = .nonCable
            return
        }
        modes = .chargement
        do {
            let types = try await bounded(timeout: session.controller.resolutionTimeout) {
                try await port.typesExercice(profession: profession)
            }
            guard await memeEpoch() else { return }
            modes = types.map(Modes.disponibles) ?? .indisponible
        } catch {
            guard await memeEpoch(), !(error is CancellationError) else { return }
            modes = .indisponible
        }
    }

    // MARK: - Enregistrement

    public func enregistrer() async {
        guard !enregistrementEnCours else { return }
        let aEnvoyer = modification
        guard !aEnvoyer.estVide else { return }
        enregistrementEnCours = true
        let reussi = await envoyer(aEnvoyer)
        enregistrementEnCours = false
        // Revalidation silencieuse de la session (profil d'Explorer) : le bouton ne l'attend pas.
        if reussi { await session.start() }
    }

    /// Une seule demande ; vrai seulement si le profil RELU a été appliqué (succès annoncé).
    private func envoyer(_ aEnvoyer: ModificationProfil) async -> Bool {
        succes = nil
        erreur = nil
        guard let gateways = await session.controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.profil
        let context = snapshot.context
        do {
            let relu = try await bounded(timeout: session.controller.resolutionTimeout) {
                try await port.modifier(aEnvoyer, context: context)
            }
            guard await memeEpoch() else { return false }
            appliquer(relu, conserverSaisie: false)
            succes = ProfilEdition.Textes.succes
            annonces += 1
            return true
        } catch {
            guard await memeEpoch(), !(error is CancellationError) else { return false }
            let jolene = error as? JoleneError
            if jolene?.kind == .cancelled { return false }
            sessionExpiree = jolene?.kind == .unauthorized
            erreur = jolene?.message ?? ProfilEdition.Textes.enregistrementEchec
            annonces += 1
            // Délai dépassé ou réseau : le serveur a pu enregistrer. Relecture (bouton toujours verrouillé,
            // aucun second envoi possible pendant ce temps), saisie conservée.
            if jolene?.kind == .network, let relu = try? await lire(gateways), await memeEpoch() {
                appliquer(relu, conserverSaisie: true)
            }
            return false
        }
    }

    // MARK: - Interne

    private func lire(_ gateways: Gateways) async throws -> ProfilComplet {
        let port = gateways.profil
        let context = snapshot.context
        return try await bounded(timeout: session.controller.resolutionTimeout) { try await port.profil(context: context) }
    }

    private func appliquer(_ relu: ProfilComplet, conserverSaisie: Bool) {
        etat = .pret(relu)
        let formulaireRelu = FormulaireProfil(profil: relu)
        initial = formulaireRelu
        if !conserverSaisie {
            let message = succes
            formulaire = formulaireRelu
            succes = message
        }
    }

    private func auditerConsultation(_ gateways: Gateways) async {
        guard !auditTente else { return }
        auditTente = true
        let audit = gateways.audit
        let context = snapshot.context
        let userId = snapshot.user.id
        _ = try? await bounded(timeout: session.controller.resolutionTimeout) {
            try await audit.ecrire(action: .donneesPersoConsultation, typeRessource: ProfilEdition.auditTypeRessource,
                                   idRessource: userId, details: ProfilEdition.auditDetails, context: context)
        }
    }

    private func memeEpoch() async -> Bool { await session.controller.epoch == snapshot.epoch }

    /// Message d'un échec de lecture ; nil pour une annulation (la vue a disparu : rien à afficher).
    static func messageLecture(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        if let jolene = error as? JoleneError {
            switch jolene.kind {
            case .cancelled: return nil
            case .unauthorized: return jolene.message
            default: return ProfilEdition.Textes.chargementEchec
            }
        }
        return ProfilEdition.Textes.chargementEchec
    }
}
