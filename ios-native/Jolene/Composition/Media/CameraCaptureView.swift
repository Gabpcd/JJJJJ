import SwiftUI
import UIKit
import JoleneCore

/// Appareil photo (`UIImagePickerController`, `.camera` ; décision 13) : la photo devient `jpegData(0.8)` — pixels seuls,
/// aucune métadonnée —, nommée `photo_<ms>.jpg` comme le web natif (`ModalTeleversement.tsx` l.102). Présenté plein écran
/// par la feuille de téléversement, seulement si l'appareil a une caméra (sinon message du web, l.106). La permission est
/// demandée par le système (`NSCameraUsageDescription`, texte verrouillé du lot 0).
struct CameraCaptureView: UIViewControllerRepresentable {
    let rendre: @MainActor @Sendable (IssueSelection) -> Void

    static var disponible: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinateur { Coordinateur(rendre: rendre) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinateur: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let rendre: @MainActor @Sendable (IssueSelection) -> Void

        init(rendre: @escaping @MainActor @Sendable (IssueSelection) -> Void) {
            self.rendre = rendre
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage, let jpeg = image.jpegData(compressionQuality: 0.8) else {
                rendre(.echec)
                return
            }
            rendre(.choisi(FichierSelectionne.photo(jpeg: jpeg, prisLe: Date())))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            rendre(.annule)
        }
    }
}
