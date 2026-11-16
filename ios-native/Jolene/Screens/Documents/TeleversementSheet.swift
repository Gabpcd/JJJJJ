import SwiftUI
import UIKit
import JoleneCore
import JoleneDesign

/// Demande d'ouverture de la feuille de téléversement pour un type proposé par l'écran.
struct DemandeTeleversement: Identifiable, Equatable {
    let typeDocument: String
    var id: String { typeDocument }
}

/// Feuille de téléversement (lot 2 T7), port de `src/components/ModalTeleversement.tsx` : appareil photo, photothèque ou
/// Fichiers (variante démo `DemoMediaPicker`), préparation immédiate (`FichierSelectionne.preparer()` : HEIC/HEIF et
/// photothèque → JPEG sans métadonnée, contrôle du web), libellé optionnel (≤ 500, exemples `PLACEHOLDERS_LIBELLE`), puis
/// l'unique envoi par `DocumentsModel.envoyer` (reçu journalisé avant l'upload, aucun renvoi). Fermée sur un document
/// enregistré ou en vérification ; ouverte sur un refus, avec le message du web.
///
/// Identifiants : `document-televersement` (+ `-titre`, `-type`), `document-source-camera`, `document-source-galerie`,
/// `document-source-fichiers`, `document-fichier-choisi`, `document-fichier-taille`, `document-fichier-erreur`,
/// `document-envoi-erreur`, `document-libelle`, `document-annuler`, `document-confirmer`.
struct TeleversementSheet: View {
    private typealias L = LibellesJustificatifs

    let typeDocument: String
    @ObservedObject var model: DocumentsModel
    let mediaDemo: DemoMediaPicker?
    @Environment(\.dismiss) private var dismiss

    @State private var fichier: FichierPret?
    @State private var erreurFichier: String?
    @State private var messageEnvoi: TexteJustificatif?
    @State private var libelle = ""
    @State private var selecteur: Selecteur?
    @State private var cameraOuverte = false
    @State private var preparation = false
    /// L'utilisateur a confirmé : l'issue de l'envoi (le sien, ou celui d'une autre instance en vol) est attendue.
    @State private var envoiDemande = false
    @State private var envoiLance = false

    private enum Selecteur: String, Identifiable {
        case galerie, fichiers
        var id: String { rawValue }
    }

