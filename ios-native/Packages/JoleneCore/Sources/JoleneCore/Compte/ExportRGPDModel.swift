import Foundation
import Combine

/// Dossier temporaire des exports RGPD (blueprint §2.6) : chaque export a son propre sous-dossier
/// `jolene-export-<uuid>` sous `racine` (dossier temporaire de l'app par défaut), écrit avec la protection
/// complète (`NSFileProtectionComplete` : illisible appareil verrouillé) et supprimé à la fermeture de la feuille
/// de partage ; les résidus d'un arrêt brutal sont purgés à l'ouverture suivante. Jamais de copie ailleurs.
public struct DossierExportTemporaire: Sendable {
    public static let prefixe = "jolene-export-"
    /// Protection complète ; `withoutOverwriting` : un fichier existant n'est jamais écrasé en silence.
    public static let optionsEcriture: Data.WritingOptions = [.completeFileProtection, .withoutOverwriting]

    public let racine: URL

    public init(racine: URL) { self.racine = racine }

    /// Dossier temporaire de l'app (`NSTemporaryDirectory`), hors sauvegarde iCloud.
    public static var systeme: DossierExportTemporaire { DossierExportTemporaire(racine: FileManager.default.temporaryDirectory) }

    /// Écrit le fichier dans un sous-dossier neuf ; rend son URL.
    public func ecrire(_ fichier: FichierExportRGPD) throws -> URL {
        let dossier = racine.appendingPathComponent(Self.prefixe + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        let url = dossier.appendingPathComponent(fichier.nom, isDirectory: false)
        do {
            try fichier.contenu.write(to: url, options: Self.optionsEcriture)
        } catch {
            try? FileManager.default.removeItem(at: dossier)
            throw error
        }
        return url
    }

    /// Supprime le sous-dossier d'un fichier écrit par `ecrire` (jamais un fichier hors de la racine).
    public func supprimer(_ url: URL) {
        let dossier = url.deletingLastPathComponent()
        guard dossier.lastPathComponent.hasPrefix(Self.prefixe),
              dossier.deletingLastPathComponent().standardizedFileURL.path == racine.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: dossier)
    }

    /// Retire les sous-dossiers d'export restés sous la racine (seuls ceux du préfixe). Appelé au lancement
    /// (`AppContainer`) et à la création du modèle du hub.
    public func purgerResidus() {
        for element in dossiersExport() {
            try? FileManager.default.removeItem(at: element)
        }
    }

    /// Nombre de sous-dossiers d'export présents sous la racine (preuve DEBUG `compte-export-residus`, tests).
    public var residus: Int { dossiersExport().count }

    private func dossiersExport() -> [URL] {
        let contenu = (try? FileManager.default.contentsOfDirectory(at: racine, includingPropertiesForKeys: nil)) ?? []
        return contenu.filter { $0.lastPathComponent.hasPrefix(Self.prefixe) }
    }
}

/// Fichier proposé à la feuille de partage.
public struct FichierAPartager: Identifiable, Equatable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let nom: String
    public let format: FormatExportRGPD
}

/// Modèle de la section « Mes données (RGPD) » du hub (lot 3, T11), port de `handleExportRGPD`
/// (`SectionConfidentialite.tsx` l.30-78) :
/// - une seule demande à la fois, les deux boutons désactivés pendant l'export et tant que la feuille est
///   ouverte (`exportLoading`, l.119 et l.127) ;
/// - `{error}` du serveur : message verbatim, AUCUN fichier écrit (l.35-41) ; session expirée : « Vérifier ma
///   session » ;
/// - export reçu : fichier JSON ou CSV écrit hors du fil principal dans un dossier temporaire protégé, proposé
///   à la feuille de partage, puis audit `RGPD_EXPORT_DONNEES` best-effort (l.42-48 ; le serveur l'écrit
///   aussi, doublon assumé) ; le contenu n'est jamais affiché ni journalisé ;
/// - feuille de partage (revue B8, M1 et m3) : présentée une seule fois (`fichierAPresenter`, puis
///   `feuillePresentee`), et seulement hub à l'écran (`hubAffiche`) — un export abouti pendant qu'un autre onglet
///   ou un écran empilé est affiché attend le retour du hub, jamais une feuille présentée depuis un onglet caché ;
/// - fin UNIQUE de la feuille (`partageTermine`, appelé par le seul `completionWithItemsHandler`) : fichier
///   supprimé, boutons réactivés ; « Données exportées en JSON. » seulement si le partage est allé à son terme
///   (le web l'annonce même sur une feuille fermée sans partage, écart consigné) ;
/// - fin de session feuille ouverte (epoch avancé) : fichier supprimé et retiré (`partage` nil : la vue ferme la
///   feuille), sans annonce (revue B8, m8) ;
/// - toute réponse d'un epoch périmé est ignorée (aucun fichier pour une identité partie).
@MainActor
public final class ExportRGPDModel: ObservableObject {
    @Published public private(set) var enCours: FormatExportRGPD?
    /// Fichier écrit, en attente de sa feuille ou en cours de partage.
    @Published public private(set) var partage: FichierAPartager?
    /// Une feuille de partage est présentée pour `partage`.
    @Published public private(set) var feuilleOuverte = false
    /// Le hub est à l'écran (onglet Profil sélectionné, hub au sommet de sa pile).
    @Published public private(set) var hubVisible = false
    @Published public private(set) var succes: String?
    @Published public private(set) var erreur: String?
    @Published public private(set) var sessionExpiree = false
    /// Jeton d'annonce VoiceOver des encarts (`InlineNotice.announcementID`).
    @Published public private(set) var annonces = 0
    /// Dernière vérification d'identité lancée par un changement d'état de session (preuves des tests).
    private(set) var verificationIdentite: Task<Void, Never>?

