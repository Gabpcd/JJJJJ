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
///   relue remplacée à sa place, nouvelles à la suite : `Map` du web l.126-131) ; à chaque lecture, l'état de toutes
///   les lignes affichées (pages précédentes comprises) suit les déclarations relues avec la page (`setPaiementsMap`
///   du web, l.140-142 ; revue B8 n°2 de T12, m2) ; un échec garde la liste et affiche l'erreur du web, « Réessayer »
///   relit la page demandée en dernier (`reloadKey`) ; jamais l'état vide sur une erreur.
/// - Audit `DONNEES_PERSO_CONSULTATION` (`page: mes_gains`, l.147-153) best-effort, une seule fois par session (epoch :
///   le modèle vit autant que l'onglet, toujours monté par `MainTabView`), après la première lecture réussie des
///   missions ; jamais bloquant : lancé après la publication dans une tâche non structurée (fire-and-forget du web),
///   que l'annulation de la vue n'interrompt pas (revue B8 de T12, m2). Écart consigné (revue B8 n°2 de T12, m3) : le
///   web l'écrit à chaque chargement réussi (montage, page, `reloadKey`) ; ni « Charger plus », ni « Réessayer », ni
///   une relecture au-delà de 60 s ou par jeton (assimilées à un montage web pour les données) ne la réécrivent ici.
/// - Fraîcheur (revue B8 de T12, m1) : le web relit l'aperçu à chaque montage de `/soignant/mes-gains` ; l'onglet
///   natif, toujours monté, relit à l'apparition chaque section lue il y a plus de `delaiRelecture` (60 s, comme
///   l'Accueil), ou toutes dès que le jeton de péremption avance (lien universel ou tap qui présente l'onglet) ; un
///   échec attend toujours « Réessayer ».
/// - Une réponse d'un epoch périmé ou d'une lecture dépassée n'est jamais publiée ; l'annulation n'est jamais une
///   erreur ; `.unauthorized` → « Vérifier ma session ».
@MainActor
public final class RevenusModel: ObservableObject {
    public enum Totaux: Equatable, Sendable {
        case chargement
        /// Section absente là où le web ne rend pas les cartes (`PageStripeConnect.tsx` l.178, l.300, l.302, l.367).
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
    /// Au-delà, une nouvelle apparition de l'onglet relit la section (même borne que l'Accueil).
    public static let delaiRelecture: TimeInterval = AccueilModel.delaiRelecture

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
    /// Trace de consultation déjà lancée : une seule par session (epoch), le modèle vivant autant que l'onglet.
    private var auditTente = false
    /// Écriture d'audit en vol (tâche non structurée ; lue par les tests pour en attendre l'issue).
    private(set) var auditEnCours: Task<Void, Never>?
    /// Instants (horloge des gateways) de la dernière lecture réussie de chaque section ; nil = à relire.
    private var totauxLusLe: Date?
    private var rapidesLusLe: Date?
    private var missionsLuesLe: Date?
    /// Dernier jeton de péremption reçu (`chargerSiNecessaire(peremption:)`).
    private var peremptionVue = 0

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

    /// « Charger plus de missions » : seulement si le serveur a annoncé une suite et sans bandeau d'erreur (« Réessayer »
    /// relit alors la page en échec ; revue B8 de T12, m3 : le web l.797-798 l'affiche à côté et saute la page).
    public var afficheChargerPlus: Bool { aSuivre && erreur == nil }

    // MARK: - Lecture

