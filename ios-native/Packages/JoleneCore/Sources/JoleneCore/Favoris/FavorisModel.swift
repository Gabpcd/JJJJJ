import Foundation
import Combine

/// État d'une liste de favoris : en attente de la première réponse, relue, ou en échec (message affiché).
public enum FavorisListe<Element: Equatable & Sendable>: Equatable, Sendable {
    case chargement
    case prete([Element])
    case echec(String)

    /// Éléments relus, vide tant que la liste n'est pas prête.
    public var elements: [Element] {
        if case let .prete(elements) = self { return elements }
        return []
    }

    public var estPrete: Bool {
        if case .prete = self { return true }
        return false
    }
}

/// Surface où une action ou une lecture des favoris a eu lieu (revue B8 de T4b, m4) : son erreur n'est affichée que
/// là, jamais sur une autre surface du même modèle (liste d'Explorer, détail d'une mission, écran « Mes favoris »).
public enum ContexteFavoris: Equatable, Sendable {
    /// Étoiles des cartes d'Explorer.
    case explorer
    /// Étoile du détail de cette mission (ouvert depuis Explorer).
    case detail(missionId: String)
    /// Écran « Mes favoris » (listes, « Retirer », feuille du retrait d'un établissement).
    case ecran
}

/// État affiché par une étoile (revue B8 de T4b, m3) : inconnu tant que la liste n'est pas relue (première lecture en
/// cours, ou en échec), jamais « Non sauvegardée » par défaut (PRINCIPES §2-§3 : aucun état plausible non relu).
public enum EtatEtoile: Equatable, Sendable {
    case inconnue
    case sauvegardee
    case nonSauvegardee
}

/// Modèle des favoris (lot 1, T4b), port de `MesFavorisSoignant.tsx` et de `BoutonSauvegarderMission.tsx`.
/// Une seule instance par epoch, partagée par l'étoile des cartes Explorer, l'étoile du détail et l'écran
/// « Mes favoris » : l'étoile suit toujours la dernière relecture (État dérivé, une seule source).
///
/// Règles :
/// - lectures et mutations bornées à `SessionController.resolutionTimeout` (décision 14) ; gateways
///   obtenues pour l'epoch de la session, réponse d'un epoch périmé ignorée ;
/// - les deux listes sont lues en parallèle (web : `Promise.all`) et échouent séparément ; Explorer ne lit
///   que les missions sauvegardées (`chargerMissionsSiNecessaire`) ;
/// - une mutation n'est annoncée qu'après une relecture qui la confirme (PRINCIPES §3) : le port rend la
///   liste relue, l'étoile et les listes en dérivent ; une relecture qui ne confirme pas est une erreur ;
/// - délai dépassé, coupure ou refus serveur sur une mutation : message affiché puis relecture, jamais de
///   renvoi automatique ; session expirée : signalée, sans relecture (revalider la session) ;
/// - un second appui sur la même étoile (ou le même retrait) pendant l'appel est ignoré ;
/// - deux lectures qui se chevauchent : seule la dernière demandée publie ;
/// - une annulation (vue qui disparaît) n'est jamais une erreur ;
/// - établissements : retrait seulement (`actif = false`, décision 8) ;
/// - deux magasins de missions, comme le web (décision 8 du lot 1 amendée le 18/11/2026) : la gateway fusionne `missions_sauvegardees` et
///   les favoris de l'inscription progressive, et le retrait vide les deux ;
/// - une mutation confirmée par sa relecture n'est jamais masquée par un état lu avant elle (revue B8, m1) : si une
///   opération plus récente a publié un état qui la contredit, la liste est relue ;
/// - toute lecture réussie lève « session à vérifier » ; « Vérifier ma session » revalide puis relit (`verifierSession`).
@MainActor
public final class FavorisModel: ObservableObject {
    public static let echecLectureMissions = "Vos missions sauvegardées n'ont pas pu être chargées. Vérifiez votre connexion puis réessayez."
    public static let echecLectureEtablissements = "Vos établissements favoris n'ont pas pu être chargés. Vérifiez votre connexion puis réessayez."
    public static let echecMutation = "L'action n'a pas pu être confirmée. Vérifiez votre connexion puis réessayez."
    public static let sauvegardeNonConfirmee = "La sauvegarde de la mission n'a pas pu être confirmée. Réessayez."
    public static let retraitNonConfirme = "Le retrait n'a pas pu être confirmé. Réessayez."

