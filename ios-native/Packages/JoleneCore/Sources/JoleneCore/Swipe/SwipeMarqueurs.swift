import Foundation

/// Vue de l'onglet Explorer (lot 4, T3b ; `LOT4_PLAN.md` §1.1 « Swipe »), port de `VueExploration` de
/// `src/hooks/useMemoireExploration.ts`. Le web a une troisième vue, « Carte » : Explorer natif n'a pas de carte de
/// la liste des missions (la carte du lot 1 est celle du détail d'une mission), la commande segmentée n'en propose
/// donc que deux (écart consigné dans `LOT4_PLAN.md`).
public enum VueExplorer: String, CaseIterable, Equatable, Sendable {
    case swipe, liste
}

/// Marqueurs locaux du swipe, par compte (lot 4, T3b ; `LOT4_PLAN.md` §2.6 : « exception locale, non métier »), ports
/// des clés `localStorage` du web : quiz vu (`jolene_quiz_prefs_fait`, `QuizPreferencesSwipe.tsx`), feuille « première
/// candidature » vue (`jolene_sheet_premiere_candidature_vue`, `VueSwipeMissions.tsx`) et vue préférée d'Explorer
/// (`jolene_missions_view_pref:<userId>`, `RechercheMissions.tsx`).
///
/// - Une clé par compte, l'identifiant en segment entier : `CompteSuppression.purgerPreferencesLocales` les retire à
///   la suppression du compte, et un second compte sur le même appareil repart sans marqueur (le web ne sépare que la
///   vue par compte).
/// - Stockage par appareil (`StockageAppareilPort`) : `UserDefaults` en staging et production, mémoire vive en démo
///   (chaque lancement démo est un premier contact).
/// - Aucune donnée personnelle ni métier : trois drapeaux d'interface.
public struct SwipeMarqueurs: Sendable {
    /// Vue affichée sans préférence mémorisée. **Écart assumé avec le web**, qui ouvre Explorer sur « Swipe »
    /// (`vueInitiale` de `useMemoireExploration.ts`) : Explorer natif garde la liste du lot 1 tant que le soignant n'a
    /// pas choisi « Swipe » (ou suivi un lien vers le swipe), puis mémorise son choix. Décision produit à trancher par
    /// la fondatrice (`LOT4_PLAN.md`, écart de T3b) : changer cette valeur suffit.
    public static let vueParDefaut: VueExplorer = .liste
    static let marque = "1"

    private let stockage: any StockageAppareilPort
    private let userId: String

    public init(stockage: any StockageAppareilPort, userId: String) {
        self.stockage = stockage
        self.userId = userId
    }

    public static func cleQuiz(userId: String) -> String { "jolene.swipe.quiz.\(userId)" }
    public static func clePremiereCandidature(userId: String) -> String { "jolene.swipe.premiereCandidature.\(userId)" }
    public static func cleVue(userId: String) -> String { "jolene.explorer.vue.\(userId)" }

    /// Les trois clés du compte (purge, tests).
    public static func cles(userId: String) -> [String] {
        [cleQuiz(userId: userId), clePremiereCandidature(userId: userId), cleVue(userId: userId)]
    }

    /// Quiz de préférences déjà proposé (validé, remis à plus tard, ou inutile : des swipes existent en base).
    public var quizVu: Bool { stockage.lire(Self.cleQuiz(userId: userId)) == Self.marque }

    public func marquerQuizVu() { stockage.ecrire(Self.cleQuiz(userId: userId), Self.marque) }

    /// Feuille « première candidature » déjà confirmée par ce compte (« J'ai compris — envoyer ma candidature »).
    public var premiereCandidatureVue: Bool { stockage.lire(Self.clePremiereCandidature(userId: userId)) == Self.marque }

    public func marquerPremiereCandidatureVue() { stockage.ecrire(Self.clePremiereCandidature(userId: userId), Self.marque) }

    /// Vue mémorisée ; absente ou illisible : `vueParDefaut`.
    public var vue: VueExplorer {
        stockage.lire(Self.cleVue(userId: userId)).flatMap(VueExplorer.init(rawValue:)) ?? Self.vueParDefaut
    }

    public func memoriser(_ vue: VueExplorer) { stockage.ecrire(Self.cleVue(userId: userId), vue.rawValue) }
}

/// Réglages de la vue Swipe injectés par l'app (`AppContainer`, lot 4, T3b) : stockage des marqueurs et durée du toast
/// d'annulation d'une candidature.
public struct ReglagesSwipe: Sendable {
    /// Durée du toast « Candidature envoyée ✓ · Annuler » (décision D4 de `DECISIONS_LOT4.md`, `duration: 5000` du
    /// web) : au-delà, la candidature se retire depuis Mes missions, plus depuis le paquet.
    public static let dureeAnnulation: TimeInterval = 5
    /// Surcharge de la durée, honorée seulement en démonstration et en build DEBUG : les XCUITest touchent « Annuler »
    /// sans dépendre de la vitesse du simulateur (une requête d'accessibilité a déjà pris plus de 5 s en CI).
    public static let variableDureeAnnulation = "JOLENE_DEMO_SWIPE_ANNULATION"
    /// Borne haute de la surcharge (secondes).
    public static let dureeAnnulationMaximale: TimeInterval = 600

    public var stockage: any StockageAppareilPort
    public var dureeAnnulation: TimeInterval

    public init(stockage: any StockageAppareilPort, dureeAnnulation: TimeInterval = ReglagesSwipe.dureeAnnulation) {
        self.stockage = stockage
        self.dureeAnnulation = dureeAnnulation
    }

    /// Durée du toast pour ce lancement : la surcharge n'est lue qu'en démonstration **et** en build DEBUG, pour une
    /// valeur entière de secondes entre 1 et `dureeAnnulationMaximale` ; toute autre valeur garde les 5 s de D4.
    public static func dureeAnnulation(demo: Bool, debug: Bool, environnement: [String: String]) -> TimeInterval {
        guard demo, debug, let brut = environnement[variableDureeAnnulation], let secondes = Int(brut),
              secondes >= 1, TimeInterval(secondes) <= dureeAnnulationMaximale else { return dureeAnnulation }
        return TimeInterval(secondes)
    }

    public func marqueurs(userId: String) -> SwipeMarqueurs { SwipeMarqueurs(stockage: stockage, userId: userId) }
}
