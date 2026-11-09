import Foundation
import Combine

/// Modèle de l'onglet Revenus (lot 3, T12, B9 ; lecture seule), port de l'aperçu `MesGainsApercuContent`
/// (`src/pages/MesGains.tsx` l.64-157) restreint au périmètre du lot 3 (D4) : totaux serveur, paiement rapide, missions
/// terminées avec leur montant et l'état de la dernière déclaration. Aucun KPI calculé côté client, aucune action de
/// paiement (T13, T14a, T14b).
///
/// - Trois sections indépendantes, lues en parallèle par `gateways.revenus` de l'epoch de la session, chacune bornée à
///   `SessionController.resolutionTimeout`, avec son état : l'échec de l'une n'efface jamais les autres (le web : trois
///   composants séparés, `PaiementsEscrowAVenir` et le bandeau d'erreur de l'aperçu).
/// - Missions : pages de 50 (`PAGE_SIZE`) ; page 0 → liste remplacée, page suivante → fusion par identifiant (ligne
///   relue remplacée à sa place, nouvelles à la suite : `Map` du web l.126-131) ; un échec garde la liste et affiche
///   l'erreur du web, « Réessayer » relit la page demandée en dernier (`reloadKey`) ; jamais l'état vide sur une erreur.
/// - Audit `DONNEES_PERSO_CONSULTATION` (`page: mes_gains`, l.147-153) best-effort, une seule fois par ouverture de
///   l'écran, après la première lecture réussie des missions ; jamais bloquant.
/// - Une réponse d'un epoch périmé ou d'une lecture dépassée n'est jamais publiée ; l'annulation n'est jamais une
///   erreur ; `.unauthorized` → « Vérifier ma session ».
@MainActor
public final class RevenusModel: ObservableObject {
    public enum Totaux: Equatable, Sendable {
        case chargement
        /// Profil sans exercice libéral : section absente (`PageStripeConnect.tsx` l.104).
        case masques
        case pret(TotauxRevenus)
        case echec(String)
    }

    public enum PaiementsRapides: Equatable, Sendable {
        case chargement
        case pret([PaiementRapide])
        case echec(String)
    }

    public static let detailsAudit = ["page": "mes_gains"]
    public static let typeRessourceAudit = "soignant"

    @Published public private(set) var totaux: Totaux = .chargement
    @Published public private(set) var paiementsRapides: PaiementsRapides = .chargement
    @Published public private(set) var missions: [MissionTerminee] = []
    /// Vrai dès qu'une page de missions a été lue (distingue « aucune mission » de « pas encore lu »).
    @Published public private(set) var missionsChargees = false
    @Published public private(set) var chargementMissions = false
    @Published public private(set) var aSuivre = false
    /// Message du bandeau d'erreur des missions (« Impossible de charger tous les revenus »).
    @Published public private(set) var erreur: String?
    @Published public private(set) var sessionExpiree = false

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    /// Page demandée en dernier (rejouée par « Réessayer »).
    private var pageDemandee = 0
    private var generationMissions = 0
    private var generationTotaux = 0
    private var generationRapides = 0
    private var auditTente = false

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    // MARK: - Présentation

    public var lignes: [LigneMissionAffichee] { missions.map(RevenusPresentation.mission) }

    public var escrowAffiche: EscrowAffiche {
        if case let .pret(lignes) = paiementsRapides { return RevenusPresentation.escrow(lignes) }
        return .vide
    }

    /// État vide du web (l.802-805) : seulement après une lecture réussie, sans erreur ni mission.
    public var afficheVide: Bool { missionsChargees && missions.isEmpty && erreur == nil }

    public var afficheNoteNetEstime: Bool { RevenusPresentation.afficheNoteNetEstime(missions) }

    public var noteBasDePage: String { RevenusPresentation.noteBasDePage(missions) }

    // MARK: - Lecture

    /// Apparition de l'onglet : lit chaque section jamais lue (premier affichage, ou relance après une tâche annulée par
    /// un changement d'onglet, qui laisse la section en chargement) ; un écran lu n'est jamais relu automatiquement et un
    /// échec attend « Réessayer » (jamais de boucle à l'apparition). Tirer pour actualiser relit tout (`charger`).
    public func chargerSiNecessaire() async {
        let totauxALire = totaux == .chargement
        let rapidesALire = paiementsRapides == .chargement
        let missionsALire = !missionsChargees && erreur == nil
        guard totauxALire || rapidesALire || missionsALire else { return }
        await withTaskGroup(of: Void.self) { groupe in
            if totauxALire { groupe.addTask { await self.rechargerTotaux() } }
            if rapidesALire { groupe.addTask { await self.rechargerPaiementsRapides() } }
            if missionsALire { groupe.addTask { await self.lireMissions(page: 0) } }
        }
    }

