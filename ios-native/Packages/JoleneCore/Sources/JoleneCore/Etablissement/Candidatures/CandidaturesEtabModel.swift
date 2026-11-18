import Foundation
import Combine

/// Modèle de l'écran des candidatures d'une mission (lot 5, T6 ; `LOT5_PLAN.md` §2.6), port de
/// `ListeCandidatures.tsx` sur la lecture habilitée `fn_lire_candidatures_mission_habilitee` et la mutation
/// `fn_traiter_candidature_planning_v1`, par `gateways.etablissement.candidatures` pour l'epoch de la session, chaque
/// appel borné à `SessionController.resolutionTimeout`.
///
/// Flux d'acceptation (web l.244-305) : planning vérifié à l'ouverture (`PlanningExactEtab`) → « Accepter » relit la
/// lecture habilitée et ouvre le récapitulatif → « Confirmer et assigner » la relit une seconde fois ; une empreinte
/// `(id, debut, fin)` différente remplace le récapitulatif et n'envoie rien (alerte du web l.277) ; sinon la charge
/// `p_creneaux_confirmes` est l'écho exact des chaînes relues (D26). L'issue ne vaut jamais confirmation : la lecture
/// est relue, `ACCEPTEE` **et** mission `ASSIGNEE` (refus : `REFUSEE`), avant tout succès (PRINCIPES §3). Une issue
/// inconnue (délai, transport) est relue, jamais renvoyée.
///
/// Hors périmètre natif (D10, D25) : mission non salariée, mission `MEDECIN`, étudiant aide-soignant → « Accepter sur
/// jolene.app », avant tout appel (`CandidaturesEtabRules`). Refus de droit (42501 en liste blanche) : message serveur
/// puis une relecture des permissions (`relirePerimetre`), jamais une déconnexion. Les refus du serveur s'affichent tels
/// quels (`[CODE DU TRAVAIL]` compris). Pas de double envoi : `enCours` est posé avant tout `await` de chaque action.
@MainActor
public final class CandidaturesEtabModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case chargee
        /// 42501 en liste blanche : texte serveur verbatim.
        case accesRefuse(String)
        /// Mission illisible sous RLS (supprimée ou hors de l'établissement).
        case introuvable
        case echec(String)
    }

    /// Récapitulatif d'acceptation : créneaux relus et vérifiés, alerte éventuelle (planning modifié, refus serveur
    /// verbatim).
    public struct Recapitulatif: Equatable, Sendable {
        public var candidature: CandidatureHabilitee
        public var creneaux: [MissionSlot]
        public var alerte: String?

        public init(candidature: CandidatureHabilitee, creneaux: [MissionSlot], alerte: String? = nil) {
            self.candidature = candidature; self.creneaux = creneaux; self.alerte = alerte
        }
    }

    /// Issue affichée au-dessus de la liste.
    public enum Annonce: Equatable, Sendable {
        /// Décision confirmée par relecture.
        case succes(String)
        /// Refus ou issue non confirmée, texte serveur verbatim quand il existe.
        case erreur(String)
        /// Refus de paiement de `fn_trg_gate_assignation_paiement`, verbatim, avec renvoi vers la facturation.
        case paiement(String)
        /// Acceptation hors périmètre natif ; `message` = refus serveur verbatim (cadre étudiant) s'il y en a un.
        case renvoiWeb(MotifRenvoiWebCandidature, message: String?)
    }

    public let missionId: String
    @Published public private(set) var etat: Etat = .chargement
    @Published public private(set) var lecture: LectureCandidaturesHabilitee?
    /// `missions.type_contrat_recherche` relu par T5 (D25) ; `nil` tant que la mission n'est pas lue.
    @Published public private(set) var typeContratRecherche: String?
    @Published public private(set) var recap: Recapitulatif?
    /// Candidature en cours de traitement (ouverture du récapitulatif, envoi, refus) : toute autre action est ignorée.
    @Published public private(set) var enCours: String?
    @Published public private(set) var annonce: Annonce?
    @Published public private(set) var rafraichissement = false
    @Published public private(set) var erreurRafraichissement: String?

    private let controller: SessionController
    private let snapshot: EtablissementSessionSnapshot
    private let relirePerimetre: @MainActor () async -> Void
    private var generation = 0

    /// `relirePerimetre` : relecture des permissions après un refus de droit (`SessionStore.refreshEtablissementScope`).
    public init(missionId: String, controller: SessionController, snapshot: EtablissementSessionSnapshot,
                relirePerimetre: @escaping @MainActor () async -> Void = {}) {
        self.missionId = missionId
        self.controller = controller
        self.snapshot = snapshot
        self.relirePerimetre = relirePerimetre
    }

    // MARK: - État dérivé

    /// Planning exact de la dernière lecture (bloque l'acceptation sinon, web l.376-386, l.489).
    public var verification: PlanningExactEtab.Verification {
        guard let lecture else { return PlanningExactEtab.verifier([], nbCreneauxAttendus: nil, indisponible: true) }
        return PlanningExactEtab.verifier(lecture.creneaux, nbCreneauxAttendus: lecture.nbCreneaux)
    }

    public var enAttente: [CandidatureHabilitee] { CandidaturesEtabRules.enAttente(lecture?.candidatures ?? []) }
    public var traitees: [CandidatureHabilitee] { CandidaturesEtabRules.traitees(lecture?.candidatures ?? []) }

    /// Renvoi web de l'acceptation (D10, D25), `nil` si elle peut être native.
    public func motifRenvoiWeb(_ candidature: CandidatureHabilitee) -> MotifRenvoiWebCandidature? {
        CandidaturesEtabRules.motifRenvoiWeb(typeContratRecherche: typeContratRecherche,
                                             professionRequise: lecture?.professionRequise, candidat: candidature.soignant)
    }

    public func peutAccepter(_ candidature: CandidatureHabilitee) -> Bool {
        enCours == nil && recap == nil && candidature.statut == CandidaturesEtabRules.statutEnAttente
            && verification.exact && motifRenvoiWeb(candidature) == nil
    }

    public func peutRefuser(_ candidature: CandidatureHabilitee) -> Bool {
        enCours == nil && recap == nil && candidature.statut == CandidaturesEtabRules.statutEnAttente
    }

    // MARK: - Lecture

    /// Lit (ou relit) la lecture habilitée et la mission (contrat recherché, D25) ; une liste affichée est conservée
    /// pendant la relecture, son échec n'expose qu'`erreurRafraichissement`.
    public func charger() async {
        generation += 1
        let courant = generation
        let conserver = lecture != nil
        erreurRafraichissement = nil
        if conserver { rafraichissement = true } else { etat = .chargement }
        defer { if generation == courant { rafraichissement = false } }

        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        guard generation == courant, !Task.isCancelled else { return }
        let candidatures = gateways.etablissement.candidatures
        let missions = gateways.etablissement.missions
        let context = snapshot.context
        let id = missionId
        let delai = controller.resolutionTimeout
        do {
            async let lue = bounded(timeout: delai) { try await candidatures.lecture(missionId: id, context: context) }
            async let detail = bounded(timeout: delai) { try await missions.mission(id: id, context: context) }
            let (relue, mission) = try await (lue, detail)
            guard await epochValide(), generation == courant else { return }
            guard let mission else {
                lecture = nil
                recap = nil
                etat = .introuvable
                return
            }
            lecture = relue
            typeContratRecherche = mission.mission.typeContratRecherche
            etat = .chargee
        } catch let refus as RefusAccesEtablissement {
            guard await epochValide(), generation == courant else { return }
            lecture = nil
            recap = nil
            etat = .accesRefuse(refus.message)
            await relirePerimetre()
        } catch {
            guard await epochValide(), generation == courant, !Task.isCancelled, let message = Self.message(error) else { return }
            if conserver { erreurRafraichissement = message } else { etat = .echec(message) }
        }
    }

    // MARK: - Acceptation

    /// « Accepter » (web l.244-263) : renvoi web hors périmètre, planning initial exact exigé, puis relecture et
    /// ouverture du récapitulatif sur les créneaux relus.
    public func ouvrirAcceptation(candidatureId: String) async {
        guard enCours == nil, recap == nil,
              let candidature = lecture?.candidatures.first(where: { $0.id == candidatureId }),
              candidature.statut == CandidaturesEtabRules.statutEnAttente else { return }
        annonce = nil
        if let motif = motifRenvoiWeb(candidature) {
            annonce = .renvoiWeb(motif, message: nil)
            return
        }
        let initiale = verification
        guard initiale.exact else {
            annonce = .erreur(initiale.erreur ?? PlanningExactEtab.messageAConfirmer)
            return
        }
        enCours = candidatureId
        defer { enCours = nil }
        let relue: LectureCandidaturesHabilitee
        do {
            guard let lue = try await lireLecture() else { return }
            relue = lue
        } catch {
            await traiterErreurAction(error)
            return
        }
        guard await epochValide() else { return }
        lecture = relue
        let planning = PlanningExactEtab.verifier(relue.creneaux, nbCreneauxAttendus: relue.nbCreneaux)
        guard planning.exact else {
            annonce = .erreur(planning.erreur ?? PlanningExactEtab.messageAConfirmer)
            return
        }
        guard let courante = relue.candidatures.first(where: { $0.id == candidatureId }),
              courante.statut == CandidaturesEtabRules.statutEnAttente else {
            annonce = .erreur(CandidaturesEtabPresentation.plusEnAttente)
            return
        }
        if let motif = motifRenvoiWeb(courante) {
            annonce = .renvoiWeb(motif, message: nil)
            return
        }
        recap = Recapitulatif(candidature: courante, creneaux: planning.creneaux)
    }

    /// « Confirmer et assigner » (web l.265-305) : seconde relecture, comparaison d'empreinte, envoi, relecture de l'issue.
    public func confirmerAcceptation() async {
        guard enCours == nil, let ouvert = recap else { return }
        let candidatureId = ouvert.candidature.id
        enCours = candidatureId
        defer { enCours = nil }
        recap?.alerte = nil
        annonce = nil

        let relue: LectureCandidaturesHabilitee
        do {
            guard let lue = try await lireLecture() else { return }
            relue = lue
        } catch {
            await traiterErreurAction(error, dansRecap: true)
            return
        }
        guard await epochValide() else { return }
        lecture = relue
        let planning = PlanningExactEtab.verifier(relue.creneaux, nbCreneauxAttendus: relue.nbCreneaux)
        guard planning.exact else {
            recap?.alerte = planning.erreur ?? PlanningExactEtab.messageAConfirmer
            return
        }
        guard let courante = relue.candidatures.first(where: { $0.id == candidatureId }),
              courante.statut == CandidaturesEtabRules.statutEnAttente else {
            recap = nil
            annonce = .erreur(CandidaturesEtabPresentation.plusEnAttente)
            return
        }
        guard PlanningExactEtab.memeEmpreinte(planning.creneaux, ouvert.creneaux) else {
            // Récapitulatif devenu obsolète : remplacé, rien n'est envoyé (web l.272-278).
            recap = Recapitulatif(candidature: courante, creneaux: planning.creneaux, alerte: PlanningExactEtab.messagePlanningModifie)
            return
        }
        if let motif = motifRenvoiWeb(courante) {
            recap = nil
            annonce = .renvoiWeb(motif, message: nil)
            return
        }
        guard let charge = PlanningExactEtab.creneauxConfirmes(planning) else {
            recap?.alerte = PlanningExactEtab.messageAConfirmer
            return
        }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.etablissement.candidatures
        let context = snapshot.context
        let issue: TraitementCandidatureOutcome
        do {
            issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.accepter(candidatureId: candidatureId, creneauxConfirmes: charge, context: context)
            }
        } catch {
            guard await epochValide() else { return }
            if let refus = error as? RefusAccesEtablissement {
                recap = nil
                annonce = .erreur(refus.message)
                await relirePerimetre()
                return
            }
            // Issue inconnue (délai, transport, refus sans drapeau) : relue, jamais renvoyée.
            await confirmerParRelecture(.acceptee, candidatureId: candidatureId,
                                        siNonConfirmee: Self.message(error) ?? CandidaturesEtabPresentation.nonConfirmee)
            return
        }
        guard await epochValide() else { return }
        switch issue {
        case .acceptee, .refusEnregistre:
            await confirmerParRelecture(.acceptee, candidatureId: candidatureId, siNonConfirmee: CandidaturesEtabPresentation.nonConfirmee)
        case let .planningAReconfirmer(_, message):
            await remplacerRecapitulatif(candidatureId: candidatureId, alerte: message)
        case let .refusee(_, message, _):
            recap?.alerte = message
        case let .cadreEtudiant(_, message):
            recap = nil
            annonce = .renvoiWeb(.cadreEtudiant, message: message)
        case let .accesRefuse(message):
            recap = nil
            annonce = .erreur(message)
            await relirePerimetre()
        case let .paiementNonConfigure(message):
            recap = nil
            annonce = .paiement(message)
        case let .renvoiWeb(motif):
            recap = nil
            annonce = .renvoiWeb(motif, message: nil)
        }
    }

    /// Ferme le récapitulatif (« Annuler », geste), jamais pendant un envoi.
    public func annulerRecapitulatif() {
        guard enCours == nil else { return }
        recap = nil
    }

    // MARK: - Refus

    /// « Refuser » (web l.308-330) : `p_motif` du web, refus relu (`REFUSEE`) avant le succès.
    public func refuser(candidatureId: String) async {
        guard enCours == nil, recap == nil,
              lecture?.candidatures.first(where: { $0.id == candidatureId })?.statut == CandidaturesEtabRules.statutEnAttente else { return }
        enCours = candidatureId
        defer { enCours = nil }
        annonce = nil
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.etablissement.candidatures
        let context = snapshot.context
        let issue: TraitementCandidatureOutcome
        do {
            issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.refuser(candidatureId: candidatureId, context: context)
            }
        } catch {
            guard await epochValide() else { return }
            if let refus = error as? RefusAccesEtablissement {
                annonce = .erreur(refus.message)
                await relirePerimetre()
                return
            }
            await confirmerParRelecture(.refusee, candidatureId: candidatureId,
                                        siNonConfirmee: Self.message(error) ?? CandidaturesEtabPresentation.nonConfirmee)
            return
        }
        guard await epochValide() else { return }
        switch issue {
        case .refusEnregistre, .acceptee:
            await confirmerParRelecture(.refusee, candidatureId: candidatureId, siNonConfirmee: CandidaturesEtabPresentation.nonConfirmee)
        case let .refusee(_, message, _), let .planningAReconfirmer(_, message), let .cadreEtudiant(_, message),
             let .paiementNonConfigure(message):
            annonce = .erreur(message)
        case let .accesRefuse(message):
            annonce = .erreur(message)
            await relirePerimetre()
        case let .renvoiWeb(motif):
            annonce = .renvoiWeb(motif, message: nil)
        }
    }

    public func effacerAnnonce() {
        annonce = nil
    }

    // MARK: - Relectures

    private func lireLecture() async throws -> LectureCandidaturesHabilitee? {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return nil }
        let port = gateways.etablissement.candidatures
        let context = snapshot.context
        let id = missionId
        return try await bounded(timeout: controller.resolutionTimeout) { try await port.lecture(missionId: id, context: context) }
    }

    private func epochValide() async -> Bool {
        await controller.epoch == snapshot.epoch
    }

    /// Relecture de l'issue (§2.4) : succès seulement si la lecture relue le confirme ; sinon `siNonConfirmee`, dans le
    /// récapitulatif tant que la candidature reste en attente, au-dessus de la liste sinon.
    private func confirmerParRelecture(_ decision: DecisionCandidature, candidatureId: String, siNonConfirmee: String) async {
        let relue = try? await lireLecture()
        guard await epochValide() else { return }
        if let relue { lecture = relue }
        if let relue, CandidaturesEtabRules.decisionConfirmee(decision, candidatureId: candidatureId, lecture: relue) {
            recap = nil
            annonce = .succes(decision == .acceptee ? CandidaturesEtabPresentation.succesAcceptation
                                                   : CandidaturesEtabPresentation.succesRefus)
            return
        }
        let toujoursEnAttente = relue?.candidatures.first(where: { $0.id == candidatureId })?.statut == CandidaturesEtabRules.statutEnAttente
        if decision == .acceptee, toujoursEnAttente, recap != nil {
            recap?.alerte = siNonConfirmee
        } else {
            recap = nil
            annonce = .erreur(siNonConfirmee)
        }
    }

    /// `PLANNING_A_RECONFIRMER` / `PLANNING_MODIFIE_RECONFIRMER` : planning relu, récapitulatif remplacé avec le
    /// message serveur ; aucun renvoi automatique (la confirmation reste à l'établissement).
    private func remplacerRecapitulatif(candidatureId: String, alerte: String) async {
        let relue = try? await lireLecture()
        guard await epochValide() else { return }
        guard let relue else {
            recap?.alerte = alerte
            return
        }
        lecture = relue
        let planning = PlanningExactEtab.verifier(relue.creneaux, nbCreneauxAttendus: relue.nbCreneaux)
        if planning.exact, let courante = relue.candidatures.first(where: { $0.id == candidatureId }),
           courante.statut == CandidaturesEtabRules.statutEnAttente {
            recap = Recapitulatif(candidature: courante, creneaux: planning.creneaux, alerte: alerte)
        } else {
            recap = nil
            annonce = .erreur(alerte)
        }
    }

    private func traiterErreurAction(_ error: Error, dansRecap: Bool = false) async {
        guard await epochValide() else { return }
        if let refus = error as? RefusAccesEtablissement {
            recap = nil
            annonce = .erreur(refus.message)
            await relirePerimetre()
            return
        }
        guard let message = Self.message(error) else { return }
        if dansRecap, recap != nil { recap?.alerte = message } else { annonce = .erreur(message) }
    }

    /// Message affiché d'une erreur ; `nil` pour une annulation (jamais une erreur affichée).
    static func message(_ error: Error) -> String? {
        if let jolene = error as? JoleneError { return jolene.kind == .cancelled ? nil : jolene.message }
        if error is CancellationError { return nil }
        if let refus = error as? RefusAccesEtablissement { return refus.message }
        return CandidaturesEtabPresentation.messageErreurGenerique
    }
}
