import Foundation

/// Règles pures des candidatures de l'espace établissement (lot 5, T6 ; `LOT5_PLAN.md` §2.6, §3 T6, D10, D25).
/// Aucune règle juridique : le périmètre d'acceptation native (D25) est un **choix de périmètre** produit (aucun
/// escrow, aucun mandat de facturation libéral, aucun statut d'internat à porter), l'aiguillage du cadre étudiant
/// n'est qu'un aiguillage (le serveur décide, correction 19 : seul `CADRE_ETUDIANT_A_CONFIRMER` renvoie au web, les
/// autres `CADRE_ETUDIANT_*` sont des refus verbatim). Le refus d'une candidature reste natif pour toute mission.
public enum CandidaturesEtabRules {
    /// Contrat recherché seul accepté nativement (D25) : `fn_trg_escrow_creer_a_confirmation` ne vise que le libéral.
    public static let contratAcceptableNativement = "SALARIE"
    /// Profession dont l'acceptation reste sur le web (statuts d'internat non portés, D10).
    public static let professionRenvoyeeAuWeb = "MEDECIN"
    /// Profession du cadre étudiant (`fn_traiter_candidature_planning_v1`, l.62452-62455 : aiguillage seulement).
    public static let professionCadreEtudiant = "AS"
    /// Statut d'une candidature à traiter (web l.366).
    public static let statutEnAttente = "EN_ATTENTE"
    public static let statutAcceptee = "ACCEPTEE"
    public static let statutRefusee = "REFUSEE"
    /// Statut de la mission relue après une acceptation confirmée (§2.4).
    public static let statutMissionAssignee = "ASSIGNEE"
    /// `p_motif` du refus, comme le web (`ListeCandidatures.tsx` l.320).
    public static let motifRefus = "Refusé par l'établissement"

    /// D25 sur la mission : `nil` si l'acceptation peut être native. Un contrat recherché inconnu ou absent n'est
    /// jamais supposé salarié (fail-closed).
    public static func motifMission(typeContratRecherche: String?, professionRequise: String?) -> MotifRenvoiWebCandidature? {
        if typeContratRecherche != contratAcceptableNativement { return .contratNonSalarie }
        if professionRequise == professionRenvoyeeAuWeb { return .medecin }
        return nil
    }

    /// Aiguillage complet d'une acceptation, avant tout appel : mission (D25) puis candidat étudiant aide-soignant
    /// (D10 ; aucune case juridique en natif, `CADRE_ETUDIANT_AS_CONFIRME` n'est jamais envoyé).
    public static func motifRenvoiWeb(typeContratRecherche: String?, professionRequise: String?,
                                      candidat: CandidatHabilite?) -> MotifRenvoiWebCandidature? {
        if let motif = motifMission(typeContratRecherche: typeContratRecherche, professionRequise: professionRequise) {
            return motif
        }
        if candidat?.estEtudiant == true, candidat?.profession == professionCadreEtudiant { return .cadreEtudiant }
        return nil
    }

    /// Candidatures en attente (web l.365-368) : ancien marqueur « super-like » d'abord (priorité historique
    /// conservée), ordre serveur sinon.
    public static func enAttente(_ candidatures: [CandidatureHabilitee]) -> [CandidatureHabilitee] {
        let enAttente = candidatures.filter { $0.statut == statutEnAttente }
        return enAttente.filter(estPrioriteHistorique) + enAttente.filter { !estPrioriteHistorique($0) }
    }

    /// Candidatures traitées (tout autre statut, web l.369), ordre serveur.
    public static func traitees(_ candidatures: [CandidatureHabilitee]) -> [CandidatureHabilitee] {
        candidatures.filter { $0.statut != statutEnAttente }
    }

    /// Marqueur système des candidatures antérieures aux favoris (web l.364).
    public static func estPrioriteHistorique(_ candidature: CandidatureHabilitee) -> Bool {
        (candidature.message ?? "").contains("super-like")
    }

    /// Issue relue d'une décision (§2.4) : acceptation = candidature `ACCEPTEE` **et** mission `ASSIGNEE` ;
    /// refus = candidature `REFUSEE`. Jamais déduite de la réponse de la mutation.
    public static func decisionConfirmee(_ decision: DecisionCandidature, candidatureId: String,
                                         lecture: LectureCandidaturesHabilitee) -> Bool {
        let statut = lecture.candidatures.first { $0.id == candidatureId }?.statut
        switch decision {
        case .acceptee: return statut == statutAcceptee && lecture.statutMission == statutMissionAssignee
        case .refusee: return statut == statutRefusee
        }
    }
}