    /// Les trois sections, missions depuis la page 0 (tirer pour actualiser, « Vérifier ma session »).
    public func charger() async {
        async let lectureTotaux: Void = rechargerTotaux()
        async let lectureRapides: Void = rechargerPaiementsRapides()
        async let lectureMissions: Void = lireMissions(page: 0)
        _ = await (lectureTotaux, lectureRapides, lectureMissions)
    }

    /// « Charger plus de missions » : page suivante, seulement si le serveur en a annoncé une.
    public func chargerPlus() async {
        guard aSuivre, !chargementMissions else { return }
        await lireMissions(page: pageDemandee + 1)
    }

    /// « Réessayer » du bandeau d'erreur : la page demandée en dernier.
    public func reessayer() async {
        await lireMissions(page: pageDemandee)
    }

    /// « Vérifier ma session » : revalide la session puis relit si elle reste prête pour cet epoch.
    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        sessionExpiree = false
        await charger()
    }

    public func rechargerTotaux() async {
        generationTotaux += 1
        let courant = generationTotaux
        if case .echec = totaux { totaux = .chargement }
        guard let gateways = await controller.gateways(for: snapshot.epoch), generationTotaux == courant else { return }
        let port = gateways.revenus
        let context = snapshot.context
        do {
            let lus = try await bounded(timeout: controller.resolutionTimeout) { try await port.totaux(context: context) }
            guard await memeEpoch(), generationTotaux == courant else { return }
            totaux = lus.map(Totaux.pret) ?? .masques
        } catch {
            guard await memeEpoch(), generationTotaux == courant, let message = message(error, defaut: RevenusTextes.totauxIndisponibles) else { return }
            totaux = .echec(message)
        }
    }

    public func rechargerPaiementsRapides() async {
        generationRapides += 1
        let courant = generationRapides
        if case .echec = paiementsRapides { paiementsRapides = .chargement }
        guard let gateways = await controller.gateways(for: snapshot.epoch), generationRapides == courant else { return }
        let port = gateways.revenus
        let context = snapshot.context
        do {
            let lus = try await bounded(timeout: controller.resolutionTimeout) { try await port.paiementsRapides(context: context) }
            guard await memeEpoch(), generationRapides == courant else { return }
            paiementsRapides = .pret(lus)
        } catch {
            guard await memeEpoch(), generationRapides == courant, let message = message(error, defaut: RevenusTextes.escrowErreurDefaut) else { return }
            paiementsRapides = .echec(message)
        }
    }

    // MARK: - Interne

    private func lireMissions(page: Int) async {
        generationMissions += 1
        let courant = generationMissions
        pageDemandee = page
        chargementMissions = true
        defer { if generationMissions == courant { chargementMissions = false } }
        guard let gateways = await controller.gateways(for: snapshot.epoch), generationMissions == courant else { return }
        let port = gateways.revenus
        let context = snapshot.context
        do {
            let lue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.missionsTerminees(context: context, page: page)
            }
            guard await memeEpoch(), generationMissions == courant else { return }
            missions = page == 0 ? lue.missions : Self.fusionner(missions, lue.missions)
            aSuivre = lue.aSuivre
            missionsChargees = true
            erreur = nil
            sessionExpiree = false
        } catch {
            guard await memeEpoch(), generationMissions == courant,
                  let message = message(error, defaut: RevenusTextes.erreurDefaut) else { return }
            if (error as? JoleneError)?.kind == .unauthorized { sessionExpiree = true }
            erreur = message
            return
        }
        await auditerConsultation(gateways)
    }

    /// Fusion par identifiant du web (`new Map(prev…)` puis `set`) : ordre de première apparition, valeur la plus récente.
    static func fusionner(_ existantes: [MissionTerminee], _ nouvelles: [MissionTerminee]) -> [MissionTerminee] {
        var resultat = existantes
        var position: [String: Int] = [:]
        for (index, mission) in resultat.enumerated() { position[mission.id] = index }
        for mission in nouvelles {
            if let index = position[mission.id] {
                resultat[index] = mission
            } else {
                position[mission.id] = resultat.count
                resultat.append(mission)
            }
        }
        return resultat
    }

    private func auditerConsultation(_ gateways: Gateways) async {
        guard !auditTente else { return }
        auditTente = true
        let audit = gateways.audit
        let context = snapshot.context
        let userId = snapshot.user.id
        _ = try? await bounded(timeout: controller.resolutionTimeout) {
            try await audit.ecrire(action: .donneesPersoConsultation, typeRessource: Self.typeRessourceAudit,
                                   idRessource: userId, details: Self.detailsAudit, context: context)
        }
    }

    private func memeEpoch() async -> Bool { await controller.epoch == snapshot.epoch }

    /// Message affiché d'une erreur ; nil pour une annulation (la vue a disparu : rien à afficher).
    private func message(_ error: Error, defaut: String) -> String? {
        if error is CancellationError || Task.isCancelled { return nil }
        guard let jolene = error as? JoleneError else { return defaut }
        return jolene.kind == .cancelled ? nil : jolene.message
    }
}
