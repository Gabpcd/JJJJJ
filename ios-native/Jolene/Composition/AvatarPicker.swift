import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Sources de la photo de profil (lot 3, T10) : photothèque (`PHPickerViewController`, hors processus : aucune
/// autorisation d'accès aux photos demandée, aucune chaîne `NSPhotoLibraryUsageDescription` requise) et appareil photo
/// (`UIImagePickerController`, chaîne `NSCameraUsageDescription`). Rendent les OCTETS d'origine (HEIC d'iPhone compris) :
/// la conversion JPEG 256 px est faite par `ConversionAvatar` (JoleneCore), jamais ici. Aucun octet n'est journalisé.
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
    let choisie: @MainActor @Sendable (Data?) -> Void

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

    final class Coordinateur: NSObject, PHPickerViewControllerDelegate {
        let choisie: @MainActor @Sendable (Data?) -> Void

        init(choisie: @escaping @MainActor @Sendable (Data?) -> Void) { self.choisie = choisie }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let rendre = choisie
            guard let fournisseur = results.first?.itemProvider,
                  fournisseur.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                Task { @MainActor in rendre(nil) }
                return
            }
            fournisseur.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { donnees, _ in
                Task { @MainActor in rendre(donnees) }
            }
        }
    }
}

/// Appareil photo : photo prise, réencodée sans perte notable (qualité 1) pour la conversion qui suit.
struct SelecteurAppareilAvatar: UIViewControllerRepresentable {
    let choisie: @MainActor @Sendable (Data?) -> Void

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

    final class Coordinateur: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let choisie: @MainActor @Sendable (Data?) -> Void

        init(choisie: @escaping @MainActor @Sendable (Data?) -> Void) { self.choisie = choisie }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let octets = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 1)
            let rendre = choisie
            Task { @MainActor in rendre(octets) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            let rendre = choisie
            Task { @MainActor in rendre(nil) }
        }
    }
}
