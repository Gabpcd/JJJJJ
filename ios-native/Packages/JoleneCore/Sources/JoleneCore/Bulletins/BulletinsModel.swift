import Foundation
import Combine

/// État de la liste des copies : en attente de la première réponse, relue, ou en échec (message affiché).
public enum ListeCopiesBulletins: Equatable, Sendable {
    case chargement
    case prete([CopieBulletin])
    case echec(String)

    public var copies: [CopieBulletin] {
        if case let .prete(copies) = self { return copies }
        return []
    }

    public var estPrete: Bool {
        if case .prete = self { return true }
        return false
    }
}

/// PDF vérifié présenté par le lecteur : octets en mémoire seulement, jamais écrits pour la lecture.
public struct PDFOuvert: Identifiable, Equatable, Sendable {
    public var copie: CopieBulletin
    public var pdf: PDFVerifie
    public var id: String { copie.id }

    public init(copie: CopieBulletin, pdf: PDFVerifie) { self.copie = copie; self.pdf = pdf }
}

/// Modèle des copies officielles des bulletins (L4-T10), port de `CopiesBulletinsSoignant` et du composant réellement
/// monté `CopiesBulletinsListe.tsx` (rôle SOIGNANT : signalement, jamais retrait ni dépôt).
///
/// Règles :
/// - lecture bornée à `SessionController.resolutionTimeout`, téléchargement borné à 30 s (web l.232) ; gateways de
///   l'epoch de l'écran, réponse d'un epoch périmé ignorée ; une seule action à la fois (`enCours`, web `enCours.current`) ;
/// - une copie `RETIREE` n'est jamais demandée au serveur ; un 410 `COPIE_RETIREE` relit la liste ; un PDF dont la taille
///   ou l'empreinte diffère n'est jamais présenté (`erreurIntegrite`) ;
/// - un signalement n'est annoncé qu'après une relecture qui le montre (`signalee`, et `RETIREE` pour `DESTINATAIRE`,
///   PRINCIPES §3) ; erreur : message du web puis relecture (le serveur a pu agir), jamais de renvoi ;
/// - une annulation (vue qui disparaît) n'est jamais une erreur ; aucun octet ni contenu de bulletin n'est journalisé.
@MainActor
public final class BulletinsModel: ObservableObject {
    @Published public private(set) var liste: ListeCopiesBulletins = .chargement
    /// Erreur d'action (ouverture, signalement) ; `nil` après un succès.
    @Published public private(set) var erreur: String?
    /// Vrai quand `erreur` est le refus d'intégrité (`copie-integrite-erreur`).
    @Published public private(set) var erreurIntegrite = false
    /// Signalement confirmé par relecture (texte du web l.42-44).
    @Published public private(set) var message: String?
    /// Jeton d'annonce VoiceOver : change à chaque message.
    @Published public private(set) var jeton = 0
    @Published public private(set) var sessionExpiree = false
    /// Copie dont l'action est en cours (un seul appui à la fois, web `busy`).
    @Published public private(set) var enCours: String?
    /// PDF vérifié à présenter (`pdf-lecteur`).
    @Published public var pdfOuvert: PDFOuvert?
    /// Filtre « Employeur » : `nil` = « Tous les employeurs ».
    @Published public var employeur: String?

    /// Copie visée par le lien (`?copie=`), mise en avant si présente.
    public let copieCible: String?

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var revision = 0

    public init(controller: SessionController, snapshot: SessionSnapshot, copieCible: String? = nil) {
        self.controller = controller
        self.snapshot = snapshot
        self.copieCible = copieCible
    }

    // MARK: - Lecture seule

    /// Copies affichées : filtre employeur puis ordre du web.
    public var copiesAffichees: [CopieBulletin] { BulletinsPresentation.liste(liste.copies, employeur: employeur) }

    /// Employeurs du filtre, affiché seulement à partir de deux (web l.54).
    public var employeurs: [BulletinsPresentation.Employeur] { BulletinsPresentation.employeurs(liste.copies) }

    /// Lien vers une copie absente de la liste de ce compte (web l.53).
    public var copieCibleIndisponible: Bool {
        guard let copieCible, liste.estPrete else { return false }
        return !liste.copies.contains { $0.id == copieCible }
    }

    public func telechargeable(_ copie: CopieBulletin) -> Bool { CopieBulletinValidation.telechargeable(copie.statut) }

    public func effacerMessages() {
        erreur = nil
        erreurIntegrite = false
        message = nil
    }

