import Foundation
import Combine

/// Modèle de l'écran des présences de l'établissement (lot 5, T8, **B9 paiements/escrow** ; `LOT5_PLAN.md` §2.6), port
/// de `src/pages/PresencesEtablissement.tsx` sur `gateways.etablissement.presences` pour l'epoch de la session, chaque
/// appel borné à `SessionController.resolutionTimeout`. Valider une présence déclenche côté serveur la libération du
/// séquestre : le modèle n'envoie que ce que l'établissement a confirmé, une seule fois, et relit avant d'annoncer.
///
/// - **Onglets dérivés** (`PresencesEtabRules.repartir`, `SynthesePresence` du lot 2) des créneaux relus et de
///   l'horloge : aucune date ni aucun statut posé localement (le web pose `valide_le` de façon optimiste, l.265-267 :
///   non porté).
/// - **Validation** (web l.251-309) : note 1-5 obligatoire, créneaux de la mission **relus** juste avant l'envoi
///   (l.213-249), `valider` (la gateway relit `valide_par_etablissement`), puis note au mieux — son échec ne défait
///   jamais la validation —, puis relecture de la liste.
/// - **Lot** (l.333-374) : présences à valider sans alerte, chacune revérifiée, identifiants éligibles envoyés ; le
///   résultat affiché est celui des lignes relues.
/// - **Contestation** (l.311-331) d'une présence à valider seulement ; **clôture** d'un segment ouvert, heure de Paris
///   bornée par `ClotureSegment` (D28).
/// - **Un seul appel par geste** : `enCours` est posé avant tout `await` de chaque action ; un second toucher est ignoré.
/// - **Issue inconnue** (délai dépassé, transport) : la liste est relue, jamais la mutation renvoyée ; seul l'état relu
///   décide de ce qui est annoncé.
/// - **Permissions** : actions offertes avec la permission `pointage` servie par le serveur, jamais recalculée ; un
///   refus de droit affiche le message de l'issue puis relit le périmètre une fois (`relirePerimetre`).
/// - Les refus du serveur s'affichent tels quels. Aucun montant, aucune durée facturée.
@MainActor
public final class PresencesEtabModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case chargee
        case echec(String)
    }

    /// Issue affichée au-dessus de la liste.
    public enum Annonce: Equatable, Sendable {
        case succes(String)
        case avertissement(String)
        case erreur(String)
        /// Résultat relu d'une validation en lot ; `complet` : toutes les présences envoyées sont relues validées.
        case lot(String, complet: Bool)
    }

    public struct Validation: Equatable, Sendable {
        public var presenceId: String
        public var note: Int
        public var prenom: String?
    }

    public struct Contestation: Equatable, Sendable {
        public var presenceId: String
        public var motif: String
        public var erreur: String?
    }

    public struct Cloture: Equatable, Sendable {
        public var missionId: String
        public var bornes: ClotureSegment.Bornes
        public var erreur: String?
    }

    public nonisolated static let noteMaximale = 5
    /// Borne basse du serveur (`length(trim(p_motif)) < 3`, `fn_contester_presence`).
    public nonisolated static let longueurMinMotif = 3
    /// Saisie bornée (choix natif) : le serveur ne garde que 500 caractères du motif dans son audit.
    public nonisolated static let longueurMaxMotif = 500
    /// Soignants lus par chargement pour le nom des cartes (`fn_soignant_pour_etablissement`, un appel par soignant).
    public nonisolated static let maxSoignantsParLecture = 25
    public nonisolated static let jetonLot = "lot"

    /// Mission de la destination `.presencesMission` ; `nil` pour l'onglet (toutes les missions).
    public let missionId: String?
    @Published public private(set) var etat: Etat = .chargement
    @Published public private(set) var presences: [PresenceEtab] = []
    @Published public private(set) var missionsSansPointage: [EtabMissionResume] = []
    @Published public private(set) var soignants: [String: SoignantPourEtab] = [:]
    @Published public private(set) var onglet: OngletPresencesEtab
    /// Horloge de la dernière lecture ou du dernier tic : les onglets en sont dérivés.
    @Published public private(set) var maintenant: Date
    /// Mutation en vol (identifiant de présence, de mission, ou `jetonLot`) : toute autre action est ignorée.
    @Published public private(set) var enCours: String?
    @Published public private(set) var annonce: Annonce?
    /// Refus serveur de la note, mot pour mot, quand la validation est acquise sans elle.
    @Published public private(set) var avisNote: String?
    @Published public private(set) var validation: Validation?
    @Published public private(set) var contestation: Contestation?
    @Published public private(set) var cloture: Cloture?
    @Published public private(set) var lotOuvert = false
    @Published public private(set) var rafraichissement = false
    @Published public private(set) var erreurRafraichissement: String?
    @Published public private(set) var context: EtablissementReadContext

    private let controller: SessionController
    private let epoch: Int
    private let relirePerimetre: @MainActor () async -> Void
    private var horloge: (any ClockPort)?
    private var generation = 0

    /// `relirePerimetre` : relecture des permissions après un refus de droit (`SessionStore.refreshEtablissementScope`).
    public init(missionId: String? = nil, onglet: String? = nil, controller: SessionController,
                snapshot: EtablissementSessionSnapshot, relirePerimetre: @escaping @MainActor () async -> Void = {}) {
        self.missionId = missionId
        self.onglet = OngletPresencesEtab(parametre: onglet)
        self.controller = controller
        self.context = snapshot.context
        self.epoch = snapshot.epoch
        self.relirePerimetre = relirePerimetre
        self.maintenant = Date()
    }

    // MARK: - État dérivé

    /// Permission `pointage` servie par `fn_mes_permissions_etab` (valider, lot, contester, clôturer).
    public var peutAgir: Bool { context.permissions.pointage }

    public var repartition: PresencesEtabRules.Repartition {
        PresencesEtabRules.repartir(presences, maintenant: maintenant)
    }

    public func nombre(_ onglet: OngletPresencesEtab) -> Int {
        let nombre = repartition.presences(onglet).count
        return onglet == .alertes ? nombre + missionsSansPointage.count : nombre
    }

    public func carte(_ presence: PresenceEtab) -> PresencesEtabPresentation.Carte {
        PresencesEtabPresentation.carte(presence, soignant: presence.soignantId.flatMap { soignants[$0] }, maintenant: maintenant)
    }

    public var peutConfirmerValidation: Bool {
        enCours == nil && (1...Self.noteMaximale).contains(validation?.note ?? 0)
    }

    public var motifNettoye: String {
        (contestation?.motif ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var peutEnvoyerContestation: Bool {
        enCours == nil && contestation != nil && motifNettoye.count >= Self.longueurMinMotif
    }

    /// Permissions relues à epoch constant (`SessionStore.refreshEtablissementScope`) : l'écran re-filtre ses actions.
    public func adopter(_ nouveau: EtablissementReadContext) {
        guard nouveau.epoch == epoch, nouveau != context else { return }
        context = nouveau
    }

    public func selectionner(_ onglet: OngletPresencesEtab) {
        self.onglet = onglet
    }

    /// Tic de l'écran (web l.185-188, 30 s) : les onglets suivent l'heure sans relecture.
    public func actualiserHorloge() {
        if let horloge { maintenant = horloge.now() }
    }

    public func effacerAnnonce() {
        annonce = nil
        avisNote = nil
    }

    // MARK: - Lecture

    /// Lit (ou relit) les présences, leurs créneaux et les missions terminées ; une liste affichée est conservée
    /// pendant la relecture, son échec n'expose qu'`erreurRafraichissement`.
    public func charger() async {
        generation += 1
        let courant = generation
        let conserver = etat == .chargee
        erreurRafraichissement = nil
        if conserver { rafraichissement = true } else { etat = .chargement }
        defer { if generation == courant { rafraichissement = false } }

        guard let gateways = await controller.gateways(for: epoch) else { return }
        guard generation == courant, !Task.isCancelled else { return }
        let port = gateways.etablissement.presences
        let contexte = context
        let delai = controller.resolutionTimeout
        do {
            async let lues = bounded(timeout: delai) { try await port.presences(context: contexte) }
            async let finies = bounded(timeout: delai) { try await port.missionsTerminees(context: contexte) }
            let (relues, terminees) = try await (lues, finies)
            guard await epochValide(), generation == courant else { return }
            let retenues = missionId.map { id in relues.filter { $0.missionId == id } } ?? relues
            let sansPointage = PresencesEtabRules.missionsSansPointage(terminees: terminees, presences: relues)
            presences = retenues
            missionsSansPointage = missionId.map { id in sansPointage.filter { $0.id == id } } ?? sansPointage
            horloge = gateways.clock
            maintenant = gateways.clock.now()
            etat = .chargee
            await lireSoignants(gateways.etablissement.missions, contexte, delai, courant)
        } catch {
            guard await epochValide(), generation == courant, !Task.isCancelled, let message = Self.message(error) else { return }
            if conserver { erreurRafraichissement = message } else { etat = .echec(message) }
        }
    }

    /// Noms des cartes, au mieux (`fn_soignant_pour_etablissement`, port de T5) : un échec laisse « Soignant », comme le
    /// repli du web (l.430) ; un soignant déjà lu n'est pas relu.
    private func lireSoignants(_ port: any EtabMissionsPort, _ contexte: EtablissementReadContext, _ delai: TimeInterval,
                               _ courant: Int) async {
        let manquants = Set(presences.compactMap(\.soignantId)).subtracting(soignants.keys).sorted()
            .prefix(Self.maxSoignantsParLecture)
        guard !manquants.isEmpty else { return }
        let lus = await withTaskGroup(of: SoignantPourEtab?.self) { groupe -> [SoignantPourEtab] in
            for id in manquants {
                groupe.addTask { (try? await bounded(timeout: delai) { try await port.soignant(id: id, context: contexte) }) ?? nil }
            }
            var lus: [SoignantPourEtab] = []
            for await soignant in groupe { if let soignant { lus.append(soignant) } }
            return lus
        }
        guard await epochValide(), generation == courant else { return }
        for soignant in lus { soignants[soignant.id] = soignant }
    }

    // MARK: - Validation

    /// « Valider » (web l.469) : ouvre la note, obligatoire avant la validation (l.244-250).
    public func ouvrirValidation(presenceId: String) {
        guard peutAgir, enCours == nil, validation == nil, let presence = aValider(presenceId) else { return }
        effacerAnnonce()
        validation = Validation(presenceId: presenceId, note: 0, prenom: carte(presence).prenom)
    }

    public func choisirNote(_ note: Int) {
        guard enCours == nil, validation != nil, (1...Self.noteMaximale).contains(note) else { return }
        validation?.note = note
    }

    public func annulerValidation() {
        guard enCours == nil else { return }
        validation = nil
    }

    /// « Valider et noter » (web l.251-309).
    public func confirmerValidation() async {
        guard peutAgir, peutConfirmerValidation, let ouverte = validation,
              let presence = presences.first(where: { $0.id == ouverte.presenceId }) else { return }
        enCours = presence.id
        defer { enCours = nil }
        effacerAnnonce()
        guard let gateways = await controller.gateways(for: epoch) else { return }
        let port = gateways.etablissement.presences
        let contexte = context
        let eligible = await toujoursEligible(presence, port, gateways.clock)
        guard await epochValide() else { return }
        guard eligible else {
            validation = nil
            annonce = .avertissement(PresencesEtabPresentation.plusEligible)
            await charger()
            return
        }
        let id = presence.id
        let issue: ValidationPresenceOutcome
        do {
            issue = try await bounded(timeout: controller.resolutionTimeout) { try await port.valider(presenceId: id, context: contexte) }
        } catch {
            guard await epochValide() else { return }
            // Issue inconnue (délai, transport, relecture non confirmée) : la liste est relue, jamais la validation renvoyée.
            validation = nil
            await charger()
            if presences.first(where: { $0.id == id })?.valideParEtablissement == true {
                await noter(presence.missionId, ouverte.note, port)
            } else if let message = Self.message(error) {
                annonce = .erreur(message)
            }
            return
        }
        guard await epochValide() else { return }
        validation = nil
        switch issue {
        case .validee:
            await noter(presence.missionId, ouverte.note, port)
        case let .refusee(message):
            annonce = .erreur(message)
        case let .accesRefuse(message):
            annonce = .erreur(message)
            await relirePerimetre()
        }
        await charger()
    }

    /// Note au mieux après une validation relue (D6) : annonce du web (l.304-307) ; un refus serveur de la note est
    /// affiché à part, mot pour mot, sans jamais défaire la validation.
    private func noter(_ missionId: String, _ note: Int, _ port: any EtabPresencesPort) async {
        let contexte = context
        let issue = try? await bounded(timeout: controller.resolutionTimeout) {
            try await port.noter(missionId: missionId, note: note, context: contexte)
        }
        guard await epochValide() else { return }
        if issue == .enregistree {
            annonce = .succes(PresencesEtabPresentation.succesValidationNotee(note))
        } else {
            annonce = .succes(PresencesEtabPresentation.succesValidation)
            if case let .nonEnregistree(message?) = issue { avisNote = message }
        }
    }

    /// Relecture des créneaux juste avant la mutation (`verifierEligibiliteActuelle`, web l.213-242) : une autre session
    /// peut avoir ouvert un pointage depuis le chargement. Toute erreur de relecture vaut « non éligible ».
    private func toujoursEligible(_ presence: PresenceEtab, _ port: any EtabPresencesPort, _ horloge: any ClockPort) async -> Bool {
        let contexte = context
        let missionId = presence.missionId
        let delai = controller.resolutionTimeout
        guard let relus = try? await bounded(timeout: delai, { try await port.creneaux(missionId: missionId, context: contexte) }) else {
            return false
        }
        return PresencesEtabRules.analyser(mission: presence.mission, missionId: missionId, creneaux: relus,
                                           maintenant: horloge.now()).validationPossible
    }

    private func aValider(_ presenceId: String) -> PresenceEtab? {
        repartition.aValider.first { $0.id == presenceId }
    }

    // MARK: - Lot

    /// Présences à valider sans alerte (web l.209-211).
    public var lotEligibles: [PresenceEtab] { repartition.sansAlerte }

    public func ouvrirLot() {
        guard peutAgir, enCours == nil, !lotOuvert, !lotEligibles.isEmpty else { return }
        effacerAnnonce()
        lotOuvert = true
    }

    public func annulerLot() {
        guard enCours == nil else { return }
        lotOuvert = false
    }

    /// « Valider N présences » (web l.333-374).
    public func confirmerLot() async {
        guard peutAgir, enCours == nil, lotOuvert else { return }
        let candidates = lotEligibles
        guard !candidates.isEmpty else {
            lotOuvert = false
            annonce = .avertissement(PresencesEtabPresentation.lotAucuneEligible)
            return
        }
        enCours = Self.jetonLot
        defer { enCours = nil }
        effacerAnnonce()
        guard let gateways = await controller.gateways(for: epoch) else { return }
        let port = gateways.etablissement.presences
        let contexte = context
        var ids: [String] = []
        // Chaque présence est revérifiée sur ses créneaux relus (web l.339-347), l'une après l'autre.
        for presence in candidates {
            if await toujoursEligible(presence, port, gateways.clock) { ids.append(presence.id) }
        }
        guard await epochValide() else { return }
        guard !ids.isEmpty else {
            lotOuvert = false
            annonce = .avertissement(PresencesEtabPresentation.lotPlusEligible)
            await charger()
            return
        }
        let envoyes = ids
        let issue: ValidationLotOutcome
        do {
            issue = try await bounded(timeout: controller.resolutionTimeout) { try await port.validerLot(ids: envoyes, context: contexte) }
        } catch {
            guard await epochValide() else { return }
            // Issue inconnue : seule la liste relue dit ce qui a été validé ; le lot n'est jamais renvoyé.
            lotOuvert = false
            await charger()
            let validees = presences.filter { envoyes.contains($0.id) && $0.valideParEtablissement }.count
            if validees > 0 {
                annoncerLot(validees: validees, selectionnees: envoyes.count)
            } else if let message = Self.message(error) {
                annonce = .erreur(message)
            }
            return
        }
        guard await epochValide() else { return }
        lotOuvert = false
        switch issue {
        case let .traitee(validees, selectionnees):
            annoncerLot(validees: validees, selectionnees: selectionnees)
        case let .refusee(message):
            annonce = .erreur(message)
        case let .accesRefuse(message):
            annonce = .erreur(message)
            await relirePerimetre()
        }
        await charger()
    }

    private func annoncerLot(validees: Int, selectionnees: Int) {
        annonce = .lot(PresencesEtabPresentation.lotResultat(validees: validees, selectionnees: selectionnees),
                       complet: validees == selectionnees)
    }

    // MARK: - Contestation

    /// « Contester » : proposé pour une présence à valider seulement (`CarteValidation.tsx` l.213-255).
    public func ouvrirContestation(presenceId: String) {
        guard peutAgir, enCours == nil, contestation == nil, aValider(presenceId) != nil else { return }
        effacerAnnonce()
        contestation = Contestation(presenceId: presenceId, motif: "", erreur: nil)
    }

    public func saisirMotif(_ texte: String) {
        guard enCours == nil, contestation != nil else { return }
        contestation?.motif = String(texte.prefix(Self.longueurMaxMotif))
    }

    public func annulerContestation() {
        guard enCours == nil else { return }
        contestation = nil
    }

    /// « Envoyer la contestation » (web l.311-331) ; `motif_litige` relu par la gateway avant le succès.
    public func envoyerContestation() async {
        guard peutAgir, peutEnvoyerContestation, let ouverte = contestation else { return }
        let id = ouverte.presenceId
        let motif = motifNettoye
        enCours = id
        defer { enCours = nil }
        contestation?.erreur = nil
        effacerAnnonce()
        guard let gateways = await controller.gateways(for: epoch) else { return }
        let port = gateways.etablissement.presences
        let contexte = context
        let issue: ContestationOutcome
        do {
            issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.contester(presenceId: id, motif: motif, context: contexte)
            }
        } catch {
            guard await epochValide() else { return }
            await charger()
            if presences.first(where: { $0.id == id })?.motifLitige == motif {
                contestation = nil
                annonce = .avertissement(PresencesEtabPresentation.succesContestation)
            } else if let message = Self.message(error) {
                contestation?.erreur = message
            }
            return
        }
        guard await epochValide() else { return }
        switch issue {
        case .contestee:
            contestation = nil
            annonce = .avertissement(PresencesEtabPresentation.succesContestation)
            await charger()
        case let .refusee(message):
            contestation?.erreur = message
        case let .accesRefuse(message):
            contestation = nil
            annonce = .erreur(message)
            await relirePerimetre()
        }
    }

    // MARK: - Clôture rétroactive

    /// « Clôturer le segment » : proposé quand un segment est ouvert ; bornes du sélecteur dérivées des créneaux relus.
    public func ouvrirCloture(missionId: String) {
        guard peutAgir, enCours == nil, cloture == nil,
              let presence = presences.first(where: { $0.missionId == missionId }),
              let bornes = ClotureSegment.bornes(creneaux: presence.creneaux, maintenant: horloge?.now() ?? maintenant) else { return }
        effacerAnnonce()
        cloture = Cloture(missionId: missionId, bornes: bornes, erreur: nil)
    }

    public func annulerCloture() {
        guard enCours == nil else { return }
        cloture = nil
    }

    /// `saisie` : heure de fin réelle `YYYY-MM-DDTHH:mm`, en heure de Paris (`cloturerRetroactif`, web l.177-202).
    public func confirmerCloture(saisie: String) async {
        guard peutAgir, enCours == nil, let ouverte = cloture else { return }
        let missionId = ouverte.missionId
        enCours = missionId
        defer { enCours = nil }
        cloture?.erreur = nil
        effacerAnnonce()
        guard let gateways = await controller.gateways(for: epoch) else { return }
        let heure: Date
        switch ClotureSegment.analyser(saisie: saisie, maintenant: gateways.clock.now()) {
        case let .refus(message):
            cloture?.erreur = message
            return
        case let .heure(instant):
            heure = instant
        }
        let port = gateways.etablissement.presences
        let contexte = context
        let issue: ClotureOutcome
        do {
            issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.cloturerSegment(missionId: missionId, heureFin: heure, context: contexte)
            }
        } catch {
            guard await epochValide() else { return }
            // Issue inconnue : la liste est relue, jamais la clôture renvoyée.
            await charger()
            if erreurRafraichissement == nil, let relue = presences.first(where: { $0.missionId == missionId }),
               PresencesEtabRules.analyser(relue, maintenant: maintenant).synthese.effectifsOuverts.isEmpty {
                cloture = nil
                annonce = .succes(PresencesEtabPresentation.succesCloture)
            } else if let message = Self.message(error) {
                cloture?.erreur = message
            }
            return
        }
        guard await epochValide() else { return }
        switch issue {
        case .cloturee:
            cloture = nil
            annonce = .succes(PresencesEtabPresentation.succesCloture)
            await charger()
        case let .refusee(message):
            cloture?.erreur = message
        case let .accesRefuse(message):
            cloture = nil
            annonce = .erreur(message)
            await relirePerimetre()
        }
    }

    // MARK: - Communs

    private func epochValide() async -> Bool {
        await controller.epoch == epoch
    }

    /// Message affiché d'une erreur ; `nil` pour une annulation (jamais une erreur affichée).
    static func message(_ error: Error) -> String? {
        if let jolene = error as? JoleneError { return jolene.kind == .cancelled ? nil : jolene.message }
        if error is CancellationError { return nil }
        return PresencesEtabPresentation.messageErreurGenerique
    }
}
