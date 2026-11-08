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

    /// Retire les sous-dossiers d'export restés sous la racine (seuls ceux du préfixe).
    public func purgerResidus() {
        let contenu = (try? FileManager.default.contentsOfDirectory(at: racine, includingPropertiesForKeys: nil)) ?? []
        for element in contenu where element.lastPathComponent.hasPrefix(Self.prefixe) {
            try? FileManager.default.removeItem(at: element)
        }
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
/// - fermeture de la feuille : fichier supprimé ; « Données exportées en JSON. » seulement si le partage est
///   allé à son terme (le web l'annonce même sur une feuille fermée sans partage, écart consigné) ;
/// - toute réponse d'un epoch périmé est ignorée (aucun fichier pour une identité partie).
@MainActor
public final class ExportRGPDModel: ObservableObject {
    @Published public private(set) var enCours: FormatExportRGPD?
    @Published public private(set) var partage: FichierAPartager?
    @Published public private(set) var succes: String?
    @Published public private(set) var erreur: String?
    @Published public private(set) var sessionExpiree = false
    /// Jeton d'annonce VoiceOver des encarts (`InlineNotice.announcementID`).
    @Published public private(set) var annonces = 0

    private let session: SessionStore
    private let snapshot: SessionSnapshot
    private let dossier: DossierExportTemporaire

    public init(session: SessionStore, snapshot: SessionSnapshot, dossier: DossierExportTemporaire = .systeme) {
        self.session = session
        self.snapshot = snapshot
        self.dossier = dossier
        dossier.purgerResidus()
    }

    /// Les deux boutons sont actifs hors export et hors feuille ouverte.
    public var peutExporter: Bool { enCours == nil && partage == nil }

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

    /// Fermeture de la feuille de partage (`complete` : un partage est allé à son terme). Sans effet si aucun
    /// fichier n'est proposé (la vue peut relayer deux fois la même fermeture).
    public func partageTermine(complete: Bool) {
        guard let fichier = partage else { return }
        dossier.supprimer(fichier.url)
        partage = nil
        if complete {
            succes = ExportRGPD.Textes.succes(fichier.format)
            annonces += 1
        }
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
