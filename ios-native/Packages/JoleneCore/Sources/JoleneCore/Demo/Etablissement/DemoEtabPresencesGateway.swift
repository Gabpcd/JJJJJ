import Foundation

/// Écritures de la session démo sur les présences (lot 5, T8) : validations, contestations, notes et clôtures restent
/// en mémoire le temps du lancement (aucun stockage) et sont **relues** par chaque lecture, comme sur le serveur.
public actor DemoEtabEtatPresences {
    /// `valide_le` par présence (heure du serveur fictif).
    private var validations: [String: String] = [:]
    /// `motif_litige` par présence.
    private var litiges: [String: String] = [:]
    /// Fin déclarée du segment ouvert, par mission.
    private var clotures: [String: String] = [:]
    private var missionsNotees: Set<String> = []

    public init() {}

    func appliquer(_ presences: [PresenceEtab]) -> [PresenceEtab] {
        presences.map { presence in
            var relue = presence
            if let valideLe = validations[presence.id] {
                relue.valideParEtablissement = true
                relue.valideLe = valideLe
            }
            if let motif = litiges[presence.id] { relue.motifLitige = motif }
            return relue
        }
    }

    func appliquer(_ effectifs: [MissionSlot]) -> [MissionSlot] {
        effectifs.map { creneau in
            guard (creneau.fin ?? "").isEmpty, let mission = creneau.missionId, let fin = clotures[mission] else { return creneau }
            var ferme = creneau
            ferme.fin = fin
            return ferme
        }
    }

    func valider(_ presenceId: String, le: String) { validations[presenceId] = le }
    func contester(_ presenceId: String, motif: String) { litiges[presenceId] = motif }
    func cloturer(_ missionId: String, fin: String) { clotures[missionId] = fin }
    /// Faux si la mission est déjà notée pour ce sens.
    func noter(_ missionId: String) -> Bool { missionsNotees.insert(missionId).inserted }
}

/// `EtabPresencesPort` du monde démo (lot 5, T8) : `demo-etab-presences.json` (générée par
/// `scripts/mobile/demo-etab-presences.mjs` : M4 segment ouvert, M6 en cours, M7 à valider, M8 hors zone) et planning de
/// `demo-etab-missions.json` (M11 terminée sans pointage), aucun réseau. Mêmes règles que le serveur, textes serveur mot
/// pour mot : contexte cohérent et compte fictif seulement (`.demoOnly`), lignes de l'établissement confirmé, permission
/// `pointage` exigée par le trigger RBAC, validation refusée avant la fin du planning, pointage ouvert ou sans segment
/// terminé (`dec_bloquer_validation_presence_avant_fin_planning`), lot limité aux présences dans le périmètre sans
/// téléportation, motif de 3 caractères, clôture réservée aux missions attribuées ou en cours. Aucun montant, aucune
/// durée servie.
public struct DemoEtabPresencesGateway: EtabPresencesPort {
    /// Message neutre du refus RBAC, celui de `RPCInterception.messageRoleInsuffisant` (égalité gardée par
    /// `SupabaseEtabPresencesGatewayTests`).
    public static let roleInsuffisant = "Votre rôle dans cet établissement ne permet pas cette action."
    // source: supabase/schema/public.sql l.66176, l.66275 (fn_valider_presence, fn_valider_presences_lot)
    static let nonAutorise = "Non autorisé"
    // source: supabase/schema/public.sql l.66186 (fn_valider_presence)
    static let presenceIntrouvable = "Présence introuvable"
    // source: supabase/schema/public.sql l.1253 (dec_bloquer_validation_presence_avant_fin_planning)
    static let avantFinPlanning = "La présence ne peut être validée avant la fin du dernier créneau planifié."
    // source: supabase/schema/public.sql l.1264
    static let planningNonTermine = "Le planning détaillé doit être terminé avant validation de la présence."
    // source: supabase/schema/public.sql l.1277
    static let pointageOuvert = "Un pointage est encore ouvert pour cette mission."
    // source: supabase/schema/public.sql l.1291
    static let aucunPointageTermine = "Aucun pointage terminé ne permet de valider cette présence."
    // source: supabase/schema/public.sql l.26441 (fn_contester_presence)
    static let motifObligatoire = "Le motif est obligatoire (3 caractères min.)"
    // source: supabase/schema/public.sql l.27981 (fn_creer_notation_mission)
    static let missionNonTerminee = "Seules les missions TERMINEE peuvent être notées"
    // source: supabase/schema/public.sql l.29326 (fn_declarer_fin_retroactive)
    static let clotureNonAutorisee = "Vous n'êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission."
    // source: supabase/schema/public.sql l.29152
    static let aucunSegmentOuvert = "Aucun créneau effectif ouvert à fermer pour cette mission."
    /// Rôles retenus par `est_admin_etablissement()` (`public.sql` l.5018-5023), que `fn_declarer_fin_retroactive`
    /// exige en plus de l'appartenance : règle du **serveur fictif**, l'app ne lit que les permissions servies.
    static let rolesClotureServeur: [RoleEtab] = [.proprietaire, .adminGroupe, .rh]

