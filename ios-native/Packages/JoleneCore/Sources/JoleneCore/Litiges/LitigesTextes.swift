import Foundation

/// Textes des litiges du soignant (lot 4, T8 ; HARD STOP n°4), repris de `src/pages/LitigesContestationsSoignant.tsx`,
/// `src/pages/LitigesSoignant.tsx` et `src/components/FilDiscussionLitige.tsx`. Chaque texte du web figure tel quel à sa
/// ligne source (`LitigesVerbatimTests`) ; les refus du serveur ne sont pas ici : ils s'affichent mot pour mot
/// (`OuvertureLitigeOutcome.refuse`, `IssueMessageLitige.refuse`).
///
/// - Texte à portée juridique (`avertissementOuverture`) : repris à l'identique, tutoiement compris, tant que la
///   fondatrice ne l'a pas validé sous une autre forme.
/// - Textes non juridiques tutoyés sur le web : passés au vouvoiement (décision 9 du lot 1), liste `vouvoiements`.
/// - **Aucun texte de délai, de pénalité ou de conséquence n'est ajouté.** Non portés, parce qu'ils énoncent un délai
///   codé en dur côté client (`LOT4_PLAN.md` §1.2) : le bandeau « En médiation amiable — vous avez 7 jours pour vous
///   accorder » (`FilDiscussionLitige.tsx` l.130) et le compte à rebours de 7 jours (`CompteARebours7j.tsx`). Non
///   portés, parce qu'ils relèvent des accords amiables, en renvoi web (D9) : la proposition de résolution reçue
///   (`LitigesSoignant.tsx` l.270), le bandeau d'accord et son suivi (`FilDiscussionLitige.tsx` l.116-119, l.181-185).
/// - Textes sans équivalent web, non juridiques : `nonConfirme`, `messageNonConfirme` (relecture qui ne confirme pas,
///   PRINCIPES §3), `accordWebTitre`, `accordWebMessage` (renvoi vers jolene.app, `LOT4_PLAN.md` §3 T8), `reessayer`,
///   `verifierSession`.
public enum LitigesTextes {
    // MARK: Écran et onglets (LitigesContestationsSoignant.tsx)

    // source: src/pages/LitigesContestationsSoignant.tsx:20
    public static let titreEcran = "Litiges & contestations"
    // source: src/pages/LitigesContestationsSoignant.tsx:29
    public static let ongletLitiges = "Litiges mission"
    // source: src/pages/LitigesContestationsSoignant.tsx:33
    public static let ongletReclamations = "Réclamations"

    // MARK: Liste (LitigesSoignant.tsx)

    // source: src/pages/LitigesSoignant.tsx:191
    public static let titre = "Mes litiges"
    // source: src/pages/LitigesSoignant.tsx:193 (vouvoyé)
    public static let sousTitre = "Suivez vos contestations de missions"
    // source: src/pages/LitigesSoignant.tsx:196
    public static let ouvrir = "Ouvrir un litige"
    // source: src/pages/LitigesSoignant.tsx:72
    public static let chargementImpossible = "Impossible de charger les litiges."
    // source: src/pages/LitigesSoignant.tsx:231
    public static let videTitre = "Aucun litige"
    // source: src/pages/LitigesSoignant.tsx:231 (vouvoyé)
    public static let videMessage = "Vous n'avez aucun litige en cours."
    // source: src/pages/LitigesSoignant.tsx:258
    public static let missionSansIntitule = "Mission"
    // source: src/pages/LitigesSoignant.tsx:261
    public static let etablissementIndisponible = "Établissement non disponible"
    // source: src/pages/LitigesSoignant.tsx:265
    public static let prefixeMotif = "Motif : "

    // MARK: Ouverture (LitigesSoignant.tsx)

