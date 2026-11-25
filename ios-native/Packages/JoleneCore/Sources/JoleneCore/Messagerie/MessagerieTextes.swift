import Foundation

/// Textes de la messagerie native (lot 4, T7b ; `LOT4_PLAN.md` §3 T7b), repris **mot pour mot** du web, source en
/// commentaire (fichier et ligne), prouvés à la ligne par `MessagerieVerbatimTests`. HARD STOP n°4 : les textes de
/// l'anti-fuite (`AntiFuite`), du blocage (`Blocage`) et du signalement (`Signalement`) ne sont jamais reformulés ici ;
/// un changement part d'abord sur le web. Aucun texte nouveau à portée contractuelle.
///
/// Seules exceptions, sans équivalent web et non contractuelles : « Écrire à l'établissement » (intitulé adopté par
/// D25, `DECISIONS_LOT4.md`, pour l'accès au fil de la mission que le web incruste dans la page) et « Envoi non
/// confirmé » (mention de `ChatBubble`, JoleneDesign, T1b), affichée quand l'issue d'un envoi n'est pas confirmée.
public enum MessagerieTextes {
    // MARK: Liste (`src/pages/PageMessagerie.tsx`)

    // source: src/pages/PageMessagerie.tsx:545
    public static let titre = "Messagerie"
    // source: src/pages/PageMessagerie.tsx:557
    public static let recherche = "Rechercher une conversation…"
    // source: src/pages/PageMessagerie.tsx:571
    public static let ongletActives = "Actives"
    // source: src/pages/PageMessagerie.tsx:580 (suivi du nombre entre parenthèses s'il est positif)
    public static let ongletArchivees = "Archivées"
    // source: src/pages/PageMessagerie.tsx:589
    public static let echecListe = "Impossible de charger vos conversations."
    // source: src/pages/PageMessagerie.tsx:591
    public static let reessayerListe = "Réessayer les conversations"
    // source: src/pages/PageMessagerie.tsx:598
    public static let videActives = "Aucune conversation"
    public static let videArchivees = "Aucune conversation archivée"
    // source: src/pages/PageMessagerie.tsx:602
    public static let videRecherche = "Aucune conversation ne correspond à votre recherche."
    // source: src/pages/PageMessagerie.tsx:604
    public static let videArchiveesDetail = "Les conversations sont archivées 30 jours après la fin d'une mission."
    // source: src/pages/PageMessagerie.tsx:605
    public static let videActivesDetail = "Les conversations s'ouvrent automatiquement quand votre candidature est acceptée."
    // source: src/pages/PageMessagerie.tsx:644 (préfixe de l'intitulé de mission)
    public static let prefixeMission = "Mission · "
    // source: src/pages/PageMessagerie.tsx:648
    public static let aucunMessage = "Aucun message"
    // source: src/pages/PageMessagerie.tsx:651
    public static let archiveeLectureSeule = "Archivée — lecture seule"
    // source: src/pages/PageMessagerie.tsx:260 (nom par défaut d'un interlocuteur sans ligne)
    public static let nomParDefaut = "Jolene"
    // source: src/pages/PageMessagerie.tsx:523
    public static let conversationIndisponible = "Cette conversation n'est plus accessible."
    // source: src/pages/PageMessagerie.tsx:669
    public static let retourConversations = "Retour aux conversations"

    // MARK: Fil

    // source: src/pages/PageMessagerie.tsx:765 (bulle d'un collègue, rôle ADMIN_ETABLISSEMENT ; lot 5, T11)
    public static let equipeEtablissement = "Équipe établissement"
    // source: src/pages/PageMessagerie.tsx:721
    public static let echecFil = "Impossible de charger les messages."
    // source: src/pages/PageMessagerie.tsx:723
    public static let reessayerFil = "Réessayer les messages"
    // source: src/pages/PageMessagerie.tsx:729
    public static let filVide = "Aucun message. Envoyez le premier !"
    // source: src/pages/PageMessagerie.tsx:106
    public static let maintenant = "Maintenant"
    // source: src/pages/PageMessagerie.tsx:108
    public static let hier = "Hier"
    // source: src/pages/PageMessagerie.tsx:118
    public static let enLigne = "En ligne"
    // source: src/pages/PageMessagerie.tsx:119
    public static let absent = "Absent"
    // source: src/pages/PageMessagerie.tsx:120
    public static let horsLigne = "Hors ligne"
    // source: src/pages/PageMessagerie.tsx:121 (`Vu ${formatDistanceToNowStrict(…)}`)
    public static let prefixeVu = "Vu "

