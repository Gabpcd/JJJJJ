import Foundation

/// Clé d'une action prioritaire de l'Accueil établissement (identifiants `etab-action-<cle>`).
public enum CleActionPrioritaire: String, CaseIterable, Sendable {
    case blocage, verification, candidatures, presences, litiges, factures, evaluations, messages
}

/// Action prioritaire : texte, compteur servi, chemin web équivalent. Le chemin est résolu par la table des liens de
/// l'espace établissement (`LinkRouter.etablissementDestination`) : onglet natif ou écran livré, sinon renvoi web —
/// une seule source décide où mène l'action, comme pour un lien reçu.
public struct ActionPrioritaire: Equatable, Sendable, Identifiable {
    public var cle: CleActionPrioritaire
    public var titre: String
    public var detail: String?
    public var cta: String
    /// Chemin web de l'action (`navigate(...)` du web), relatif à `https://jolene.app`.
    public var chemin: String
    /// Valeur servie par le serveur ; `nil` pour une action sans compteur (correction 20).
    public var compteur: Int?
    public var urgente: Bool

    public var id: String { cle.rawValue }

    public init(cle: CleActionPrioritaire, titre: String, detail: String? = nil, cta: String, chemin: String,
                compteur: Int? = nil, urgente: Bool = false) {
        self.cle = cle; self.titre = titre; self.detail = detail; self.cta = cta; self.chemin = chemin
        self.compteur = compteur; self.urgente = urgente
    }
}

/// Liste des actions prioritaires de l'Accueil (lot 5, T4 ; `LOT5_PLAN.md` §1.1, §2.7, §3 T4), fonction pure.
///
/// Ordre (celui du web, `DashboardEtablissement.tsx` l.646-702, présences et factures insérées) : blocage >
/// vérification > candidatures > présences > litiges > factures > évaluations > messages. Toutes les actions sont
/// listées (le web n'en garde que deux, l.702). Filtrage fail-closed par les booléens servis (§2.7) — le natif
/// n'écrit aucune correspondance rôle → permission :
/// - candidatures : `candidatures` ; présences : `pointage` ; factures (compteur sans montant) : `lecture_paiement` ∨
///   `paiement` ; litiges et évaluations : `missions` (aucune clé serveur ne les vise ; choix d'affichage consigné
///   dans `DECISIONS_LOT5.md`, T4) ; messages : `lecture` ; blocage et vérification : tout membre, comme le bandeau du
///   web (l.555-570).
/// - présences et évaluations n'ont pas de source serveur (correction 20) : action sans compteur, toujours listée, sous
///   un libellé neutre (« Valider les présences », « Évaluer vos soignants ») qui n'affirme aucun fait inconnu de l'app.
///
/// Blocage et vérification : le titre de suspension (`TextesWeb.BlocageEtablissement`, `BandeauBlocageAuto.tsx` l.61)
/// et le bandeau de vérification (l.564-565) attendent la validation HARD STOP n°4 de Gabrielle (§6.4, garde
/// `contrats-etablissement-ios.node.mjs`) : d'ici là, l'action porte un texte natif de navigation, sans qualification
/// de l'état du compte, et mène à la page web qui l'explique. Aucun montant (`BandeauBlocageAuto.tsx` l.74-88).
public enum PrioriteActions {
    public enum Textes {
        public static let blocageTitre = "Action requise sur jolene.app"
        public static let blocageDetail = "Consultez la situation de votre établissement sur jolene.app."
        public static let blocageCta = "Voir sur jolene.app"
        public static let verificationTitre = "Vérification de l'établissement"
        public static let verificationDetail = "Suivez la vérification de votre établissement sur jolene.app."
        /// Bouton du bandeau web (`DashboardEtablissement.tsx` l.567).
        public static let verificationCta = "Vérifier mon établissement"
        /// Sous-texte et bouton des candidatures (l.661-662).
        public static let candidaturesDetail = "Répondez vite — ils peuvent accepter ailleurs"
        public static let candidaturesCta = "Répondre"
        /// Présences et évaluations n'ont pas de compteur (correction 20) : libellés neutres, qui n'affirment pas qu'il
        /// reste quelque chose à faire (intégration de la vague C, revue B8 de #1160, m3 ; texte d'interface, non juridique).
        public static let presencesTitre = "Valider les présences"
        public static let presencesCta = "Voir"
        public static let litigesCta = "Gérer"
        public static let facturesCta = "Voir"
        public static let evaluationsTitre = "Évaluer vos soignants"
        /// Bouton du web (l.682).
        public static let evaluationsCta = "Évaluer"
        public static let messagesCta = "Ouvrir"

