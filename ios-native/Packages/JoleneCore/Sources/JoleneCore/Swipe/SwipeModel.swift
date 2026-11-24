import Foundation
import Combine

/// Vue Swipe d'Explorer (lot 4, T3a ; `LOT4_PLAN.md` §2.5 « Swipe »), port de `VueSwipeMissions.tsx`. L'écran (T3b) ne
/// lit que ce modèle ; le modèle ne lit que les ports.
///
/// Règles :
/// - lectures et mutations bornées à `SessionController.resolutionTimeout` (décision 14 du lot 1) ; gateways obtenues
///   pour l'epoch de la session, réponse d'un epoch périmé ignorée ; deux lectures qui se chevauchent : seule la
///   dernière demandée publie ;
/// - une carte n'est retirée du paquet qu'après la réponse du serveur : ✕ / ⭐ `ok:true` (⭐ relu dans
///   `missions_sauvegardees` par la gateway), ❤️ `.confirmed` (candidature relue par `CandidaturePort`). Écart assumé
///   avec le web, qui retire la carte avant la réponse puis la remet ;
/// - refus, délai dépassé ou coupure : message affiché, carte remise en tête, **aucun renvoi automatique** (un délai ne
///   prouve rien) ; exception : un refus définitif pour cette mission (`SwipeRefus.horsPaquet`, dont `acces_refuse` et
///   `profession_incompatible`, que le serveur resservirait ; mission déjà attribuée) la retire après le message et
///   l'écarte des paquets relus de la session (revue B8 de #1165, m1) ;
/// - ❤️ : `CandidaturePort.confirmer(.swipeLike)` avec le planning exact (`CreneauxConfirmes.pourAction`) ; choix de
///   contrat demandé → options exposées, l'action est rejouée avec l'option ; planning modifié → mission relue
///   (`MissionsPort.mission`), carte mise à jour, jamais renvoyée ;
/// - « Annuler » (toast de 5 s de l'écran) → `SwipePort.retirer` ; la carte n'est **jamais** remise dans le paquet
///   (D4, correction 12 : la ligne `swipes` est immuable) ;
/// - fin de paquet → missions sauvegardées `OUVERTE` à venir re-proposées (`FavorisRegles.missionsAffichees`) ;
/// - une seule action à la fois : un second geste pendant l'appel est ignoré ;
/// - une annulation (vue qui disparaît) n'est jamais une erreur ; session expirée signalée (`sessionExpiree`).
@MainActor
public final class SwipeModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case pret
        /// Première lecture en échec (planning illisible compris) : message de l'erreur.
        case echec(String)
    }

    /// Annonce affichée par l'écran après une action confirmée.
    public enum Annonce: Equatable, Sendable {
        case candidatureEnvoyee(missionId: String)
        /// D4 : « Candidature retirée », carte non remise, accès au détail de la mission.
        case candidatureRetiree(missionId: String)
        case favoriSauvegarde(missionId: String)
    }

    /// Candidature que le toast de 5 s peut retirer (`candidature_id` relu par la gateway).
    public struct CandidatureAnnulable: Equatable, Sendable {
        public var candidatureId: String
        public var missionId: String
    }

    /// Reprise : le paquet est relu si la dernière lecture date de plus de 60 s (`staleTime: 60_000` du web).
    public static let delaiReprise: TimeInterval = 60
    /// Missions sauvegardées re-proposées en fin de paquet (web : `.limit(10)`).
    public static let favorisMax = 10
    public static let echecAction = "Votre réponse n'a pas pu être enregistrée. Vérifiez votre connexion puis réessayez."

    @Published public private(set) var etat: Etat = .chargement
    /// Cartes restantes, ordre serveur ; une carte refusée revient en tête.
    @Published public private(set) var cartes: [CarteSwipe] = []
    /// Vrai si la dernière lecture a rendu au moins une carte (« Tu as tout vu » plutôt que « Aucune nouvelle mission »).
    @Published public private(set) var paquetLuNonVide = false
    @Published public private(set) var favorisFinDePaquet: [MissionSauvegardee] = []
    /// Mission dont l'action est en vol ; `nil` sinon.
    @Published public private(set) var actionEnCours: String?
    /// Dernier refus ou dernière erreur d'action, verbatim ; `nil` après une action confirmée.
    @Published public private(set) var message: String?
    @Published public private(set) var annonce: Annonce?
    @Published public private(set) var candidatureAnnulable: CandidatureAnnulable?
    /// Avis du dernier ❤️ confirmé (T3b, revue B8 de #1165, m3) : avertissement de planning du serveur, verbatim, et
    /// documents à compléter ; `nil` sans avis. Reste affiché jusqu'à sa fermeture ou au ❤️ suivant, indépendamment
    /// du toast d'annulation (aucun avis ne disparaît sur minuterie).
    @Published public private(set) var avisCandidature: AvisSwipeLike?
    /// Options du serveur quand `choix_requis` : non vide → feuille de choix, ❤️ rejoué avec l'option.
    @Published public private(set) var optionsContrat: [ChoixContratOption] = []
    @Published public private(set) var missionChoixContrat: String?
    @Published public private(set) var sessionExpiree = false
    /// Chips rapides (filtre du paquet, golden T2) ; `nil` : paquet rendu tel quel.
    @Published public private(set) var filtre: FiltrePaquetSwipe?

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var luLe: Date?
    private var jetonLecture = 0
    /// Missions écartées de la session par un refus définitif : jamais remises, même si un paquet relu les resservait
    /// (`fn_obtenir_missions_swipe` ne filtre pas les exclusions, correctif backend B9 en suivi).
    private var ecarteesDeLaSession: Set<String> = []

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    /// Cartes affichées : le paquet passé au filtre des chips, ordre conservé.
    public var cartesAffichees: [CarteSwipe] {
        FiltrePaquetSwipe.filtrer(cartes, filtre: filtre, professionParcours: nil, mission: \.missionPaquet)
    }

    public var finDePaquet: Bool { etat == .pret && cartesAffichees.isEmpty }

    // MARK: - Lecture

    public func charger() async {
        jetonLecture += 1
        let jeton = jetonLecture
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.swipe
        let context = snapshot.context
        do {
            let lues = try await bounded(timeout: controller.resolutionTimeout) { try await port.paquet(context: context) }
            guard await courant(), jeton == jetonLecture else { return }
            cartes = lues.filter { !ecarteesDeLaSession.contains($0.id) }
            paquetLuNonVide = !lues.isEmpty
            etat = .pret
            luLe = gateways.clock.now()
            sessionExpiree = false
            await chargerFavorisSiFinDePaquet(gateways)
        } catch {
            guard await courant(), jeton == jetonLecture, let texte = texte(error) else { return }
            if etat == .pret { message = texte } else { etat = .echec(texte) }
        }
    }

    /// Apparition ou retour au premier plan : relit si jamais lu, ou lu depuis plus de `delaiReprise`.
    public func reprendre() async {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        if let luLe, gateways.clock.now().timeIntervalSince(luLe) <= Self.delaiReprise { return }
        await charger()
    }

    public func appliquerFiltre(_ nouveau: FiltrePaquetSwipe?) async {
        filtre = nouveau
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        await chargerFavorisSiFinDePaquet(gateways)
    }

    // MARK: - ✕ et ⭐

    public func passer(_ missionId: String) async { await enregistrer(missionId, .passer) }

    public func sauvegarder(_ missionId: String) async { await enregistrer(missionId, .favori) }

    /// ✕ ou ⭐ depuis un geste ou un bouton (T3b) : pose le verrou `actionEnCours` **dans l'appel**, avant toute
    /// suspension, puis lance l'enregistrement. Le paquet (`SwipeCardStack`) garde ainsi la carte décalée pendant
    /// l'appel serveur au lieu de la ramener au centre, et un second geste dans le même tour de boucle est ignoré.
    /// Rend `nil` si une action est déjà en vol ou si la carte n'est plus dans le paquet.
    @discardableResult
    public func lancer(_ direction: DirectionSwipe, _ missionId: String) -> Task<Void, Never>? {
        guard actionEnCours == nil, carte(missionId) != nil else { return nil }
        actionEnCours = missionId
        return Task { await self.enregistrer(missionId, direction, verrouPose: true) }
    }

    private func enregistrer(_ missionId: String, _ direction: DirectionSwipe, verrouPose: Bool = false) async {
        if verrouPose {
            // Verrou posé par `lancer` pour cette mission : toute autre situation le relâche sans rien envoyer.
            guard actionEnCours == missionId, carte(missionId) != nil else {
                if actionEnCours == missionId { actionEnCours = nil }
                return
            }
        } else {
            guard actionEnCours == nil, carte(missionId) != nil else { return }
            actionEnCours = missionId
        }
        defer { actionEnCours = nil }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.swipe
        let context = snapshot.context
        message = nil
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.enregistrer(missionId: missionId, direction: direction, context: context)
            }
            guard await courant() else { return }
            switch issue {
            case .enregistre:
                retirerCarte(missionId)
                if direction == .favori { annonce = .favoriSauvegarde(missionId: missionId) }
            case let .refuse(code, texte):
                message = texte
                retirerOuRemettre(missionId, horsPaquet: SwipeRefus.estHorsPaquet(code))
            }
        } catch {
            guard await courant() else { return }
            if let texte = texte(error) { message = texte }
            remettreEnTete(missionId)
        }
        await chargerFavorisSiFinDePaquet(gateways)
    }

    // MARK: - ❤️

    /// ❤️ après le récapitulatif exact (T3b) ; `choixContrat` : option choisie quand le serveur l'a demandée.
    public func candidater(_ missionId: String, choixContrat: String? = nil) async {
        guard actionEnCours == nil, let carte = carte(missionId) else { return }
        actionEnCours = missionId
        defer { actionEnCours = nil }
        message = nil
        optionsContrat = []
        missionChoixContrat = nil
        let planning = PlanningCandidatInput(mission: carte.mission)
        // Fail-closed : un planning non exact n'est jamais envoyé.
        guard let creneaux = CreneauxConfirmes.pourAction(planning) else {
            message = PlanningCandidatRules.construirePlanningCandidat(planning).messageBlocage
                ?? PlanningCandidatRules.messagePlanningIncomplet
            remettreEnTete(missionId)
            return
        }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.candidature
        let context = snapshot.context
        do {
            // T3b : le port des deux mondes rend aussi les avis du ❤️ (`CandidatureSwipePort`) ; un port qui ne le
            // propose pas (doubles de test) répond par `confirmer(.swipeLike)`, sans avis.
            let reponse = try await bounded(timeout: controller.resolutionTimeout) { () -> IssueSwipeLike in
                if let avecAvis = port as? any CandidatureSwipePort {
                    return try await avecAvis.confirmerSwipeLike(missionId: missionId, creneaux: creneaux,
                                                                 choixContrat: choixContrat, context: context)
                }
                return IssueSwipeLike(issue: try await port.confirmer(action: .swipeLike, missionId: missionId, creneaux: creneaux,
                                                                      message: nil, choixContrat: choixContrat,
                                                                      candidatureId: nil, context: context))
            }
            guard await courant() else { return }
            switch reponse.issue {
            case let .confirmed(candidatureId, _):
                retirerCarte(missionId)
                annonce = .candidatureEnvoyee(missionId: missionId)
                candidatureAnnulable = candidatureId.map { CandidatureAnnulable(candidatureId: $0, missionId: missionId) }
                avisCandidature = reponse.avis.flatMap { $0.estVide ? nil : $0 }
            case let .choixRequis(options):
                optionsContrat = options
                missionChoixContrat = missionId
                remettreEnTete(missionId)
            case let .refusee(code, texte, _):
                message = texte
                retirerOuRemettre(missionId, horsPaquet: SwipeRefus.estHorsPaquet(code))
            case let .planningAReconfirmer(_, texte):
                message = texte
                await relireMission(missionId, gateways)
            case let .missionDejaAttribuee(texte):
                message = texte
                ecarter(missionId)
            }
        } catch {
            guard await courant() else { return }
            if let texte = texte(error) { message = texte }
            remettreEnTete(missionId)
        }
        await chargerFavorisSiFinDePaquet(gateways)
    }

    /// Feuille de choix fermée sans choisir : la carte reste en tête.
    public func annulerChoixContrat() {
        optionsContrat = []
        missionChoixContrat = nil
    }

    /// « Annuler » du toast : retrait relu (candidature absente), carte jamais remise dans le paquet (D4).
    public func retirerCandidature() async {
        guard actionEnCours == nil, let annulable = candidatureAnnulable else { return }
        actionEnCours = annulable.missionId
        defer { actionEnCours = nil }
        candidatureAnnulable = nil
        message = nil
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.swipe
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.retirer(candidatureId: annulable.candidatureId, context: context)
            }
            guard await courant() else { return }
            switch issue {
            case .retiree:
                annonce = .candidatureRetiree(missionId: annulable.missionId)
                avisCandidature = nil // candidature supprimée : ses avis ne valent plus
            case let .refuse(texte): message = texte
            }
        } catch {
            guard await courant(), let texte = texte(error) else { return }
            message = texte
        }
    }

    /// Toast expiré ou fermé : la candidature n'est plus annulable depuis le paquet.
    public func fermerAnnonce() {
        annonce = nil
        candidatureAnnulable = nil
    }

    public func effacerMessage() { message = nil }

    /// Avis du dernier ❤️ refermé par l'utilisateur.
    public func fermerAvis() { avisCandidature = nil }

    /// Carte encore dans le paquet (récapitulatif, feuille de détail), `nil` si elle en est sortie.
    public func carteDuPaquet(_ missionId: String) -> CarteSwipe? { carte(missionId) }

    // MARK: - Quiz (D6)

    /// Quiz au premier contact : marqueur local absent (`dejaVu`, `UserDefaults` par userId, T3b), compte hors cohorte
    /// E2E (`playwright-`, comme le web) et aucun swipe relu en base. Une lecture en échec ne propose rien (aucun état
    /// non relu ; le web, lui, propose le quiz quand le compte est illisible).
    public func quizAProposer(dejaVu: Bool) async -> Bool {
        await quizPremierContact(dejaVu: dejaVu) == .proposer
    }

    /// Issue de la question « faut-il proposer le quiz ? » (T3b), pour que l'écran mémorise « vu » quand des swipes
    /// existent déjà, comme le web (`RechercheMissions.tsx` : `else localStorage.setItem(CLE_QUIZ_PREFS, '1')`).
    public enum QuizPremierContact: Equatable, Sendable {
        /// Premier contact : aucun swipe relu en base, marqueur local absent.
        case proposer
        /// Rien à proposer, à mémoriser : marqueur déjà posé, ou des swipes existent (préférences déjà apprises).
        case dejaFait
        /// Rien à proposer, rien à mémoriser : compte de recette E2E, lecture en échec, session périmée.
        case indetermine
    }

    public func quizPremierContact(dejaVu: Bool) async -> QuizPremierContact {
        guard !dejaVu else { return .dejaFait }
        guard !MissionBusiness.estComptePlaywright(email: snapshot.context.email),
              let gateways = await controller.gateways(for: snapshot.epoch) else { return .indetermine }
        let port = gateways.swipe
        let context = snapshot.context
        guard let nombre = try? await bounded(timeout: controller.resolutionTimeout, { try await port.nombreSwipes(context: context) }),
              await courant() else { return .indetermine }
        return nombre == 0 ? .proposer : .dejaFait
    }

    /// Validation du quiz : préférences amorcées côté serveur (sans effet dès le premier signal appris). Best-effort comme
    /// le web : rend `true` seulement si le serveur a répondu `success:true` ; hors bornes → rien n'est envoyé.
    public func appliquerQuiz(_ preferences: PreferencesMatching) async -> Bool {
        guard preferences.dansLesBornes, let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.swipe
        let context = snapshot.context
        do {
            try await bounded(timeout: controller.resolutionTimeout) { try await port.initialiserPreferences(preferences, context: context) }
            return await courant()
        } catch {
            return false
        }
    }

    // MARK: - Interne

    private func courant() async -> Bool { await controller.epoch == snapshot.epoch }

    private func carte(_ missionId: String) -> CarteSwipe? { cartes.first { $0.id == missionId } }

    private func retirerCarte(_ missionId: String) {
        cartes.removeAll { $0.id == missionId }
    }

    private func retirerOuRemettre(_ missionId: String, horsPaquet: Bool) {
        if horsPaquet { ecarter(missionId) } else { remettreEnTete(missionId) }
    }

    /// Refus définitif : retirée du paquet et des paquets relus de la session.
    private func ecarter(_ missionId: String) {
        ecarteesDeLaSession.insert(missionId)
        retirerCarte(missionId)
    }

    private func remettreEnTete(_ missionId: String) {
        guard let index = cartes.firstIndex(where: { $0.id == missionId }) else { return }
        cartes.insert(cartes.remove(at: index), at: 0)
    }

    /// Planning modifié : la mission est relue, son planning remplace celui de la carte (établissement, distance et score
    /// du paquet conservés) ; une mission illisible ou sortie de `OUVERTE` quitte le paquet.
    private func relireMission(_ missionId: String, _ gateways: Gateways) async {
        let port = gateways.missions
        let context = snapshot.context
        do {
            let relue = try await bounded(timeout: controller.resolutionTimeout) { try await port.mission(id: missionId, context: context) }
            guard await courant() else { return }
            guard let relue, relue.record.statut == LigneSwipe.statutServi, let index = cartes.firstIndex(where: { $0.id == missionId }) else {
                retirerCarte(missionId)
                return
            }
            var carte = cartes.remove(at: index)
            carte.mission.record = relue.record
            carte.mission.creneauxPlanifies = relue.creneauxPlanifies
            carte.mission.planningExact = relue.planningExact
            carte.mission.erreurPlanning = relue.erreurPlanning
            cartes.insert(carte, at: 0)
        } catch {
            guard await courant() else { return }
            remettreEnTete(missionId)
        }
    }

    /// Fin de paquet : missions sauvegardées `OUVERTE` à venir (horloge des gateways), dix au plus. Lecture en échec :
    /// rien n'est re-proposé (le web n'affiche pas la section).
    private func chargerFavorisSiFinDePaquet(_ gateways: Gateways) async {
        guard finDePaquet else { return }
        let port = gateways.favoris
        let context = snapshot.context
        guard let lignes = try? await bounded(timeout: controller.resolutionTimeout, { try await port.missionsSauvegardees(context: context) }),
              await courant() else { return }
        favorisFinDePaquet = Array(FavorisRegles.missionsAffichees(lignes, maintenant: gateways.clock.now()).prefix(Self.favorisMax))
    }

    /// Message d'une erreur (`nil` : annulation, rien à montrer) ; session expirée signalée.
    private func texte(_ error: Error) -> String? {
        if let jolene = error as? JoleneError {
            if jolene.kind == .cancelled { return nil }
            if jolene.kind == .unauthorized { sessionExpiree = true }
            return jolene.message
        }
        if error is CancellationError { return nil }
        return Self.echecAction
    }
}
