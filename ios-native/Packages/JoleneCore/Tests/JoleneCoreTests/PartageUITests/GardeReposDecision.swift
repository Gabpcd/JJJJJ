import Foundation

/// Décisions de la garde de repos XCUITest (`JoleneUITests/GardeRepos.swift`), extraites en fonctions pures testées sans
/// simulateur (`GardeReposDecisionTests`).
///
/// Fichier PARTAGÉ, comme `RequireWait.swift` et `PasDeDefilement.swift` : compilé dans la cible JoleneUITests (source
/// listée dans `project.yml`) et dans JoleneCoreTests. Il ne dépend que de Foundation.
///
/// Pourquoi (`docs/mobile-swift/DECISIONS_LOT2.md`, « Garde de repos XCUITest — 26/11/2026 ») : sur iPad (iOS 26.2,
/// Xcode 26.4.1), environ 4 touchers « OK » du clavier sur 80 laissent la partie d'XCTest logée dans l'app sans jamais
/// répondre à « animations idle ». Chaque geste suivant attend alors 60 s de plus, jusqu'à la fin du processus de l'app,
/// sans qu'aucune assertion échoue, et le test dépasse ses 10 minutes. La garde laisse passer l'attente expirée, puis, pour
/// ce processus seulement, n'attend plus que le repos de la boucle principale.
struct GardeReposDecision: Sendable, Equatable {
    /// Préfixe des sélecteurs enveloppés de `XCUIApplicationProcess`.
    static let prefixeSelecteur = "waitForQuiescenceIncludingAnimationsIdle:"
    /// Marque des lignes de la garde au journal de l'éclat, relevée par `scripts/mobile/ios-ci-resume-tests.mjs`.
    static let marque = "Jolene diagnostic repos-xcuitest"
    /// Une attente avec animations au moins aussi longue est tenue pour expirée (délai d'XCTest : 60 s).
    static let seuilExpiration: TimeInterval = 50
    /// L'attente de la seule boucle principale, rejouée après une attente expirée, doit tenir sous ce délai pour que
    /// l'expiration soit imputée aux animations (sinon c'est l'app qui est occupée : la garde ne change rien).
    static let seuilBoucleRapide: TimeInterval = 10
    /// Vérifications au plus par processus : une app réellement occupée (boucle principale bloquée, gel du 16/11) ne paie
    /// l'attente de vérification que trois fois, pas à chaque geste.
    static let verificationsMax = 3

    /// Formes connues de la méthode, d'après son encodage de types sans les décalages (relevé sur Xcode 16.4 :
    /// `waitForQuiescenceIncludingAnimationsIdle:usingActivity:isPreEvent:` = `v28@0:8B16B20B24`,
    /// `waitForQuiescenceIncludingAnimationsIdle:isPreEvent:` = `v24@0:8B16B20`).
    enum Forme: String, Sendable, Equatable {
        /// `(BOOL animations, BOOL isPreEvent)`.
        case deuxBooleens = "v@:BB"
        /// `(BOOL animations, BOOL usingActivity, BOOL isPreEvent)`.
        case troisBooleens = "v@:BBB"
        /// `(BOOL animations, id activity, BOOL isPreEvent)`.
        case activiteObjet = "v@:B@B"
    }

    /// Forme reconnue d'un sélecteur et de son encodage ; nil si le sélecteur ne commence pas par le préfixe ou si la
    /// signature est inconnue (la garde n'enveloppe alors rien).
    static func forme(selecteur: String, encodage: String) -> Forme? {
        guard selecteur.hasPrefix(prefixeSelecteur) else { return nil }
        let sansDecalages = String(encodage.filter { !$0.isNumber })
        guard let forme = Forme(rawValue: sansDecalages) else { return nil }
        let arguments = selecteur.filter { $0 == ":" }.count
        let attendus: Int
        switch forme {
        case .deuxBooleens: attendus = 2
        case .troisBooleens, .activiteObjet: attendus = 3
        }
        return arguments == attendus ? forme : nil
    }

    /// Processus d'app dont l'attente des animations est suspendue, avec la durée de l'attente expirée.
    private(set) var suspendus: [Int64: TimeInterval] = [:]
    /// Vérifications déjà faites, par processus.
    private var verifications: [Int64: Int] = [:]

    /// Valeur de `includingAnimationsIdle` à transmettre à XCTest pour ce processus.
    func avecAnimations(processus: Int64, demande: Bool) -> Bool {
        demande && suspendus[processus] == nil
    }

    /// Faut-il vérifier la boucle principale seule après cette attente (attente avec animations, non suspendue,
    /// au moins aussi longue que le seuil) ?
    func aVerifier(processus: Int64, avecAnimations: Bool, duree: TimeInterval) -> Bool {
        avecAnimations && suspendus[processus] == nil && duree >= Self.seuilExpiration
            && verifications[processus, default: 0] < Self.verificationsMax
    }

    /// Enregistre l'issue de la vérification ; vrai si le processus vient d'être suspendu (première expiration :
    /// une ligne au journal). Une boucle principale lente laisse tout en l'état : l'app est occupée, pas les animations.
    mutating func apresVerification(processus: Int64, dureeAttente: TimeInterval, dureeBoucleSeule: TimeInterval) -> Bool {
        verifications[processus, default: 0] += 1
        guard suspendus[processus] == nil, dureeBoucleSeule < Self.seuilBoucleRapide else { return false }
        suspendus[processus] = dureeAttente
        return true
    }

    /// Nouveau test : chaque lancement de l'app repart à zéro.
    mutating func oublier() {
        suspendus.removeAll()
        verifications.removeAll()
    }

    static func ligneExpiration(duree: TimeInterval, test: String) -> String {
        "\(marque) : attente des animations expirée (\(Int(duree.rounded())) s) pendant \(test) ; "
            + "attente des animations suspendue pour ce processus"
    }

    static func ligneInstallee(selecteurs: [String]) -> String {
        "\(marque) : garde de repos installée sur \(selecteurs.sorted().joined(separator: ", "))"
    }

    static func ligneNonInstallee(vus: [String]) -> String {
        "\(marque) : garde de repos non installée : \(vus.isEmpty ? "aucun sélecteur vu" : vus.sorted().joined(separator: ", "))"
    }
}
