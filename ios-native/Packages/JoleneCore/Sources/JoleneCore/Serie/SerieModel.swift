import Foundation
import Combine

/// État de la série : en attente de la première réponse, relue, sans mission accessible, ou en échec.
public enum EtatSerie: Equatable, Sendable {
    case chargement
    /// Missions de la série, ordre serveur (`debut_le` croissant), jamais vide.
    case prete([Mission])
    /// Aucune mission accessible (« Pack introuvable », web l.234-242).
    case introuvable
    /// Lecture en échec (« Pack indisponible », web l.225-233), message affiché.
    case echec(String)

    public var missions: [Mission] {
        if case let .prete(missions) = self { return missions }
        return []
    }

    public var estPrete: Bool {
        if case .prete = self { return true }
        return false
    }
}

/// Issue d'une mission de la série après la boucle d'acceptation. Chaque texte de refus est celui du serveur, mot
/// pour mot (HARD STOP n°4) : ce type ne porte aucune règle, il range l'issue rendue par le port.
public enum IssueMissionSerie: Equatable, Sendable {
    /// Acceptée et relue attribuée au soignant (la gateway relit avant de répondre, PRINCIPES §3).
    case acceptee
    /// Le serveur demande un mode de contrat : jamais rejoué ici, lien vers le détail de la mission (web l.310-316).
    case choixContratRequis
    /// Refus du serveur, texte verbatim ; `code` = code du refus structuré (`CONFLIT_PLANNING`…), nil sinon.
    case refusee(code: String?, message: String)
    /// Refus levé par un trigger de conformité (`CandidatureOutcome.codeRefusCodeDuTravail`) : texte du serveur tel
    /// que servi, et la boucle s'arrête sur lui (web l.306-309).
    case codeDuTravail(message: String)
    /// Planning modifié depuis l'affichage : texte du serveur, mission relue, jamais renvoyée telle quelle.
    case planningModifie(message: String)
    /// Planning exact indisponible au moment de l'envoi : rien n'est parti (web l.290-294).
    case planningIncomplet
    /// Réponse perdue (délai, réseau, relecture) : issue inconnue, rien n'est renvoyé, la série est relue.
    case nonConfirmee(message: String)
    /// Boucle arrêtée avant cette mission : rien n'est parti.
    case nonEnvoyee

    /// Mission que le serveur vient de refuser par un refus structuré (planning ou conformité) : elle compte comme
    /// « en conflit » pour la sélection (`SelectionSerieCandidat`) tant qu'elle n'est pas décochée ou la série relue.
    /// Verdict du serveur seulement : aucune règle de planning n'est évaluée côté client (décision 2 du lot 1).
    public var estConflitServeur: Bool {
        switch self {
        case .codeDuTravail: return true
        case let .refusee(code, _): return code != nil
        default: return false
        }
    }
}

/// Constantes de la série, lisibles hors de l'acteur principal (gateway démo).
public enum SerieRegles {
    /// Statut d'une mission encore ouverte (`missions.statut`, web l.135 et l.244).
    public static let statutOuverte = "OUVERTE"

    /// Une série n'est un pack que si toutes ses missions viennent du même établissement (revue B8 sécurité de la vague
    /// D, M1) : le marqueur `[SERIE_ID:…]` est du texte libre, que le serveur ne retire pas d'une description. Fermé
    /// par défaut : aucune ligne, ou plusieurs établissements, rend `false` (« Pack introuvable »).
    public static func unSeulEtablissement(_ etablissementIds: [String]) -> Bool {
        guard let premier = etablissementIds.first else { return false }
        return etablissementIds.allSatisfy { $0 == premier }
    }
}

/// Refus de conformité sur lequel la boucle s'est arrêtée : `message` est le texte du serveur, mot pour mot.
public struct RefusConformiteSerie: Equatable, Sendable {
    public var missionId: String
    public var message: String

    public init(missionId: String, message: String) {
        self.missionId = missionId; self.message = message
    }
}

/// Bilan de la dernière boucle (web l.336-347) : missions acceptées, envoyées sans être acceptées, non envoyées.
public struct BilanSerie: Equatable, Sendable {
    public enum Ton: Equatable, Sendable { case succes, partiel, echec }

    public var acceptees: Int
    public var echouees: Int
    public var nonEnvoyees: Int

    public init(acceptees: Int, echouees: Int, nonEnvoyees: Int) {
        self.acceptees = acceptees; self.echouees = echouees; self.nonEnvoyees = nonEnvoyees
    }

