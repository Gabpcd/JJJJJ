import Combine
import Foundation

/// Modèle du bloc de pointage rotatif d'une mission (blueprint lot 2 §2.5, §3 T3 ; parité
/// `src/components/pointage/PointageRotatifSoignant.tsx`). Aucun texte affiché ici : l'écran (T4b) traduit `Issue`
/// avec les libellés web ; seuls les messages serveur traversent tels quels (décision 6).
///
/// Règles :
/// - un seul envoi à la fois (`envoiEnCours`, web l.116 `envoiEnCours.current`) : un double tap ne fait qu'un appel ;
/// - avant chaque envoi, l'état et les preuves `scans_pointage` sont relus (base du reçu `RecuScan`) ; le reçu est
///   journalisé en `prepared`, puis `started` juste avant l'UNIQUE requête `fn_scanner_code_pointage` ;
/// - succès annoncé seulement après relecture (la gateway relit état et preuves), puis nouvelle relecture de l'état :
///   un second scan n'est possible qu'après la relecture du nouvel état (`PointageRotatifSoignant.continuite.test.tsx`) ;
/// - réponse perdue, délai `bounded` ou erreur de transport → `.verification` : reçu `started` gardé, réconciliation
///   par relecture, JAMAIS de renvoi (décision 2) ; hors ligne → aucun appel, reçu `not_sent` ;
/// - réponse ignorée si l'écran a disparu (`desactiver()`, web l.53-55 `actif.current`) ou si l'epoch a changé ;
/// - état relu toutes les 15 s quand le bloc est visible (`suivre()`, web l.71 `refetchInterval: 15000`).
///
/// Réconciliation (consignes T3 de `docs/mobile-swift/DECISIONS_LOT2.md`) : reçu `prepared` orphelin → `not_sent` puis
/// effacé (aucune requête n'est partie : `started` précède toujours l'envoi) ; reçu terminal → effacé ; reçu `started`
/// → `PointagePort.reconcilier`. Le verdict « non reçu » attend aussi 8 s sur l'horloge MONOTONE du processus quand
/// l'essai y a démarré (revue de T1, M1 : une horloge d'appareil avancée ne raccourcit pas l'attente).
@MainActor
public final class PointageModel: ObservableObject {
    /// `refetchInterval` du web (l.71).
    public static let intervalleSuivi: TimeInterval = 15
    /// Pause entre deux relectures d'un reçu encore incertain.
    public static let pauseRelecture: TimeInterval = 2
    /// Relectures enchaînées après une réponse perdue ; au-delà, le suivi (15 s) reprend la réconciliation.
    public static let maxRelectures = 3
    /// Message du web quand l'état ne se charge pas (`PointageRotatifSoignant.tsx` l.86), sans message serveur.
    public static let messageEtatIndisponible = "Impossible de charger son état."

    public enum Chargement: Equatable, Sendable {
        case chargement
        case pret(EtatPointage)
        /// `{error}` serveur verbatim (« Accès interdit », « Mission introuvable ») ou message de transport.
        case indisponible(String)
    }

    /// Dernière issue d'un pointage, traduite par l'écran (T4b).
    public enum Issue: Equatable, Sendable {
        /// Accepté par le serveur ET relu.
        case enregistre(TypeScan?)
        /// Refus serveur verbatim ; `codeInvalide` : surcharge vouvoyée de la décision 6 (`P0002` du code inconnu).
        case refuse(message: String, codeInvalide: Bool)
        /// Hors ligne : aucun appel, reçu `not_sent`.
        case horsLigne
        /// Réponse perdue : vérification par relecture en cours.
        case verification
        /// Le serveur n'a rien reçu (relecture ≥ 8 s) : saisir le code courant (il a pu tourner).
        case nonRecu
        /// `RecuScan.messageRecuEnCours`.
        case recuEnCours
        /// `RecuScan.messageIllisible` et renvoi web `/soignant/presences` (journal illisible, horloge incohérente).
        case suiviIllisible
        /// Erreur avant tout envoi (identifiant terminal, relecture de la base) : message tel quel.
        case erreur(String)
    }

    @Published public private(set) var chargement: Chargement = .chargement
    @Published public private(set) var envoiEnCours = false
    @Published public private(set) var issue: Issue?
    /// FERMETURE relue alors que la fin prévue est atteinte à 30 min près (l.155-160) ; la mémoire « une fois par
    /// mission » relève de la notation (T5a).
    @Published public private(set) var notationAProposer = false
    @Published public private(set) var sessionExpired = false