    private let fixture: DemoFixtures.EtabPresencesFile?
    private let missions: DemoFixtures.EtabMissionsFile?
    private let etat: DemoEtabEtatPresences

    public init(etat: DemoEtabEtatPresences = DemoEtabEtatPresences()) {
        fixture = try? DemoFixtures.loadEtabPresences()
        missions = try? DemoFixtures.loadEtabMissions()
        self.etat = etat
    }

    // MARK: - Lecture

    private struct Donnees {
        var presences: [PresenceEtab]
        var missions: DemoFixtures.EtabMissionsFile
    }

    /// Lignes relues de l'établissement du contexte, avec leurs créneaux hors pause (planning + EFFECTIF de la session).
    private func donnees(_ context: EtablissementReadContext) async throws -> Donnees {
        try DemoEtablissementWorld.verifier(context)
        guard let fixture, let missions else { throw JoleneError(.contract, "Fixture démo des présences établissement illisible.") }
        let effectifs = await etat.appliquer(fixture.effectifs)
        let planning = missions.creneaux.filter { $0.typeCreneau == "PREVISIONNEL" && !$0.estPause }
        let lignes = await etat.appliquer(fixture.presences)
            .filter { $0.mission?.etablissementId == context.etablissementId }
            .map { presence -> PresenceEtab in
                var relue = presence
                relue.creneaux = (planning + effectifs).filter { $0.missionId == presence.missionId }
                return relue
            }
        return Donnees(presences: lignes, missions: missions)
    }

    public func presences(context: EtablissementReadContext) async throws -> [PresenceEtab] {
        try await donnees(context).presences
    }

    public func missionsTerminees(context: EtablissementReadContext) async throws -> [EtabMissionResume] {
        try await donnees(context).missions.missions
            .filter { $0.etablissementId == context.etablissementId && $0.statut == "TERMINEE"
                && $0.typeContratRecherche == "SALARIE" && !($0.soignantAssigneId ?? "").isEmpty }
            .sorted { ($0.finLe ?? "") > ($1.finLe ?? "") }
    }

    public func creneaux(missionId: String, context: EtablissementReadContext) async throws -> [MissionSlot] {
        try await donnees(context).presences.first { $0.missionId == missionId }?.creneaux ?? []
    }

    // MARK: - Validation

    /// Refus du trigger de validation pour une présence, `nil` si elle est validable maintenant (heure du serveur fictif).
    private static func refusValidation(_ presence: PresenceEtab) -> String? {
        let synthese = SynthesePresence.construire(presence.creneaux, maintenant: DemoWorld.fixedNow)
        if synthese.previsionnels.isEmpty { return planningNonTermine }
        if !synthese.planningTermine { return avantFinPlanning }
        if !synthese.effectifsOuverts.isEmpty { return pointageOuvert }
        return synthese.effectifsFermes.isEmpty ? aucunPointageTermine : nil
    }

    public func valider(presenceId: String, context: EtablissementReadContext) async throws -> ValidationPresenceOutcome {
        let lues = try await donnees(context).presences
        guard let presence = lues.first(where: { $0.id == presenceId }) else { return .refusee(message: Self.presenceIntrouvable) }
        if presence.valideParEtablissement, let valideLe = presence.valideLe { return .validee(valideLe: valideLe) }
        guard context.permissions.pointage else { return .accesRefuse(message: Self.roleInsuffisant) }
        if let refus = Self.refusValidation(presence) { return .refusee(message: refus) }
        let valideLe = DateHeureParis.isoUTC(DemoWorld.fixedNow)
        await etat.valider(presenceId, le: valideLe)
        return .validee(valideLe: valideLe)
    }