    /// Toutes les lignes `missions_sauvegardees` relues (état des étoiles).
    @Published public private(set) var missions: FavorisListe<MissionSauvegardee> = .chargement
    /// Missions listées dans « Mes favoris » (`FavorisRegles.missionsAffichees`, horloge des gateways).
    @Published public private(set) var missionsAffichees: [MissionSauvegardee] = []
    @Published public private(set) var etablissements: FavorisListe<EtablissementFavori> = .chargement
    /// Dernière erreur d'action ou de relecture d'une liste déjà affichée ; `nil` après un succès confirmé.
    @Published public private(set) var erreurAction: String?
    /// Surface de `erreurAction` (m4) : chaque surface n'affiche que la sienne (`erreur(pour:)`).
    @Published public private(set) var contexteErreur: ContexteFavoris?
    /// Nombre d'erreurs signalées : jeton d'annonce VoiceOver (`InlineNotice.announcementID`).
    @Published public private(set) var tentatives = 0
    @Published public private(set) var sessionExpired = false
    @Published public private(set) var missionsEnCours: Set<String> = []
    @Published public private(set) var etablissementsEnCours: Set<String> = []

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    /// Numéro de la dernière opération demandée sur chaque liste : seule celle-ci publie sa relecture.
    private var revisionMissions = 0
    private var revisionEtablissements = 0

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    // MARK: - État dérivé

    public func estSauvegardee(_ missionId: String) -> Bool {
        FavorisRegles.estSauvegardee(missionId, dans: missions.elements)
    }

    /// État de l'étoile : inconnu tant que la liste n'est pas relue (m3).
    public func etoile(_ missionId: String) -> EtatEtoile {
        guard missions.estPrete else { return .inconnue }
        return estSauvegardee(missionId) ? .sauvegardee : .nonSauvegardee
    }

    /// Message d'échec de la lecture des étoiles (première lecture en échec), `nil` sinon : affiché par la liste et
    /// par le détail, avec « Réessayer » (`chargerMissions(depuis:)`).
    public var echecLectureEtoiles: String? {
        if case let .echec(message) = missions { return message }
        return nil
    }

    /// Erreur à afficher sur une surface : celle de son contexte seulement (m4).
    public func erreur(pour contexte: ContexteFavoris) -> String? {
        contexteErreur == contexte ? erreurAction : nil
    }

    /// Vrai pendant l'appel : l'étoile est désactivée.
    public func enCours(missionId: String) -> Bool { missionsEnCours.contains(missionId) }

    public func retraitEnCours(etablissementId: String) -> Bool { etablissementsEnCours.contains(etablissementId) }

    public func etablissement(id: String) -> EtablissementFavori? { etablissements.elements.first { $0.id == id } }

    public func effacerErreur() {
        erreurAction = nil
        contexteErreur = nil
    }