    /// « Vérifier ma session » : revalide la session, puis relit si elle est toujours prête pour cet epoch.
    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await charger()
    }

    // MARK: - Lecture

    /// À l'apparition et « Réessayer les copies ».
    public func charger() async {
        await lire(explicite: true)
    }

    // MARK: - Ouverture

    /// « Ouvrir / télécharger le PDF original » : octets de l'edge vérifiés, puis présentés par le lecteur.
    public func ouvrir(_ copie: CopieBulletin) async {
        guard enCours == nil else { return }
        effacerMessages()
        guard telechargeable(copie) else {
            signaler(RefusCopieBulletin.retiree.message)
            return
        }
        enCours = copie.id
        defer { enCours = nil }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.bulletins
        let context = snapshot.context
        do {
            let pdf = try await bounded(timeout: BulletinsTelechargement.delaiSecondes) {
                try await port.telecharger(copie: copie, context: context)
            }
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled else { return }
            sessionExpiree = false
            pdfOuvert = PDFOuvert(copie: copie, pdf: pdf)
        } catch let refus as RefusCopieBulletin {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled else { return }
            signaler(refus.message, integrite: refus == .integrite)
            if refus == .retiree { await lire(explicite: false) }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: LibellesWeb.CopiesBulletins.ouvertureImpossible) else { return }
            sessionExpiree = issue.sessionExpiree
            signaler(issue.sessionExpiree ? issue.message : RefusCopieBulletin.indisponible.message)
        }
    }

    /// Fermeture du lecteur : octets libérés.
    public func fermerPDF() {
        pdfOuvert = nil
    }

    // MARK: - Signalement

    /// « Envoyer le signalement » ; `true` si la relecture le confirme (la feuille se referme).
    @discardableResult
    public func signaler(_ copie: CopieBulletin, motif: MotifSignalementCopie) async -> Bool {
        guard enCours == nil, telechargeable(copie) else { return false }
        effacerMessages()
        enCours = copie.id
        defer { enCours = nil }
        revision += 1
        let revisionMutation = revision
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.bulletins
        let context = snapshot.context
        do {
            let lignes = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.signaler(copieId: copie.id, motif: motif, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return false }
            sessionExpiree = false
            if revisionMutation == revision { liste = .prete(lignes) }
            let relue = lignes.first { $0.id == copie.id }
            let confirme = relue?.signalee == true && (motif != .destinataire || relue?.statut == .retiree)
            guard confirme else {
                signaler(LibellesWeb.CopiesBulletins.signalementNonConfirme)
                return false
            }
            message = motif == .destinataire ? LibellesWeb.CopiesBulletins.copieRetiree
                : LibellesWeb.CopiesBulletins.signalementEnregistre
            jeton += 1
            return true
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: LibellesWeb.CopiesBulletins.signalementNonConfirme) else {
                return false
            }
            sessionExpiree = issue.sessionExpiree
            signaler(issue.sessionExpiree ? issue.message : LibellesWeb.CopiesBulletins.signalementNonConfirme)
            if !issue.sessionExpiree { await lire(explicite: false) }
            return false
        }
    }

    // MARK: - Interne

    private func lire(explicite: Bool) async {
        revision += 1
        let revisionLecture = revision
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.bulletins
        let context = snapshot.context
        do {
            let lignes = try await bounded(timeout: controller.resolutionTimeout) { try await port.copies(context: context) }
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision else { return }
            liste = .prete(lignes)
            sessionExpiree = false
            if let employeur, !lignes.contains(where: { $0.etablissementId == employeur }) { self.employeur = nil }
        } catch {
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: LibellesWeb.CopiesBulletins.chargementImpossible) else { return }
            if issue.sessionExpiree { sessionExpiree = true }
            if liste.estPrete {
                if explicite { signaler(issue.message) }
            } else {
                liste = .echec(issue.message)
            }
        }
    }

    private func signaler(_ texte: String, integrite: Bool = false) {
        message = nil
        erreur = texte
        erreurIntegrite = integrite
        jeton += 1
    }

    /// Message affiché pour une erreur, `nil` pour une annulation (jamais présentée comme une erreur).
    nonisolated static func message(pour error: Error, repli: String) -> (message: String, sessionExpiree: Bool)? {
        if error is CancellationError { return nil }
        if let jolene = error as? JoleneError {
            if jolene.kind == .cancelled { return nil }
            return (jolene.message, jolene.kind == .unauthorized)
        }
        if let refus = error as? CopieBulletinValidation.ListeNonVerifiable { return (refus.message, false) }
        return (repli, false)
    }
}