    // source: src/pages/LitigesSoignant.tsx:310
    public static let ouvertureTitre = "Ouvrir un nouveau litige"
    /// Texte à portée juridique : mot pour mot, tutoiement du web compris (jamais reformulé).
    // source: src/pages/LitigesSoignant.tsx:315
    public static let avertissementOuverture = "⚠️ Un litige déclenche une procédure de résolution entre toi et l'établissement. Privilégie d'abord la messagerie pour résoudre le problème."
    // source: src/pages/LitigesSoignant.tsx:319
    public static let missionConcernee = "Mission concernée"
    // source: src/pages/LitigesSoignant.tsx:321
    public static let aucuneMissionEligible = "Aucune mission éligible"
    // source: src/pages/LitigesSoignant.tsx:324
    public static let selectionnerMission = "Sélectionner une mission"
    // source: src/pages/LitigesSoignant.tsx:336
    public static let motifDuLitige = "Motif du litige"
    // source: src/pages/LitigesSoignant.tsx:337 (vouvoyé)
    public static let motifPlaceholder = "Décrivez le problème rencontré (minimum 10 caractères)..."
    // source: src/pages/LitigesSoignant.tsx:342
    public static let annuler = "Annuler"
    // source: src/pages/LitigesSoignant.tsx:344
    public static let creation = "Création…"
    // source: src/pages/LitigesSoignant.tsx:344
    public static let ouvrirLeLitige = "⚠️ Ouvrir le litige"
    // source: src/pages/LitigesSoignant.tsx:144
    public static let missionsIndisponibles = "Impossible de charger les missions."
    // source: src/pages/LitigesSoignant.tsx:177 (vouvoyé)
    public static let erreurOuverture = "Une erreur est survenue. Réessayez."
    // source: src/pages/LitigesSoignant.tsx:179
    public static let litigeOuvert = "Litige ouvert avec succès."

    // MARK: Fil de discussion (FilDiscussionLitige.tsx)

    // source: src/components/FilDiscussionLitige.tsx:137
    public static let revueAdmin = "En revue admin — un administrateur va trancher"
    // source: src/components/FilDiscussionLitige.tsx:144
    public static let litigeCloture = "Litige clôturé"
    // source: src/components/FilDiscussionLitige.tsx:154
    public static let aucunMessage = "Aucun message pour le moment"
    // source: src/components/FilDiscussionLitige.tsx:163
    public static let auteurJolene = "🛡️ Jolene"
    // source: src/components/FilDiscussionLitige.tsx:163
    public static let auteurVous = "Vous"
    // source: src/components/FilDiscussionLitige.tsx:163
    public static let auteurSoignant = "Soignant(e)"
    // source: src/components/FilDiscussionLitige.tsx:163
    public static let auteurEtablissement = "Établissement"
    // source: src/components/FilDiscussionLitige.tsx:196
    public static let messagePlaceholder = "Votre message (min. 10 caractères)..."
    // source: src/components/FilDiscussionLitige.tsx:202
    public static let envoi = "Envoi…"
    // source: src/components/FilDiscussionLitige.tsx:202
    public static let envoyer = "Envoyer"
    // source: src/components/FilDiscussionLitige.tsx:70 (`'Erreur lors de l\'envoi'`)
    public static let erreurEnvoi = "Erreur lors de l'envoi"

    // MARK: Sans équivalent web (non juridiques)

    /// Relecture qui ne montre pas le litige annoncé (PRINCIPES §3) : jamais un succès affiché.
    public static let nonConfirme = "L’ouverture du litige n’a pas pu être confirmée. Réessayez."
    /// Relecture du fil qui ne montre pas le message envoyé.
    public static let messageNonConfirme = "L’envoi du message n’a pas pu être confirmé. Réessayez."
    /// Échec de lecture du fil (le web n'affiche rien) : message neutre.
    public static let filIndisponible = "Les messages n’ont pas pu être chargés."
    /// Renvoi des accords amiables vers jolene.app (`LOT4_PLAN.md` §3 T8, D9) : titre de la carte.
    public static let accordWebTitre = "Accord amiable sur jolene.app"
    /// Message neutre de la carte : aucune règle, aucun délai, aucune conséquence.
    public static let accordWebMessage = "Cette étape se fait sur jolene.app."
    public static let reessayer = "Réessayer"
    public static let verifierSession = "Vérifier ma session"

    /// Textes tutoyés du web et leur forme vouvoyée (décision 9 du lot 1 ; aucun n'est juridique). Le texte du web
    /// figure à sa ligne source (`LitigesVerbatimTests`).
    public static let vouvoiements: [(web: String, natif: String, ligne: Int)] = [
        ("Suis tes contestations de missions", sousTitre, 193),
        ("Tu n'as aucun litige en cours.", videMessage, 231),
        ("Décris le problème rencontré (minimum 10 caractères)...", motifPlaceholder, 337),
        ("Une erreur est survenue. Réessaie.", erreurOuverture, 177),
    ]
}

/// Filtre de la liste des litiges (`FiltreStatut` du web, `LitigesSoignant.tsx` l.33 et l.204-209) : groupes de la
/// règle golden `StatutLitige` ; « Résolus » réunit accord et décision (l.118).
public enum FiltreLitiges: String, Equatable, Sendable, CaseIterable {
    case tous = "TOUS"
    case ouvert = "OUVERT"
    case mediation = "MEDIATION"
    case actionAttendue = "ACTION_ATTENDUE"
    case resolu = "RESOLU"
    case ferme = "FERME"

