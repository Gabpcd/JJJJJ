import Foundation

/// Table unique des renvois web de l'espace établissement (lot 5, T12 ; `docs/mobile-swift/LOT5_PLAN.md` §1.2, §3 T12,
/// D16, D17) : `clé → chemin` des pages servies par jolene.app, affichées par l'onglet Compte
/// (`Jolene/Screens/Etablissement/Compte/EtabCompteScreen.swift`, identifiants `etab-compte-web-<clé>`).
///
/// Un renvoi est un **lien constant** : `https://jolene.app` + chemin littéral. Ni jeton, ni identifiant de session, ni
/// donnée de l'utilisateur ou de l'établissement n'entre dans l'URL ; la session de l'app n'est pas partagée avec
/// Safari (D16), la page web redemande une connexion. Le permis de voir une page reste celui du web et du serveur :
/// la table ne fait que masquer une entrée que le serveur ne sert pas à ce membre (§2.7, fail-closed).
///
/// Ouverture : chaque entrée rend une route externe (`route`) présentée par le présentateur `.safari` du coordinateur
/// des liens (`PresentateurRenvoiWeb`, `SFSafariViewController`). Jamais `openURL` : un chemin `/etablissement/*` est
/// couvert par l'AASA de l'app (`AASAPatterns`) et reviendrait dans l'app par lien universel. Les pages légales ne
/// sont pas couvertes ; elles passent par le même présentateur, sans aller-retour.
///
/// Libellés : ceux du menu web « Mon compte » de l'établissement (`src/pages/MonCompteEtablissement.tsx`, l.37-93),
/// ligne par ligne avec leur route ; deux pages hors de ce menu portent le titre de leur page web (Chorus Pro, API).
/// `libellesNatifs` nomme les deux entrées dont le libellé ne vient pas d'une ligne du menu. Garde de dérive :
/// `RenvoisWebEtabTests`.
public enum RenvoisWebEtab {
    public enum Cle: String, CaseIterable, Sendable {
        case soignants
        case mesFavoris = "mes-favoris"
        case poolUrgence = "pool-urgence"
        case evaluationsAFaire = "evaluations-a-faire"
        case equipe
        case rh
        case exportPaie = "export-paie"
        case score
        case parrainage
        case premium
        case parametres
        case facturation
        case sepa
        case chorusConfig = "chorus-config"
        case litiges
        case notifications
        case api
        case aide
        case confidentialite
        case cgu
        case cgv
        case mentionsLegales = "mentions-legales"
        case supprimer
    }

    /// Sections du menu web, dans son ordre (`MonCompteEtablissement.tsx` l.39, l.50, l.61, l.82).
    public enum Section: String, CaseIterable, Sendable {
        case activite
        case equipePilotage = "equipe-pilotage"
        /// Section sans titre du web (l.61) : établissement, factures, litiges, notifications.
        case gestion
        case aideLegal = "aide-legal"

        public var titre: String? {
            switch self {
            case .activite: return "Activité"
            case .equipePilotage: return "Équipe & pilotage"
            case .gestion: return nil
            case .aideLegal: return "Aide & légal"
            }
        }
    }

    /// Condition d'affichage d'une entrée, lue sur les seules valeurs servies (`fn_mes_permissions_etab`,
    /// `fn_mon_etablissement_complet`). Aucune correspondance rôle → permission n'est écrite ici.
    public enum Condition: Equatable, Sendable {
        /// Tout membre de l'établissement, comme le menu web.
        case toutMembre
        case permission(PermissionEtab)
        /// `lecture_paiement` ∨ `paiement` : `canReadFinance` du web (`BarreNavigation.tsx` l.217), qui masque
        /// « Facturation » aux autres membres.
        case finances
        /// `finances`, et `est_secteur_public` servi vrai : le web ne propose la configuration Chorus Pro qu'à un
        /// établissement du secteur public (`FacturationEtablissement.tsx` l.1765-1777). Valeur absente : masqué.
        case financesSecteurPublic

        public func satisfaite(profil: EtablissementProfil, permissions: PermissionsEtab) -> Bool {
            switch self {
            case .toutMembre: return true
            case let .permission(permission): return permissions[permission]
            case .finances: return permissions.lecturePaiement || permissions.paiement
            case .financesSecteurPublic:
                return (permissions.lecturePaiement || permissions.paiement) && profil.estSecteurPublic == true
            }
        }
    }

    public struct Entree: Identifiable, Equatable, Sendable {
        public let cle: Cle
        public let libelle: String
        /// Chemin web relatif à `https://jolene.app`, query et fragment compris.
        public let chemin: String
        public let section: Section
        public let condition: Condition