    public var ton: Ton {
        if acceptees == 0 { return .echec }
        return echouees == 0 && nonEnvoyees == 0 ? .succes : .partiel
    }

    /// Textes du web : tout accepté (l.574), partiel (l.343), rien (l.346).
    public var texte: String {
        if acceptees == 0 { return SerieTextes.bilanAucune }
        return echouees == 0 ? SerieTextes.bilanSucces(acceptees) : SerieTextes.bilanPartiel(reussies: acceptees, echouees: echouees)
    }
}

/// Détail de série (`/soignant/missions/serie/:serieId`, L4-T12), port de `DetailSerieSoignant.tsx` : lecture de la
/// série, sélection (`SelectionSerieCandidat`, lot 1 T2) et acceptation des missions sélectionnées **une par une**.
///
/// Boucle d'acceptation (web l.289-323) :
/// - séquentielle, dans l'ordre affiché, une requête par mission, **jamais de renvoi** : après un refus, un délai ou
///   une erreur, rien n'est rejoué ; c'est le soignant qui relance, après avoir corrigé sa sélection ;
/// - une issue par mission (`IssueMissionSerie`) ; refus du serveur affichés verbatim ;
/// - arrêt sur le refus de conformité (`CandidatureOutcome.codeRefusCodeDuTravail`) comme le web (l.306-309) : son
///   texte est publié tel que servi (`refusConformite`), les missions suivantes ne sont pas envoyées ;
/// - `choixRequis` : issue « choix de contrat requis » et lien vers le détail, aucune feuille rejouée en boucle ;
/// - arrêt aussi sur une session expirée ou une réponse perdue (délai, réseau) : l'état du serveur est inconnu, la
///   série est relue, et une mission relue attribuée au soignant est rangée « acceptée » (PRINCIPES §4) ;
/// - audit `MISSION_ASSIGNATION` par mission acceptée : écrit par la gateway de candidature du lot 1 (décision 5).
///
/// Aucune règle de conformité n'est évaluée ici : seuls les refus du serveur marquent une mission « en conflit ».
/// Mêmes gardes que les autres modèles : appels bornés à `resolutionTimeout`, gateways de l'epoch de l'écran, réponse
/// d'un epoch périmé ignorée, second appui ignoré pendant la boucle, annulation jamais présentée comme une erreur.
@MainActor
public final class SerieModel: ObservableObject {
    @Published public private(set) var etat: EtatSerie = .chargement
    /// Missions cochées. Seule une mission ouverte au planning exact peut l'être.
    @Published public private(set) var selection: Set<String> = []
    /// Issue par mission de la dernière boucle (et refus antérieurs des missions décochées depuis).
    @Published public private(set) var resultats: [String: IssueMissionSerie] = [:]
    /// Refus de conformité de la dernière boucle, texte du serveur mot pour mot ; nil sinon.
    @Published public private(set) var refusConformite: RefusConformiteSerie?
    @Published public private(set) var bilan: BilanSerie?
    @Published public private(set) var enCours = false
    /// Mission en cours d'envoi pendant la boucle.
    @Published public private(set) var missionEnCours: String?
    /// Message d'une action ou d'une relecture en échec sur une série affichée.
    @Published public private(set) var erreur: String?
    @Published public private(set) var sessionExpiree = false
    /// Jeton d'annonce VoiceOver (`InlineNotice.announcementID`) : change à chaque message ou bilan.
    @Published public private(set) var jeton = 0

    public let serieId: String
    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var dejaChargee = false
    private var revision = 0
    /// Missions de la dernière boucle, dans l'ordre d'envoi (le bilan en est dérivé).
    private var derniereBoucle: [String] = []

    public init(serieId: String, controller: SessionController, snapshot: SessionSnapshot) {
        self.serieId = serieId
        self.controller = controller
        self.snapshot = snapshot
    }

    // MARK: - État dérivé

    public var missions: [Mission] { etat.missions }

    /// Missions encore ouvertes (web l.244).
    public var ouvertes: [Mission] { missions.filter { $0.record.statut == SerieRegles.statutOuverte } }

    /// Missions que le serveur a refusées par un refus structuré depuis la dernière lecture complète.
    public var idsConflit: Set<String> {
        Set(resultats.filter { $0.value.estConflitServeur }.map(\.key))
    }

    /// Analyse de la sélection (lot 1 T2) : jamais de retrait silencieux d'une mission.
    public var analyse: AnalyseSelectionSerie<Mission> {
        SelectionSerieCandidat.analyser(ouvertes, idsSelectionnes: selection, idsConflit: idsConflit)
    }