    /// Apparition de l'onglet (première fois, retour sur l'onglet, retour au premier plan) : lit chaque section jamais
    /// lue (premier affichage, ou relance après une tâche annulée par un changement d'onglet, qui laisse la section à
    /// lire) ou lue il y a plus de `delaiRelecture` ; un jeton de `peremption` nouveau (lien universel ou tap qui
    /// présente l'onglet) rend toutes les sections périmées jusqu'à leur prochaine lecture réussie. Un échec attend
    /// « Réessayer » (jamais de boucle à l'apparition). Les missions périmées sont relues depuis la page 0, comme un
    /// montage du web. Tirer pour actualiser relit tout (`charger`).
    public func chargerSiNecessaire(peremption: Int? = nil) async {
        if let peremption, peremption != peremptionVue {
            peremptionVue = peremption
            totauxLusLe = nil
            rapidesLusLe = nil
            missionsLuesLe = nil
        }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let maintenant = gateways.clock.now()
        func perime(_ luLe: Date?) -> Bool {
            guard let luLe else { return true }
            return maintenant.timeIntervalSince(luLe) > Self.delaiRelecture
        }
        let totauxALire: Bool
        switch totaux {
        case .chargement: totauxALire = true
        case .echec: totauxALire = false
        case .masques, .pret: totauxALire = perime(totauxLusLe)
        }
        let rapidesALire: Bool
        switch paiementsRapides {
        case .chargement: rapidesALire = true
        case .echec: rapidesALire = false
        case .pret: rapidesALire = perime(rapidesLusLe)
        }
        let missionsALire = erreur == nil && (!missionsChargees || perime(missionsLuesLe))
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

    /// « Charger plus de missions » : page suivante, seulement si le serveur en a annoncé une. Après un échec (bouton
    /// masqué, `afficheChargerPlus`), la page en échec est relue, jamais la suivante : aucune page n'est sautée (m3).
    public func chargerPlus() async {
        guard aSuivre, !chargementMissions else { return }
        await lireMissions(page: erreur == nil ? pageDemandee + 1 : pageDemandee)
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
            totauxLusLe = gateways.clock.now()
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
            rapidesLusLe = gateways.clock.now()
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
            // Revue B8 n°2 de T12, m2 : l'état de TOUTES les lignes affichées suit les déclarations de cette lecture.
            missions = Self.appliquer(lue.derniersPaiements, a: page == 0 ? lue.missions : Self.fusionner(missions, lue.missions))
            aSuivre = lue.aSuivre
            missionsChargees = true
            if page == 0 { missionsLuesLe = gateways.clock.now() }
            erreur = nil
            sessionExpiree = false
        } catch {
            guard await memeEpoch(), generationMissions == courant,
                  let message = message(error, defaut: RevenusTextes.erreurDefaut) else { return }
            if (error as? JoleneError)?.kind == .unauthorized { sessionExpiree = true }
            erreur = message
            return
        }
        // Publié : l'audit part hors de la lecture, qui se termine aussitôt (`defer` ci-dessus).
        auditerConsultation(gateways)
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

    /// Dernière déclaration de chaque ligne affichée, prise dans l'index de la dernière lecture (toutes les déclarations
    /// du soignant, `PageMissionsTerminees.derniersPaiements`) : le web remplace sa carte entière à chaque chargement
    /// (`setPaiementsMap`, l.140-142), si bien que les lignes des pages précédentes prennent l'état le plus récent
    /// (revue B8 n°2 de T12, m2) ; une mission absente de l'index n'a plus de déclaration.
    static func appliquer(_ derniers: [String: PaiementSoignantLu], a missions: [MissionTerminee]) -> [MissionTerminee] {
        missions.map { mission in
            var relue = mission
            relue.dernierPaiement = derniers[mission.id]
            return relue
        }
    }

    /// Revue B8 de T12, m2 : tâche non structurée, lancée après la publication — elle n'hérite pas de l'annulation de la
    /// tâche de la vue (changement d'onglet) et personne ne l'attend (« Charger plus », « Réessayer » et tirer pour
    /// actualiser restent libres), comme le `.then(undefined, …)` du web. Bornée au délai de la session ; son échec
    /// est silencieux (`handleErrorSilent` du web). `auditTente` est posé au lancement : l'écriture, désormais jamais
    /// interrompue par la vue, rend toujours une issue.
    private func auditerConsultation(_ gateways: Gateways) {
        guard !auditTente else { return }
        auditTente = true
        let audit = gateways.audit
        let context = snapshot.context
        let userId = snapshot.user.id
        let delai = controller.resolutionTimeout
        auditEnCours = Task {
            _ = try? await bounded(timeout: delai) {
                try await audit.ecrire(action: .donneesPersoConsultation, typeRessource: Self.typeRessourceAudit,
                                       idRessource: userId, details: Self.detailsAudit, context: context)
            }
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