        public var id: String { cle.rawValue }
        /// Identifiant d'accessibilité de l'entrée.
        public var identifiant: String { "etab-compte-web-\(cle.rawValue)" }

        /// Chemin sans query ni fragment : la route déclarée dans `src/App.tsx`.
        public var cheminSeul: String {
            String(chemin.prefix { $0 != "?" && $0 != "#" })
        }

        /// URL canonique du renvoi.
        public var url: URL {
            // Chemin littéral de la table : la construction ne peut pas échouer.
            URL(string: JoleneLink.canonicalOrigin + chemin)!
        }

        /// Route externe présentée hors du lien universel : `.etablissement` pour un chemin couvert par l'AASA de
        /// l'app, `.safari` pour une page publique. Les deux s'ouvrent par le même présentateur.
        public var route: JoleneRoute {
            AASAPatterns.firstMatch(path: cheminSeul) != nil ? .etablissement(url) : .safari(url)
        }
    }

    /// Les entrées, dans l'ordre du menu web ; les clés hors menu sont rangées dans la section de leur domaine.
    public static let table: [Entree] = [
        // « Activité » (l.39-47). Présences, contrats et messagerie du web sont des écrans natifs de la coquille.
        Entree(cle: .soignants, libelle: "Annuaire des soignants", chemin: "/etablissement/soignants",
               section: .activite, condition: .toutMembre),                                             // l.43
        Entree(cle: .mesFavoris, libelle: "Soignants favoris", chemin: "/etablissement/mes-favoris",
               section: .activite, condition: .toutMembre),                                             // l.44
        Entree(cle: .poolUrgence, libelle: "Pool urgence", chemin: "/etablissement/pool-urgence",
               section: .activite, condition: .toutMembre),                                             // l.45
        // Hors du menu web. Libellé neutre de l'Accueil (`PrioriteActions.Textes.evaluationsTitre`) et même choix
        // d'affichage que lui : membres qui gèrent les missions (`DECISIONS_LOT5.md`, T4, point 2).
        Entree(cle: .evaluationsAFaire, libelle: PrioriteActions.Textes.evaluationsTitre,
               chemin: "/etablissement/evaluations-a-faire", section: .activite, condition: .permission(.missions)),
        // « Équipe & pilotage » (l.50-58).
        Entree(cle: .equipe, libelle: "Gérer mon équipe", chemin: "/etablissement/equipe",
               section: .equipePilotage, condition: .permission(.gererEquipe)),                         // l.52, §2.7
        Entree(cle: .rh, libelle: "Pilotage RH & statistiques", chemin: "/etablissement/rh",
               section: .equipePilotage, condition: .toutMembre),                                       // l.53
        Entree(cle: .exportPaie, libelle: "Export paie", chemin: "/etablissement/export-paie",
               section: .equipePilotage, condition: .toutMembre),                                       // l.54
        Entree(cle: .score, libelle: "Score qualité", chemin: "/etablissement/score",
               section: .equipePilotage, condition: .toutMembre),                                       // l.55
        Entree(cle: .parrainage, libelle: "Parrainage", chemin: "/etablissement/parrainage",
               section: .equipePilotage, condition: .toutMembre),                                       // l.56
        Entree(cle: .premium, libelle: "Offre Premium", chemin: "/etablissement/premium",
               section: .equipePilotage, condition: .toutMembre),                                       // l.57
        // Section sans titre (l.61-78).
        Entree(cle: .parametres, libelle: "Mon établissement", chemin: "/etablissement/parametres?tab=profil",
               section: .gestion, condition: .toutMembre),                                              // l.63
        Entree(cle: .facturation, libelle: "Mes factures", chemin: "/etablissement/facturation",
               section: .gestion, condition: .finances),                                                // l.65
        // Hors du menu web : même page que les factures (mandat, prélèvements). Libellé de navigation, le mot est
        // celui du mode de paiement sur le web (`DetailFacture.tsx` l.44).
        Entree(cle: .sepa, libelle: "Prélèvement SEPA", chemin: "/etablissement/facturation",
               section: .gestion, condition: .finances),
        // Hors du menu web : titre de la page (`ChorusConfig.tsx` l.30).
        Entree(cle: .chorusConfig, libelle: "Configuration Chorus Pro", chemin: "/etablissement/chorus-config",
               section: .gestion, condition: .financesSecteurPublic),
        // Même choix d'affichage que l'action « litiges » de l'Accueil (T4, point 2).
        Entree(cle: .litiges, libelle: "Litiges & contestations", chemin: "/etablissement/litiges",
               section: .gestion, condition: .permission(.missions)),                                   // l.66
        // Centre de notifications (`PageNotifications.tsx` l.29) ; même libellé que la ligne du menu (l.68).
        Entree(cle: .notifications, libelle: "Notifications", chemin: "/etablissement/notifications",
               section: .gestion, condition: .toutMembre),
        // Hors du menu web : titre de la section API de la page (`APIEtablissement.tsx` l.117) ; `/etablissement/api`
        // redirige vers l'onglet Sécurité des paramètres (`App.tsx` l.429).
        Entree(cle: .api, libelle: "API REST Jolene", chemin: "/etablissement/api",
               section: .gestion, condition: .toutMembre),
        // « Aide & légal » (l.82-91). « Contacter Jolene » (l.85) est une modale du web, sans page.
        Entree(cle: .aide, libelle: "Centre d'aide", chemin: "/aide", section: .aideLegal, condition: .toutMembre),   // l.84
        Entree(cle: .confidentialite, libelle: "Confidentialité", chemin: "/confidentialite",
               section: .aideLegal, condition: .toutMembre),                                            // l.86
        Entree(cle: .cgu, libelle: "CGU", chemin: "/cgu", section: .aideLegal, condition: .toutMembre),               // l.87
        Entree(cle: .cgv, libelle: "CGV", chemin: "/cgv", section: .aideLegal, condition: .toutMembre),               // l.88
        Entree(cle: .mentionsLegales, libelle: "Mentions légales", chemin: "/mentions-legales",
               section: .aideLegal, condition: .toutMembre),                                            // l.89
        // D17 : lien direct, visible de tout membre comme le web (l.90) ; la page et l'edge `delete-account` décident.
        Entree(cle: .supprimer, libelle: "Supprimer mon compte",
               chemin: "/etablissement/parametres?tab=securite#suppression-compte",
               section: .aideLegal, condition: .toutMembre),                                            // l.90
    ]

