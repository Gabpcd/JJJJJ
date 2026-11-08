import Foundation

/// Présentations de la racine de la fenêtre (lot 3, T3b — revue fraîche B8, m1, m7 et M1 ; `DECISIONS_LOT3.md`,
/// section T3b) : feuille du renvoi web (présentateur `.safari`) et alerte du refus d'un lien de réinitialisation
/// `?code=` (option B). Logique pure, exécutée par `DeepLinkCoordinator` (app), prouvée par `PresentationsRacineTests`.
///
/// SwiftUI ne présente qu'une feuille par niveau : posées sur la racine, la feuille et l'alerte ne s'affichent pas tant
/// qu'une autre feuille est ouverte (filtres d'Explorer). Ce type garantit qu'aucun état ne reste collé :
/// - **demandé n'est pas affiché** : `renvoi` est l'item de `sheet(item:)` ; `renvoiAffiche` n'est posé qu'à
///   l'apparition effective du contenu (`apparition(_:)`, `onAppear`), qui rend la route pour l'anti-boucle de
///   `AiguillageLiens` et le libellé DEBUG `deeplink-route` ; `disparition(_:)` (`onDisappear`) les lève, par numéro :
///   l'ancienne feuille d'un remplacement ne lève jamais l'anti-boucle de la nouvelle. Une feuille demandée mais jamais
///   affichée ne bloque rien : le même lien est redemandé sous un nouvel item ;
/// - **refus après le renvoi** : un refus reçu pendant qu'un renvoi est affiché ferme d'abord la feuille et attend la
///   fin de sa présentation (`congediement()`, `onDismiss`), jamais dans la même transaction ; sans renvoi affiché, il
///   est présenté aussitôt ;
/// - **un item par refus** : chaque refus est un nouvel item numéroté (l'hôte de l'alerte est recréé), si bien qu'un
///   refus jamais affiché ne fait pas taire les suivants ; l'acquittement porte le numéro de l'item ;
/// - **fin d'identité (M1)** : la feuille est fermée (`fermerRenvoi()`), et un renvoi demandé pendant l'effacement des
///   données web (`debutEffacement()` … `finEffacement()`) est différé jusqu'à sa fin ; une nouvelle fin d'identité
///   l'abandonne.
public struct PresentationsRacine: Equatable, Sendable {
    /// Renvoi web : numéro d'item, route externe (`.safari`, `.etablissement`) et son URL.
    public struct Renvoi: Identifiable, Equatable, Sendable {
        public let id: Int
        public let route: JoleneRoute
        public let url: URL
    }

    /// Alerte du refus de réinitialisation (`DeepLinkIntent.Textes.reinitialisationRefusee`), numérotée.
    public struct Refus: Identifiable, Equatable, Sendable {
        public let id: Int
    }

    /// Feuille demandée (item de `sheet(item:)`).
    public private(set) var renvoi: Renvoi?
    /// Feuille effectivement affichée (contenu apparu, pas encore disparu).
    public private(set) var renvoiAffiche: Renvoi?
    /// Alerte demandée.
    public private(set) var refus: Refus?
    /// Un refus attend la fin de la présentation du renvoi affiché.
    public private(set) var refusApresRenvoi = false
    /// Renvoi demandé pendant un effacement des données web, présenté à sa fin.
    public private(set) var renvoiDiffere: JoleneRoute?
    /// Effacements des données web en cours (fins d'identité rapprochées).
    public private(set) var effacementsEnCours = 0
    private var numero = 0

    public init() {}

    /// Demande la feuille d'un renvoi web ; sans effet pour une route native. Le dernier lien reçu reste visible : un
    /// refus qui attendait la fermeture d'un renvoi précédent est abandonné.
    public mutating func demanderRenvoi(_ route: JoleneRoute) {
        guard let url = route.externalURL else { return }
        refusApresRenvoi = false
        guard effacementsEnCours == 0 else {
            renvoiDiffere = route
            return
        }
        numero += 1
        renvoi = Renvoi(id: numero, route: route, url: url)
    }

    /// Apparition effective du contenu de la feuille `id` : rend sa route (anti-boucle, libellé DEBUG), nil pour une
    /// feuille qui n'est plus demandée.
    public mutating func apparition(_ id: Int) -> JoleneRoute? {
        guard let renvoi, renvoi.id == id else { return nil }
        renvoiAffiche = renvoi
        return renvoi.route
    }

    /// Disparition du contenu de la feuille `id` : vrai si c'était le renvoi affiché (anti-boucle à lever).
    public mutating func disparition(_ id: Int) -> Bool {
        guard renvoiAffiche?.id == id else { return false }
        renvoiAffiche = nil
        return true
    }

    /// Fin de la présentation de la feuille (`onDismiss`) : présente le refus qui attendait sa fermeture.
    public mutating func congediement() {
        guard refusApresRenvoi, renvoi == nil else { return }
        refusApresRenvoi = false
        presenterRefus()
    }

    /// Ferme la feuille demandée ou affichée (navigation, refus, fin d'identité, fermeture par l'utilisateur) et
    /// abandonne un renvoi différé.
    public mutating func fermerRenvoi() {
        renvoi = nil
        renvoiDiffere = nil
    }

    /// Lien de réinitialisation `?code=` refusé : la feuille est fermée d'abord ; l'alerte suit la fin de sa
    /// présentation si un renvoi est affiché, sinon elle est présentée aussitôt.
    public mutating func refuser() {
        fermerRenvoi()
        if renvoiAffiche != nil {
            refusApresRenvoi = true
        } else {
            refusApresRenvoi = false
            presenterRefus()
        }
    }

    /// Alerte fermée par l'utilisateur ; sans effet pour un item remplacé depuis.
    public mutating func refusAcquitte(_ id: Int) {
        if refus?.id == id { refus = nil }
    }

    /// Début de l'effacement des données web d'une fin d'identité.
    public mutating func debutEffacement() {
        effacementsEnCours += 1
    }

    /// Fin d'un effacement : le renvoi différé est présenté une fois tous les effacements terminés.
    public mutating func finEffacement() {
        effacementsEnCours = max(0, effacementsEnCours - 1)
        guard effacementsEnCours == 0, let differe = renvoiDiffere else { return }
        renvoiDiffere = nil
        demanderRenvoi(differe)
    }

    private mutating func presenterRefus() {
        numero += 1
        refus = Refus(id: numero)
    }
}
