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
/// - un HTTP 200 n'aboutit jamais à « non reçu » (revue fraîche de T3, M-A) : scan relu sur une autre mission →
///   `.enregistreSurAutreMission`, non confirmé → `.suiviIllisible` ; dans les deux cas le reçu est soldé, sans
///   réconciliation (filtrée sur la mission du reçu, elle conclurait à tort « non reçu ») ;
/// - réponse perdue, délai `bounded` ou erreur de transport → `.verification` : reçu `started` gardé, réconciliation
///   par relecture, JAMAIS de renvoi (décision 2) ; hors ligne → aucun appel, reçu `not_sent` ;
/// - session expirée (`.unauthorized`) au scan ou pendant la réconciliation → `sessionExpired`, reçu `started` gardé
///   (réconcilié au retour de l'utilisateur, nouvel epoch), jamais un refus ni un renvoi (m1) ;
/// - réponse ignorée si l'écran a disparu (`desactiver()`, web l.53-55 `actif.current`) ou si l'epoch a changé.
///   L'écran qui réapparaît (onglet rouvert : même `@StateObject`) réactive le bloc par `activer()`, ou `charger()` et
///   `suivre()` qui l'appellent ; une réponse émise avant la disparition reste ignorée (génération, M-B). Une issue
///   décidée par le serveur (succès, refus, « non reçu ») solde quand même le reçu si l'epoch n'a pas changé ;
/// - état relu toutes les 15 s quand le bloc est visible (`suivre()`, web l.71 `refetchInterval: 15000`) ;
///   `charger()` ne relit rien pendant un envoi (m7).
///
/// Réconciliation (consignes T3 de `docs/mobile-swift/DECISIONS_LOT2.md`) : reçu `prepared` orphelin → `not_sent` puis
/// effacé (aucune requête n'est partie : `started` précède toujours l'envoi) ; reçu terminal → effacé ; reçu `started`
/// → `PointagePort.reconcilier`. Le verdict « non reçu » attend aussi, sur l'horloge MONOTONE du processus quand l'essai
/// y a démarré, 8 s après `started` (revue de T1, M1 : une horloge d'appareil avancée ne raccourcit pas l'attente) et,
/// pour un essai sorti sans réponse, l'instant de sortie (au moins le délai `bounded`) + 10 s d'attente du pool
/// PostgREST (`PGRST003`) + 8 s de `statement_timeout` (revue fraîche de T3, m2).
@MainActor
public final class PointageModel: ObservableObject {
    /// `refetchInterval` du web (l.71).
    public static let intervalleSuivi: TimeInterval = 15
    /// Pause entre deux relectures d'un reçu encore incertain.
    public static let pauseRelecture: TimeInterval = 2
    /// Relectures enchaînées après une réponse perdue ; au-delà, le suivi (15 s) reprend la réconciliation.
    public static let maxRelectures = 3
    /// Attente d'une connexion du pool PostgREST avant l'ouverture de la transaction (`PGRST003`, délai d'acquisition
    /// de 10 s) : une requête sortie sans réponse peut encore être validée jusqu'à cette attente plus
    /// `RecuScan.delaiAbsenceProuvee` (`statement_timeout`) après sa sortie (revue fraîche de T3, m2).
    public static let attentePoolPostgREST: TimeInterval = 10
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
        /// Accepté par le serveur (HTTP 200) et relu sur une AUTRE mission : le code saisi était celui de `missionId`
        /// (revue fraîche de T3, M-A). L'écran affiche le succès du web et recharge les présences (T4b).
        case enregistreSurAutreMission(TypeScan?, missionId: String)
        /// Refus serveur verbatim ; `codeInvalide` : surcharge vouvoyée de la décision 6 (`P0002` du code inconnu).
        case refuse(message: String, codeInvalide: Bool)
        /// Hors ligne : aucun appel, reçu `not_sent`.
        case horsLigne
        /// Réponse perdue (ou session expirée) : vérification par relecture en cours.
        case verification
        /// Le serveur n'a rien reçu (relecture ≥ 8 s) : saisir le code courant (il a pu tourner).
        case nonRecu
        /// `RecuScan.messageRecuEnCours`.
        case recuEnCours
        /// `RecuScan.messageIllisible` et renvoi web `/soignant/presences` (journal illisible, horloge incohérente,
        /// HTTP 200 sans preuve relue).
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
    /// Avance à chaque disparition : une opération commencée avant ne publie plus rien (M-B).
    private var generation = 0
    private var reconciliationEnCours = false