    private var enCours: Bool {
        if envoiLance { return true }
        if case .enCours = model.envoi { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                    entete
                    sources
                    fichierChoisi
                    if let erreurFichier {
                        InlineNotice(erreurFichier, tone: .error, identifier: "document-fichier-erreur", announcesOnAppear: true)
                    }
                    if let messageEnvoi {
                        InlineNotice(messageEnvoi.texte, tone: TonsJustificatifs.notice(messageEnvoi.ton), identifier: "document-envoi-erreur",
                                     announcesOnAppear: true)
                    }
                    champLibelle
                    boutons
                }
                .padding(JoleneSpacing.lg)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("document-televersement")
            .background(JoleneColor.lavender.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L.fermerAccessibilite)
                        .disabled(enCours)
                }
            }
        }
        .interactiveDismissDisabled(enCours)
        .fullScreenCover(isPresented: $cameraOuverte) {
            CameraCaptureView { issue in
                cameraOuverte = false
                recevoir(issue, origine: .camera)
            }
            .ignoresSafeArea()
        }
        .sheet(item: $selecteur) { choix in
            switch choix {
            case .galerie:
                PhotoPickerView { issue in
                    selecteur = nil
                    recevoir(issue, origine: .phototheque)
                }
                .ignoresSafeArea()
            case .fichiers:
                DocumentPickerView { issue in
                    selecteur = nil
                    recevoir(issue, origine: .fichiers)
                }
                .ignoresSafeArea()
            }
        }
        .onChange(of: model.envoi) { etat in
            // Envoi d'une autre instance (écran rouvert, autre fenêtre) suivi jusqu'à son issue.
            guard envoiDemande, !envoiLance else { return }
            conclure(etat)
        }
    }

    // MARK: - Sections

    private var entete: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(L.televerserTitre)
                .font(JoleneFont.title)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("document-televersement-titre")
            Text(L.libelleType(typeDocument))
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("document-televersement-type")
            Text(L.aidePhoto)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sources: some View {
        VStack(spacing: JoleneSpacing.sm) {
            JoleneButton(L.prendrePhoto) { choisir(.camera) }
                .accessibilityIdentifier("document-source-camera")
            JoleneButton(L.choisirGalerie, style: .secondary) { choisir(.phototheque) }
                .accessibilityIdentifier("document-source-galerie")
            Button { choisir(.fichiers) } label: {
                Text(L.choisirFichier)
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.rose800)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.choisirFichierAccessibilite)
            .accessibilityIdentifier("document-source-fichiers")
        }
        .disabled(enCours || preparation)
    }

    @ViewBuilder private var fichierChoisi: some View {
        if let fichier {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                Text(PresentationJustificatifs.fichierChoisi(nom: fichier.fichier.nom))
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityIdentifier("document-fichier-choisi")
                Text(PresentationJustificatifs.taille(octets: fichier.fichier.tailleOctets))
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("document-fichier-taille")
            }
            .padding(JoleneSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        } else if preparation {
            ProgressView().tint(JoleneColor.rose700).frame(maxWidth: .infinity)
        } else {
            Text(L.formats)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityLabel(L.formatsAccessibilite)
        }
    }

    private var champLibelle: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(L.libelleOptionnel)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityHidden(true)
            TextField(L.placeholder(typeDocument: typeDocument), text: $libelle)
                .font(JoleneFont.body)
                .padding(JoleneSpacing.md)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .submitLabel(.done)
                .accessibilityLabel(L.libelleOptionnel)
                .accessibilityIdentifier("document-libelle")
                .onChange(of: libelle) { saisi in
                    // Borne serveur en points de code (`fn_remplacer_document_soignant`) : jamais au-delà.
                    if saisi.unicodeScalars.count > L.libelleMax {
                        libelle = String(String.UnicodeScalarView(saisi.unicodeScalars.prefix(L.libelleMax)))
                    }
                }
                .disabled(enCours)
        }
    }

    private var boutons: some View {
        HStack(spacing: JoleneSpacing.md) {
            JoleneButton(L.annuler, style: .secondary) { dismiss() }
                .disabled(enCours)
                .accessibilityIdentifier("document-annuler")
            JoleneButton(enCours ? L.envoi : L.televerser, isLoading: enCours) { confirmer() }
                .disabled(fichier == nil || enCours || preparation)
                .accessibilityIdentifier("document-confirmer")
        }
        .padding(.top, JoleneSpacing.sm)
    }

    // MARK: - Sélection

    private func choisir(_ origine: SourceFichier) {
        messageEnvoi = nil
        if let mediaDemo {
            recevoir(mediaDemo.choisir(origine), origine: origine)
            return
        }
        switch origine {
        case .camera:
            guard CameraCaptureView.disponible else {
                erreurFichier = L.cameraImpossible
                return
            }
            cameraOuverte = true
        case .phototheque:
            selecteur = .galerie
        case .fichiers:
            selecteur = .fichiers
        }
    }

    private func recevoir(_ issue: IssueSelection, origine: SourceFichier) {
        switch issue {
        case .annule:
            return
        case .echec:
            fichier = nil
            erreurFichier = origine == .camera ? L.cameraImpossible
                : origine == .phototheque ? L.galerieImpossible : MessagesDocuments.erreurGenerique
        case let .choisi(choisi):
            preparation = true
            Task {
                // ImageIO (HEIC → JPEG) hors du fil principal.
                let resultat = await Task.detached(priority: .userInitiated) { choisi.preparer() }.value
                preparation = false
                switch resultat {
                case let .pret(pret):
                    fichier = pret
                    erreurFichier = nil
                case let .refuse(_, message):
                    fichier = nil
                    erreurFichier = message
                }
            }
        }
    }

    // MARK: - Envoi

    private func confirmer() {
        guard let fichier, !enCours else { return }
        envoiDemande = true
        envoiLance = true
        messageEnvoi = nil
        let saisi = libelle
        Task {
            await model.envoyer(typeDocument: typeDocument, fichier: fichier, libelle: saisi)
            envoiLance = false
            conclure(model.envoi)
        }
    }

    /// Issue de l'envoi demandé : feuille fermée (document enregistré ou en vérification), sinon message dans la feuille ;
    /// un envoi « non reçu » demande une nouvelle sélection (aucun octet conservé, décision 14).
    private func conclure(_ etat: DocumentsModel.EtatEnvoi) {
        guard envoiDemande else { return }
        if case .enCours = etat { return }
        envoiDemande = false
        if PresentationJustificatifs.fermeLeTeleversement(etat) {
            dismiss()
            return
        }
        messageEnvoi = PresentationJustificatifs.messageEnvoi(etat)
        if case .termine(.nonEnvoye) = etat { fichier = nil }
    }
}

/// Correspondance des tons de la présentation (Core) vers les composants (JoleneDesign).
enum TonsJustificatifs {
    static func notice(_ ton: TonJustificatif) -> InlineNotice.Tone {
        switch ton {
        case .succes: return .success
        case .attention: return .warning
        case .erreur: return .error
        case .info, .neutre: return .info
        }
    }

    static func badge(_ ton: TonJustificatif) -> StatusBadge.Tone {
        switch ton {
        case .succes: return .success
        case .attention: return .warning
        case .erreur: return .error
        case .info: return .info
        case .neutre: return .neutral
        }
    }
}
