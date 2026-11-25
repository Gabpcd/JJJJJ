import PDFKit
import SwiftUI
import JoleneCore
import JoleneDesign

/// Lecteur PDF de l'app (L4-T10, `LOT4_PLAN.md` §3 T10 : créé ici, le lot 2 n'en livre pas). Affiche des octets
/// **déjà vérifiés** (`PDFVerifie` : type, taille et SHA-256 contrôlés par la gateway) depuis la mémoire : aucun fichier
/// n'est écrit pour la lecture, aucun cache. « Partager » écrit une copie temporaire protégée
/// (`FichierCopieBulletinTemporaire`, protection `complete`, exclue de la sauvegarde), présentée par la seule feuille de
/// partage de l'app (`ShareSheet.presenter(fichier:)`) et effacée à la fermeture de la feuille comme à celle du lecteur.
/// Aucun octet, nom de fichier ou contenu n'est journalisé.
///
/// Identifiants : `pdf-lecteur` (document), `pdf-partager`, `pdf-fermer`, `pdf-partage-erreur`.
struct PDFLecteur: View {
    let titre: String
    let pdf: PDFVerifie
    let fermer: () -> Void

    @State private var copiePartagee: URL?
    @State private var partageEnCours = false
    @State private var erreur: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let erreur {
                    InlineNotice(erreur, tone: .error, identifier: "pdf-partage-erreur")
                        .padding(JoleneSpacing.md)
                }
                PDFDocumentVue(donnees: pdf.donnees)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(titre)
                    .accessibilityIdentifier("pdf-lecteur")
            }
            .background(JoleneColor.lavender.ignoresSafeArea())
            .navigationTitle(titre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { fermerLecteur() }
                        .accessibilityIdentifier("pdf-fermer")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { partager() } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Partager")
                        .disabled(partageEnCours)
                        .accessibilityIdentifier("pdf-partager")
                }
            }
        }
        .onDisappear { effacerCopie() }
    }

    private func partager() {
        guard !partageEnCours else { return }
        partageEnCours = true
        defer { partageEnCours = false }
        erreur = nil
        effacerCopie()
        do {
            let url = try FichierCopieBulletinTemporaire.ecrire(pdf)
            copiePartagee = url
            let presentee = ShareSheet.presenter(fichier: url) {
                FichierCopieBulletinTemporaire.effacer(url)
            }
            if !presentee {
                effacerCopie()
                erreur = RefusCopieBulletin.indisponible.message
            }
        } catch {
            erreur = RefusCopieBulletin.indisponible.message
        }
    }

    private func fermerLecteur() {
        effacerCopie()
        fermer()
    }

    private func effacerCopie() {
        if let copiePartagee { FichierCopieBulletinTemporaire.effacer(copiePartagee) }
        copiePartagee = nil
    }
}

/// `PDFView` (PDFKit) sur des octets en mémoire.
private struct PDFDocumentVue: UIViewRepresentable {
    let donnees: Data

    func makeUIView(context: Context) -> PDFView {
        let vue = PDFView()
        vue.autoScales = true
        vue.displayMode = .singlePageContinuous
        vue.displayDirection = .vertical
        vue.document = PDFDocument(data: donnees)
        return vue
    }

    func updateUIView(_ vue: PDFView, context: Context) {}
}