    /// Essais en vol dans ce processus, tous blocs confondus : un autre modèle ne les réconcilie pas.
    private static var essaisEnVol: Set<String> = []
    /// Passage `started` sur l'horloge monotone du processus, par essai.
    private static var demarragesMonotones: [String: TimeInterval] = [:]
    /// Attente monotone minimale avant « non reçu », par essai sorti sans réponse (m2) ; sinon `delaiAbsenceProuvee`.
    private static var delaisAbsence: [String: TimeInterval] = [:]

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

    // MARK: - Cycle de vie (consigne T4b)

    /// L'écran réapparaît : le bloc redevient opérant. Les opérations commencées avant la disparition restent ignorées
    /// (leur génération est périmée). `charger()` et `suivre()` l'appellent eux-mêmes.
    public func activer() {
        actif = true
    }

    /// L'écran a disparu : toute réponse encore en vol est ignorée, `suivre()` s'arrête.
    public func desactiver() {
        guard actif else { return }
        actif = false
        generation &+= 1
    }

    // MARK: - Lecture

    /// Relit l'état (`fn_etat_pointage_mission`), puis réconcilie un reçu en attente. Réactive le bloc (apparition) ;
    /// ne relit rien pendant un envoi, qui relit lui-même l'état (m7).
    public func charger() async {
        activer()
        guard !envoiEnCours else { return }
        let jeton = generation
        guard let x = await contexte(), await estCourant(jeton) else { return }
        let port = x.port, mission = missionId, context = x.context
        do {
            let etat = try await bounded(timeout: x.delai) { try await port.etat(missionId: mission, context: context) }
            guard await estCourant(jeton) else { return }
            sessionExpired = false
            chargement = .pret(etat)
        } catch {
            guard await estCourant(jeton), !Self.estAnnulation(error) else { return }
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

    /// Suivi tant que le bloc est visible (à lancer dans le `.task` de l'écran, annulé à sa disparition). S'arrête à
    /// l'annulation, à `desactiver()`, et quand une réapparition en a relancé un autre (génération).
    public func suivre() async {
        guard !Task.isCancelled else { return }
        activer()
        let jeton = generation
        while visible(jeton), !Task.isCancelled {
            await attendre(Self.intervalleSuivi)
            guard visible(jeton), !Task.isCancelled else { return }
            await rafraichir()
        }
    }

    // MARK: - Pointage

    /// Envoie le code saisi ou lu (six chiffres après `trim`, sinon rien). `gps` : observation de `LocationPort`, nil
    /// si la position n'est pas demandée (consentement absent ou refusé, T4b). Rien n'est envoyé pendant une
    /// vérification ni quand le suivi n'est pas vérifiable.
    public func pointer(code saisie: String, gps: ObservationGps?) async {
        guard actif, !envoiEnCours, issue != .verification, issue != .suiviIllisible,
              let code = PointageRules.codeSaisi(saisie), etat != nil else { return }
        let jeton = generation
        envoiEnCours = true
        defer { envoiEnCours = false }
        issue = nil
        notationAProposer = false
        guard let x = await contexte(), await estCourant(jeton) else { return }
        await envoyer(code: code, gps: gps, x, jeton)
    }

    private func envoyer(code: String, gps: ObservationGps?, _ x: Contexte, _ jeton: Int) async {
        let userId = x.context.userId
        let existant: RecuScan?
        do { existant = try await journal.lire(userId: userId) } catch { publier(.suiviIllisible, jeton); return }
        if let existant, !existant.estTermine {
            publier(.recuEnCours, jeton)
            return
        }
        let terminal: String
        do { terminal = try appareil.terminal.identifiant() } catch { publier(.erreur(Self.message(error)), jeton); return }
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
                    publier(.suiviIllisible, jeton)
                    return
                }
            }
            publier(.horsLigne, jeton)
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
            guard await estCourant(jeton), !Self.estAnnulation(error) else { return }
            noterSession(error)
            issue = .erreur(Self.message(error))
            return
        }
        guard await estCourant(jeton) else { return }
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
            publier((error as? RecuErreur) == .recuEnCours ? .recuEnCours : .suiviIllisible, jeton)
            return
        }
        defer { Self.essaisEnVol.remove(demarre.attemptId) }

        let metadonnees = MetadonneesScan(idTerminal: terminal, observation: gps)
        let resultat: IssueScan
        do {
            resultat = try await bounded(timeout: x.delai) {
                try await port.scanner(code: code, metadonnees: metadonnees, recu: demarre, context: context)
            }
        } catch let erreur as JoleneError where erreur.kind == .unauthorized {
            // Session expirée (m1) : rien n'est affirmé ; reçu `started` gardé, réconcilié au retour de l'utilisateur.
            noterSortieSansReponse(demarre, delaiDepasse: false)
            guard await estCourant(jeton) else { return }
            sessionExpired = true
            issue = .verification
            return
        } catch {
            // Délai `bounded` ou transport : la requête a pu être appliquée (PRINCIPES §3-§4).
            noterSortieSansReponse(demarre, delaiDepasse: Self.estDelaiDepasse(error), delai: x.delai)
            resultat = .incertain
        }
        if resultat == .incertain || resultat == .nonEnvoye { noterSortieSansReponse(demarre, delaiDepasse: false) }
        guard await estCourant(jeton) else {
            // Écran disparu ou epoch périmé : rien n'est publié. Même utilisateur : l'essai décidé est soldé.
            if await controller.epoch == snapshot.epoch { await solder(resultat, recu: demarre) }
            return
        }
        await traiter(resultat, recu: demarre, x, jeton)
    }

    private func traiter(_ resultat: IssueScan, recu: RecuScan, _ x: Contexte, _ jeton: Int) async {
        switch resultat {
        case let .enregistre(typeScan, _):
            await conclureEnregistre(recu, typeScan: typeScan, x, jeton)
        case let .enregistreSurAutreMission(autre, typeScan, _):
            await conclureSurAutreMission(recu, autre: autre, typeScan: typeScan, x, jeton)
        case .accepteSansPreuve:
            await conclureSansPreuve(recu, x, jeton)
        case let .refuse(sqlstate, message):
            // Anti-rejeu juste après une réponse perdue : un scan de ce terminal vient d'être enregistré (§2.5).
            if PointageRules.estAntiRejeu(sqlstate: sqlstate, message: message) {
                let port = x.port, context = x.context
                if case let .enregistre(type, _)? = try? await bounded(timeout: x.delai, {
                    try await port.reconcilier(recu: recu, context: context)
                }) {
                    await conclureEnregistre(recu, typeScan: type, x, jeton)
                    return
                }
            }
            // Rollback prouvé : `refused` si SQLSTATE, puis relecture, puis effacement (consigne T3).
            await marquerRefuse(recu, sqlstate: sqlstate)
            await relireEtat(x, jeton)
            oublier(recu.attemptId)
            try? await journal.effacer(recu)
            publier(.refuse(message: message, codeInvalide: PointageRules.estCodeInvalide(sqlstate: sqlstate, message: message)),
                    jeton)
        case .incertain, .nonEnvoye:
            // `scanner` ne rend jamais `.nonEnvoye` : traité, par prudence, comme une réponse perdue.
            await reconcilierRecu(recu, x, jeton)
        case .nonRecu:
            oublier(recu.attemptId)
            try? await journal.effacer(recu)
            publier(.nonRecu, jeton)
        case .horlogeIncoherente:
            publier(.suiviIllisible, jeton)
        }
    }

    private func conclureEnregistre(_ recu: RecuScan, typeScan: TypeScan?, _ x: Contexte, _ jeton: Int) async {
        oublier(recu.attemptId)
        try? await journal.effacer(recu)
        await relireEtat(x, jeton)
        guard recu.missionId == missionId, visible(jeton) else { return }
        issue = .enregistre(typeScan)
        notationAProposer = PointageRules.notationAProposer(typeScan: typeScan, finLe: finLe, maintenant: x.horloge.now())
    }

    /// HTTP 200 relu sur une autre mission (M-A) : reçu soldé, état de CE bloc relu (inchangé). Aucune note : elle est
    /// celle de la mission pointée (T5a).
    private func conclureSurAutreMission(_ recu: RecuScan, autre: String, typeScan: TypeScan?, _ x: Contexte, _ jeton: Int) async {
        guard autre != recu.missionId else {
            await conclureEnregistre(recu, typeScan: typeScan, x, jeton)
            return
        }
        oublier(recu.attemptId)
        try? await journal.effacer(recu)
        await relireEtat(x, jeton)
        guard recu.missionId == missionId else { return }
        publier(.enregistreSurAutreMission(typeScan, missionId: autre), jeton)
    }

    /// HTTP 200 sans preuve relue (M-A) : COMMIT prouvé, mission non établie. Le reçu est soldé (aucun renvoi n'est
    /// possible, et sa réconciliation, filtrée sur sa mission, conclurait à tort « non reçu ») ; suivi non vérifiable,
    /// renvoi web `/soignant/presences` (T4b) ; ce bloc n'envoie plus rien.
    private func conclureSansPreuve(_ recu: RecuScan, _ x: Contexte, _ jeton: Int) async {
        oublier(recu.attemptId)
        try? await journal.effacer(recu)
        await relireEtat(x, jeton)
        guard recu.missionId == missionId else { return }
        publier(.suiviIllisible, jeton)
    }

    /// Rollback prouvé à SQLSTATE : phase `refused` journalisée avant l'effacement.
    private func marquerRefuse(_ recu: RecuScan, sqlstate: String?) async {
        if let sqlstate, RecuScan.sqlstateValide(sqlstate), let refuse = try? recu.refuser(sqlstate: sqlstate) {
            try? await journal.ecrire(refuse)
        }
    }

    /// Issue décidée par le serveur alors que l'écran a disparu (même epoch) : reçu soldé, rien n'est publié ; une
    /// issue incertaine garde le reçu `started` pour la réconciliation.
    private func solder(_ resultat: IssueScan, recu: RecuScan) async {
        switch resultat {
        case .enregistre, .enregistreSurAutreMission, .accepteSansPreuve, .nonRecu:
            oublier(recu.attemptId)
            try? await journal.effacer(recu)
        case let .refuse(sqlstate, _):
            await marquerRefuse(recu, sqlstate: sqlstate)
            oublier(recu.attemptId)
            try? await journal.effacer(recu)
        case .incertain, .nonEnvoye, .horlogeIncoherente:
            break
        }
    }

    // MARK: - Réconciliation

    /// Réconcilie le reçu en attente de l'utilisateur (lancement, retour au premier plan, ouverture, suivi).
    public func reconcilier() async {
        guard actif, !reconciliationEnCours, !envoiEnCours else { return }
        let jeton = generation
        reconciliationEnCours = true
        defer { reconciliationEnCours = false }
        guard let x = await contexte(), await estCourant(jeton) else { return }
        let recu: RecuScan?
        do {
            recu = try await journal.lire(userId: x.context.userId)
        } catch {
            if await estCourant(jeton) { issue = .suiviIllisible }
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
            await reconcilierRecu(recu, x, jeton)
        }
    }

    private func reconcilierRecu(_ recu: RecuScan, _ x: Contexte, _ jeton: Int) async {
        let memeMission = recu.missionId == missionId
        if memeMission { publier(.verification, jeton) }
        let port = x.port, context = x.context
        for tentative in 0..<Self.maxRelectures {
            if let debut = Self.demarragesMonotones[recu.attemptId] {
                let requis = Self.delaisAbsence[recu.attemptId] ?? RecuScan.delaiAbsenceProuvee
                let reste = requis - (monotone() - debut)
                if reste > 0 { await attendre(reste) }
            }
            if tentative > 0 { await attendre(Self.pauseRelecture) }
            guard await estCourant(jeton) else { return }
            let verdict: IssueScan
            do {
                verdict = try await bounded(timeout: x.delai) { try await port.reconcilier(recu: recu, context: context) }
            } catch is RecuErreur {
                if await estCourant(jeton) { issue = .suiviIllisible }
                return
            } catch let erreur as JoleneError where erreur.kind == .unauthorized {
                // m1 : session expirée signalée tout de suite ; le reçu reste `started`, réconcilié au retour.
                if await estCourant(jeton) { sessionExpired = true }
                return
            } catch {
                continue
            }
            guard await estCourant(jeton) else { return }
            switch verdict {
            case let .enregistre(type, _):
                await conclureEnregistre(recu, typeScan: type, x, jeton)
                return
            case let .enregistreSurAutreMission(autre, type, _):
                await conclureSurAutreMission(recu, autre: autre, typeScan: type, x, jeton)
                return
            case .accepteSansPreuve:
                await conclureSansPreuve(recu, x, jeton)
                return
            case .nonRecu:
                oublier(recu.attemptId)
                try? await journal.effacer(recu)
                await relireEtat(x, jeton)
                if memeMission { publier(.nonRecu, jeton) }
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

    private func relireEtat(_ x: Contexte, _ jeton: Int) async {
        let port = x.port, mission = missionId, context = x.context
        guard let etat = try? await bounded(timeout: x.delai, { try await port.etat(missionId: mission, context: context) }),
              await estCourant(jeton) else { return }
        chargement = .pret(etat)
    }

    /// Écran visible depuis le début de l'opération (même génération).
    private func visible(_ jeton: Int) -> Bool {
        actif && generation == jeton
    }

    /// Visible, non annulé, et epoch inchangé (relu après la suspension).
    private func estCourant(_ jeton: Int) async -> Bool {
        guard visible(jeton), !Task.isCancelled else { return false }
        let epoch = await controller.epoch
        return epoch == snapshot.epoch && visible(jeton)
    }

    private func publier(_ nouvelle: Issue, _ jeton: Int) {
        guard visible(jeton) else { return }
        issue = nouvelle
    }

    /// Essai sorti sans réponse (m2) : « non reçu » seulement après l'instant de sortie (au moins le délai `bounded`
    /// s'il est dépassé) + attente du pool PostgREST + `statement_timeout`, sur l'horloge monotone.
    private func noterSortieSansReponse(_ recu: RecuScan, delaiDepasse: Bool, delai: TimeInterval = 0) {
        guard let debut = Self.demarragesMonotones[recu.attemptId] else { return }
        let sortie = max(monotone() - debut, delaiDepasse ? delai : 0)
        let requis = sortie + Self.attentePoolPostgREST + RecuScan.delaiAbsenceProuvee
        Self.delaisAbsence[recu.attemptId] = max(Self.delaisAbsence[recu.attemptId] ?? 0, requis)
    }

    private func oublier(_ essai: String) {
        Self.essaisEnVol.remove(essai)
        Self.demarragesMonotones[essai] = nil
        Self.delaisAbsence[essai] = nil
    }

    private func noterSession(_ error: Error) {
        sessionExpired = (error as? JoleneError)?.kind == .unauthorized
    }

    private static func estAnnulation(_ error: Error) -> Bool {
        error is CancellationError || (error as? JoleneError)?.kind == .cancelled
    }

    /// Dépassement de `bounded` (`SessionController.timeoutMessage`), distinct d'une erreur de transport du port.
    private static func estDelaiDepasse(_ error: Error) -> Bool {
        (error as? JoleneError) == JoleneError(.network, SessionController.timeoutMessage)
    }

    private static func message(_ error: Error) -> String {
        (error as? JoleneError)?.message ?? messageEtatIndisponible
    }
}