    // MARK: Refus d'envoi (`src/components/messagerie/InputMessage.tsx`)

    // source: src/components/messagerie/InputMessage.tsx:113
    public static let refusLimite = "Trop de messages envoyés. Patientez quelques secondes."
    // source: src/components/messagerie/InputMessage.tsx:115
    public static let refusTropLong = "Message trop long."
    // source: src/components/messagerie/InputMessage.tsx:117
    public static let refusArchivee = "Cette conversation est archivée."
    // source: src/components/messagerie/InputMessage.tsx:123
    public static let refusGenerique = "Impossible d'envoyer le message. Veuillez réessayer."

    // MARK: Barre de navigation (`src/components/BarreNavigation.tsx`)

    // source: src/components/BarreNavigation.tsx:401
    public static let boutonMessages = "Messages"

    // MARK: « Écrire à l'établissement » (détail de mission)

    /// Intitulé du bouton (D25, sans équivalent web : le web incruste le fil dans la page, `DetailMissionSoignant.tsx`
    /// l.1550-1558).
    public static let ecrireEtablissement = "Écrire à l'établissement"
    // source: src/hooks/useOuvrirConversation.ts:46
    public static let ouvertureImpossible = "Impossible d'ouvrir la conversation."
    // source: src/pages/DetailMissionSoignant.tsx:1170
    public static let autresActions = "Autres actions"

    /// Mention d'un envoi dont l'issue n'est pas confirmée (`ChatBubble.nonConfirmeText`, JoleneDesign T1b) : le fil a été
    /// relu, rien n'a été renvoyé, le texte reste dans le composeur.
    public static let envoiNonConfirme = "Envoi non confirmé"

    // MARK: - Anti-fuite (HARD STOP, `src/components/messagerie/ModaleEducativeAntiLeak.tsx`)

    public enum AntiFuite {
        // source: src/components/messagerie/ModaleEducativeAntiLeak.tsx:60
        public static let titre = "Pour votre sécurité"
        // source: src/components/messagerie/ModaleEducativeAntiLeak.tsx:62
        public static let sousTitre = "Règle de protection des échanges avant la confirmation d'une mission."
        // source: src/components/messagerie/ModaleEducativeAntiLeak.tsx:44
        public static let telephone = "Les numéros de téléphone ne peuvent pas être échangés via la messagerie Jolene."
        // source: src/components/messagerie/ModaleEducativeAntiLeak.tsx:45
        public static let email = "Les adresses email ne peuvent pas être échangées via la messagerie Jolene."
        // source: src/components/messagerie/ModaleEducativeAntiLeak.tsx:46
        public static let url = "Les liens externes ne peuvent pas être partagés via la messagerie Jolene."
        // source: src/components/messagerie/ModaleEducativeAntiLeak.tsx:47
        public static let handle = "Les noms d'utilisateurs de réseaux sociaux ne peuvent pas être partagés via la messagerie Jolene."
        // source: src/components/messagerie/ModaleEducativeAntiLeak.tsx:48
        public static let motCle = "Cette mention pourrait suggérer un échange hors plateforme."
        // source: src/components/messagerie/ModaleEducativeAntiLeak.tsx:51
        public static let explication = "Toutes les communications doivent rester sur la plateforme pour votre protection mutuelle et le bon fonctionnement de la mission. En cas de besoin pratique, contactez le support Jolene."
        // source: src/components/messagerie/ModaleEducativeAntiLeak.tsx:74
        public static let compris = "J'ai compris, je modifie mon message"

