import SwiftUI
import UIKit
import UniformTypeIdentifiers
import JoleneCore

/// Fichiers (`UIDocumentPickerViewController`, PDF, JPEG, PNG, WebP ; décision 13), formats acceptés par le web
/// (`ModalTeleversement.tsx` l.190). Copie sécurisée (`asCopy`) lue en mémoire puis effacée : aucun octet de document ne
/// reste sur disque (décision 14). Octets inchangés jusqu'au contrôle du web (`SourceFichier.fichiers`), sauf un HEIC.
struct DocumentPickerView: UIViewControllerRepresentable {
    let rendre: @MainActor @Sendable (IssueSelection) -> Void

    static let types: [UTType] = [.pdf, .jpeg, .png, .webP]

    func makeCoordinator() -> Coordinateur { Coordinateur(rendre: rendre) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: Self.types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}

    @MainActor
    final class Coordinateur: NSObject, UIDocumentPickerDelegate {
        private let rendre: @MainActor @Sendable (IssueSelection) -> Void

        init(rendre: @escaping @MainActor @Sendable (IssueSelection) -> Void) {
            self.rendre = rendre
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                rendre(.annule)
                return
            }
            let accede = url.startAccessingSecurityScopedResource()
            defer {
                if accede { url.stopAccessingSecurityScopedResource() }
                // Copie du sélecteur (`asCopy`) : effacée dès la lecture, aucun octet conservé.
                try? FileManager.default.removeItem(at: url)
            }
            // Projection mémoire : un fichier très lourd n'est pas recopié avant le refus « 10 Mo » du web.
            guard let octets = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                rendre(.echec)
                return
            }
            rendre(.choisi(FichierSelectionne.fichier(nom: url.lastPathComponent, octets: octets)))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            rendre(.annule)
        }
    }
}