    /// « Vérifier ma session » (session à vérifier) : revalide la session, puis relit les deux listes si elle est toujours
    /// prête pour l'epoch de cet écran (revue B8 de T4b, M1 ; même règle que `AccueilModel.verifierSession`). Sans cette
    /// relecture, une session encore valide (même epoch : `SessionStore.start` ne démonte pas un espace prêt) laisserait
    /// l'écran sur « session à vérifier », « Réessayer » masqué. Une session fermée ou une autre identité est reprise
    /// par la racine (`RootView`, `.id(epoch)`), sans lecture pour l'identité périmée.
    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await charger()
    }

    // MARK: - Lectures

    /// Écran « Mes favoris » : relit les deux listes en parallèle (à chaque apparition, tirer pour actualiser).
    public func charger() async {
        effacerErreur()
        async let lectureMissions: Void = lireMissions(explicite: true, contexte: .ecran)
        async let lectureEtablissements: Void = lireEtablissements(explicite: true)
        _ = await (lectureMissions, lectureEtablissements)
    }

    /// Relecture des missions sauvegardées (« Réessayer » de la section, ou de l'avis d'échec des étoiles).
    public func chargerMissions(depuis contexte: ContexteFavoris = .ecran) async {
        await lireMissions(explicite: true, contexte: contexte)
    }

    /// Relecture des établissements suivis (« Réessayer » de la section).
    public func chargerEtablissements() async { await lireEtablissements(explicite: true) }

    /// Explorer : état des étoiles, lu une fois par epoch (les mutations rendent ensuite la liste relue).
    public func chargerMissionsSiNecessaire() async {
        guard !missions.estPrete else { return }
        await lireMissions(explicite: true, contexte: .explorer)
    }

    // MARK: - Missions

    /// Étoile : sauvegarde une mission non sauvegardée, retire une mission sauvegardée. `depuis` : surface de l'étoile,
    /// où son erreur éventuelle est affichée (m4).
    public func basculer(missionId: String, depuis contexte: ContexteFavoris = .explorer) async {
        await appliquer(missionId: missionId, sauvegarder: !estSauvegardee(missionId), contexte: contexte)
    }

    /// « Retirer » de l'écran « Mes favoris ».
    public func retirerMission(_ missionId: String) async {
        await appliquer(missionId: missionId, sauvegarder: false, contexte: .ecran)
    }

    private func appliquer(missionId: String, sauvegarder: Bool, contexte: ContexteFavoris) async {
        guard !missionId.isEmpty, !missionsEnCours.contains(missionId) else { return }
        missionsEnCours.insert(missionId)
        defer { missionsEnCours.remove(missionId) }
        revisionMissions += 1
        let revision = revisionMissions
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.favoris
        let context = snapshot.context
        let horloge = gateways.clock
        do {
            let lignes = try await bounded(timeout: controller.resolutionTimeout) {
                sauvegarder ? try await port.sauvegarder(missionId: missionId, context: context)
                            : try await port.retirer(missionId: missionId, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            let publiee = revision == revisionMissions
            if publiee { publier(missions: lignes, maintenant: horloge.now()) }
            sessionExpired = false
            // Succès annoncé seulement si la relecture le confirme (PRINCIPES §3).
            let confirmee = FavorisRegles.estSauvegardee(missionId, dans: lignes) == sauvegarder
            if confirmee {
                effacerErreur()
            } else {
                signaler(sauvegarder ? Self.sauvegardeNonConfirmee : Self.retraitNonConfirme, contexte: contexte)
            }
            // m1 : une opération plus récente a publié son état ; s'il contredit cette mutation confirmée (lu avant
            // l'écriture) ou si aucune liste n'est relue, la liste est relue : jamais une écriture masquée.
            if confirmee, !publiee, !missions.estPrete || estSauvegardee(missionId) != sauvegarder {
                await lireMissions(explicite: false, contexte: contexte)
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: Self.echecMutation) else { return }
            sessionExpired = issue.sessionExpiree
            signaler(issue.message, contexte: contexte)
            // Le serveur a pu agir (délai, coupure) : relecture, jamais de renvoi.
            if !issue.sessionExpiree { await lireMissions(explicite: false, contexte: contexte) }
        }
    }

    // MARK: - Établissements (retrait seulement, décision 8)

    /// Retrait confirmé par la relecture : `true` (la feuille de confirmation se referme) ; sinon le message
    /// reste affiché (`erreurAction`) et la feuille reste ouverte pour une nouvelle tentative manuelle.
    @discardableResult
    public func retirerEtablissement(_ etablissementId: String) async -> Bool {
        guard !etablissementId.isEmpty, !etablissementsEnCours.contains(etablissementId) else { return false }
        etablissementsEnCours.insert(etablissementId)
        defer { etablissementsEnCours.remove(etablissementId) }
        revisionEtablissements += 1
        let revision = revisionEtablissements
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.favoris
        let context = snapshot.context
        do {
            let liste = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.basculerEtablissement(id: etablissementId, actif: false, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return false }
            if revision == revisionEtablissements { etablissements = .prete(liste) }
            sessionExpired = false
            guard !liste.contains(where: { $0.id == etablissementId }) else {
                signaler(Self.retraitNonConfirme, contexte: .ecran)
                return false
            }
            effacerErreur()
            return true
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: Self.echecMutation) else { return false }
            sessionExpired = issue.sessionExpiree
            signaler(issue.message, contexte: .ecran)
            if !issue.sessionExpiree { await lireEtablissements(explicite: false) }
            return false
        }
    }

    // MARK: - Interne

    /// `explicite` : lecture demandée par l'utilisateur ou par l'écran (son échec sur une liste affichée est
    /// signalé) ; sinon relecture de réconciliation après une mutation (son échec n'écrase pas le message
    /// de l'action).
    private func lireMissions(explicite: Bool, contexte: ContexteFavoris) async {
        revisionMissions += 1
        let revision = revisionMissions
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.favoris
        let context = snapshot.context
        let horloge = gateways.clock
        do {
            let lignes = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.missionsSauvegardees(context: context)
            }
            guard await controller.epoch == snapshot.epoch, revision == revisionMissions else { return }
            publier(missions: lignes, maintenant: horloge.now())
            sessionExpired = false
        } catch {
            guard await controller.epoch == snapshot.epoch, revision == revisionMissions, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: Self.echecLectureMissions) else { return }
            if issue.sessionExpiree { sessionExpired = true }
            if missions.estPrete {
                if explicite { signaler(issue.message, contexte: contexte) }
            } else {
                missions = .echec(issue.message)
            }
        }
    }

    private func lireEtablissements(explicite: Bool) async {
        revisionEtablissements += 1
        let revision = revisionEtablissements
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.favoris
        let context = snapshot.context
        do {
            let liste = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.etablissementsFavoris(context: context)
            }
            guard await controller.epoch == snapshot.epoch, revision == revisionEtablissements else { return }
            etablissements = .prete(liste)
            sessionExpired = false // M1 : comme `lireMissions`, toute lecture réussie lève « session à vérifier »
        } catch {
            guard await controller.epoch == snapshot.epoch, revision == revisionEtablissements, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: Self.echecLectureEtablissements) else { return }
            if issue.sessionExpiree { sessionExpired = true }
            if etablissements.estPrete {
                if explicite { signaler(issue.message, contexte: .ecran) }
            } else {
                etablissements = .echec(issue.message)
            }
        }
    }

    private func publier(missions lignes: [MissionSauvegardee], maintenant: Date) {
        missions = .prete(lignes)
        missionsAffichees = FavorisRegles.missionsAffichees(lignes, maintenant: maintenant)
    }

    private func signaler(_ message: String, contexte: ContexteFavoris) {
        tentatives += 1
        erreurAction = message
        contexteErreur = contexte
    }

    /// Message affiché pour une erreur, `nil` pour une annulation (jamais présentée comme une erreur).
    nonisolated static func message(pour error: Error, repli: String) -> (message: String, sessionExpiree: Bool)? {
        if error is CancellationError { return nil }
        if let jolene = error as? JoleneError {
            if jolene.kind == .cancelled { return nil }
            return (jolene.message, jolene.kind == .unauthorized)
        }
        return (repli, false)
    }
}