    public func validerLot(ids: [String], context: EtablissementReadContext) async throws -> ValidationLotOutcome {
        let lues = try await donnees(context).presences
        guard context.permissions.pointage else { return .refusee(message: Self.nonAutorise) }
        // Prédicat de `fn_valider_presences_lot` : non validée, périmètre confirmé, aucune téléportation.
        let cibles = lues.filter { ids.contains($0.id) && !$0.valideParEtablissement && PresencesEtabRules.sansAlerte($0) }
        // Une seule ligne refusée par le trigger annule tout le lot (une instruction `UPDATE`).
        if let refus = cibles.compactMap(Self.refusValidation).first { return .refusee(message: refus) }
        let valideLe = DateHeureParis.isoUTC(DemoWorld.fixedNow)
        for cible in cibles { await etat.valider(cible.id, le: valideLe) }
        let relues = try await donnees(context).presences.filter { ids.contains($0.id) && $0.valideParEtablissement }
        return .traitee(validees: relues.count, selectionnees: ids.count)
    }

    // MARK: - Contestation et note

    public func contester(presenceId: String, motif: String, context: EtablissementReadContext) async throws -> ContestationOutcome {
        let lues = try await donnees(context).presences
        let propre = motif.trimmingCharacters(in: .whitespacesAndNewlines)
        guard propre.count >= PresencesEtabModel.longueurMinMotif else { return .refusee(message: Self.motifObligatoire) }
        guard lues.contains(where: { $0.id == presenceId }) else { return .refusee(message: Self.presenceIntrouvable) }
        guard context.permissions.pointage else { return .accesRefuse(message: Self.roleInsuffisant) }
        await etat.contester(presenceId, motif: propre)
        return .contestee(motifLitige: propre)
    }

    public func noter(missionId: String, note: Int, context: EtablissementReadContext) async throws -> NotationOutcome {
        let missions = try await donnees(context).missions
        guard (1...PresencesEtabModel.noteMaximale).contains(note) else { throw JoleneError(.contract, "Note hors de 1 à 5.") }
        guard missions.missions.first(where: { $0.id == missionId && $0.etablissementId == context.etablissementId })?.statut == "TERMINEE" else {
            return .nonEnregistree(message: Self.missionNonTerminee)
        }
        // « Mission déjà notée pour ce sens » vaut succès (`NotationRapide.tsx` l.61).
        _ = await etat.noter(missionId)
        return .enregistree
    }

    // MARK: - Clôture rétroactive

    public func cloturerSegment(missionId: String, heureFin: Date, context: EtablissementReadContext) async throws -> ClotureOutcome {
        let lues = try await donnees(context)
        guard let mission = lues.missions.missions.first(where: { $0.id == missionId && $0.etablissementId == context.etablissementId }),
              mission.statut == "ASSIGNEE" || mission.statut == "EN_COURS" else {
            // source: supabase/schema/public.sql l.29122 (`%` = identifiant de la mission)
            return .refusee(message: "Mission \(missionId) introuvable ou dans un statut incompatible.")
        }
        guard Self.rolesClotureServeur.contains(context.roleEtab) else { return .accesRefuse(message: Self.clotureNonAutorisee) }
        let ouverts = (lues.presences.first { $0.missionId == missionId }?.creneaux ?? [])
            .filter { $0.typeCreneau == "EFFECTIF" && ($0.fin ?? "").isEmpty }
        guard let debut = ouverts.map(\.debut).max(), let instantDebut = try? DateHeureParis.instantJolene(debut) else {
            return .refusee(message: Self.aucunSegmentOuvert)
        }
        let fin = DateHeureParis.isoUTC(heureFin)
        guard heureFin > instantDebut else {
            // source: supabase/schema/public.sql l.29156 (`%` = heure de fin, début du créneau)
            return .refusee(message: "L'heure de fin (\(fin)) doit être postérieure au début du créneau (\(debut)).")
        }
        await etat.cloturer(missionId, fin: fin)
        return .cloturee
    }
}

// MARK: - Fixture

public extension DemoFixtures {
    /// `demo-etab-presences.json` : lignes `presences` (embed `missions` compris) et créneaux EFFECTIF.
    struct EtabPresencesFile: Decodable, Sendable {
        public var fixedNow: String
        public var presences: [PresenceEtab]
        public var effectifs: [MissionSlot]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", presences, effectifs }
    }

    static func loadEtabPresences() throws -> EtabPresencesFile { try load("demo-etab-presences") }
}