        /// `${n} soignant${n > 1 ? 's' : ''} attend${n > 1 ? 'ent' : ''} votre réponse` (l.660).
        public static func candidatures(_ n: Int) -> String {
            n > 1 ? "\(n) soignants attendent votre réponse" : "\(n) soignant attend votre réponse"
        }

        /// `${n} litige${n > 1 ? 's' : ''} en cours` (l.670).
        public static func litiges(_ n: Int) -> String { "\(n) litige\(n > 1 ? "s" : "") en cours" }

        /// `${n} facture(s) à régler` (l.858), sans montant.
        public static func factures(_ n: Int) -> String { "\(n) facture(s) à régler" }

        /// `${n} message${s} non lu${s}` (l.693).
        public static func messages(_ n: Int) -> String {
            n > 1 ? "\(n) messages non lus" : "\(n) message non lu"
        }
    }

    /// Chemins web des actions (`navigate(...)` du web, routes de `src/App.tsx`).
    public enum Chemins {
        public static let facturation = "/etablissement/facturation"
        public static let activer = "/etablissement/activer"
        /// Liste des missions ouvertes (l.664).
        public static let candidatures = "/etablissement/missions?statut=OUVERTE"
        public static let presences = "/etablissement/presences"
        public static let litiges = "/etablissement/litiges"
        public static let evaluations = "/etablissement/evaluations-a-faire"
        public static let messagerie = "/etablissement/messagerie"
        public static let publier = "/etablissement/missions/creer"

        /// Détail d'une mission (`ouvrir(id)` de `SectionPlanning.tsx` l.217), identifiant encodé.
        public static func mission(_ id: String) -> String {
            "/etablissement/missions/\(id.addingPercentEncoding(withAllowedCharacters: segment) ?? "")"
        }

        private static let segment = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    }

    public static func liste(profil: EtablissementProfil, stats: EtabDashboardStats, permissions: PermissionsEtab) -> [ActionPrioritaire] {
        var actions: [ActionPrioritaire] = []
        // Blocage dur (web l.555-570) : suspension automatique, sinon vérification requise (`!peut_publier_missions`,
        // une valeur absente comprise, comme le web).
        if profil.bloqueAutoLe != nil {
            actions.append(ActionPrioritaire(cle: .blocage, titre: Textes.blocageTitre, detail: Textes.blocageDetail,
                                             cta: Textes.blocageCta, chemin: Chemins.facturation, urgente: true))
        } else if profil.peutPublierMissions != true {
            actions.append(ActionPrioritaire(cle: .verification, titre: Textes.verificationTitre, detail: Textes.verificationDetail,
                                             cta: Textes.verificationCta, chemin: Chemins.activer, urgente: true))
        }
        if permissions.candidatures, let n = stats.candidaturesEnAttente, n > 0 {
            actions.append(ActionPrioritaire(cle: .candidatures, titre: Textes.candidatures(n), detail: Textes.candidaturesDetail,
                                             cta: Textes.candidaturesCta, chemin: Chemins.candidatures, compteur: n, urgente: true))
        }
        if permissions.pointage {
            actions.append(ActionPrioritaire(cle: .presences, titre: Textes.presencesTitre, cta: Textes.presencesCta,
                                             chemin: Chemins.presences))
        }
        if permissions.missions, let n = stats.litigesOuverts, n > 0 {
            actions.append(ActionPrioritaire(cle: .litiges, titre: Textes.litiges(n), cta: Textes.litigesCta,
                                             chemin: Chemins.litiges, compteur: n))
        }
        if permissions.lecturePaiement || permissions.paiement, let n = stats.nbFacturesImpayees, n > 0 {
            actions.append(ActionPrioritaire(cle: .factures, titre: Textes.factures(n), cta: Textes.facturesCta,
                                             chemin: Chemins.facturation, compteur: n))
        }
        if permissions.missions {
            actions.append(ActionPrioritaire(cle: .evaluations, titre: Textes.evaluationsTitre, cta: Textes.evaluationsCta,
                                             chemin: Chemins.evaluations))
        }
        if permissions.lecture, let n = stats.messagesNonLus, n > 0 {
            actions.append(ActionPrioritaire(cle: .messages, titre: Textes.messages(n), cta: Textes.messagesCta,
                                             chemin: Chemins.messagerie, compteur: n))
        }
        return actions
    }

    /// Résolution d'un chemin d'action par la table des liens de l'espace établissement (T2b) : onglet ou écran livré,
    /// sinon renvoi web de l'URL canonique. `nil` seulement pour un chemin qui n'est pas un lien Jolene (jamais ici).
    public static func presentation(chemin: String) -> PresentationLienEtablissement? {
        guard let resultat = LinkRouter.etablissementDestination(link: chemin) else { return nil }
        return resultat.route.presentation(canonique: resultat.canonique)
    }
}