    private let session: SessionStore
    private let snapshot: SessionSnapshot
    private let dossier: DossierExportTemporaire
    private var suiviSession: AnyCancellable?

    public init(session: SessionStore, snapshot: SessionSnapshot, dossier: DossierExportTemporaire = .systeme) {
        self.session = session
        self.snapshot = snapshot
        self.dossier = dossier
        dossier.purgerResidus()
        suiviSession = session.$state.dropFirst().sink { [weak self] _ in self?.verifierIdentite() }
    }

    /// Les deux boutons sont actifs hors export et hors fichier en attente ou en partage.
    public var peutExporter: Bool { enCours == nil && partage == nil }

    /// Dossiers d'export présents dans le dossier temporaire (preuve DEBUG `compte-export-residus`).
    public var residus: Int { dossier.residus }

    /// Fichier dont la feuille doit être présentée maintenant : hub à l'écran, aucune feuille déjà présentée.
    public var fichierAPresenter: FichierAPartager? { hubVisible && !feuilleOuverte ? partage : nil }

    /// Apparition (`true`) ou disparition (`false`) du hub : changement d'onglet, écran empilé ou dépilé.
    public func hubAffiche(_ affiche: Bool) {
        hubVisible = affiche
    }

    /// La vue a présenté la feuille de `fichier` (avant sa présentation effective, pour ne jamais en présenter deux).
    public func feuillePresentee(_ fichier: FichierAPartager) {
        guard partage == fichier else { return }
        feuilleOuverte = true
    }

    public func exporter(_ format: FormatExportRGPD) async {
        guard peutExporter else { return }
        enCours = format
        defer { enCours = nil }
        succes = nil
        erreur = nil
        guard let gateways = await session.controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.exportRGPD
        let context = snapshot.context
        let maintenant = gateways.clock.now()
        let fichier: FichierExportRGPD
        do {
            let donnees = try await bounded(timeout: session.controller.resolutionTimeout) {
                try await port.exporter(context: context)
            }
            guard await memeEpoch() else { return }
            fichier = try await Task.detached(priority: .userInitiated) {
                try ExportRGPD.fichier(donnees, format: format, maintenant: maintenant)
            }.value
        } catch {
            guard await memeEpoch(), !(error is CancellationError) else { return }
            let jolene = error as? JoleneError
            if jolene?.kind == .cancelled { return }
            sessionExpiree = jolene?.kind == .unauthorized
            erreur = jolene?.message ?? ExportRGPD.Textes.echec
            annonces += 1
            return
        }
        guard await memeEpoch() else { return }
        let dossier = self.dossier
        let url: URL
        do {
            url = try await Task.detached(priority: .userInitiated) { try dossier.ecrire(fichier) }.value
        } catch {
            erreur = ExportRGPD.Textes.echec
            annonces += 1
            return
        }
        guard await memeEpoch() else {
            dossier.supprimer(url)
            return
        }
        sessionExpiree = false
        partage = FichierAPartager(url: url, nom: fichier.nom, format: format)
        enCours = nil
        await auditer(gateways, format: format)
    }

    /// Fin de la feuille de partage, signalée UNE fois par `completionWithItemsHandler` (`complete` : une activité
    /// est allée à son terme) : seule source de fin, aucun autre signal de fermeture n'est relayé. Sans effet si
    /// aucun fichier n'est proposé (fin tardive après une fin de session).
    public func partageTermine(complete: Bool) {
        guard let fichier = partage else { return }
        dossier.supprimer(fichier.url)
        partage = nil
        feuilleOuverte = false
        if complete {
            succes = ExportRGPD.Textes.succes(fichier.format)
            annonces += 1
        }
    }

    /// Changement d'état de session : si l'identité de l'écran est partie (epoch avancé), le fichier en attente ou
    /// en partage est supprimé tout de suite — même si le hub est détruit entre-temps — puis retiré (`partage` nil :
    /// la vue ferme la feuille). Aucune annonce.
    private func verifierIdentite() {
        guard let fichier = partage else { return }
        let (controleur, epoch, dossier) = (session.controller, snapshot.epoch, self.dossier)
        verificationIdentite = Task { [weak self] in
            guard await controleur.epoch != epoch else { return }
            dossier.supprimer(fichier.url)
            self?.retirer(fichier)
        }
    }

    private func retirer(_ fichier: FichierAPartager) {
        guard partage == fichier else { return }
        partage = nil
        feuilleOuverte = false
    }

    /// « Vérifier ma session » : revalide la session ; si elle reste prête pour l'epoch de l'écran, le refus est
    /// effacé (un nouvel export reste manuel).
    public func verifierSession() async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch, await memeEpoch() else { return }
        sessionExpiree = false
        erreur = nil
    }

    private func auditer(_ gateways: Gateways, format: FormatExportRGPD) async {
        let audit = gateways.audit
        let context = snapshot.context
        let userId = snapshot.user.id
        _ = try? await bounded(timeout: session.controller.resolutionTimeout) {
            try await audit.ecrire(action: .rgpdExportDonnees, typeRessource: ExportRGPD.auditTypeRessource,
                                   idRessource: userId, details: ExportRGPD.auditDetails(format), context: context)
        }
    }

    private func memeEpoch() async -> Bool { await session.controller.epoch == snapshot.epoch }
}
