import Foundation

/// Confirmation de présence J-2 → J0 du détail de mission (lot 1, T6c, `LOT1_PLAN.md` §2.6 et §3 T6c, décision 16).
/// Parité `DetailMissionSoignant.tsx` l.1414-1440 : bloc affiché au soignant assigné d'une mission `ASSIGNEE` qui démarre
/// dans moins de 48 h et n'est pas encore confirmée ; état « confirmée » dès que `presence_confirmee_le` est relu. Le
/// seuil de 48 h est celui du web, en dur, alors que le cron des rappels lit `confirmation_j1_max_h` (36 h) : parité
/// assumée (§7 Q16). `EN_COURS` est exclu comme sur le web, bien que le serveur l'accepte. Aucune règle juridique.
public enum PresenceRules {
    public enum Bloc: Equatable, Sendable {
        case masque
        /// Bloc « Confirmez votre présence » avec le bouton `TextesWeb.ConfirmationPresence.bouton`.
        case aConfirmer
        /// `presence_confirmee_le` relu non nul : état `TextesWeb.ConfirmationPresence.etatConfirme`, plus de bouton.
        case confirmee
    }

    /// Fenêtre du web (`48 * 3600000`, l.1415).
    public static let fenetre: TimeInterval = 48 * 3600

    /// Textes du bloc que le web tutoie, vouvoyés (décision 9 : seule la personne change). Le bouton, la confirmation,
    /// l'état et le repli sont repris à l'identique dans `TextesWeb.ConfirmationPresence` (HARD STOP n°4).
    public enum Textes {
        // source: src/pages/DetailMissionSoignant.tsx:1419 (vouvoyé : « Confirme ta »)
        public static let titre = "Confirmez votre présence"
        // source: src/pages/DetailMissionSoignant.tsx:1421 (vouvoyé : « confirme en 1 clic »)
        public static let description = "La mission démarre bientôt — confirmez en 1 clic pour rassurer l'établissement."
        /// Issue incertaine (revue B8 delta de #1157, M1) : texte opérationnel sans équivalent web (le web n'a ni
        /// relecture ni délai), hors HARD STOP. Après `{success:true}` sans relecture concluante, ou un délai dépassé. Il
        /// renvoie au bouton « Actualiser » affiché sur place (revue B8 de #1158, m3), sans promettre de nouvel envoi.
        public static let envoyeeNonRelue = "Votre confirmation a été envoyée mais n'a pas pu être relue. Actualisez pour la vérifier."
        /// Relecture proposée à la place d'un nouvel envoi tant que l'issue reste incertaine.
        public static let actualiser = "Actualiser"
    }

    public static func bloc(_ mission: MissionRecord, userId: String, maintenant: Date) -> Bloc {
        // `estAssigne` (l.633) : le bloc vit dans la section du soignant assigné (l.1406).
        guard let assigne = mission.soignantAssigneId, !userId.isEmpty,
              assigne.caseInsensitiveCompare(userId) == .orderedSame, mission.statut == "ASSIGNEE" else { return .masque }
        if let confirmee = mission.presenceConfirmeeLe, !confirmee.isEmpty { return .confirmee }
        // `new Date(debut_le)` illisible : `NaN < x` et `NaN > x` sont faux, le web n'affiche rien.
        guard let debut = try? DateHeureParis.instantJolene(mission.debutLe) else { return .masque }
        let ecart = debut.timeIntervalSince(maintenant)
        return ecart > 0 && ecart < fenetre ? .aConfirmer : .masque
    }

    /// Message d'un refus `{error}` du serveur : `data?.error || 'Confirmation impossible.'` (l.1426).
    public static func messageRefus(_ erreur: String?) -> String {
        guard let erreur, !erreur.isEmpty else { return TextesWeb.ConfirmationPresence.repliRefus }
        return erreur
    }
}
