import SwiftUI
import UIKit
import JoleneCore
import JoleneDesign

/// Photo de profil de « Mon profil » (lot 3, T10), en tête de l'écran comme sur le web (`ProfilSoignant.tsx` l.318-326,
/// `AvatarUpload` 96 px, `rounded-full`). « Changer ma photo de profil » ouvre un choix en ligne (photothèque ;
/// appareil photo s'il existe) ; la photo choisie est convertie puis envoyée par `AvatarProfilModel` (reçu durable,
/// relecture de `avatar_url`). En démo, aucune feuille système : les deux sources rendent `selectionDemo` (photo de
/// démonstration `DemoFixtures.avatarDemo()`, HEIC de synthèse, ou lecture impossible simulée), et l'appareil photo est
/// proposé.
///
/// Revue B8 de T10 : l'issue du sélecteur (`SelectionPhotoAvatar`) distingue l'annulation (silencieuse) de l'échec de
/// lecture (message du web, M1) ; la vignette montre un indicateur pendant la lecture des octets (photo iCloud) et
/// pendant l'envoi ; « Changer ma photo » reste inactif pendant la réconciliation d'ouverture (m6) ; l'appareil photo
/// est présenté en plein écran (`fullScreenCover`, m13), la photothèque en feuille.
///
/// Identifiants : `profil-avatar` (vignette), `profil-avatar-changer`, `profil-avatar-phototheque`,
/// `profil-avatar-camera`, `profil-avatar-annuler`, `profil-avatar-avis` (succès ou refus) ; DEBUG démo seulement :
/// `profil-avatar-etat` (« photo » ou « initiales », jamais l'URL).
struct AvatarProfilSection: View {
    @ObservedObject var model: AvatarProfilModel
    let prenom: String
    let nom: String
    /// Démo seulement (nil en staging et en production) : issue des deux sources, sans feuille système.
    let selectionDemo: SelectionPhotoAvatar?
    @State private var choixOuvert = false
    @State private var source: SourcePhotoAvatar?

    private typealias Textes = AvatarProfil.Textes

    private var estDemo: Bool { selectionDemo != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            HStack(spacing: JoleneSpacing.lg) {
                AvatarView(image: image, prenom: prenom, nom: nom, size: 96,
                           isLoading: model.envoiEnCours || model.lectureEnCours, identifier: "profil-avatar")
                JoleneButton(Textes.changerPhoto, style: .secondary, isLoading: model.envoiEnCours || model.lectureEnCours) {
                    choixOuvert.toggle()
                }
                .disabled(!model.peutChanger)
                .accessibilityIdentifier("profil-avatar-changer")
            }
            if choixOuvert && model.peutChanger { choix }
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
        .sheet(isPresented: presentation(.phototheque)) {
            SelecteurPhotothequeAvatar(choisie: Self.recepteur(model: model, source: $source))
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: presentation(.appareil)) {
            SelecteurAppareilAvatar(choisie: Self.recepteur(model: model, source: $source))
                .ignoresSafeArea()
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

    /// Présentation d'une source : la photothèque en feuille, l'appareil photo en plein écran (m13).
    private func presentation(_ cible: SourcePhotoAvatar) -> Binding<Bool> {
        Binding(get: { source == cible },
                set: { presente in if !presente, source == cible { source = nil } })
    }

    private func choisir(_ choisie: SourcePhotoAvatar) {
        choixOuvert = false
        if let selectionDemo {
            // Aucune feuille système en démo : la même issue pour les deux options.
            let model = self.model
            model.lectureCommencee()
            Task { await model.recevoir(selectionDemo) }
        } else {
            source = choisie
        }
    }

    /// Réception d'un sélecteur : la feuille se ferme à toute issue. `.lectureEnCours` est appliquée sur-le-champ
    /// (indicateur) ; annulation, échec de lecture et octets lus passent par `recevoir` (message du web pour l'échec).
    private static func recepteur(model: AvatarProfilModel,
                                  source: Binding<SourcePhotoAvatar?>) -> @MainActor @Sendable (SelectionPhotoAvatar) -> Void {
        { selection in
            source.wrappedValue = nil
            if selection == .lectureEnCours {
                model.lectureCommencee()
            } else {
                Task { await model.recevoir(selection) }
            }
        }
    }
}
