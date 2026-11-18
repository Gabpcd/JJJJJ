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

    /// Exception PostgREST d'une mission prise entre l'affichage et l'action : le web ouvre la modale
    /// « mission perdue » si le message contient `0 rows` ou `déjà prise` (`DetailMissionSoignant.tsx`
    /// l.807, `includes`, sensible à la casse).
    public static func estMissionDejaAttribuee(_ message: String) -> Bool {
        message.contains("0 rows") || message.contains("déjà prise")
    }
}
