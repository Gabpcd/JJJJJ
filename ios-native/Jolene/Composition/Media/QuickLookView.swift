import QuickLook
import SwiftUI
import JoleneCore

/// Consultation d'un justificatif (lot 2 T7) : copie temporaire protégée (`ConsultationDocuments`, `NSFileProtectionComplete`,
/// exclue de la sauvegarde) affichée par QuickLook, jamais une URL distante ni une URL signée. À la fermeture, seule CETTE
/// copie est effacée (revue fraîche de T6, m2 : `effacerTout()` casserait la consultation d'une autre fenêtre iPad) ; les
/// copies d'une identité précédente sont effacées à la première apparition sous un nouvel epoch (`CopiesConsultees`).
struct ConsultationQuickLook: ViewModifier {
    @Binding var copie: URL?
    @State private var affichee: URL?

    func body(content: Content) -> some View {
        content
            .quickLookPreview($copie)
            .onChange(of: copie) { nouvelle in
                if nouvelle != affichee, let ancienne = affichee { CopiesConsultees.effacer(ancienne) }
                affichee = nouvelle
            }
    }
}

extension View {
    /// Présente `copie` dans QuickLook, puis l'efface à la fermeture.
    func consultationQuickLook(_ copie: Binding<URL?>) -> some View {
        modifier(ConsultationQuickLook(copie: copie))
    }
}

/// Copies de consultation de ce processus.
@MainActor
enum CopiesConsultees {
    private static var dernierEpoch: Int?

    /// Première apparition sous un epoch nouveau (connexion, autre identité, relancement) : toute copie restante est effacée.
    static func purgerSiNouvelEpoch(_ epoch: Int) {
        guard dernierEpoch != epoch else { return }
        dernierEpoch = epoch
        ConsultationDocuments.effacerTout()
    }

    /// Efface une copie et son sous-dossier, seulement s'ils sont dans le dossier des consultations.
    static func effacer(_ copie: URL) {
        let dossier = copie.deletingLastPathComponent().standardizedFileURL
        guard dossier.deletingLastPathComponent().path == ConsultationDocuments.dossier.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: dossier)
    }
}