    public let missionId: String
    private let finLe: String?
    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private let appareil: Appareil
    private let journal: ReceiptJournal<RecuScan>
    private let attendre: @Sendable (TimeInterval) async -> Void
    private let monotone: @Sendable () -> TimeInterval
    private var actif = true
    private var reconciliationEnCours = false

    /// Essais en vol dans ce processus, tous blocs confondus : un autre modèle ne les réconcilie pas.
    private static var essaisEnVol: Set<String> = []
    /// Passage `started` sur l'horloge monotone du processus, par essai.
    private static var demarragesMonotones: [String: TimeInterval] = [:]

    public init(missionId: String, finLe: String?, controller: SessionController, snapshot: SessionSnapshot, appareil: Appareil,
                attendre: @escaping @Sendable (TimeInterval) async -> Void = { await PointageModel.attendreReellement($0) },
                monotone: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.missionId = missionId
        self.finLe = finLe
        self.controller = controller
        self.snapshot = snapshot
        self.appareil = appareil
        self.journal = ReceiptJournal<RecuScan>(store: appareil.recus)
        self.attendre = attendre
        self.monotone = monotone
    }

    public nonisolated static func attendreReellement(_ secondes: TimeInterval) async {
        try? await Task.sleep(nanoseconds: delaiEnNanosecondes(secondes))
    }

    public var etat: EtatPointage? {
        if case let .pret(etat) = chargement { return etat }
        return nil
    }

    /// Envoi possible : état relu, statut pointable, aucun envoi ni vérification en cours, suivi lisible. La fenêtre
    /// (`DisponibilitePointage`) et le réseau sont combinés par l'écran.
    public var peutEnvoyer: Bool {
        guard actif, !envoiEnCours, let etat, PointageRules.pointageDisponible(statut: etat.statut) else { return false }
        return issue != .verification && issue != .suiviIllisible
    }

    /// L'écran a disparu : toute réponse encore en vol est ignorée.
    public func desactiver() { actif = false }

    // MARK: - Lecture

    /// Relit l'état (`fn_etat_pointage_mission`), puis réconcilie un reçu en attente.
    public func charger() async {
        guard actif, let x = await contexte() else { return }
        let port = x.port, mission = missionId, context = x.context
        do {
            let etat = try await bounded(timeout: x.delai) { try await port.etat(missionId: mission, context: context) }
            guard await estCourant() else { return }
            sessionExpired = false
            chargement = .pret(etat)
        } catch {
            guard await estCourant(), !Self.estAnnulation(error) else { return }
            noterSession(error)
            chargement = .indisponible(Self.message(error))
        }
        await reconcilier()
    }

    /// Tic du suivi (15 s) : relecture, sauf pendant un envoi.
    public func rafraichir() async {
        guard !envoiEnCours else { return }
        await charger()
    }

    /// Suivi tant que le bloc est visible (à lancer dans le `.task` de l'écran, annulé à sa disparition).
    public func suivre() async {
        while actif, !Task.isCancelled {
            await attendre(Self.intervalleSuivi)
            guard actif, !Task.isCancelled else { return }
            await rafraichir()
        }
    }

    // MARK: - Pointage

    /// Envoie le code saisi ou lu (six chiffres après `trim`, sinon rien). `gps` : observation de `LocationPort`, nil
    /// si la position n'est pas demandée (consentement absent ou refusé, T4b).
    public func pointer(code saisie: String, gps: ObservationGps?) async {
        guard actif, !envoiEnCours, let code = PointageRules.codeSaisi(saisie), etat != nil else { return }
        envoiEnCours = true
        defer { envoiEnCours = false }
        issue = nil
        notationAProposer = false
        guard let x = await contexte(), actif else { return }
        await envoyer(code: code, gps: gps, x)
    }

