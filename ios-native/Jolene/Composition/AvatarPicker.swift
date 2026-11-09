import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import JoleneCore

/// Sources de la photo de profil (lot 3, T10) : photothèque (`PHPickerViewController`, hors processus : aucune
/// autorisation d'accès aux photos demandée, aucune chaîne `NSPhotoLibraryUsageDescription` requise) et appareil photo
/// (`UIImagePickerController`, chaîne `NSCameraUsageDescription`). Rendent les OCTETS d'origine (HEIC d'iPhone compris) :
/// la conversion JPEG 256 px est faite par `ConversionAvatar` (JoleneCore), jamais ici. Aucun octet n'est journalisé.
///
/// Issue rendue (revue B8 de T10, M1) : `SelectionPhotoAvatar` — l'ANNULATION (aucun résultat, « Annuler ») n'est jamais
/// confondue avec l'ÉCHEC de lecture d'une photo choisie (photo iCloud non téléchargeable hors ligne, représentation
/// illisible, prise de vue non encodable), qui affiche le message du web. `.lectureEnCours` est rendue AVANT la lecture
/// des octets, de façon synchrone sur le fil principal : la feuille se ferme et la vignette montre un indicateur ; l'issue
/// finale arrive toujours après.
/// Point de fusion avec le lot 2 (`Jolene/Composition/Media/PhotoPickerView.swift`, justificatifs) : deux sélecteurs aux
/// usages distincts (photo de profil 256 px / pièce justificative), à unifier si leurs contrats convergent.
enum SourcePhotoAvatar: Identifiable {
    case phototheque
    case appareil

    var id: Self { self }

    /// L'appareil photo n'existe pas sur le simulateur ni sur certains iPad : l'option n'est alors pas proposée.
    @MainActor static var appareilDisponible: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
}

/// Photothèque : une image, octets de la représentation d'origine (`public.image`).
struct SelecteurPhotothequeAvatar: UIViewControllerRepresentable {
    let choisie: @MainActor @Sendable (SelectionPhotoAvatar) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let selecteur = PHPickerViewController(configuration: configuration)
        selecteur.delegate = context.coordinator
        return selecteur
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinateur { Coordinateur(choisie: choisie) }

    @MainActor
    final class Coordinateur: NSObject, PHPickerViewControllerDelegate {
        let choisie: @MainActor @Sendable (SelectionPhotoAvatar) -> Void

        init(choisie: @escaping @MainActor @Sendable (SelectionPhotoAvatar) -> Void) { self.choisie = choisie }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Aucun résultat : feuille fermée sans choix (annulation), ni message ni envoi.
            guard let fournisseur = results.first?.itemProvider else {
                choisie(.annulee)
                return
            }
            // Un résultat qui n'est pas une image (filtre `.images` contourné) : fichier choisi, illisible.
            guard fournisseur.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                choisie(.illisible)
                return
            }
            // Indicateur AVANT la lecture (synchrone, fil principal) : l'issue finale arrive toujours après.
            choisie(.lectureEnCours)
            let rendre = choisie
            fournisseur.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { @Sendable donnees, erreur in
                // Données absentes ou erreur (photo iCloud indisponible hors ligne…) : échec de lecture, jamais annulation.
                let issue: SelectionPhotoAvatar = erreur == nil ? donnees.map(SelectionPhotoAvatar.octets) ?? .illisible : .illisible
                Task { @MainActor in rendre(issue) }
            }
        }
    }
}

/// Appareil photo : photo prise, réencodée sans perte notable (qualité 1) pour la conversion qui suit. Présenté en plein
/// écran (`fullScreenCover`, revue B8 de T10, m13), jamais en feuille de formulaire sur iPad.
struct SelecteurAppareilAvatar: UIViewControllerRepresentable {
    let choisie: @MainActor @Sendable (SelectionPhotoAvatar) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let selecteur = UIImagePickerController()
        selecteur.sourceType = .camera
        selecteur.cameraCaptureMode = .photo
        selecteur.allowsEditing = false
        selecteur.delegate = context.coordinator
        return selecteur
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinateur { Coordinateur(choisie: choisie) }

    @MainActor
    final class Coordinateur: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let choisie: @MainActor @Sendable (SelectionPhotoAvatar) -> Void

        init(choisie: @escaping @MainActor @Sendable (SelectionPhotoAvatar) -> Void) { self.choisie = choisie }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Photo prise mais non encodable : échec de lecture, jamais annulation.
            let octets = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 1)
            choisie(octets.map(SelectionPhotoAvatar.octets) ?? .illisible)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            choisie(.annulee)
        }
    }
}