        /// Description du type détecté ; `KEYWORD` à défaut (l.54).
        public static func description(_ type: DetectedType?) -> String {
            switch type ?? .keyword {
            case .telephone: return telephone
            case .email: return email
            case .url: return url
            case .handle: return handle
            case .keyword: return motCle
            }
        }
    }

    // MARK: - Blocage (HARD STOP, `src/components/BloquerUtilisateur.tsx`)

    public enum Blocage {
        // source: src/components/BloquerUtilisateur.tsx:80
        public static let bloquer = "Bloquer"
        public static let debloquer = "Débloquer"
        // source: src/components/BloquerUtilisateur.tsx:88
        public static let confirmer = "Confirmer"
        // source: src/components/BloquerUtilisateur.tsx:89
        public static let annuler = "Annuler"
        // source: src/components/BloquerUtilisateur.tsx:74
        public static let statutIndisponible = "Statut de blocage indisponible."
        // source: src/components/BloquerUtilisateur.tsx:75
        public static let reessayerStatut = "Réessayer le statut de blocage"
        // source: src/components/BloquerUtilisateur.tsx:55
        public static let echec = "Action impossible pour le moment."
        // source: src/components/BloquerUtilisateur.tsx:66
        public static let echecReessayer = "Action impossible pour le moment. Réessayez."
        // source: src/components/BloquerUtilisateur.tsx:20 (défaut de `libelleCible`)
        public static let cibleUtilisateur = "cet utilisateur"
        // source: src/pages/PageMessagerie.tsx:710 (soignant, conversation d'un établissement)
        public static let cibleEtablissement = "l’établissement"
        // source: src/components/BloquerUtilisateur.tsx:63 (suite du message de blocage)
        public static let suiteBlocage = " — les nouveaux messages sont coupés dans les deux sens."

        /// Libellé de la cible (`PageMessagerie.tsx` l.708-712) : `l’établissement` pour une conversation rattachée à un
        /// établissement, `cet utilisateur` sinon.
        public static func cible(etablissement: Bool) -> String { etablissement ? cibleEtablissement : cibleUtilisateur }

        /// « Bloquer l’établissement ? » (l.87).
        public static func question(cible: String) -> String { "\(bloquer) \(cible) ?" }

        /// Message de succès (l.60-64) : `L’établissement débloqué.`, `Cet utilisateur bloqué·e — les nouveaux
        /// messages sont coupés dans les deux sens.` (accord `·e` sauf pour `l’établissement`).
        public static func succes(cible: String, bloque: Bool) -> String {
            let majuscule = cible.prefix(1).uppercased() + cible.dropFirst()
            let accord = cible == cibleEtablissement ? "" : "·e"
            return bloque ? "\(majuscule) bloqué\(accord)\(suiteBlocage)" : "\(majuscule) débloqué\(accord)."
        }
    }

    // MARK: - Signalement (HARD STOP, `src/components/SignalerUtilisateur.tsx`)

    public enum Signalement {
        /// Catégories dans l'ordre du web (l.6-14) : valeur envoyée (`SignalementUtilisateur.categories`) et libellé.
        // source: src/components/SignalerUtilisateur.tsx:6-14
        public static let categories: [(valeur: String, libelle: String)] = [
            ("COMPORTEMENT_INAPPROPRIE", "Comportement inapproprié"),
            ("NON_PROFESSIONNALISME", "Manque de professionnalisme"),
            ("FRAUDE_SUSPECTEE", "Fraude suspectée"),
            ("FAUX_DOCUMENT", "Faux document"),
            ("USURPATION_IDENTITE", "Usurpation d'identité"),
            ("SECURITE_DANGER", "Sécurité / danger"),
            ("AUTRE", "Autre"),
        ]
        /// Catégorie présélectionnée (l.30).
        public static let categorieParDefaut = "COMPORTEMENT_INAPPROPRIE"
        // source: src/components/SignalerUtilisateur.tsx:68 (variante lien)
        public static let signaler = "Signaler"
        // source: src/components/SignalerUtilisateur.tsx:75
        public static let titre = "Signaler à Jolene"
        // source: src/components/SignalerUtilisateur.tsx:76
        public static let introduction = "Votre signalement est transmis à l'administration Jolene, qui l'examinera. Soyez précis et factuel."
        // source: src/components/SignalerUtilisateur.tsx:78
        public static let motif = "Motif"
        // source: src/components/SignalerUtilisateur.tsx:84
        public static let precisez = "Précisez (obligatoire)"
        // source: src/components/SignalerUtilisateur.tsx:86
        public static let placeholder = "Décrivez précisément ce que vous signalez…"
        // source: src/components/SignalerUtilisateur.tsx:89
        public static let annuler = "Annuler"
        // source: src/components/SignalerUtilisateur.tsx:92
        public static let envoi = "Envoi…"
        public static let envoyer = "Envoyer le signalement"
        // source: src/components/SignalerUtilisateur.tsx:36
        public static let motifTropCourt = "Merci de préciser le motif (10 caractères minimum)."
        // source: src/components/SignalerUtilisateur.tsx:50
        public static let echec = "Échec de l'envoi du signalement."
        // source: src/components/SignalerUtilisateur.tsx:53
        public static let succes = "Signalement transmis à Jolene. Merci, notre équipe va l’examiner."
    }
}

