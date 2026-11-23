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

    /// Glissements sans élan consécutifs restés sans effet avant de passer à un glissement avec élan (`scrollTo`).
    static let seuilSansEffet = 2

    /// Vrai si un glissement n'a rien déplacé : la cible avait un cadre et le garde, et le conteneur garde le sien.
    /// Une cible sans cadre (ligne pas encore créée par une liste paresseuse) ne prouve rien : faux.
    ///
    /// Défaut relevé au run 44797977486 (UI — ipad-portrait, `DemoEtabCandidaturesTests`, récapitulatif d'acceptation) :
    /// dans une feuille à crans (`presentationDetents([.medium, .large])`) dont le contenu est en haut, un glissement
    /// tenu à l'arrivée (relâché sans vitesse) étire la feuille, qui revient à son cran au relâché ; le contenu ne
    /// défile pas. Quarante glissements identiques (410 ; 791,2 → 664,8) ont laissé `etab-recap-confirm` à
    /// (154 ; 899 ; 512 × 48) sous un conteneur resté à (120 ; 546 ; 580 × 364). Le même écran avait demandé douze
    /// glissements identiques en paysage au même run, et 266 s en portrait au run 44475153698 (test réussi).
    static func sansEffet(cibleAvant: CGRect?, cibleApres: CGRect?, conteneurAvant: CGRect, conteneurApres: CGRect) -> Bool {
        guard let avant = cibleAvant, let apres = cibleApres, !avant.isEmpty, !apres.isEmpty else { return false }
        return memeCadre(avant, apres) && memeCadre(conteneurAvant, conteneurApres)
    }

    /// Un glissement avec élan remplace le glissement sans élan dès que `seuilSansEffet` glissements de suite n'ont
    /// rien déplacé : le relâché en vitesse fait passer la feuille au cran suivant, ou défiler son contenu.
    /// Seulement vers la suite de la page (doigt qui remonte) : dans l'autre sens, un élan en haut d'une page fermerait
    /// une feuille ou déclencherait un rafraîchissement.
    static func elanRequis(glissementsSansEffet: Int, versLaSuite: Bool) -> Bool {
        versLaSuite && glissementsSansEffet >= seuilSansEffet
    }

    /// Deux cadres confondus au demi-point près (les cadres relus par XCUITest sont arrondis au demi-point).
    static func memeCadre(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    /// Champ recouvert, même en partie, par l'une des `barres` (cadres des barres de navigation
    /// atteignables, celles de l'écran au premier plan) ; un cadre vide ne recouvre rien.
    static func recouvertParUneBarre(_ champ: CGRect, barres: [CGRect]) -> Bool {
        barres.contains { !$0.isEmpty && $0.intersects(champ) }
    }

    /// Part de la largeur du viewport entre son bord et le couloir latéral d'un glissement.
    static let margeLaterale: CGFloat = 0.1
    /// Débord vertical de la zone tactile d'un curseur au-delà de son cadre (31 pt pour 44 pt tactiles).
    static let debordTactile: CGFloat = 8
    /// Distance entre le bord du viewport et une gouttière de glissement, hors de la piste d'un curseur pleine largeur
    /// (marge de page de 16 pt au moins, piste à 32 pt du bord sur iPhone).
    static let margeGouttiere: CGFloat = 12

    /// Abscisse du point de départ d'un glissement vertical à `departY` : le milieu du viewport, sauf si
    /// ce point tombe sur un obstacle (curseur, dont la zone tactile déborde de `debordTactile`), qui
    /// capterait le geste et changerait sa valeur sans faire défiler la page (run 42593592247,
    /// ipad-landscape : `profil-rayon` passé à 50 km, vingt glissements sans effet) ; alors le couloir
    /// gauche (`margeLaterale`), puis le couloir droit ; puis, quand un curseur pleine largeur couvre les trois
    /// (iPhone, run 43296363876), la gouttière droite (`margeGouttiere`), puis la gauche (le bord gauche porte le geste
    /// système de retour) ; le milieu si aucun n'est libre.
    static func abscisseDeGlissement(viewport: CGRect, departY: CGFloat, obstacles: [CGRect]) -> CGFloat {
        let couloirs = [viewport.midX, viewport.minX + viewport.width * margeLaterale,
                        viewport.maxX - viewport.width * margeLaterale,
                        viewport.maxX - margeGouttiere, viewport.minX + margeGouttiere]
        let zones = obstacles.filter { !$0.isEmpty }.map { $0.insetBy(dx: 0, dy: -debordTactile) }
        return couloirs.first { x in !zones.contains { $0.contains(CGPoint(x: x, y: departY)) } } ?? viewport.midX
    }
}
