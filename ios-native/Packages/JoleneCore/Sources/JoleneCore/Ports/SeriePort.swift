import Foundation

// Port du détail de série (lot 4, T12 ; `docs/mobile-swift/LOT4_PLAN.md` §3 T12, report de la décision 11 du lot 1).
// Quatorzième champ du bloc « Lot 4 » de `Gateways` (`serie`) : le blueprint §2.2 n'en prévoyait que treize, mais la
// lecture des missions d'une série n'entre dans aucun d'eux (précision 13 de `DECISIONS_LOT4.md`). Mêmes règles que
// les autres ports du lot 4 (`Ports/Lot4Ports.swift`) : `Sendable`, `MissionReadContext` de l'epoch courant, appels
// bornés par l'appelant (`bounded(timeout: resolutionTimeout)`), stub « non câblé » qui refuse en citant sa tranche.

/// Détail de série (`/soignant/missions/serie/:serieId`, `src/pages/DetailSerieSoignant.tsx`) — tranche T12.
public protocol SeriePort: Sendable {
    /// Missions de la série, dans l'ordre `debut_le` croissant (web l.90-95 : `description ILIKE '%[SERIE_ID:<id>]%'`),
    /// enrichies comme Explorer (établissement, créneaux prévisionnels hors pauses, planning candidat). Une série sans
    /// mission accessible rend `[]` (« Pack introuvable »), jamais une erreur.
    func missions(serieId: String, context: MissionReadContext) async throws -> [Mission]

    /// ACCEPTER d'**une** mission de la série (web l.295-302 : `fn_confirmer_action_planning_v1`, action `ACCEPTER`,
    /// `p_message`, `p_choix_contrat` et `p_candidature_id` à null) avec le planning exact affiché. Même issue que
    /// `CandidaturePort.confirmer(action: .accepter, …)` du lot 1, dont le monde Supabase réutilise la gateway (RPC,
    /// relecture de l'attribution, audit `MISSION_ASSIGNATION`) : refus serveur verbatim (`[CODE DU TRAVAIL]` compris,
    /// `CandidatureOutcome.codeRefusCodeDuTravail`), jamais de renvoi. Un `choixRequis` n'est jamais rejoué ici : la
    /// série n'a pas de feuille de choix de contrat (web l.310-316).
    func accepter(missionId: String, creneaux: [CreneauConfirmePayload],
                  context: MissionReadContext) async throws -> CandidatureOutcome
}

public struct UnwiredSeriePort: SeriePort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot4.erreur("série", "T12") }
    public func missions(serieId: String, context: MissionReadContext) async throws -> [Mission] { throw erreur }
    public func accepter(missionId: String, creneaux: [CreneauConfirmePayload],
                         context: MissionReadContext) async throws -> CandidatureOutcome { throw erreur }
}