/// Règles d'affichage de la messagerie (lot 4, T7b), portées de `PageMessagerie.tsx` et d'`InputMessage.tsx`. Fonctions
/// pures : l'écran n'y ajoute aucune règle.
public enum MessageriePresentation {
    /// Auteur des messages système (`PageMessagerie.tsx` l.734) et cible exclue du blocage (l.705).
    public static let auteurSysteme = "00000000-0000-0000-0000-000000000000"

    /// Libellé d'un refus d'envoi (`InputMessage.tsx` l.110-124) ; l'anti-fuite avec un type détecté ouvre la feuille
    /// éducative à la place. Le message serveur n'est jamais affiché ici, comme le web.
    public static func libelleRefus(code: String?) -> String {
        switch code {
        case CodeEnvoi.limite: return MessagerieTextes.refusLimite
        case CodeEnvoi.contenuTropLong: return MessagerieTextes.refusTropLong
        case CodeEnvoi.conversationArchivee: return MessagerieTextes.refusArchivee
        default: return MessagerieTextes.refusGenerique
        }
    }

    /// Nom affiché d'une conversation (`${autre_prenom} ${autre_nom}`, l.260-261) : `Jolene` sans prénom servi.
    public static func nom(_ conversation: ConversationAffichee) -> String {
        let prenom = conversation.interlocuteur?.prenom.flatMap { $0.isEmpty ? nil : $0 } ?? MessagerieTextes.nomParDefaut
        let nom = conversation.interlocuteur?.nom ?? ""
        return "\(prenom) \(nom)".trimmingCharacters(in: .whitespaces)
    }

    /// Aperçu du dernier message : 60 premiers caractères (unités UTF-16 comme `slice(0, 60)`), sinon « Aucun message ».
    public static func apercu(_ conversation: ConversationAffichee) -> String {
        guard let contenu = conversation.apercu.dernierContenu, !contenu.isEmpty else { return MessagerieTextes.aucunMessage }
        var sortie = ""
        var unites = 0
        for caractere in contenu {
            let longueur = String(caractere).utf16.count
            guard unites + longueur <= 60 else { break }
            sortie.append(caractere)
            unites += longueur
        }
        return sortie
    }

    /// Pastille de non-lus (`99+` au-delà), `nil` à zéro.
    public static func pastille(_ nonLus: Int) -> String? {
        guard nonLus > 0 else { return nil }
        return nonLus > 99 ? "99+" : String(nonLus)
    }

    /// Badge du bouton Messages (`BarreNavigation.tsx` l.405-408) : `9+` au-delà de 9, `nil` à zéro ou non lu.
    public static func badge(_ nonLus: Int?) -> String? {
        guard let nonLus, nonLus > 0 else { return nil }
        return nonLus > 9 ? "9+" : String(nonLus)
    }

