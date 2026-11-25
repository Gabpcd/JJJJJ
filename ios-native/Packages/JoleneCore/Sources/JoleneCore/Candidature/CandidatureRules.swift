import Foundation

/// Règles pures de la candidature (lot 1, T6a, `docs/mobile-swift/LOT1_PLAN.md` §3 T6a). Aucune règle
/// juridique ici : les refus (Code du travail, plafond, documents, conflit) viennent du serveur et sont
/// affichés verbatim (HARD STOP n°4). Ces fonctions disent seulement quelle action envoyer et ce qu'une
/// relecture doit montrer pour qu'un succès soit annoncé (PRINCIPES §3 : jamais un succès supposé).
public enum CandidatureRules {
    /// `missions.mode_attribution` qui impose une candidature (`missions_mode_attribution_check` :
    /// `PREMIER_ARRIVE` par défaut, ou `CANDIDATURE`).
    public static let modeCandidature = "CANDIDATURE"

    /// Statuts d'une candidature posée par POSTULER et relue (`fn_postuler_mission` insère `EN_ATTENTE` ;
    /// `EN_ATTENTE_VALIDATION_ETAB` est l'autre statut « en attente » listé par Mes missions).
    public static let statutsCandidaturePosee: Set<String> = ["EN_ATTENTE", "EN_ATTENTE_VALIDATION_ETAB"]

    /// Statut d'une mission attribuée au soignant après ACCEPTER ou PROPOSITION.
    public static let statutAssignee = "ASSIGNEE"

    /// Statut d'une proposition en attente de réponse, et fenêtre de réponse du serveur
    /// (`fn_repondre_proposition` : `cree_le < now() - interval '2 hours'` → `EXPIREE`).
    public static let statutProposee = "PROPOSEE"
    public static let statutRefusee = "REFUSEE"
    public static let fenetreProposition: TimeInterval = 2 * 3600

    /// Action du détail d'une mission ouverte : POSTULER si la mission est en mode candidature, sinon
    /// ACCEPTER (web : `estModeCandidature = mission.mode_attribution === 'CANDIDATURE'`,
    /// `DetailMissionSoignant.tsx` l.637). Un mode absent vaut le défaut serveur `PREMIER_ARRIVE`.
    public static func action(pour mission: MissionRecord) -> ActionPlanning {
        mission.modeAttribution == modeCandidature ? .postuler : .accepter
    }

    /// Vrai si la candidature relue est celle que le serveur vient de créer, sur la bonne mission, encore
    /// en attente.
    public static func candidaturePoseeRelue(_ relue: CandidatureRecord?, id: String, missionId: String) -> Bool {
        guard let relue, relue.id == id, relue.missionId == missionId, let statut = relue.statut else { return false }
        return statutsCandidaturePosee.contains(statut)
    }

    /// Vrai si la mission relue est attribuée au soignant de la session (`statut = ASSIGNEE` et
    /// `soignant_assigne_id = userId`), seule preuve d'un ACCEPTER ou d'une PROPOSITION réussis.
    public static func assignationRelue(statut: String?, soignantAssigneId: String?, userId: String) -> Bool {
        guard !userId.isEmpty, statut == statutAssignee, let soignantAssigneId else { return false }
        return soignantAssigneId.caseInsensitiveCompare(userId) == .orderedSame
    }

    /// Vrai si la proposition relue est refusée (`fn_repondre_proposition(p_accepter := false)`).
    public static func refusRelu(_ relue: CandidatureRecord?, id: String) -> Bool {
        relue?.id == id && relue?.statut == statutRefusee
    }

    /// Proposition encore ouverte côté serveur : `PROPOSEE` et créée il y a moins de 2 h. Une date
    /// illisible ou absente n'ouvre rien (le serveur tranche, l'écran ne promet pas une réponse possible).
    public static func propositionOuverte(_ candidature: CandidatureRecord?, maintenant: Date) -> Bool {
        guard let candidature, candidature.statut == statutProposee,
              let creeLe = candidature.creeLe, let cree = try? DateHeureParis.instantJolene(creeLe) else { return false }
        return cree >= maintenant.addingTimeInterval(-fenetreProposition)
    }

    /// Messages serveur exacts d'une mission sortie de l'état `OUVERTE` entre l'affichage et l'action
    /// (revue B8 de T6a, m1) : forme 3 de `fn_confirmer_action_planning_v1` (`public.sql` l.24649-24653,
    /// verrou `FOR UPDATE`), sa variante sans point de `fn_accepter_mission` (l.5308) et de
    /// `fn_finaliser_attribution_mission` (l.37259), et la course de l'attribution (l.37381). La branche
    /// « `0 rows` / `déjà prise` » du web (`DetailMissionSoignant.tsx` l.807) n'est pas reprise : aucune
    /// fonction live n'émet ces textes, et `contains("0 rows")` reconnaissait aussi « 10 rows ».
    public static let messagesMissionDejaAttribuee: Set<String> = [
        "Cette mission n'est plus disponible.",
        "Cette mission n'est plus disponible",
        "Cette mission vient d'être attribuée.",
    ]

    /// Égalité exacte (aucun `contains`) avec l'un des messages ci-dessus.
    public static func estMissionDejaAttribuee(_ message: String) -> Bool {
        messagesMissionDejaAttribuee.contains(message)
    }

    // MARK: - Proposition (verrou de l'attestation hebdomadaire)

    public static let contratLiberal = "LIBERAL"

    /// Contrat d'une proposition, comme le web : `type_contrat_choisi ?? type_contrat_recherche`
    /// (`CarteProposition.tsx` l.89). Une chaîne vide compte comme absente.
    public static func contratProposition(typeContratChoisi: String?, typeContratRecherche: String?) -> String? {
        let choisi = typeContratChoisi.flatMap { $0.isEmpty ? nil : $0 }
        return choisi ?? typeContratRecherche.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Décision par délégation (revue B8 de T6a, M1) : tant que l'attestation hebdomadaire des heures du web
    /// (`preparerAttestations`, `ModalAttestationHebdo`, table `attestations_heures_externes`) n'est pas portée,
    /// toute proposition dont le contrat n'est pas `LIBERAL` (absent compris) est acceptée sur jolene.app
    /// (`CandidatureVerrou.renvoiWeb`). Gap consigné dans `docs/mobile-swift/LOT1_PLAN.md` §3 T6b et §7.
    public static func propositionVerrouillee(contrat: String?) -> Bool {
        contrat != contratLiberal
    }

    // MARK: - Actions hors lot 1

    /// Garde des actions de `fn_confirmer_action_planning_v1` non servies au lot 1 (SWIPE_LIKE, URGENCE) :
    /// refus avant tout envoi, en citant le périmètre (`LOT1_PLAN.md` §1.2) et le lot qui les livre.
    public static func actionHorsLot1(_ action: ActionPlanning) -> JoleneError {
        JoleneError(.contract, "Action \(action.rawValue) hors du lot 1 (docs/mobile-swift/LOT1_PLAN.md §1.2) : livrée au lot 4 avec sa propre relecture.")
    }
}
