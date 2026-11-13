import Foundation
import Combine

/// Photo de l'écran « Mon profil » (lot 3, T10). Règles :
/// - `demarrer(avatarUrl:)` à la lecture du profil : réconciliation d'un envoi interrompu (`gateways.avatar`,
///   relecture de `avatar_url`, jamais de renvoi ; un reçu illisible est retiré, revue B8 m8), puis lecture des octets
///   de l'avatar relu. « Changer ma photo » reste inactif jusqu'à la fin de cette réconciliation (`peutChanger`,
///   revue B8 m6) : deux réconciliations du même reçu ne s'entrelacent jamais ;
/// - `recevoir(_:)` : issue du sélecteur (revue B8 M1) — annulation silencieuse ; fichier choisi mais illisible →
///   « Impossible de lire le fichier sélectionné. » (web) ; `lectureCommencee()` pose l'indicateur pendant la lecture
///   des octets (photo iCloud) ;
/// - `changer(source:)` : conversion JPEG 256 px (`ConversionAvatar`, hors du thread principal), puis un seul envoi
///   (`televerser`) borné au budget propre de l'envoi (`AvatarProfil.delaiEnvoi`, revue B8 m7) ; succès annoncé
///   (« Photo mise à jour ! ») seulement sur l'URL RELUE ; refus certain (`RefusAvatar`, conversion refusée) affiché
///   tel quel ; issue inconnue (délai, réseau, 5xx) → message d'échec du web, puis réconciliation (relecture) : la
///   photo n'est annoncée que si le profil la porte ;
/// - epoch d'identité vérifié avant toute publication (même règle que `ProfilEditionModel`).
@MainActor
public final class AvatarProfilModel: ObservableObject {
    public enum Avis: Equatable, Sendable {
        case succes(String)
        case erreur(String)
    }

    @Published public private(set) var avatarUrl: String?
    /// Octets affichés : JPEG envoyé (succès) ou image relue à l'URL du profil.
    @Published public private(set) var image: Data?
    @Published public private(set) var envoiEnCours = false
    /// Photo choisie dont les octets sont en cours de lecture (feuille déjà fermée) : indicateur sur la vignette.
    @Published public private(set) var lectureEnCours = false
    /// Réconciliation d'ouverture en cours (`demarrer`) : « Changer ma photo » inactif.
    @Published public private(set) var reconciliationEnCours = false
    @Published public private(set) var avis: Avis?
    /// Jeton d'annonce VoiceOver de l'encart (`InlineNotice.announcementID`).
    @Published public private(set) var annonces = 0

    private let session: SessionStore
    private let snapshot: SessionSnapshot
    private var demarre = false

    public init(session: SessionStore, snapshot: SessionSnapshot) {
        self.session = session
        self.snapshot = snapshot
    }

    /// « Changer ma photo de profil » actif : ni réconciliation d'ouverture, ni lecture, ni envoi en cours.
    public var peutChanger: Bool { !reconciliationEnCours && !lectureEnCours && !envoiEnCours }

    /// Première lecture du profil (une fois par instance) : réconciliation puis image.
    public func demarrer(avatarUrl: String?) async {
        guard !demarre else { return }
        demarre = true
        self.avatarUrl = avatarUrl
        reconciliationEnCours = true
        guard let gateways = await session.controller.gateways(for: snapshot.epoch) else {
            reconciliationEnCours = false
            return
        }
        let port = gateways.avatar
        let context = snapshot.context
        // Erreur de la réconciliation (trousseau momentanément indisponible) : rien à annoncer à l'ouverture, aucun envoi
        // n'ayant été demandé ; le reçu est conservé et l'envoi suivant reste fail-closed (EnvoiAvatar).
        let issue = try? await bounded(timeout: session.controller.resolutionTimeout) { try await port.reconcilier(context: context) }
        reconciliationEnCours = false
        guard await memeEpoch() else { return }
        if let issue { appliquer(issue) }
        await chargerImage(port)
    }