    private func envoyer(code: String, gps: ObservationGps?, _ x: Contexte) async {
        let userId = x.context.userId
        let existant: RecuScan?
        do { existant = try await journal.lire(userId: userId) } catch { issue = .suiviIllisible; return }
        if let existant, !existant.estTermine {
            issue = .recuEnCours
            return
        }
        let terminal: String
        do { terminal = try appareil.terminal.identifiant() } catch { issue = .erreur(Self.message(error)); return }
        let gpsRecu = RecuScan.Gps(observation: gps)

        guard await appareil.reseau.estEnLigne() else {
            if let etat, let recu = try? RecuScan.preparer(userId: userId, epoch: snapshot.epoch, missionId: missionId,
                                                            terminalId: terminal, typeAttendu: etat.prochainTypeScan ?? .ouverture,
                                                            nbScansAvant: etat.nbScans ?? 0, preuvesAvant: [], gps: gpsRecu,
                                                            existant: existant) {
                do {
                    try await journal.ecrire(recu)
                    try await journal.ecrire(recu.marquerNonEnvoye())
                } catch {
                    issue = .suiviIllisible
                    return
                }
            }
            issue = .horsLigne
            return
        }

        // Base du reçu : état et preuves relus juste avant l'envoi.
        let port = x.port, mission = missionId, context = x.context
        let base: (etat: EtatPointage, preuves: [PreuveScan])
        do {
            base = try await bounded(timeout: x.delai) {
                async let etat = port.etat(missionId: mission, context: context)
                async let preuves = port.preuvesScan(missionId: mission, context: context)
                return try await (etat: etat, preuves: preuves)
            }
        } catch {
            guard await estCourant(), !Self.estAnnulation(error) else { return }
            noterSession(error)
            issue = .erreur(Self.message(error))
            return
        }
        guard await estCourant() else { return }
        chargement = .pret(base.etat)
        guard PointageRules.pointageDisponible(statut: base.etat.statut) else { return }

        let demarre: RecuScan
        var essai: String?
        do {
            let recu = try RecuScan.preparer(userId: userId, epoch: snapshot.epoch, missionId: missionId, terminalId: terminal,
                                             typeAttendu: base.etat.prochainTypeScan ?? .ouverture,
                                             nbScansAvant: base.etat.nbScans ?? 0,
                                             preuvesAvant: base.preuves.filter { $0.missionId == mission }.map(\.id),
                                             gps: gpsRecu, existant: existant)
            essai = recu.attemptId
            Self.essaisEnVol.insert(recu.attemptId)
            try await journal.ecrire(recu)
            demarre = try recu.demarrer(le: x.horloge.now())
            Self.demarragesMonotones[recu.attemptId] = monotone()
            try await journal.ecrire(demarre)
        } catch {
            if let essai { oublier(essai) }
            issue = (error as? RecuErreur) == .recuEnCours ? .recuEnCours : .suiviIllisible
            return
        }
        defer { Self.essaisEnVol.remove(demarre.attemptId) }

        let metadonnees = MetadonneesScan(idTerminal: terminal, observation: gps)
        let resultat: IssueScan
        do {
            resultat = try await bounded(timeout: x.delai) {
                try await port.scanner(code: code, metadonnees: metadonnees, recu: demarre, context: context)
            }
        } catch {
            // Délai `bounded` ou transport : la requête a pu être appliquée (PRINCIPES §3-§4).
            resultat = .incertain
        }
        guard await estCourant() else { return }
        await traiter(resultat, recu: demarre, x)
    }

    private func traiter(_ resultat: IssueScan, recu: RecuScan, _ x: Contexte) async {
        switch resultat {
        case let .enregistre(typeScan, _):
            await conclureEnregistre(recu, typeScan: typeScan, x)
        case let .refuse(sqlstate, message):
            // Anti-rejeu juste après une réponse perdue : un scan de ce terminal vient d'être enregistré (§2.5).
            if PointageRules.estAntiRejeu(sqlstate: sqlstate, message: message) {
                let port = x.port, context = x.context
                if case let .enregistre(type, _)? = try? await bounded(timeout: x.delai, {
                    try await port.reconcilier(recu: recu, context: context)
                }) {
                    await conclureEnregistre(recu, typeScan: type, x)
                    return
                }
            }
            // Rollback prouvé : `refused` si SQLSTATE, puis relecture, puis effacement (consigne T3).
            if let sqlstate, RecuScan.sqlstateValide(sqlstate), let refuse = try? recu.refuser(sqlstate: sqlstate) {
                try? await journal.ecrire(refuse)
            }
            await relireEtat(x)
            oublier(recu.attemptId)
            try? await journal.effacer(recu)
            issue = .refuse(message: message, codeInvalide: PointageRules.estCodeInvalide(sqlstate: sqlstate, message: message))
        case .incertain, .nonEnvoye:
            // `scanner` ne rend jamais `.nonEnvoye` : traité, par prudence, comme une réponse perdue.
            await reconcilierRecu(recu, x)
        case .nonRecu:
            oublier(recu.attemptId)
            try? await journal.effacer(recu)
            issue = .nonRecu
        case .horlogeIncoherente:
            issue = .suiviIllisible
        }
    }