    // source: src/pages/LitigesSoignant.tsx:204-209
    public var libelle: String {
        switch self {
        case .tous: return "Tous"
        case .ouvert: return "Ouverts"
        case .mediation: return "Médiation"
        case .actionAttendue: return "Revue admin"
        case .resolu: return "Résolus"
        case .ferme: return "Fermés"
        }
    }

    /// `litiges-filtre-<groupe>` (`LOT4_PLAN.md` §3 T8), groupe en minuscules.
    public var identifiant: String { "litiges-filtre-\(rawValue.lowercased())" }

    public func contient(_ statut: String) -> Bool {
        let groupe = StatutLitige.regle(statut).groupe
        switch self {
        case .tous: return true
        case .ouvert: return groupe == .ouvert
        case .mediation: return groupe == .mediation
        case .actionAttendue: return groupe == .actionAttendue
        case .resolu: return groupe == .resoluAccord || groupe == .resoluDecision
        case .ferme: return groupe == .ferme
        }
    }
}

/// Filtre proposé et nombre de litiges de son groupe (pastille de `LitigesSoignant.tsx` l.210-225).
public struct CompteFiltreLitiges: Equatable, Sendable, Identifiable {
    public let filtre: FiltreLitiges
    public let nombre: Int
    public var id: String { filtre.rawValue }

    public init(filtre: FiltreLitiges, nombre: Int) { self.filtre = filtre; self.nombre = nombre }
}

/// Règles et mise en forme des litiges (aucun texte nouveau : assemblages du web, valeurs serveur telles quelles).
public enum LitigesPresentation {
    /// Saisie bornée comme le web (`maxLength={1000}` du motif, l.337, et du message, `FilDiscussionLitige.tsx` l.198).
    public static let longueurMaxSaisie = 1000
    /// Borne basse vérifiée avant l'envoi, comme le web (`newMotif.trim().length < 10`, l.343 ;
    /// `newMsg.trim().length < 10`, `FilDiscussionLitige.tsx` l.201) ; le serveur reste seul juge.
    public static let longueurMin = 10

    /// `String.prototype.trim` du web avant l'envoi.
    public static func nettoyer(_ saisie: String) -> String { PrimitivesJS.trim(saisie) }

    /// Longueur JavaScript (`String.length`, unités UTF-16) du texte nettoyé.
    public static func longueur(_ saisie: String) -> Int { nettoyer(saisie).utf16.count }

    public static func envoyable(_ saisie: String) -> Bool { longueur(saisie) >= longueurMin }

    /// `maxLength` d'un champ web : au plus `longueurMaxSaisie` unités UTF-16, sans couper un caractère.
    public static func borner(_ saisie: String) -> String {
        guard saisie.utf16.count > longueurMaxSaisie else { return saisie }
        var unites = 0
        var fin = saisie.startIndex
        for index in saisie.indices {
            let suivant = saisie.index(after: index)
            let taille = saisie.utf16.distance(from: index, to: suivant)
            guard unites + taille <= longueurMaxSaisie else { break }
            unites += taille
            fin = suivant
        }
        return String(saisie[..<fin])
    }

    /// Compteur du motif (`{newMotif.length}/1000`, l.338).
    public static func compteur(_ saisie: String) -> String { "\(saisie.utf16.count)/\(longueurMaxSaisie)" }

    /// Champ de message proposé tant que le litige n'est pas résolu (`LOT4_PLAN.md` §2.4, règle golden `estResolu`) ;
    /// pour les statuts de `litiges_statut_check`, c'est l'ensemble que le serveur accepte (`OUVERT`, `EN_DISCUSSION`,
    /// `EN_MEDIATION`, `MEDIATION_EN_COURS`, `REVUE_ADMIN`). Le serveur reste seul juge (« Ce litige est clôturé. »).
    public static func peutEcrire(statut: String) -> Bool { !StatutLitige.estResolu(statut) }

    /// Renvoi « Accord amiable sur jolene.app » : statuts où le web propose ou confirme un accord
    /// (`peutConfirmerAccord`, règle golden).
    public static func accordSurLeWeb(statut: String) -> Bool { StatutLitige.peutConfirmerAccord(statut) }

    /// Filtres affichés (l.201-210) : aucun sans litige ; sinon « Tous » et les groupes non vides, avec leur compte.
    public static func filtres(_ litiges: [Litige]) -> [CompteFiltreLitiges] {
        guard !litiges.isEmpty else { return [] }
        return FiltreLitiges.allCases.compactMap { filtre in
            let nombre = litiges.filter { filtre.contient($0.statut) }.count
            return filtre == .tous || nombre > 0 ? CompteFiltreLitiges(filtre: filtre, nombre: nombre) : nil
        }
    }