    /// Filtre de la recherche locale (l.494-503) : nom, intitulé de mission ou dernier message, sans casse.
    public static func filtrer(_ conversations: [ConversationAffichee], terme: String) -> [ConversationAffichee] {
        let cle = terme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cle.isEmpty else { return conversations }
        return conversations.filter { c in
            nom(c).lowercased().contains(cle)
                || (c.apercu.missionIntitule ?? "").lowercased().contains(cle)
                || (c.apercu.dernierContenu ?? "").lowercased().contains(cle)
        }
    }

    /// Horodatage de la liste (`formatTimestampIntelligent`, l.101-112), heure de Paris : `Maintenant` sous une minute,
    /// `HH:mm` le jour même, `Hier`, jour abrégé sous sept jours, `d MMM` au-delà ; `nil` si la date est illisible.
    public static func horodatage(_ valeur: String?, maintenant: Date) -> String? {
        guard let valeur, let date = PlanningHorlogeParis.instant(valeur) else { return nil }
        if maintenant.timeIntervalSince(date) < 60 { return MessagerieTextes.maintenant }
        if DateHeureParis.memeJour(date, maintenant) { return DateHeureParis.format(date, "HH:mm") }
        if DateHeureParis.memeJour(date, DateHeureParis.ajouterJoursCivils(maintenant, -1)) { return MessagerieTextes.hier }
        // `differenceInDays` : jours entiers écoulés (heure murale comprise), tronqués.
        let jours = Int((maintenant.timeIntervalSince(date) / 86_400).rounded(.towardZero))
        if jours < 7 { return DateHeureParis.format(date, "EEE") }
        return DateHeureParis.format(date, "d MMM")
    }

    /// Heure d'une bulle (`format(new Date(cree_le), 'HH:mm')`, l.775), heure de Paris.
    public static func heure(_ message: MessageChat) -> String? {
        message.instant.map { DateHeureParis.format($0, "HH:mm") }
    }

    /// Présence de l'interlocuteur (`formatPresence`, l.114-122).
    public static func presence(_ etat: EtatPresence?, maintenant: Date) -> String {
        switch etat?.statut {
        case .enLigne?: return MessagerieTextes.enLigne
        case .absent?: return MessagerieTextes.absent
        default:
            guard let vu = etat?.vuLe else { return MessagerieTextes.horsLigne }
            return MessagerieTextes.prefixeVu + distanceStricte(depuis: vu, maintenant: maintenant)
        }
    }

    /// `formatDistanceToNowStrict(date, { addSuffix: true, locale: fr })` de date-fns (arrondi `round`, unités seconde à
    /// année ; mois de 30 jours, année de 365 jours) : « il y a 6 jours », « dans 2 minutes ».
    public static func distanceStricte(depuis date: Date, maintenant: Date) -> String {
        let secondes = maintenant.timeIntervalSince(date)
        let minutes = abs(secondes) / 60
        let unite: (un: String, plusieurs: String, valeur: Double)
        if minutes < 1 {
            unite = ("1 seconde", "secondes", abs(secondes))
        } else if minutes < 60 {
            unite = ("1 minute", "minutes", minutes)
        } else if minutes < 1440 {
            unite = ("1 heure", "heures", minutes / 60)
        } else if minutes < 43_200 {
            unite = ("1 jour", "jours", minutes / 1440)
        } else if minutes < 525_600 {
            unite = ("1 mois", "mois", minutes / 43_200)
        } else {
            unite = ("1 an", "ans", minutes / 525_600)
        }
        let n = Int(unite.valeur.rounded(.toNearestOrAwayFromZero))
        let texte = n == 1 ? unite.un : "\(n) \(unite.plusieurs)"
        return secondes >= 0 ? "il y a \(texte)" : "dans \(texte)"
    }

    /// Nature d'une bulle (l.732-750, rôle soignant) : message système (admin, auteur nul), le mien, la plateforme
    /// (`est_admin`), l'interlocuteur.
    public enum NatureBulle: Equatable, Sendable { case moi, interlocuteur, jolene, systeme }

