import CoreGraphics

/// Pas suivant du défilement borné de `scrollTo` et dégagement d'un champ recouvert par une barre
/// de navigation (`JoleneUITests/UITestSupport.swift`), extraits en fonctions pures testées sans
/// simulateur (`PasDeDefilementTests`).
///
/// Fichier PARTAGÉ, comme `RequireWait.swift` : compilé dans la cible JoleneUITests (source listée
/// dans `project.yml`) et dans JoleneCoreTests. Il ne dépend que de CoreGraphics.
///
/// Défaut corrigé à l'intégration du lot 3 (run 42579729412, UI — ipad-landscape) : quand la cible
/// est revenue dans le cadre du conteneur sans y être encore entièrement visible (recouverte par la
/// barre de navigation translucide, ou défilement inertiel en cours), l'ancienne règle reprenait la
/// direction par défaut de la recherche et la renvoyait hors du cadre ; vingt glissements en
/// alternance, sans jamais l'atteindre (`DemoPreferencesTests`, `prefs-canal-sms`).
struct PasDeDefilement: Sendable, Equatable {
    /// Vrai : le doigt remonte, le contenu monte et révèle la suite de la page.
    let versLaSuite: Bool
    /// Part de la hauteur du conteneur parcourue par le glissement.
    let amplitude: CGFloat

    /// Pas de recherche d'une cible absente ou sans cadre.
    static let amplitudeRecherche: CGFloat = 0.55
    /// Pas court qui ramène vers le centre une cible déjà dans le cadre du conteneur.
    static let amplitudeRecentrage: CGFloat = 0.15

    /// - cible au-dessus du conteneur : la page redescend ; au-dessous : elle monte ; amplitude
    ///   proportionnelle à la place libre (40 % de la hauteur hors cible, entre 0,08 et 0,55) ;
    /// - cible dans le cadre mais pas entièrement visible : pas court vers le centre ;
    /// - cible absente, sans cadre, ou conteneur vide : direction de recherche `versLaSuiteParDefaut`.
    static func suivant(cible: CGRect?, conteneur: CGRect, versLaSuiteParDefaut: Bool) -> PasDeDefilement {
        guard let cible, !cible.isEmpty, conteneur.height > 0 else {
            return PasDeDefilement(versLaSuite: versLaSuiteParDefaut, amplitude: amplitudeRecherche)
        }
        let approche = min(amplitudeRecherche, max(0.08, (conteneur.height - cible.height) * 0.4 / conteneur.height))
        if cible.minY < conteneur.minY { return PasDeDefilement(versLaSuite: false, amplitude: approche) }
        if cible.maxY > conteneur.maxY { return PasDeDefilement(versLaSuite: true, amplitude: approche) }
        return PasDeDefilement(versLaSuite: cible.midY > conteneur.midY, amplitude: amplitudeRecentrage)
    }

    /// Champ recouvert, même en partie, par l'une des `barres` (cadres des barres de navigation
    /// atteignables, celles de l'écran au premier plan) ; un cadre vide ne recouvre rien.
    static func recouvertParUneBarre(_ champ: CGRect, barres: [CGRect]) -> Bool {
        barres.contains { !$0.isEmpty && $0.intersects(champ) }
    }
}
