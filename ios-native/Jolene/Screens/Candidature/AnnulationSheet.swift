import SwiftUI
import UIKit
import JoleneCore
import JoleneDesign

/// Modale d'annulation d'une candidature retenue (lot 1, T7), port de `src/components/soignant/ModaleAnnulationCandidature.tsx` :
/// récapitulatif de la mission, motif structuré, explication (20 caractères au moins, comme le web), justificatif non
/// médical optionnel (photothèque ou Fichiers, préparé par la chaîne du lot 2 et borné à 5 Mo), avertissement sur les
/// données de santé, case « J'ai compris les conséquences », bandeau de notification de l'établissement, puis
/// « Confirmer l'annulation ». Textes de consentement, de santé et de score : `TextesWeb.Annulation` (HARD STOP n°4).
/// Le minuteur de rétractation du web (barème client) n'est pas porté (décision 4) : les conséquences sont celles que
/// rend le serveur, annoncées après la relecture. Fermée sur l'annulation relue.
///
/// Identifiants : `annulation-sheet` (+ `-titre`), `annulation-recap`, `annulation-motif-<MOTIF>`, `annulation-texte`,
/// `annulation-texte-compteur`, `annulation-justificatif-libelle`, `annulation-justificatif-fichiers`,
/// `annulation-justificatif-galerie`, `annulation-justificatif-choisi`, `annulation-justificatif-deja-envoye`,
/// `annulation-justificatif-erreur`, `annulation-avertissement-sante`, `annulation-confirmation`,
/// `annulation-notification-etablissement`, `annulation-erreur`, `annulation-garder`, `annulation-confirmer`.
struct AnnulationSheet: View {
    private typealias L = LibellesAnnulation
    private typealias T = TextesWeb.Annulation

    let candidatureId: String
    let mission: Mission
    @ObservedObject var model: AnnulationModel
    let mediaDemo: DemoMediaPicker?
    @Environment(\.dismiss) private var dismiss

    @State private var motif: AnnulationRules.Motif?
    @State private var texte = ""
    @State private var accepte = false
    @State private var fichier: FichierPret?
    @State private var erreurFichier: String?
    @State private var preparation = false
    @State private var selecteur: Selecteur?
    /// Focus de l'explication : « OK » au-dessus du clavier le ferme sans défilement (`BoutonClavierOK`, « Gel iPhone CI —
    /// 16/11/2026 » de `DECISIONS_LOT2.md` : jamais de fermeture du clavier par un glissement).
    @FocusState private var focusTexte: Bool

    private enum Selecteur: String, Identifiable {
        case galerie, fichiers
        var id: String { rawValue }
    }