    public var peutAccepter: Bool { !enCours && analyse.peutAccepter }

    /// Libellé de l'action (web l.524-528).
    public var libelleAction: String {
        if enCours { return SerieTextes.acceptationEnCours }
        let analyse = self.analyse
        return analyse.idsEnConflit.isEmpty
            ? SerieTextes.accepterSelection(analyse.missionsSelectionnees.count) : SerieTextes.decocherConflits
    }

    /// Planning exact de la mission (`construirePlanningCandidat(m).exact`, web l.437).
    public nonisolated static func planningExact(_ mission: Mission) -> Bool {
        PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(mission: mission)).exact
    }

    /// Case à cocher proposée : mission ouverte au planning exact (web l.447).
    public func selectionnable(_ mission: Mission) -> Bool {
        mission.record.statut == SerieRegles.statutOuverte && Self.planningExact(mission)
    }

    public func estSelectionnee(_ id: String) -> Bool { selection.contains(id) }

    // MARK: - Lecture

    /// À chaque apparition : première lecture complète, puis simple relecture (sélection et issues conservées, par
    /// exemple au retour du détail d'une mission).
    public func charger() async {
        if dejaChargee {
            await relire()
        } else {
            await recharger()
        }
    }

    /// Lecture complète (« Réessayer », tirer pour actualiser) : la sélection revient à toutes les missions ouvertes
    /// au planning exact (web l.135-136), les issues et les refus de la boucle précédente sont effacés.
    public func recharger() async {
        guard !enCours else { return }
        erreur = nil
        guard let lues = await lire() else { return }
        resultats = [:]
        derniereBoucle = []
        refusConformite = nil
        bilan = nil
        publier(lues, reinitialiserSelection: true)
        dejaChargee = true
    }

    /// « Vérifier ma session » : revalide la session, puis relit si elle est toujours prête pour cet epoch.
    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await charger()
    }

    // MARK: - Sélection

    public func basculer(_ id: String) {
        guard !enCours, let mission = missions.first(where: { $0.id == id }), selectionnable(mission) else { return }
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        erreur = nil
    }

    // MARK: - Acceptation

    /// Accepte, une par une et dans l'ordre affiché, exactement les missions de la sélection analysée.
    public func accepter() async {
        guard !enCours else { return }
        let analyse = self.analyse
        guard analyse.peutAccepter else {
            signaler(SerieTextes.selectionACorriger)
            return
        }
        // `enCours` posé avant le premier `await` : un second appui est ignoré.
        enCours = true
        defer {
            enCours = false
            missionEnCours = nil
        }
        erreur = nil
        bilan = nil
        refusConformite = nil
        sessionExpiree = false
        let aAccepter = analyse.missionsSelectionnees
        derniereBoucle = aAccepter.map(\.id)
        for mission in aAccepter { resultats[mission.id] = nil }

        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.serie
        let context = snapshot.context
        let delai = controller.resolutionTimeout
        var arretee = false
        for mission in aAccepter {
            let id = mission.id
            if arretee {
                resultats[id] = .nonEnvoyee
                continue
            }
            // Fail-closed : sans planning exact, rien n'est envoyé pour cette mission (web l.290-294).
            guard let creneaux = CreneauxConfirmes.pourAction(PlanningCandidatInput(mission: mission)) else {
                resultats[id] = .planningIncomplet
                continue
            }
            missionEnCours = id
            do {
                let outcome = try await bounded(timeout: delai) {
                    try await port.accepter(missionId: id, creneaux: creneaux, context: context)
                }
                guard await controller.epoch == snapshot.epoch else { return }
                switch outcome {
                case .confirmed:
                    resultats[id] = .acceptee
                case .choixRequis:
                    resultats[id] = .choixContratRequis
                case let .refusee(code, message, _) where code == CandidatureOutcome.codeRefusCodeDuTravail:
                    // Texte du serveur tel que servi ; la boucle s'arrête ici, comme le web.
                    resultats[id] = .codeDuTravail(message: message)
                    refusConformite = RefusConformiteSerie(missionId: id, message: message)
                    arretee = true
                case let .refusee(code, message, _):
                    resultats[id] = .refusee(code: code, message: message)
                case let .planningAReconfirmer(_, message):
                    resultats[id] = .planningModifie(message: message)
                case let .missionDejaAttribuee(message):
                    resultats[id] = .refusee(code: nil, message: message)
                }
            } catch {
                guard await controller.epoch == snapshot.epoch else { return }
                switch Self.classer(error) {
                case .annulation:
                    return
                case let .refus(message):
                    // Refus du serveur sans code (« error » seul) : la mission suivante est tentée, comme le web.
                    resultats[id] = .refusee(code: nil, message: message)
                case let .session(message):
                    // Requête refusée faute de session : rien n'a été traité, rien d'autre n'est envoyé.
                    resultats[id] = .nonEnvoyee
                    sessionExpiree = true
                    erreur = message
                    arretee = true
                case let .inconnue(message):
                    // Délai, réseau, relecture : le serveur a pu agir. Jamais de renvoi ; la relecture tranche.
                    resultats[id] = .nonConfirmee(message: message)
                    arretee = true
                }
            }
        }
        missionEnCours = nil
        bilan = calculerBilan()
        jeton += 1
        // Relecture de la série (statuts, attributions) : seule preuve, jamais un état supposé.
        if !sessionExpiree { await relire() }
    }

    // MARK: - Interne

    private enum Classe {
        case annulation
        case refus(String)
        case session(String)
        case inconnue(String)
    }

    /// Erreur levée par le port : refus verbatim du serveur (`.unknown`), session expirée, annulation, ou réponse
    /// perdue (délai, réseau, contrat, relecture).
    private nonisolated static func classer(_ error: Error) -> Classe {
        if error is CancellationError { return .annulation }
        guard let jolene = error as? JoleneError else { return .inconnue(SerieTextes.nonConfirmee) }
        switch jolene.kind {
        case .cancelled: return .annulation
        case .unknown: return .refus(jolene.message)
        case .unauthorized: return .session(jolene.message)
        default: return .inconnue(jolene.message)
        }
    }

    private func calculerBilan() -> BilanSerie? {
        guard !derniereBoucle.isEmpty else { return nil }
        var bilan = BilanSerie(acceptees: 0, echouees: 0, nonEnvoyees: 0)
        for id in derniereBoucle {
            switch resultats[id] {
            case .acceptee?: bilan.acceptees += 1
            case .nonEnvoyee?, nil: bilan.nonEnvoyees += 1
            default: bilan.echouees += 1
            }
        }
        return bilan
    }

    /// Relecture sans réinitialisation : sélection et issues conservées, issue inconnue réconciliée.
    private func relire() async {
        guard let lues = await lire() else { return }
        // Réconciliation par relecture (PRINCIPES §4) : une mission à l'issue inconnue, relue attribuée au soignant de
        // la session, a bien été acceptée ; sinon elle reste « non confirmée » et n'est jamais renvoyée d'office.
        var reconciliee = false
        for mission in lues {
            guard case .nonConfirmee? = resultats[mission.id],
                  CandidatureRules.assignationRelue(statut: mission.record.statut,
                                                    soignantAssigneId: mission.record.soignantAssigneId,
                                                    userId: snapshot.context.userId) else { continue }
            resultats[mission.id] = .acceptee
            reconciliee = true
        }
        publier(lues, reinitialiserSelection: false)
        if reconciliee {
            bilan = calculerBilan()
            jeton += 1
        }
    }

    private func publier(_ lues: [Mission], reinitialiserSelection: Bool) {
        // Plusieurs établissements : pas un pack (`SerieRegles.unSeulEtablissement`), rien n'est présenté ni coché.
        let pack = SerieRegles.unSeulEtablissement(lues.map(\.record.etablissementId)) ? lues : []
        etat = pack.isEmpty ? .introuvable : .prete(pack)
        let cochables = Set(pack.filter(selectionnable).map(\.id))
        selection = reinitialiserSelection ? cochables : selection.intersection(cochables)
    }

    /// Lecture bornée de la série ; `nil` si elle échoue (message publié), est annulée ou vient d'un epoch périmé.
    private func lire() async -> [Mission]? {
        revision += 1
        let revisionLecture = revision
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return nil }
        let port = gateways.serie
        let context = snapshot.context
        let id = serieId
        do {
            let lues = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.missions(serieId: id, context: context)
            }
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision else { return nil }
            sessionExpiree = false
            return lues
        } catch {
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision, !Task.isCancelled else { return nil }
            let message: String
            switch Self.classer(error) {
            case .annulation:
                return nil
            case let .session(texte):
                sessionExpiree = true
                message = texte
            case .refus, .inconnue:
                message = SerieTextes.indisponibleTexte
            }
            if etat.estPrete {
                signaler(message)
            } else {
                etat = .echec(message)
            }
            return nil
        }
    }

    private func signaler(_ message: String) {
        erreur = message
        jeton += 1
    }
}