    /// Photo choisie, octets en cours de lecture (le sélecteur est déjà fermé) : indicateur jusqu'à `recevoir`.
    public func lectureCommencee() {
        guard peutChanger else { return }
        avis = nil
        lectureEnCours = true
    }

    /// Issue du sélecteur (photothèque ou appareil photo).
    public func recevoir(_ selection: SelectionPhotoAvatar) async {
        switch selection {
        case .lectureEnCours:
            lectureCommencee()
        case .annulee:
            lectureEnCours = false
        case .illisible:
            lectureEnCours = false
            guard await memeEpoch() else { return }
            publier(.erreur(AvatarProfil.Textes.fichierIllisible))
        case let .octets(source):
            lectureEnCours = false
            await changer(source: source)
        }
    }

    /// Photo lue (photothèque ou appareil) : conversion puis envoi unique. Ignorée pendant un envoi ou la réconciliation
    /// d'ouverture (le bouton est alors inactif).
    public func changer(source: Data) async {
        guard !envoiEnCours, !reconciliationEnCours else { return }
        lectureEnCours = false
        envoiEnCours = true
        defer { envoiEnCours = false }
        avis = nil
        let jpeg: Data
        do {
            jpeg = try await Task.detached(priority: .userInitiated) { try ConversionAvatar.jpeg(depuis: source) }.value
        } catch let erreur as ConversionAvatar.Erreur {
            guard await memeEpoch() else { return }
            publier(.erreur(ConversionAvatar.message(erreur)))
            return
        } catch {
            guard await memeEpoch() else { return }
            publier(.erreur(AvatarProfil.Textes.fichierIllisible))
            return
        }
        guard let gateways = await session.controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.avatar
        let context = snapshot.context
        do {
            let url = try await bounded(timeout: AvatarProfil.delaiEnvoi(resolution: session.controller.resolutionTimeout)) {
                try await port.televerser(jpeg: jpeg, context: context)
            }
            guard await memeEpoch() else { return }
            avatarUrl = url.absoluteString
            image = jpeg
            publier(.succes(AvatarProfil.Textes.succes))
        } catch let refus as RefusAvatar {
            guard await memeEpoch() else { return }
            publier(.erreur(refus.message))
        } catch {
            guard await memeEpoch(), !(error is CancellationError) else { return }
            let jolene = error as? JoleneError
            if jolene?.kind == .cancelled { return }
            publier(.erreur(jolene?.kind == .unauthorized ? jolene?.message ?? AvatarProfil.Textes.echecEnvoi
                                                         : AvatarProfil.Textes.echecEnvoi))
            // Issue inconnue : le profil a pu être lié. Relecture, jamais de second envoi.
            guard jolene?.kind != .unauthorized,
                  let issue = try? await bounded(timeout: session.controller.resolutionTimeout, { try await port.reconcilier(context: context) }),
                  await memeEpoch() else { return }
            if case let .confirmee(relue) = issue {
                avatarUrl = relue.absoluteString
                image = jpeg
                publier(.succes(AvatarProfil.Textes.succes))
            }
        }
    }

    public func effacerAvis() { avis = nil }

    // MARK: - Interne

    private func appliquer(_ issue: ReconciliationAvatar) {
        switch issue {
        case .aucune:
            return
        case let .confirmee(url):
            avatarUrl = url.absoluteString
            publier(.succes(AvatarProfil.Textes.succes))
        case .nonConfirmee:
            publier(.erreur(AvatarProfil.Textes.echecEnvoi))
        }
    }

    private func chargerImage(_ port: AvatarStoragePort) async {
        guard image == nil, let avatarUrl, let url = URL(string: avatarUrl) else { return }
        let octets = await port.image(url: url)
        guard await memeEpoch(), self.avatarUrl == avatarUrl, image == nil else { return }
        image = octets
    }

    private func publier(_ nouvel: Avis) {
        avis = nouvel
        annonces += 1
    }

    private func memeEpoch() async -> Bool { await session.controller.epoch == snapshot.epoch }
}
