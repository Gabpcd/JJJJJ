import Foundation

/// Destination d'un lien Jolene dans l'app native (lot 0, complétée au lot 3 par T3). Les cas
/// natifs reflètent les cinq onglets et les écrans du parcours soignant ; les deux sorties non
/// natives renvoient vers le web avec l'URL canonique (`https://jolene.app/...`, query et fragment
/// conservés).
///
/// Une route native n'a pas forcément d'écran livré : `DestinationLien.destination` la renvoie vers
/// Safari tant que la tranche de son écran n'est pas mergée (`DestinationLien.ecranNatifLivre`).
/// Tout consommateur (coordinateur de liens `DeepLinkIntent` / `AiguillageLiens` de L3-T3b, taps push,
/// centre de notifications, `EcranNatif(route:)` à venir) part de `DestinationLien.destination`,
/// jamais de la route brute. Seule exception : le refus de `/reset-password?code=` (option B), lu sur
/// la route par `DeepLinkIntent`. Description masquée : `LienMasque.swift`.
public enum JoleneRoute: Equatable, Sendable {
    case connexion
    /// `/reset-password` : identifiants extraits de la query et du fragment, `nil` si le lien
    /// ne porte aucun format reconnu (l'écran affiche alors « lien invalide ou expiré »).
    case resetPassword(credentials: AuthCallbackCredentials?)
    /// `/inscription/confirmer` : mêmes trois formats, types `signup` / `email`.
    case confirmerInscription(credentials: AuthCallbackCredentials?)
    /// `/inscription/soignant`, `/inscription/reprendre`, `/inscription/completer` (lot 3, T7/T8),
    /// query conservée.
    case inscription(EtapeInscription)
    case accueil
    case explorer
    case missions
    case missionDetail(id: String)
    case serieDetail(id: String)
    /// Onglet Revenus (`/soignant/mes-gains` et ses alias) ; section issue de `?tab=` ou de l'alias.
    case revenus(section: SectionRevenus)
    /// Hub du compte, onglet Profil (`Screens/ProfileScreen.swift`, onglet web
    /// `/soignant/mon-compte`, `BarreNavigation.tsx` l.37) : `/soignant/mon-compte`, `parametres`,
    /// `parametres-complet` ; `score`, `fiabilite`, `fiabilite-legacy` tant que la page score est au
    /// lot 4 (blueprint v2 §3 T3 ; écart assumé : le hub n'affiche pas de score, `DECISIONS_LOT3.md`).
    /// `/soignant/profil?tab=confidentialite` (export RGPD et suppression de compte) aussi, depuis que le hub porte
    /// l'export RGPD (L3-T11, intégration du lot 3 ; revue B8 de T3b, m3).
    case monCompte
    /// Édition du profil (lot 3, T9) : `/soignant/profil` (hors onglet `confidentialite`, qui mène au hub) et l'alias
    /// `reputation`.
    case profil
    /// Centre de notifications (lot 3, T5) : `/soignant/notifications`.
    case notifications
    /// Préférences de notifications (lot 3, T6) : `/soignant/parametres/notifications`.
    case parametresNotifications
    /// Stripe Connect (lot 3, T14a) : `/soignant/stripe-connect`, avec le retour de l'onboarding
    /// hébergé (`return_url` / `refresh_url`) s'il est présent.
    case stripeConnect(retour: RetourConnect?)
    /// Chemin servi par Safari (`SFSafariViewController`) : `/admin/*`, `/groupe/*` et tout
    /// chemin sans écran natif.
    case safari(URL)
    /// Espace établissement (lot 5) : renvoi Safari tant qu'il n'est pas natif.
    case etablissement(URL)

    /// Vrai pour une destination rendue dans l'app, faux pour un renvoi web.
    public var isNative: Bool {
        switch self {
        case .safari, .etablissement: return false
        default: return true
        }
    }

    /// URL à ouvrir hors de l'app, `nil` pour une destination native.
    public var externalURL: URL? {
        switch self {
        case .safari(let url), .etablissement(let url): return url
        default: return nil
        }
    }
}

/// Section de l'onglet Revenus visée par un lien. Valeurs brutes = onglets du web
/// (`TABS_FINANCES`, `src/pages/MesGains.tsx` l.833), plus `paiements`.
public enum SectionRevenus: String, Equatable, Sendable, CaseIterable {
    case apercu
    /// Factures d'honoraires, bulletins et avances : renvoi web assumé jusqu'au lot 4.
    case factures, bulletins, avances
    /// `?tab=paiements` : route des pushs `PAIEMENT_RECU` / `PAIEMENT_RECLAME`
    /// (`src/lib/pushNative.ts` l.294-296), onglet absent du web (correction 15 du blueprint du
    /// lot 3) ; le natif ouvre la section « Paiements à confirmer » (T13).
    case paiementsAConfirmer = "paiements"

    /// Lecture de `?tab=` comme `MesGains.tsx` l.899-900 (`TABS_FINANCES.includes(tab) ? tab :
    /// 'apercu'`, comparaison exacte), `paiements` en plus.
    public init(tab: String?) {
        self = tab.flatMap(SectionRevenus.init(rawValue:)) ?? .apercu
    }
}

/// Retour de l'onboarding Stripe Connect hébergé : `return_url` et `refresh_url` de
/// `supabase/functions/stripe-connect-onboard/index.ts` l.202-203.
public enum RetourConnect: Equatable, Sendable {
    /// `?success=true` (lu comme `searchParams.get('success') === 'true'`, `PageStripeConnect.tsx`
    /// l.28) : relecture forcée du statut, jamais un succès en soi.
    case succes
    /// `?refresh=true` (`refresh_url`, `stripe-connect-onboard/index.ts` l.202) : lien expiré ; un
    /// nouveau lien n'est demandé que sur un tap. Ajout natif : le web ne lit jamais `refresh`.
    case rafraichir

    /// `success` l'emporte sur `refresh`, comme le web qui ne lit que `success`.
    init?(query: String?) {
        let parametres = FormQuery(query ?? "")
        if parametres.get("success") == "true" {
            self = .succes
        } else if parametres.get("refresh") == "true" {
            self = .rafraichir
        } else {
            return nil
        }
    }
}

/// Page d'inscription visée par un lien, avec sa query telle que reçue (encodage pourcent
/// conservé) : `profession` et `ville` (`InscriptionRapide.tsx` l.35-42), `ref` / `parrain`
/// (`InscriptionSoignant.tsx` l.109-117, parrainage au lot 4).
public struct EtapeInscription: Equatable, Sendable {
    public enum Page: String, Equatable, Sendable, CaseIterable {
        /// `/inscription/soignant` (`InscriptionRapide type="SOIGNANT"`, `src/App.tsx` l.286).
        case soignant
        /// `/inscription/reprendre` (`ParcoursInscription`, l.290).
        case reprendre
        /// `/inscription/completer` (`ParcoursInscription completer`, l.291).
        case completer
    }

    public let page: Page
    /// Query sans « ? », encodée comme dans le lien ; `nil` si absente ou vide.
    public let query: String?

    public init(page: Page, query: String?) {
        self.page = page
        self.query = query?.isEmpty == true ? nil : query
    }

    /// Valeur d'un paramètre avec la sémantique de `URLSearchParams.get` (« + » vaut espace,
    /// décodage pourcent, première occurrence).
    public func parametre(_ nom: String) -> String? {
        FormQuery(query ?? "").get(nom)
    }
}