    /// Missions proposées à l'ouverture : celles qui n'ont encore aucun litige (`enrichirMissionsLitigeAvecEtablissements`,
    /// `src/lib/litigeResolutionUi.ts`).
    public static func contestables(_ missions: [MissionContestable], idsEnLitige: Set<String>) -> [MissionContestable] {
        missions.filter { !idsEnLitige.contains($0.id) }
    }

    /// `format(new Date(iso), 'd MMM yyyy', { locale: fr })` à l'heure de Paris ; `nil` si absent ou illisible.
    public static func jour(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty, let instant = try? DateHeureParis.instantJolene(iso) else { return nil }
        return DateHeureParis.format(instant, "d MMM yyyy")
    }

    /// `format(new Date(iso), 'd MMM HH:mm', { locale: fr })` d'un message (`FilDiscussionLitige.tsx` l.166).
    public static func heureMessage(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty, let instant = try? DateHeureParis.instantJolene(iso) else { return nil }
        return DateHeureParis.format(instant, "d MMM HH:mm")
    }

    /// `{mission?.intitule || 'Mission'}` (l.258).
    public static func intitule(_ litige: Litige) -> String {
        guard let intitule = litige.missionIntitule, !intitule.isEmpty else { return LitigesTextes.missionSansIntitule }
        return intitule
    }

    /// « 🏥 {établissement} · {date de la mission} » (l.261-262).
    public static func etablissement(_ litige: Litige) -> String {
        let nom = litige.etablissementNom.flatMap { $0.isEmpty ? nil : $0 } ?? LitigesTextes.etablissementIndisponible
        guard let date = jour(litige.missionDebutLe) else { return "🏥 \(nom)" }
        return "🏥 \(nom) · \(date)"
    }

    /// « Motif : {motif} » (l.265).
    public static func motif(_ litige: Litige) -> String { LitigesTextes.prefixeMotif + (litige.motif ?? "") }

    /// Option du sélecteur de mission (l.328) : « {intitulé} — {établissement} — {date} ».
    public static func option(_ mission: MissionContestable) -> String {
        let nom = mission.etablissementNom.flatMap { $0.isEmpty ? nil : $0 } ?? LitigesTextes.etablissementIndisponible
        return "\(mission.intitule ?? "") — \(nom) — \(jour(mission.debutLe) ?? "")"
    }

    /// Auteur d'un message (`FilDiscussionLitige.tsx` l.157-163) : Jolene pour un admin, « Vous » pour soi, sinon le rôle.
    public static func auteur(_ message: MessageLitige, userId: String) -> String {
        if message.typeAuteur == "ADMIN" { return LitigesTextes.auteurJolene }
        if message.auteurId == userId { return LitigesTextes.auteurVous }
        return message.typeAuteur == "SOIGNANT" ? LitigesTextes.auteurSoignant : LitigesTextes.auteurEtablissement
    }
}

/// Refus de `fn_ouvrir_litige_rate_limited(uuid, type_litige, text)` et de `fn_ajouter_message_litige(uuid, text)`
/// repris mot pour mot du dump (`supabase/schema/public.sql`) : rejoués par le monde démo, jamais reformulés. Garde :
/// `LitigesVerbatimTests.testMessagesServeurPresentsDansLeDump`.
public enum MessagesLitigesServeur {
    public static let accesRefuse = "Accès refusé"
    public static let motifLongueur = "Le motif doit contenir entre 10 et 2 000 caractères."
    public static let missionIntrouvable = "Mission introuvable"
    public static let pasPartiePrenante = "Vous n'êtes pas partie prenante de cette mission."
    public static let dejaOuvert = "Un litige de ce type est déjà ouvert pour cette mission."
    public static let tropDeLitiges = "Trop de litiges ouverts récemment. Réessayez plus tard."
    public static let fenetreFermee = "Fenêtre de contestation fermée pour ce type de litige. Contactez le support."
    public static let litigeIntrouvable = "Litige introuvable ou accès refusé"
    public static let litigeClotureServeur = "Ce litige est clôturé."
    public static let messageLongueur = "Le message doit contenir entre 10 et 5000 caractères."

    /// Refus de l'ouverture (`fn_ouvrir_litige_rate_limited`, 3 arguments).
    public static let ouverture = [accesRefuse, motifLongueur, missionIntrouvable, pasPartiePrenante, dejaOuvert, tropDeLitiges,
                                   fenetreFermee]
    /// Refus de l'ajout d'un message (`fn_ajouter_message_litige`).
    public static let message = [accesRefuse, litigeIntrouvable, litigeClotureServeur, messageLongueur]
}
