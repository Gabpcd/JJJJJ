import Foundation
import Combine

/// Modèle de l'écran du code de pointage rotatif côté établissement (lot 5, T7 ; `LOT5_PLAN.md` §2.6, D23), port du
/// cycle de lecture de `src/components/pointage/AffichageCodeRotatifEtab.tsx` (l.118-171) sur
/// `gateways.etablissement.pointage` pour l'epoch de la session, chaque appel borné à
/// `SessionController.resolutionTimeout`. La décision d'affichage est celle de `CodeRotatifRules` (T3).
///
/// - **Code lu au serveur, jamais calculé** : `code_pointage_actif` de `fn_etat_pointage_mission`, relu toutes les
///   `cadenceNominale` secondes (web `refetchInterval: 5000`, l.132) ; aucun secret, aucun code suivant côté client. Une
///   valeur qui n'est pas exactement six chiffres ASCII (`PayloadQR.codePointage`) n'est jamais présentée.
/// - **Seulement écran visible et scène active** : `suivre()` est lancé par la tâche de l'écran (annulée à la
///   disparition et hors de `scenePhase == .active`) ; `desactiver()` périme toute réponse encore en vol. Au retour, la
///   première lecture part sans attendre.
/// - **Planning et signature** (`planning`, `contratSigne`) relus toutes les `periodePlanning` secondes (web
///   `staleTime: 60_000`, l.170), et à chaque tic tant qu'ils n'ont pas pu être lus ; un échec masque le code d'arrivée
///   (fail-closed, règle du web l.231-255).
/// - **Erreurs** : la dernière lecture réussie reste affichée jusqu'à `seuilErreurs` échecs consécutifs (le web les
///   absorbe par trois relances) ; au-delà, code retiré, bloc « Code de pointage indisponible » avec le message de
///   l'erreur, cadence ralentie à `cadenceDegradee`. Une lecture réussie rétablit la cadence nominale.
/// - **Affichage réévalué** au moins toutes les `periodeReevaluation` secondes, même sans réponse nouvelle (web l.119-123) :
///   la fenêtre du créneau ouvre et ferme le code à l'heure, pas à la lecture suivante.
/// - **Sans la permission `pointage`** : aucune lecture ni relecture (web l.102-115), bloc `.reservePointage`.
@MainActor
public final class CodeRotatifModel: ObservableObject {
    /// D23 : cadence de lecture de l'état, parité web (l.132).
    public nonisolated static let cadenceNominale: TimeInterval = 5
    /// D23 : cadence après `seuilErreurs` échecs consécutifs.
    public nonisolated static let cadenceDegradee: TimeInterval = 30
    public nonisolated static let seuilErreurs = 3
    /// Relecture du planning et de la signature (web l.170).
    public nonisolated static let periodePlanning: TimeInterval = 60
    /// Réévaluation de l'affichage sans réponse nouvelle (web l.121).
    public nonisolated static let periodeReevaluation: TimeInterval = 15
    /// Plancher d'une cadence servie par le monde (démo accélérée).
    public nonisolated static let cadenceMinimale: TimeInterval = 1

    /// Dernière décision de `CodeRotatifRules` ; `chargement` la masque tant que la première lecture n'a pas abouti.
    @Published public private(set) var affichage: CodeRotatifRules.Affichage
    /// « Pointages enregistrés » de la dernière lecture retenue, rendus avec le code ou son masque (web l.354-367).
    @Published public private(set) var segments: [CodeRotatifRules.LigneSegment] = []
    @Published public private(set) var chargement: Bool
    @Published public private(set) var erreursConsecutives = 0

    public let missionId: String
    private let controller: SessionController
    private let snapshot: EtablissementSessionSnapshot
    private let attendre: @Sendable (TimeInterval) async -> Void
    private var etat: EtatPointageEtab?
    private var messageErreur: String?
    private var planning: CodeRotatifRules.Planning = .indisponible
    private var planningLu = false
    private var depuisPlanning: TimeInterval = 0
    private var actif = false
    /// Avance à chaque `suivre()` et `desactiver()` : une lecture commencée avant ne publie plus rien.
    private var generation = 0