    private var justificatifBloque: Bool {
        if case .bloquee = model.issue { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                    Text(L.titreCandidature)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("annulation-sheet-titre")
                    recapitulatif
                    motifs
                    explication
                    justificatif
                    confirmation
                    InlineNotice(T.notificationEtablissement, tone: .warning, identifier: "annulation-notification-etablissement")
                    issue
                    boutons
                }
                .padding(JoleneSpacing.lg)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("annulation-sheet")
            .background(JoleneColor.lavender.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L.garderCandidature)
                        .disabled(model.envoiEnCours)
                }
            }
        }
        .interactiveDismissDisabled(model.envoiEnCours)
        .task { await model.preparerJustificatif(candidatureId: candidatureId) }
        .onChange(of: model.issue) { issue in
            if case .annulee = issue { dismiss() }
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
    }

    // MARK: - Sections

    private var recapitulatif: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(mission.record.intitule).font(JoleneFont.headline).foregroundStyle(JoleneColor.midnight)
            Text(mission.etablissement?.nom ?? "Établissement").font(JoleneFont.callout).foregroundStyle(JoleneColor.bubblegum)
            Text(MissionPresentation.periode(mission)).font(JoleneFont.callout).foregroundStyle(JoleneColor.bubblegum)
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("annulation-recap")
    }

    private var motifs: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(L.motifLibelle).font(JoleneFont.caption.weight(.semibold)).foregroundStyle(JoleneColor.midnight)
            ForEach(AnnulationRules.Motif.allCases) { choix in
                Button {
                    motif = choix
                    model.effacerIssue()
                } label: {
                    HStack {
                        Text(choix.libelle).font(JoleneFont.body).foregroundStyle(JoleneColor.midnight)
                        Spacer()
                        Image(systemName: motif == choix ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(JoleneColor.rose700)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, JoleneSpacing.md)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(JoleneColor.cloud)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.envoiEnCours)
                .accessibilityAddTraits(motif == choix ? .isSelected : [])
                .accessibilityIdentifier("annulation-motif-\(choix.rawValue)")
            }
        }
    }

    private var explication: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(L.explicationLibelle).font(JoleneFont.caption.weight(.semibold)).foregroundStyle(JoleneColor.midnight)
                .accessibilityHidden(true)
            TextField(L.explicationExemple, text: $texte, axis: .vertical)
                .lineLimit(4...8)
                .font(JoleneFont.body)
                .padding(JoleneSpacing.md)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .accessibilityLabel(L.explicationLibelle)
                .accessibilityIdentifier("annulation-texte")
                .focused($focusTexte)
                .boutonOKClavier($focusTexte)
                .disabled(model.envoiEnCours)
                .onChange(of: texte) { _ in model.effacerIssue() }
            Text(AnnulationRules.compteur(texte))
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("annulation-texte-compteur")
        }
    }

    @ViewBuilder private var justificatif: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(T.justificatifLibelle).font(JoleneFont.caption.weight(.semibold)).foregroundStyle(JoleneColor.midnight)
                .accessibilityIdentifier("annulation-justificatif-libelle")
            if let deja = model.justificatifDejaDepose {
                Text(L.fichierDejaEnvoye + " " + deja)
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityIdentifier("annulation-justificatif-deja-envoye")
            } else {
                if let fichier {
                    Text(fichier.fichier.nom)
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityIdentifier("annulation-justificatif-choisi")
                } else if preparation {
                    ProgressView().tint(JoleneColor.rose700).frame(maxWidth: .infinity)
                }
                HStack(spacing: JoleneSpacing.sm) {
                    JoleneButton(L.choisirFichier, style: .secondary) { choisir(.fichiers) }
                        .accessibilityIdentifier("annulation-justificatif-fichiers")
                    JoleneButton(L.choisirPhototheque, style: .secondary) { choisir(.phototheque) }
                        .accessibilityIdentifier("annulation-justificatif-galerie")
                }
                .disabled(model.envoiEnCours || preparation || justificatifBloque)
            }
            if let erreurFichier {
                InlineNotice(erreurFichier, tone: .error, identifier: "annulation-justificatif-erreur", announcesOnAppear: true)
            }
            Text(T.avertissementDonneesSante)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("annulation-avertissement-sante")
        }
    }

    private var confirmation: some View {
        Button {
            accepte.toggle()
            model.effacerIssue()
        } label: {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                Image(systemName: accepte ? "checkmark.square.fill" : "square")
                    .foregroundStyle(JoleneColor.rose700)
                    .accessibilityHidden(true)
                Text(T.confirmationConsequences)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.midnight)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(JoleneSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.envoiEnCours)
        .accessibilityAddTraits(accepte ? .isSelected : [])
        .accessibilityIdentifier("annulation-confirmation")
    }

    @ViewBuilder private var issue: some View {
        switch model.issue {
        case let .erreur(message), let .sessionExpiree(message):
            InlineNotice(message, tone: .error, identifier: "annulation-erreur", announcesOnAppear: true)
        case let .bloquee(message):
            InlineNotice(message, tone: .warning, identifier: "annulation-erreur", announcesOnAppear: true)
        case .annulee, .none:
            EmptyView()
        }
    }

    private var boutons: some View {
        HStack(spacing: JoleneSpacing.md) {
            JoleneButton(L.garderCandidature, style: .secondary) { dismiss() }
                .disabled(model.envoiEnCours)
                .accessibilityIdentifier("annulation-garder")
            JoleneButton(T.confirmerAnnulation, style: .destructive, isLoading: model.envoiEnCours) { confirmer() }
                .disabled(!AnnulationRules.peutConfirmer(motif: motif, texte: texte, accepte: accepte)
                          || model.envoiEnCours || preparation)
                .accessibilityIdentifier("annulation-confirmer")
        }
        .padding(.top, JoleneSpacing.sm)
    }

    // MARK: - Sélection du justificatif

    private func choisir(_ origine: SourceFichier) {
        erreurFichier = nil
        if let mediaDemo {
            recevoir(mediaDemo.choisir(origine), origine: origine)
            return
        }
        selecteur = origine == .phototheque ? .galerie : .fichiers
    }

    private func recevoir(_ issue: IssueSelection, origine: SourceFichier) {
        switch issue {
        case .annule:
            return
        case .echec:
            fichier = nil
            erreurFichier = origine == .phototheque ? LibellesJustificatifs.galerieImpossible : MessagesDocuments.erreurGenerique
        case let .choisi(choisi):
            preparation = true
            Task {
                // Même chaîne que les justificatifs du lot 2 (HEIC et photothèque → JPEG sans métadonnée), bornée à 5 Mo
                // comme le web (`verifierFichierDocument(fichier, { maxBytes: 5 * 1024 * 1024 })`).
                let resultat = await Task.detached(priority: .userInitiated) {
                    FichierDocument.preparer(nom: choisi.nom, type: choisi.type, octets: choisi.octets, source: choisi.source,
                                             tailleMax: RecuJustificatif.tailleMaxOctets)
                }.value
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

    private func confirmer() {
        let choisi = justificatifBloque ? nil : fichier
        Task {
            await model.annulerCandidature(id: candidatureId, motif: motif, texte: texte, accepte: accepte, fichier: choisi)
        }
    }
}
