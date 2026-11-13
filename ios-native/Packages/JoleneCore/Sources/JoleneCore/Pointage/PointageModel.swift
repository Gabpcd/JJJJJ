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
/// - la requête et les relectures d'un HTTP 200 sont bornées séparément (`PointagePort.envoyerScan` puis
///   `relireScanAccepte`, seconde revue fraîche de T3, mi-1) : un HTTP 200 reçu dans le délai n'aboutit jamais à
///   « non reçu » (revue fraîche de T3, M-A), même si ses relectures dépassent le délai : scan relu sur une autre
///   mission → `.enregistreSurAutreMission`, non confirmé → `.suiviIllisible` ; dans les deux cas le reçu est soldé,
///   sans réconciliation (filtrée sur la mission du reçu, elle conclurait à tort « non reçu ») ;
/// - réponse perdue, délai `bounded` ou erreur de transport → `.verification` : reçu `started` gardé, réconciliation
///   par relecture, JAMAIS de renvoi (décision 2) ; l'envoi se termine et la vérification se poursuit hors de lui
///   (`charger()` relit l'état pendant l'attente, mi-2) ; hors ligne → aucun appel, reçu `not_sent` ;
/// - session expirée (`.unauthorized`) au scan ou pendant la réconciliation → `sessionExpired`, reçu `started` gardé
///   (réconcilié au retour de l'utilisateur, nouvel epoch), jamais un refus ni un renvoi (m1) ;
/// - réponse ignorée si l'écran a disparu (`desactiver()`, web l.53-55 `actif.current`) ou si l'epoch a changé.
///   L'écran qui réapparaît (onglet rouvert : même `@StateObject`) réactive le bloc par `activer()`, ou `charger()` et
///   `suivre()` qui l'appellent ; une réponse émise avant la disparition reste ignorée (génération, M-B). Une issue
///   décidée par le serveur (succès, refus, « non reçu ») solde quand même le reçu si l'epoch n'a pas changé ; le bloc
///   réactivé pendant l'envoi relit alors son état, et réconcilie un reçu resté `started`, dans sa génération (mi-4) ;
/// - état relu toutes les 15 s quand le bloc est visible (`suivre()`, web l.71 `refetchInterval: 15000`) ;
///   `charger()` ne relit rien pendant un envoi (m7).
///
/// Réconciliation (consignes T3 de `docs/mobile-swift/DECISIONS_LOT2.md`) : reçu `prepared` orphelin → `not_sent` puis
/// effacé (aucune requête n'est partie : `started` précède toujours l'envoi) ; reçu terminal → effacé ; reçu `started`
/// → `PointagePort.reconcilier`, par un seul modèle à la fois dans le processus. Première relecture immédiate (§2.5,
/// mi-2) ; une absence de preuve ne vaut « non reçu » qu'après, sur l'horloge MONOTONE du processus quand l'essai y a
/// démarré, 8 s après `started` (revue de T1, M1 : une horloge d'appareil avancée ne raccourcit pas l'attente) et, pour
/// un essai sorti sans réponse, l'instant de sortie (au moins le délai `bounded`) + 10 s d'attente du pool PostgREST
/// (`PGRST003`) + 8 s de `statement_timeout` (revue fraîche de T3, m2) ; avant, elle reste « à relire ».
///
/// Journal commun (un reçu par utilisateur, tous blocs confondus ; seconde revue fraîche de T3, MJ-1) : un reçu peut
/// être soldé par la réconciliation d'un autre bloc. Son issue est alors rendue au bloc qui affiche la vérification de
/// cet essai, à sa prochaine réconciliation ; à défaut (reçu effacé sans issue), la vérification est levée. Un
/// `.suiviIllisible` venu d'un HTTP 200 sans preuve est levé par la première lecture d'état réussie après une
/// réapparition du bloc (mi-3).
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
        /// Réponse perdue (ou session expirée) : vérification par relecture en cours. Levée quand l'essai est soldé,
        /// ici ou par un autre bloc (MJ-1).
        case verification
        /// Le serveur n'a rien reçu (relecture ≥ 8 s) : saisir le code courant (il a pu tourner).
        case nonRecu
        /// `RecuScan.messageRecuEnCours`.
        case recuEnCours
        /// `RecuScan.messageIllisible` et renvoi web `/soignant/presences` (journal illisible, horloge incohérente,
        /// HTTP 200 sans preuve relue). Horloge incohérente : levée quand l'essai est soldé (MJ-1) ; HTTP 200 sans
        /// preuve : levée après une réapparition du bloc (mi-3) ; journal illisible : jamais levée.
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
    /// Génération de la réconciliation en cours : une seule par génération ; une réapparition peut en lancer une
    /// nouvelle pendant que l'ancienne finit son attente (elle ne publiera rien).
    private var reconciliationGeneration: Int?
    /// Essai dont ce bloc affiche la vérification (`.verification`) ou le suivi non vérifiable venu de sa réconciliation
    /// (`.suiviIllisible`, horloge incohérente) : levés quand cet essai est soldé, ici ou par un autre bloc (MJ-1).
    private var essaiAffiche: String?
    /// Génération où `.suiviIllisible` d'un HTTP 200 sans preuve a été publié (mi-3).
    private var generationSansPreuve: Int?

    /// Issue décidée pour un essai soldé (reçu effacé).
    private enum Conclusion: Equatable {
        case enregistre(TypeScan?)
        case surAutreMission(TypeScan?, missionId: String)
        case sansPreuve
        case nonRecu
    }

    /// Essais en vol (envoi, ou réconciliation par un modèle) dans ce processus, tous blocs confondus : un autre modèle
    /// ne les réconcilie pas en parallèle.
    private static var essaisEnVol: Set<String> = []
    /// Passage `started` sur l'horloge monotone du processus, par essai.
    private static var demarragesMonotones: [String: TimeInterval] = [:]
    /// Attente monotone minimale avant « non reçu », par essai sorti sans réponse (m2) ; sinon `delaiAbsenceProuvee`.
    private static var delaisAbsence: [String: TimeInterval] = [:]
    /// Issues d'essais soldés par la réconciliation d'un bloc d'une autre mission, en attente du bloc qui affiche leur
    /// vérification (MJ-1) ; bornées (un bloc disparu pour de bon ne les reprend jamais).
    private static var conclusionsTransmises: [(essai: String, conclusion: Conclusion)] = []
    private static let maxConclusionsTransmises = 16

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
            leverSansPreuveApresReapparition(jeton)
        } catch {
            guard await estCourant(jeton), !Self.estAnnulation(error) else { return }
            noterSession(error)
            chargement = .indisponible(Self.message(error))
        }
        await reconcilier()
    }

    /// « Vérifier ma session » du bloc de session expirée (revue fraîche de T4b, M1 ; règle de
    /// `PresencesModel.verifierSession`) : revalide la session (lot 1 ; une session révoquée ramène à la connexion, nouvel
    /// epoch, et la zone est reconstruite), puis, si elle reste celle de ce bloc, relit le consentement de la page s'il avait
    /// expiré (et lève son retour d'échec, `ConsentementGpsModel.reprendreApresSession`), l'état, et réconcilie le reçu
    /// gardé (`charger`) — jamais un renvoi du code.
    public func verifierSession(_ session: SessionStore, consentement: ConsentementGpsModel? = nil) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        if let consentement { await consentement.reprendreApresSession() }
        await charger()
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
        issue = nil
        essaiAffiche = nil
        generationSansPreuve = nil
        notationAProposer = false
        var perdu: (recu: RecuScan, x: Contexte)?
        if let x = await contexte(), await estCourant(jeton) {
            perdu = await envoyer(code: code, gps: gps, x, jeton)
        }
        envoiEnCours = false
        if let perdu {
            if generation == jeton {
                // Réponse perdue (mi-2) : l'envoi est terminé, la vérification se poursuit ; `charger()` relit l'état
                // pendant l'attente et aucune seconde réconciliation ne part en parallèle.
                await reconcilierApresEnvoi(perdu.recu, perdu.x, jeton)
            } else {
                Self.essaisEnVol.remove(perdu.recu.attemptId)
            }
        }
        if generation != jeton, actif {
            // mi-4 : bloc réactivé pendant l'envoi ou sa vérification (son `charger()` a sauté la lecture) : état relu,
            // et reçu resté `started` réconcilié, dans la génération courante.
            await charger()
        }
    }

    /// Envoi d'un code ; rend le reçu `started` dont la réponse est perdue (à réconcilier hors de l'envoi), sinon nil.
    private func envoyer(code: String, gps: ObservationGps?, _ x: Contexte, _ jeton: Int) async -> (recu: RecuScan, x: Contexte)? {
        let userId = x.context.userId
        let existant: RecuScan?
        do { existant = try await journal.lire(userId: userId) } catch { publier(.suiviIllisible, jeton); return nil }
        if let existant, !existant.estTermine {
            publier(.recuEnCours, jeton)
            return nil
        }
        let terminal: String
        do { terminal = try appareil.terminal.identifiant() } catch { publier(.erreur(Self.message(error)), jeton); return nil }
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
                    return nil
                }
            }
            publier(.horsLigne, jeton)
            return nil
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
            guard await estCourant(jeton), !Self.estAnnulation(error) else { return nil }
            noterSession(error)
            publier(.erreur(Self.message(error)), jeton)
            return nil
        }
        guard await estCourant(jeton) else { return nil }
        chargement = .pret(base.etat)
        guard PointageRules.pointageDisponible(statut: base.etat.statut) else { return nil }

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
            return nil
        }
        // L'essai reste « en vol » jusqu'à la fin de sa vérification quand la réponse est perdue (`pointer`).
        var resteEnVol = false
        defer { if !resteEnVol { Self.essaisEnVol.remove(demarre.attemptId) } }

        let metadonnees = MetadonneesScan(idTerminal: terminal, observation: gps)
        let resultat: IssueScan
        do {
            resultat = try await envoyerRequete(code: code, metadonnees: metadonnees, recu: demarre, x, jeton)
        } catch let erreur as JoleneError where erreur.kind == .unauthorized {
            // Session expirée (m1) : rien n'est affirmé ; reçu `started` gardé, réconcilié au retour de l'utilisateur.
            noterSortieSansReponse(demarre, delaiDepasse: false)
            guard await estCourant(jeton) else { return nil }
            sessionExpired = true
            afficherSuivi(.verification, essai: demarre.attemptId, jeton)
            return nil
        } catch {
            // Délai `bounded` de la requête ou transport : elle a pu être appliquée (PRINCIPES §3-§4).
            noterSortieSansReponse(demarre, delaiDepasse: Self.estDelaiDepasse(error), delai: x.delai)
            resultat = .incertain
        }
        if resultat == .incertain || resultat == .nonEnvoye { noterSortieSansReponse(demarre, delaiDepasse: false) }
        guard await estCourant(jeton) else {
            // Écran disparu ou epoch périmé : rien n'est publié. Même utilisateur : l'essai décidé est soldé.
            if await controller.epoch == snapshot.epoch { await solder(resultat, recu: demarre) }
            return nil
        }
        guard await traiter(resultat, recu: demarre, x, jeton) else { return nil }
        resteEnVol = true
        return (demarre, x)
    }

    /// L'unique requête, bornée seule, puis, pour un HTTP 200, ses relectures bornées à part (seconde revue fraîche de
    /// T3, mi-1) : un HTTP 200 n'aboutit qu'à `.enregistre`, `.enregistreSurAutreMission` ou `.accepteSansPreuve`, même
    /// quand ses relectures échouent ou dépassent le délai. Lève l'erreur de la requête (délai, transport, session).
    private func envoyerRequete(code: String, metadonnees: MetadonneesScan, recu: RecuScan, _ x: Contexte,
                                _ jeton: Int) async throws -> IssueScan {
        let port = x.port, context = x.context
        let envoi = try await bounded(timeout: x.delai) {
            try await port.envoyerScan(code: code, metadonnees: metadonnees, recu: recu, context: context)
        }
        switch envoi {
        case let .issue(issue):
            return issue
        case let .accepte(scan):
            let relu: IssueScan
            do {
                relu = try await bounded(timeout: x.delai) { try await port.relireScanAccepte(scan, recu: recu, context: context) }
            } catch {
                // COMMIT prouvé, mission non établie : jamais « incertain » ; une session expirée est signalée (m1).
                if (error as? JoleneError)?.kind == .unauthorized, await estCourant(jeton) { sessionExpired = true }
                return .accepteSansPreuve
            }
            switch relu {
            case .enregistre, .enregistreSurAutreMission, .accepteSansPreuve:
                return relu
            case .refuse, .incertain, .nonEnvoye, .nonRecu, .horlogeIncoherente:
                return .accepteSansPreuve
            }
        }
    }

    /// Traite l'issue d'un envoi ; vrai si la réponse est perdue (réconciliation à mener hors de l'envoi).
    private func traiter(_ resultat: IssueScan, recu: RecuScan, _ x: Contexte, _ jeton: Int) async -> Bool {
        switch resultat {
        case let .enregistre(typeScan, _):
            await conclure(.enregistre(typeScan), recu, x, jeton)
        case let .enregistreSurAutreMission(autre, typeScan, _):
            await conclure(Self.conclusion(autre: autre, typeScan: typeScan, recu: recu), recu, x, jeton)
        case .accepteSansPreuve:
            await conclure(.sansPreuve, recu, x, jeton)
        case let .refuse(sqlstate, message):
            // Anti-rejeu juste après une réponse perdue : un scan de ce terminal vient d'être enregistré (§2.5).
            if PointageRules.estAntiRejeu(sqlstate: sqlstate, message: message) {
                let port = x.port, context = x.context
                if case let .enregistre(type, _)? = try? await bounded(timeout: x.delai, {
                    try await port.reconcilier(recu: recu, context: context)
                }) {
                    await conclure(.enregistre(type), recu, x, jeton)
                    return false
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
            return true
        case .nonRecu:
            await conclure(.nonRecu, recu, x, jeton)
        case .horlogeIncoherente:
            afficherSuivi(.suiviIllisible, essai: recu.attemptId, jeton)
        }
        return false
    }

    /// Essai soldé (succès relu, HTTP 200, « non reçu ») : reçu effacé, état de ce bloc relu, issue publiée par le bloc de
    /// la mission du reçu ; conclue par le bloc d'une autre mission (journal commun), elle est transmise au bloc qui
    /// affiche la vérification de cet essai (MJ-1).
    private func conclure(_ conclusion: Conclusion, _ recu: RecuScan, _ x: Contexte, _ jeton: Int) async {
        oublier(recu.attemptId)
        try? await journal.effacer(recu)
        await relireEtat(x, jeton)
        guard recu.missionId == missionId else {
            Self.transmettre(conclusion, essai: recu.attemptId)
            leverSuivi(essai: recu.attemptId, jeton)
            return
        }
        appliquer(conclusion, x, jeton)
    }

    /// Publie une issue conclue pour la mission de ce bloc. Aucune note pour un scan relu sur une autre mission : elle
    /// est celle de la mission pointée (T5a).
    private func appliquer(_ conclusion: Conclusion, _ x: Contexte, _ jeton: Int) {
        guard visible(jeton) else { return }
        switch conclusion {
        case let .enregistre(type):
            publier(.enregistre(type), jeton)
            notationAProposer = PointageRules.notationAProposer(typeScan: type, finLe: finLe, maintenant: x.horloge.now())
        case let .surAutreMission(type, autre):
            publier(.enregistreSurAutreMission(type, missionId: autre), jeton)
        case .sansPreuve:
            // HTTP 200 sans preuve relue (M-A) : COMMIT prouvé, mission non établie ; suivi non vérifiable, renvoi web
            // `/soignant/presences` (T4b) ; levé après une réapparition du bloc (mi-3).
            publier(.suiviIllisible, jeton)
            generationSansPreuve = jeton
        case .nonRecu:
            publier(.nonRecu, jeton)
        }
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
        guard actif, reconciliationGeneration != generation, !envoiEnCours else { return }
        let jeton = generation
        reconciliationGeneration = jeton
        defer { if reconciliationGeneration == jeton { reconciliationGeneration = nil } }
        guard let x = await contexte(), await estCourant(jeton) else { return }
        let recu: RecuScan?
        do {
            recu = try await journal.lire(userId: x.context.userId)
        } catch {
            // Journal illisible : jamais réécrit ni effacé, et ce suivi n'est jamais levé par l'app.
            if await estCourant(jeton) { publier(.suiviIllisible, jeton) }
            return
        }
        guard await estCourant(jeton) else { return }
        reprendreSuiviSolde(recu, x, jeton)
        guard let recu, !Self.essaisEnVol.contains(recu.attemptId) else { return }
        switch recu.phase {
        case .prepared:
            // Orphelin : `started` est toujours écrit avant l'unique requête, rien n'est parti.
            if let nonEnvoye = try? recu.marquerNonEnvoye() { try? await journal.ecrire(nonEnvoye) }
            try? await journal.effacer(recu)
        case .refused, .notSent:
            try? await journal.effacer(recu)
        case .started:
            Self.essaisEnVol.insert(recu.attemptId)
            defer { Self.essaisEnVol.remove(recu.attemptId) }
            await reconcilierRecu(recu, x, jeton)
        }
    }

    /// Réconciliation d'un essai de ce bloc juste après son envoi : l'essai reste « en vol » (aucun autre bloc ne le
    /// réconcilie en parallèle) jusqu'à la fin des relectures.
    private func reconcilierApresEnvoi(_ recu: RecuScan, _ x: Contexte, _ jeton: Int) async {
        defer { Self.essaisEnVol.remove(recu.attemptId) }
        if recu.missionId == missionId { afficherSuivi(.verification, essai: recu.attemptId, jeton) }
        // Une réconciliation de cette génération tourne déjà (autre reçu, soldé depuis) : elle, ou le suivi, reprendra
        // celui-ci ; la vérification reste affichée et bloque tout envoi.
        guard reconciliationGeneration != jeton else { return }
        reconciliationGeneration = jeton
        defer { if reconciliationGeneration == jeton { reconciliationGeneration = nil } }
        await reconcilierRecu(recu, x, jeton)
    }

    /// Relectures d'un reçu `started` : la première tout de suite (§2.5, mi-2) ; sans preuve, « non reçu » seulement
    /// après l'attente monotone de l'essai, sinon « à relire » après le reste de cette attente (ou la pause).
    private func reconcilierRecu(_ recu: RecuScan, _ x: Contexte, _ jeton: Int) async {
        if recu.missionId == missionId { afficherSuivi(.verification, essai: recu.attemptId, jeton) }
        let port = x.port, context = x.context
        var relectures = 0
        while true {
            guard await estCourant(jeton) else { return }
            let verdict: IssueScan
            do {
                verdict = try await bounded(timeout: x.delai) { try await port.reconcilier(recu: recu, context: context) }
            } catch is RecuErreur {
                if await estCourant(jeton) { publier(.suiviIllisible, jeton) }
                return
            } catch let erreur as JoleneError where erreur.kind == .unauthorized {
                // m1 : session expirée signalée tout de suite ; le reçu reste `started`, réconcilié au retour.
                if await estCourant(jeton) { sessionExpired = true }
                return
            } catch {
                verdict = .incertain
            }
            guard await estCourant(jeton) else { return }
            switch verdict {
            case let .enregistre(type, _):
                await conclure(.enregistre(type), recu, x, jeton)
                return
            case let .enregistreSurAutreMission(autre, type, _):
                await conclure(Self.conclusion(autre: autre, typeScan: type, recu: recu), recu, x, jeton)
                return
            case .accepteSansPreuve:
                await conclure(.sansPreuve, recu, x, jeton)
                return
            case .horlogeIncoherente:
                afficherSuivi(.suiviIllisible, essai: recu.attemptId, jeton)
                return
            case .nonRecu where resteAvantAbsence(recu) <= 0:
                await conclure(.nonRecu, recu, x, jeton)
                return
            case .nonRecu, .incertain, .refuse, .nonEnvoye:
                relectures += 1
                guard relectures < Self.maxRelectures else { return }
                let reste = resteAvantAbsence(recu)
                await attendre(reste > 0 ? reste : Self.pauseRelecture)
            }
        }
    }

    /// MJ-1 : l'essai dont ce bloc affiche la vérification n'est plus en attente dans le journal commun (soldé par un
    /// autre bloc, ou effacé) : son issue transmise est publiée ; à défaut, la vérification est levée (l'état vient
    /// d'être relu, et tout nouvel envoi relit sa base), jamais un succès supposé.
    private func reprendreSuiviSolde(_ enAttente: RecuScan?, _ x: Contexte, _ jeton: Int) {
        guard let essai = essaiAffiche, visible(jeton) else { return }
        if let enAttente, enAttente.attemptId == essai, !enAttente.estTermine { return }
        if let conclusion = Self.retirerConclusion(essai) {
            appliquer(conclusion, x, jeton)
        } else {
            leverSuivi(essai: essai, jeton)
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

    /// Issue sans essai attaché : jamais levée par la reprise d'un essai soldé.
    private func publier(_ nouvelle: Issue, _ jeton: Int) {
        guard visible(jeton) else { return }
        issue = nouvelle
        essaiAffiche = nil
        generationSansPreuve = nil
    }

    /// `.verification` ou `.suiviIllisible` attachés à l'essai `essai` : levés quand il est soldé (MJ-1).
    private func afficherSuivi(_ nouvelle: Issue, essai: String, _ jeton: Int) {
        guard visible(jeton) else { return }
        issue = nouvelle
        essaiAffiche = essai
        generationSansPreuve = nil
    }

    /// Essai soldé sans issue à publier ici : la vérification (ou le suivi non vérifiable) qui lui était attachée est
    /// levée ; rien ne change si ce bloc n'est pas visible (reprise à la prochaine réconciliation).
    private func leverSuivi(essai: String, _ jeton: Int) {
        guard essaiAffiche == essai, visible(jeton) else { return }
        essaiAffiche = nil
        if issue == .verification || issue == .suiviIllisible { issue = nil }
    }

    /// mi-3 : `.suiviIllisible` d'un HTTP 200 sans preuve, publié dans une génération antérieure (le bloc a disparu puis
    /// réapparu), est levé par une lecture d'état réussie : le reçu est soldé et tout nouvel envoi relit sa base.
    private func leverSansPreuveApresReapparition(_ jeton: Int) {
        guard let publiee = generationSansPreuve, publiee != jeton, issue == .suiviIllisible else { return }
        generationSansPreuve = nil
        issue = nil
    }

    /// Temps monotone restant avant qu'une absence de preuve vaille « non reçu » (M1, m2) ; 0 pour un essai d'un autre
    /// processus (seul l'écart d'horloge murale de la gateway s'applique alors).
    private func resteAvantAbsence(_ recu: RecuScan) -> TimeInterval {
        guard let debut = Self.demarragesMonotones[recu.attemptId] else { return 0 }
        let requis = Self.delaisAbsence[recu.attemptId] ?? RecuScan.delaiAbsenceProuvee
        return requis - (monotone() - debut)
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

    private static func conclusion(autre: String, typeScan: TypeScan?, recu: RecuScan) -> Conclusion {
        autre == recu.missionId ? .enregistre(typeScan) : .surAutreMission(typeScan, missionId: autre)
    }

    private static func transmettre(_ conclusion: Conclusion, essai: String) {
        conclusionsTransmises.removeAll { $0.essai == essai }
        conclusionsTransmises.append((essai: essai, conclusion: conclusion))
        if conclusionsTransmises.count > maxConclusionsTransmises {
            conclusionsTransmises.removeFirst(conclusionsTransmises.count - maxConclusionsTransmises)
        }
    }

    private static func retirerConclusion(_ essai: String) -> Conclusion? {
        guard let index = conclusionsTransmises.firstIndex(where: { $0.essai == essai }) else { return nil }
        return conclusionsTransmises.remove(at: index).conclusion
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
