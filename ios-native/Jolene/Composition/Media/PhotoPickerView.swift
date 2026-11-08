import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import JoleneCore

/// Photothèque (`PHPickerViewController`, images seules, une sélection ; décision 13) : sélecteur hors processus, sans
/// permission photothèque. L'image garde ses métadonnées (GPS compris) jusqu'à `FichierSelectionne.preparer()`, qui la
/// ré-encode toujours en JPEG sans métadonnée (`SourceFichier.phototheque`, comme le web natif, Capacitor qualité 80).
/// Échec de chargement : message du web (`ModalTeleversement.tsx` l.158).
struct PhotoPickerView: UIViewControllerRepresentable {
    let rendre: @MainActor @Sendable (IssueSelection) -> Void

    func makeCoordinator() -> Coordinateur { Coordinateur(rendre: rendre) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}

    @MainActor
    final class Coordinateur: NSObject, PHPickerViewControllerDelegate {
        private let rendre: @MainActor @Sendable (IssueSelection) -> Void

        init(rendre: @escaping @MainActor @Sendable (IssueSelection) -> Void) {
            self.rendre = rendre
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let fournisseur = results.first?.itemProvider else {
                rendre(.annule)
                return
            }
            guard let type = fournisseur.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
                rendre(.echec)
                return
            }
            let nom = fournisseur.suggestedName
            let rendre = self.rendre
            _ = fournisseur.loadDataRepresentation(forTypeIdentifier: type) { octets, _ in
                let issue: IssueSelection = octets.map {
                    .choisi(FichierSelectionne.galerie(octets: $0, typeIdentifier: type, nomSuggere: nom, choisiLe: Date()))
                } ?? .echec
                Task { @MainActor in rendre(issue) }
            }
        }
    }
}