    public init(missionId: String, controller: SessionController, snapshot: EtablissementSessionSnapshot,
                attendre: @escaping @Sendable (TimeInterval) async -> Void = { await CodeRotatifModel.attendreReellement($0) }) {
        self.missionId = missionId
        self.controller = controller
        self.snapshot = snapshot
        self.attendre = attendre
        let autorise = snapshot.context.permissions.pointage
        affichage = CodeRotatifRules.affichage(etat: nil, planning: .indisponible, autoriseAuPointage: autorise, maintenant: Date())
        chargement = autorise
    }

    public nonisolated static func attendreReellement(_ secondes: TimeInterval) async {
        try? await Task.sleep(nanoseconds: delaiEnNanosecondes(secondes))
    }

    /// Permission `pointage` servie par `fn_mes_permissions_etab` pour l'epoch de l'écran.
    public var autorise: Bool { snapshot.context.permissions.pointage }

    /// Un code est présenté (l'écran garde alors l'écran allumé et propose le plein écran).
    public var codePresente: CodeRotatifRules.CodeVisible? { chargement ? nil : affichage.codeVisible }

    // MARK: - Cycle de vie

    /// Suit l'état tant que la tâche de l'écran vit : lecture immédiate, puis une lecture par cadence. S'arrête à
    /// l'annulation, à `desactiver()`, à un changement d'epoch, et quand un nouvel appel en relance un autre.
    public func suivre() async {
        guard autorise else {
            chargement = false
            return
        }
        generation &+= 1
        actif = true
        let jeton = generation
        guard let x = await contexte(), estCourant(jeton) else { return }
        await lire(x, jeton, planningAussi: true)
        while estCourant(jeton) {
            var reste = intervalle(x)
            while reste > 0 {
                let pas = min(reste, Self.periodeReevaluation)
                await attendre(pas)
                guard estCourant(jeton) else { return }
                reste -= pas
                depuisPlanning += pas
                reevaluer(maintenant: x.horloge.now())
            }
            await lire(x, jeton, planningAussi: !planningLu || depuisPlanning >= Self.periodePlanning)
        }
    }

    /// Écran disparu ou scène inactive : la boucle s'arrête, toute réponse encore en vol est ignorée.
    public func desactiver() {
        actif = false
        generation &+= 1
    }

    /// « Réessayer » : relit l'état, le planning et la signature sans attendre le tic suivant.
    public func reessayer() async {
        guard autorise, actif else { return }
        let jeton = generation
        guard let x = await contexte(), estCourant(jeton) else { return }
        await lire(x, jeton, planningAussi: true)
    }

    // MARK: - Lecture

    struct Contexte: Sendable {
        let port: any EtabPointagePort
        let context: EtablissementReadContext
        let delai: TimeInterval
        let horloge: any ClockPort
        let cadence: TimeInterval
    }

    enum Issue<T: Sendable>: Sendable {
        case lue(T)
        case echec(String)
        case annulee
    }

