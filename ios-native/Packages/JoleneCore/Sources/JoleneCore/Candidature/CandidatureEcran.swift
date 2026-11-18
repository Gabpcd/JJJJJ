import Foundation

/// Bloc « actions » du détail d'une mission (lot 1, T6b) : ce que l'écran montre, dérivé de la mission relue, de la
/// dernière candidature relue côté serveur (`CandidaturePort.candidature(missionId:)`), du profil relu (soft-gate
/// `ProfilCompletion`) et de l'horloge des gateways. Fonction pure, parité `DetailMissionSoignant.tsx` l.1300-1405 et
/// l.1407-1410, l.1540-1547 ; propositions : `CarteProposition.tsx`. Aucune règle juridique : les refus restent ceux
/// du serveur.
public enum CandidatureEcran: Equatable, Sendable {
    /// Rien à proposer (mission terminée, annulée…, ni attribuée au soignant ni à un autre).
    case masque
    /// `soignant_assigne_id` = session (web `estAssigne`).
    case assignee
    /// Mission non ouverte attribuée à quelqu'un d'autre (web `estAssigneAutre`).
    case dejaAttribuee
    /// Proposition `PROPOSEE` encore ouverte (moins de 2 h), d'un contrat libéral : acceptation et refus natifs.
    case proposition(candidatureId: String)
    /// Proposition ouverte d'un autre contrat : l'acceptation exige l'attestation hebdomadaire des heures externes
    /// (`CarteProposition.tsx` l.154-256, HARD STOP n°4), non portée au lot 1 → renvoi web ; refus natif.
    case propositionWeb(candidatureId: String)
    /// Mission en mode candidature déjà postulée (web : une ligne `candidatures` existe, l.473-479).
    case envoyee
    /// Soft-gate du profil : libellés des champs obligatoires manquants, dans l'ordre du web.
    case profilIncomplet(manquants: [String])
    /// Planning exact indisponible : action désactivée, message de blocage du cœur.
    case planningBloque(action: ActionPlanning, message: String)
    /// Action possible : POSTULER (mode candidature) ou ACCEPTER.
    case ouverte(ActionPlanning)

    public static func etat(mission: Mission, candidature: CandidatureRecord?, profil: SoignantProfile?,
                            userId: String, maintenant: Date) -> CandidatureEcran {
        let record = mission.record
        if let assigne = record.soignantAssigneId, !userId.isEmpty, assigne.caseInsensitiveCompare(userId) == .orderedSame {
            return .assignee
        }
        guard record.statut == "OUVERTE" else {
            return (record.soignantAssigneId ?? "").isEmpty ? .masque : .dejaAttribuee
        }
        if let candidature, candidature.missionId == record.id,
           CandidatureRules.propositionOuverte(candidature, maintenant: maintenant) {
            // Verrou de T6a (revue B8, M1) : seul un contrat `LIBERAL` se passe de l'attestation hebdomadaire.
            let contrat = CandidatureRules.contratProposition(typeContratChoisi: candidature.typeContratChoisi,
                                                              typeContratRecherche: record.typeContratRecherche)
            return CandidatureRules.propositionVerrouillee(contrat: contrat)
                ? .propositionWeb(candidatureId: candidature.id) : .proposition(candidatureId: candidature.id)
        }
        let action = CandidatureRules.action(pour: record)
        if action == .postuler, candidature?.missionId == record.id { return .envoyee }
        let completion = ProfilCompletion.calculer(profil)
        guard completion.peutCandidater else {
            let manquants = completion.items.filter { $0.obligatoire && !$0.rempli }.map(\.label)
            return .profilIncomplet(manquants: profil == nil ? [] : manquants)
        }
        let planning = PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(mission: mission))
        guard planning.exact else {
            return .planningBloque(action: action, message: planning.messageBlocage ?? PlanningCandidatRules.messagePlanningIncomplet)
        }
        return .ouverte(action)
    }
}