    private func conclureEnregistre(_ recu: RecuScan, typeScan: TypeScan?, _ x: Contexte) async {
        oublier(recu.attemptId)
        try? await journal.effacer(recu)
        await relireEtat(x)
        guard recu.missionId == missionId else { return }
        issue = .enregistre(typeScan)
        notationAProposer = PointageRules.notationAProposer(typeScan: typeScan, finLe: finLe, maintenant: x.horloge.now())
    }

    // MARK: - Réconciliation

    /// Réconcilie le reçu en attente de l'utilisateur (lancement, retour au premier plan, ouverture, suivi).
    public func reconcilier() async {
        guard actif, !reconciliationEnCours, !envoiEnCours else { return }
        reconciliationEnCours = true
        defer { reconciliationEnCours = false }
        guard let x = await contexte(), actif else { return }
        let recu: RecuScan?
        do {
            recu = try await journal.lire(userId: x.context.userId)
        } catch {
            if await estCourant() { issue = .suiviIllisible }
            return
        }
        guard let recu, !Self.essaisEnVol.contains(recu.attemptId) else { return }
        switch recu.phase {
        case .prepared:
            // Orphelin : `started` est toujours écrit avant l'unique requête, rien n'est parti.
            if let nonEnvoye = try? recu.marquerNonEnvoye() { try? await journal.ecrire(nonEnvoye) }
            try? await journal.effacer(recu)
        case .refused, .notSent:
            try? await journal.effacer(recu)
        case .started:
            await reconcilierRecu(recu, x)
        }
    }

    private func reconcilierRecu(_ recu: RecuScan, _ x: Contexte) async {
        let memeMission = recu.missionId == missionId
        if memeMission { issue = .verification }
        let port = x.port, context = x.context
        for tentative in 0..<Self.maxRelectures {
            if let debut = Self.demarragesMonotones[recu.attemptId] {
                let reste = RecuScan.delaiAbsenceProuvee - (monotone() - debut)
                if reste > 0 { await attendre(reste) }
            }
            if tentative > 0 { await attendre(Self.pauseRelecture) }
            guard await estCourant() else { return }
            let verdict: IssueScan
            do {
                verdict = try await bounded(timeout: x.delai) { try await port.reconcilier(recu: recu, context: context) }
            } catch is RecuErreur {
                if await estCourant() { issue = .suiviIllisible }
                return
            } catch {
                continue
            }
            guard await estCourant() else { return }
            switch verdict {
            case let .enregistre(type, _):
                await conclureEnregistre(recu, typeScan: type, x)
                return
            case .nonRecu:
                oublier(recu.attemptId)
                try? await journal.effacer(recu)
                await relireEtat(x)
                if memeMission { issue = .nonRecu }
                return
            case .horlogeIncoherente:
                issue = .suiviIllisible
                return
            case .incertain, .refuse, .nonEnvoye:
                continue
            }
        }
    }

    // MARK: - Interne

    private struct Contexte {
        let port: any PointagePort
        let horloge: any ClockPort
        let context: MissionReadContext
        let delai: TimeInterval
    }

    private func contexte() async -> Contexte? {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return nil }
        return Contexte(port: gateways.pointage, horloge: gateways.clock, context: snapshot.context,
                        delai: controller.resolutionTimeout)
    }

    private func relireEtat(_ x: Contexte) async {
        let port = x.port, mission = missionId, context = x.context
        guard let etat = try? await bounded(timeout: x.delai, { try await port.etat(missionId: mission, context: context) }),
              await estCourant() else { return }
        chargement = .pret(etat)
    }

    private func estCourant() async -> Bool {
        guard actif, !Task.isCancelled else { return false }
        return await controller.epoch == snapshot.epoch
    }

    private func oublier(_ essai: String) {
        Self.essaisEnVol.remove(essai)
        Self.demarragesMonotones[essai] = nil
    }

    private func noterSession(_ error: Error) {
        sessionExpired = (error as? JoleneError)?.kind == .unauthorized
    }

    private static func estAnnulation(_ error: Error) -> Bool {
        error is CancellationError || (error as? JoleneError)?.kind == .cancelled
    }

    private static func message(_ error: Error) -> String {
        (error as? JoleneError)?.message ?? messageEtatIndisponible
    }
}