    private func contexte() async -> Contexte? {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return nil }
        let port = gateways.etablissement.pointage
        return Contexte(port: port, context: snapshot.context, delai: controller.resolutionTimeout,
                        horloge: gateways.clock, cadence: port.cadenceLecture)
    }

    private func intervalle(_ x: Contexte) -> TimeInterval {
        let base = x.cadence.isFinite ? max(Self.cadenceMinimale, x.cadence) : Self.cadenceNominale
        return erreursConsecutives >= Self.seuilErreurs ? max(base, Self.cadenceDegradee) : base
    }

    private func estCourant(_ jeton: Int) -> Bool {
        actif && generation == jeton && !Task.isCancelled
    }

    private func lire(_ x: Contexte, _ jeton: Int, planningAussi: Bool) async {
        let port = x.port, context = x.context, id = missionId
        async let etatLu = Self.capturer(x.delai) { try await port.etat(missionId: id, context: context) }
        async let planningRelu = Self.lirePlanning(planningAussi ? x : nil, missionId: id)
        let (issueEtat, issuePlanning) = await (etatLu, planningRelu)
        guard estCourant(jeton) else { return }
        guard await controller.epoch == snapshot.epoch else {
            // Epoch périmé : la réponse appartient à une autre session, rien n'est publié et le suivi s'arrête.
            desactiver()
            return
        }
        guard estCourant(jeton) else { return }
        switch issuePlanning {
        case nil, .annulee?:
            break
        case let .lue(relu)?:
            planning = relu
            planningLu = true
            depuisPlanning = 0
        case .echec?:
            planning = .indisponible
            planningLu = false
            depuisPlanning = 0
        }
        switch issueEtat {
        case let .lue(lu):
            etat = Self.assainir(lu)
            erreursConsecutives = 0
            messageErreur = nil
        case let .echec(message):
            erreursConsecutives += 1
            messageErreur = message
        case .annulee:
            return
        }
        chargement = false
        reevaluer(maintenant: x.horloge.now())
    }

    private func reevaluer(maintenant: Date) {
        let retenu = erreursConsecutives >= Self.seuilErreurs ? nil : etat
        var nouvel = CodeRotatifRules.affichage(etat: retenu, planning: planning, autoriseAuPointage: autorise, maintenant: maintenant)
        if retenu == nil, case .indisponible = nouvel.bloc {
            nouvel = CodeRotatifRules.Affichage(bloc: .indisponible(message: messageErreur ?? CodeRotatifRules.messageEtatIndisponible),
                                                creneauActif: nil)
        }
        let lignes: [CodeRotatifRules.LigneSegment]
        switch nouvel.bloc {
        case .code, .momentanementIndisponible, .masque:
            lignes = CodeRotatifRules.lignesSegments(retenu?.segments ?? [], maintenant: maintenant)
        case .reservePointage, .indisponible, .aucun, .planningInutilisable:
            lignes = []
        }
        if nouvel != affichage { affichage = nouvel }
        if lignes != segments { segments = lignes }
    }

    /// Code présenté seulement s'il est exactement six chiffres ASCII (ce que le scanner natif du soignant accepte).
    nonisolated static func assainir(_ etat: EtatPointageEtab) -> EtatPointageEtab {
        var copie = etat
        if let code = etat.codePointageActif, PayloadQR.codePointage(depuis: code) != code { copie.codePointageActif = nil }
        return copie
    }

    nonisolated static func capturer<T: Sendable>(_ delai: TimeInterval,
                                                  _ operation: @escaping @Sendable () async throws -> T) async -> Issue<T> {
        do {
            return .lue(try await bounded(timeout: delai, operation))
        } catch let erreur as JoleneError {
            return erreur.kind == .cancelled ? .annulee : .echec(erreur.message)
        } catch is CancellationError {
            return .annulee
        } catch {
            return .echec(CodeRotatifRules.messageEtatIndisponible)
        }
    }

    /// Planning (mission + créneaux PREVISIONNEL hors pause) et signature lus ensemble ; `nil` sans demande.
    nonisolated static func lirePlanning(_ x: Contexte?, missionId: String) async -> Issue<CodeRotatifRules.Planning>? {
        guard let x else { return nil }
        let port = x.port, context = x.context
        async let lu = capturer(x.delai) { try await port.planning(missionId: missionId, context: context) }
        async let signe = capturer(x.delai) { try await port.contratSigne(missionId: missionId, context: context) }
        switch (await lu, await signe) {
        case let (.lue(planning), .lue(contratSigne)):
            return .lue(.depuis(mission: planning.mission, creneaux: planning.creneaux, contratSigne: contratSigne))
        case (.annulee, _), (_, .annulee):
            return .annulee
        case let (.echec(message), _), let (_, .echec(message)):
            return .echec(message)
        }
    }
}