    /// Entrées dont le libellé ne vient ni d'une ligne du menu web ni du titre de leur page.
    public static let libellesNatifs: [Cle] = [.evaluationsAFaire, .sepa]

    public static func entree(_ cle: Cle) -> Entree {
        // Une entrée par clé (`RenvoisWebEtabTests.testUneEntreeParCleIdentifiantEtUrlCanonique`).
        table.first { $0.cle == cle }!
    }

    /// Entrées offertes à ce membre, dans l'ordre de la table.
    public static func visibles(profil: EtablissementProfil, permissions: PermissionsEtab) -> [Entree] {
        table.filter { $0.condition.satisfaite(profil: profil, permissions: permissions) }
    }

    public struct SectionVisible: Identifiable, Equatable, Sendable {
        public let section: Section
        public let entrees: [Entree]
        public var id: String { section.rawValue }
    }

    /// Entrées visibles regroupées par section, dans l'ordre du menu web ; une section sans entrée n'est pas rendue.
    public static func sections(profil: EtablissementProfil, permissions: PermissionsEtab) -> [SectionVisible] {
        let offertes = visibles(profil: profil, permissions: permissions)
        return Section.allCases.compactMap { section in
            let entrees = offertes.filter { $0.section == section }
            return entrees.isEmpty ? nil : SectionVisible(section: section, entrees: entrees)
        }
    }
}

/// Textes et identité de l'onglet Compte de l'espace établissement (lot 5, T12). Le rôle affiché est le rôle
/// d'équipe **servi** par `fn_mes_permissions_etab` (contexte de la session), jamais le rôle d'application ni une
/// valeur du JWT ; une valeur hors des cinq rôles connus est affichée telle quelle (`RoleEtab.libelle`).
public enum EtabComptePresentation {
    /// Repli du web quand le nom n'est pas servi (`titre={etab?.nom || 'Mon établissement'}`,
    /// `MonCompteEtablissement.tsx` l.103).
    public static let nomParDefaut = "Mon établissement"
    /// `MonCompteEtablissement.tsx` l.77.
    public static let seDeconnecter = "Se déconnecter"
    public static let libelleVersion = "Version"
    public static let titreApplication = "Application"
    /// Annonce de la reconnexion web (D16), même formule que l'Accueil et le détail d'une mission.
    public static let noteRenvois = "Les pages ci-dessous s'ouvrent sur jolene.app, où une nouvelle connexion peut vous être demandée."

    public static func nom(_ profil: EtablissementProfil) -> String {
        profil.nom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nomParDefaut : profil.nom
    }

    public static func role(_ snapshot: EtablissementSessionSnapshot) -> String {
        snapshot.context.roleEtab.libelle
    }

    public static func email(_ user: AuthenticatedUser) -> String {
        user.email ?? "—"
    }
}