    public static func nature(_ message: MessageChat, moi: String) -> NatureBulle {
        if message.estAdmin, message.auteurId == auteurSysteme { return .systeme }
        if message.auteurId?.lowercased() == moi.lowercased() { return .moi }
        return message.estAdmin ? .jolene : .interlocuteur
    }

    /// Nature d'une bulle côté établissement (lot 5, T11 ; l.738-745, rôle `ADMIN_ETABLISSEMENT`) : dans une
    /// conversation rattachée à un soignant, tout message non administrateur qui n'est pas du soignant est du côté de
    /// l'établissement (le mien ou celui d'un collègue) ; sinon, règle du soignant (`moi` = utilisateur courant).
    public static func natureEtablissement(_ message: MessageChat, moi: String, soignantId: String?) -> NatureBulle {
        if message.estAdmin { return nature(message, moi: moi) }
        guard let soignantId, !soignantId.isEmpty else { return nature(message, moi: moi) }
        return message.auteurId?.lowercased() == soignantId.lowercased() ? .interlocuteur : .moi
    }

    /// Message écrit par un collègue de l'équipe (l.746-748) : du côté de l'établissement, mais pas par l'utilisateur
    /// courant ; la bulle porte alors « Équipe établissement ».
    public static func messageEquipe(_ message: MessageChat, moi: String, soignantId: String?) -> Bool {
        natureEtablissement(message, moi: moi, soignantId: soignantId) == .moi && !message.estAdmin
            && message.auteurId?.lowercased() != moi.lowercased()
    }
}

/// Cibles du blocage et du signalement depuis le fil (exigence Apple 1.2). Blocage sur `autre_id` (l.701-713),
/// signalement de l'établissement (`ETABLISSEMENT`, `etablissement_id`, `mission_id`, comme le détail de mission) ;
/// aucun des deux pour une conversation avec la plateforme (`LOT4_PLAN.md` §3 T7b, corrigé v2).
public struct ModerationConversation: Equatable, Sendable {
    public struct CibleSignalement: Equatable, Sendable {
        public var cibleId: String
        public var type: TypeCibleSignalement
        public var missionId: String?

        public init(cibleId: String, type: TypeCibleSignalement, missionId: String?) {
            self.cibleId = cibleId; self.type = type; self.missionId = missionId
        }
    }

    /// `autre_id` à bloquer ; `nil` : pas de blocage proposé.
    public var blocage: String?
    /// Libellé de la cible du blocage (`l’établissement` ou `cet utilisateur`).
    public var libelleCible: String
    public var signalement: CibleSignalement?

    public static func pour(_ conversation: ConversationAffichee) -> ModerationConversation {
        pour(conversation, etablissement: false)
    }

    /// Lot 5 (T11) : côté établissement, cible du blocage `cet utilisateur` (le web ne passe `l’établissement` qu'au
    /// rôle `SOIGNANT`, l.709-712) et signalement du soignant de la conversation (`SOIGNANT`, `soignant_id`, sans
    /// mission, comme `ProfilSoignantEtablissement.tsx` l.145) ; rien pour une conversation avec la plateforme.
    public static func pour(_ conversation: ConversationAffichee, etablissement: Bool) -> ModerationConversation {
        let apercu = conversation.apercu
        let libelle = MessagerieTextes.Blocage.cible(etablissement: !etablissement && apercu.etablissementId != nil)
        guard !conversation.estJolene else { return ModerationConversation(blocage: nil, libelleCible: libelle, signalement: nil) }
        let autre = apercu.autreId.flatMap { $0.isEmpty || $0 == MessageriePresentation.auteurSysteme ? nil : $0 }
        let signalement: CibleSignalement?
        if etablissement {
            signalement = apercu.soignantId.flatMap { id in
                id.isEmpty ? nil : CibleSignalement(cibleId: id, type: .soignant, missionId: nil)
            }
        } else {
            signalement = apercu.etablissementId.flatMap { id in
                id.isEmpty ? nil : CibleSignalement(cibleId: id, type: .etablissement, missionId: apercu.missionId)
            }
        }
        return ModerationConversation(blocage: autre, libelleCible: libelle, signalement: signalement)
    }
}
