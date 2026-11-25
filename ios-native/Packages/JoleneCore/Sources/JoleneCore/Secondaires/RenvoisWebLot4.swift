import Foundation

/// Renvois web assumés du lot 4 (L4-T13, `docs/mobile-swift/LOT4_PLAN.md` §1.3 et §3 T13), contenu définitif, sans
/// aucun texte juridique ni jeton transmis : titres des pages web (`usePageTitle`, annotés `// source:`), chemins de
/// `src/App.tsx`, présentés par le présentateur `.safari` du coordinateur des liens (`SFSafariViewController`), jamais par
/// `openURL` ni `UIApplication.open` (les chemins `/soignant/*` reviendraient dans l'app par lien universel ; garde
/// `RenvoisWebSourcesAppTests` de JoleneSupabase).
///
/// - `titreEcran(_:)` : titre de la page web d'un écran secondaire natif, porté par `RenvoiWebScreen` quand son
///   coupe-circuit `ios_natif_<ecran>_actif` est lu faux (`nil` : la page web n'a pas de titre, aucun titre affiché).
/// - `entreesDocumentsProtection` : section « Documents & protection » du hub web (`MonCompteSoignant.tsx` l.80-89),
///   réduite à « Prévoyance », la seule ligne que le web montre à tous. « Passer en libéral » et « Attestation
///   d'heures » dépendent de l'éligibilité au libéral (`estEligibleLiberal`, `src/lib/regles-installation-liberal.ts`,
///   règle de restriction d'un mode d'exercice, HARD STOP n°4) : jamais recalculée en natif, ces deux lignes ne sont pas
///   affichées et leurs pages restent atteintes par lien (renvoi web canonique de `DestinationLien`).
/// - Les autres renvois de §1.3 ont déjà leur emplacement : Revenus (avances, charges, factures, `RevenusScreen`),
///   bulletins (simulations de paie, `BulletinsScreen`), Paiements & facturation (mandat), litiges (accords amiables,
///   `LitigeFilView`) ; premium et classement n'ont aucune entrée dans le hub web et restent atteints par lien.
public enum RenvoisWebLot4 {
    public struct Entree: Equatable, Sendable {
        public let libelle: String
        public let chemin: String
        /// Identifiant d'accessibilité (`hub-renvoi-<clé>`).
        public let identifiant: String
        public var url: URL { URL(string: "https://jolene.app" + chemin)! }
    }

    /// Titre de la section du hub web (`MonCompteSoignant.tsx` l.82).
    public static let titreDocumentsProtection = "Documents & protection"

    /// Lignes affichées à tout soignant (voir l'en-tête).
    public static let entreesDocumentsProtection: [Entree] = [
        // source: src/pages/MonCompteSoignant.tsx:88
        Entree(libelle: "Prévoyance", chemin: "/soignant/prevoyance", identifiant: "hub-renvoi-prevoyance"),
    ]

    /// Titre de la page web d'un écran secondaire (`usePageTitle`), pour son renvoi web.
    public static func titreEcran(_ nom: EcranSecondaire.Nom) -> String? {
        switch nom {
        case .swipe: return "Trouver une mission"                       // source: src/pages/RechercheMissions.tsx:56
        case .recherches: return "Mes recherches sauvegardées"          // source: src/pages/PageRecherchesSauvegardees.tsx:57
        case .disponibilites: return "Mes disponibilités"               // source: src/pages/MesDisponibilites.tsx:29
        case .litiges, .reclamations: return "Litiges & contestations"  // source: src/pages/LitigesContestationsSoignant.tsx:13
        case .messagerie: return "Messagerie"                           // source: src/pages/PageMessagerie.tsx:125
        case .bulletins: return "Revenus"                               // source: src/pages/MesGains.tsx:837
        case .evaluations: return "Mes évaluations"                     // source: src/pages/EvaluationsSoignant.tsx:58
        case .score: return "Mon score"                                 // source: src/pages/PageScoreSoignant.tsx:38
        case .poolUrgence: return "Pool urgence"                        // source: src/pages/PoolUrgenceSoignant.tsx:47
        case .exclusions: return "Exclusions"                           // source: src/pages/ExclusionsSoignant.tsx:28
        case .parrainage, .serie: return nil                            // pages web sans titre
        }
    }
}
