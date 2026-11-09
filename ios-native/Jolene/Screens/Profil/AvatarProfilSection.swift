import SwiftUI
import UIKit
import JoleneCore
import JoleneDesign

/// Photo de profil de « Mon profil » (lot 3, T10), en tête de l'écran comme sur le web (`ProfilSoignant.tsx` l.318-326,
/// `AvatarUpload` 96 px, `rounded-full`). « Changer ma photo de profil » ouvre un choix en ligne (photothèque ;
/// appareil photo s'il existe) ; la photo choisie est convertie puis envoyée par `AvatarProfilModel` (reçu durable,
/// relecture de `avatar_url`). En démo, aucune feuille système : les deux sources rendent la photo de démonstration
/// (`DemoFixtures.avatarDemo()`, HEIC de synthèse), et l'appareil photo est proposé.
///
/// Identifiants : `profil-avatar` (vignette), `profil-avatar-changer`, `profil-avatar-phototheque`,
/// `profil-avatar-camera`, `profil-avatar-annuler`, `profil-avatar-avis` (succès ou refus) ; DEBUG démo seulement :
/// `profil-avatar-etat` (« photo » ou « initiales », jamais l'URL).
struct AvatarProfilSection: View {
    @ObservedObject var model: AvatarProfilModel
    let prenom: String
    let nom: String
    let estDemo: Bool
    @State private var choixOuvert = false
    @State private var source: SourcePhotoAvatar?

    private typealias Textes = AvatarProfil.Textes

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            HStack(spacing: JoleneSpacing.lg) {
                AvatarView(image: image, prenom: prenom, nom: nom, size: 96, isLoading: model.envoiEnCours,
                           identifier: "profil-avatar")
                JoleneButton(Textes.changerPhoto, style: .secondary, isLoading: model.envoiEnCours) {
                    choixOuvert.toggle()
                }
                .disabled(model.envoiEnCours)
                .accessibilityIdentifier("profil-avatar-changer")
            }
            if choixOuvert && !model.envoiEnCours { choix }
            if let avis = model.avis {
                switch avis {
                case let .succes(message):
                    InlineNotice(message, tone: .success, identifier: "profil-avatar-avis", announcesOnAppear: true,
                                 announcementID: model.annonces)
                case let .erreur(message):
                    InlineNotice(message, tone: .error, identifier: "profil-avatar-avis", announcesOnAppear: true,
                                 announcementID: model.annonces)
                }
            }
        }
        .sheet(item: $source) { source in
            switch source {
            case .phototheque:
                SelecteurPhotothequeAvatar(choisie: Self.recepteur(model: model, source: $source))
                    .ignoresSafeArea()
            case .appareil:
                SelecteurAppareilAvatar(choisie: Self.recepteur(model: model, source: $source))
                    .ignoresSafeArea()
            }
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if estDemo {
                Text(model.image == nil ? "initiales" : "photo")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("profil-avatar-etat")
            }
        }
        #endif
    }

    private var image: Image? {
        model.image.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
    }

    private var choix: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            JoleneButton(Textes.choisirPhototheque, style: .secondary) { choisir(.phototheque) }
                .accessibilityIdentifier("profil-avatar-phototheque")
            if estDemo || SourcePhotoAvatar.appareilDisponible {
                JoleneButton(Textes.prendrePhoto, style: .secondary) { choisir(.appareil) }
                    .accessibilityIdentifier("profil-avatar-camera")
            }
            Button(Textes.annuler) { choixOuvert = false }
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.rose800)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("profil-avatar-annuler")
        }
    }

    private func choisir(_ choisie: SourcePhotoAvatar) {
        choixOuvert = false
        if estDemo {
            // Aucune feuille système en démo : la photo de démonstration est la source des deux options.
            guard let octets = try? DemoFixtures.avatarDemo() else { return }
            let model = self.model
            Task { await model.changer(source: octets) }
        } else {
            source = choisie
        }
    }

    /// Réception d'un sélecteur : la feuille se ferme, puis la photo choisie est envoyée (annulation : rien n'est envoyé).
    private static func recepteur(model: AvatarProfilModel,
                                  source: Binding<SourcePhotoAvatar?>) -> @MainActor @Sendable (Data?) -> Void {
        { octets in
            source.wrappedValue = nil
            guard let octets else { return }
            Task { await model.changer(source: octets) }
        }
    }
}
