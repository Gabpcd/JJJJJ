import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet « Réclamations » (L4-T8), port de `ReclamationsContent` (`MesReclamations.tsx`) : vue de `ReclamationsModel`
/// (JoleneCore). Réclamations générales seulement ; la contestation d'un événement de score relève de « Mon score » (T9).
///
/// - En-tête, « Signaler un problème », liste dans l'ordre serveur : sujet, catégorie et date, statut, détails, réponse
///   de l'équipe (texte serveur tel quel).
/// - Une erreur de lecture est affichée avec « Réessayer » (le web montre alors une liste vide).
///
/// Identifiants : `reclamation-nouvelle`, `reclamation-<id>`, `reclamation-statut-<id>`, `reclamation-reponse-<id>`,
/// `reclamations-chargement`, `reclamations-erreur` (+ `-reessayer`), `reclamations-vide` (+ `-signaler`),
/// `reclamations-action-erreur`, `reclamations-confirmation`, `reclamations-session-check` ; feuille
/// `reclamation-formulaire` (`ReclamationSheet`).
struct ReclamationsView: View {
    @ObservedObject var model: ReclamationsModel
    @ObservedObject var session: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
            entete
            if !model.formulaireOuvert { avis }
            if model.sessionExpiree {
                JoleneButton(LitigesTextes.verifierSession, style: .secondary) { Task { await model.verifierSession(session) } }
                    .accessibilityIdentifier("reclamations-session-check")
            }
            contenu
        }
        // À chaque apparition de l'onglet, comme le web au montage.
        .task { await model.charger() }
        .sheet(isPresented: Binding(get: { model.formulaireOuvert }, set: { if !$0 { model.fermerFormulaire() } })) {
            ReclamationSheet(model: model)
        }
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(ReclamationsTextes.titre)
                .font(JoleneFont.title)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            Text(ReclamationsTextes.sousTitre)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            JoleneButton(ReclamationsTextes.signaler) { model.ouvrirFormulaire() }
                .accessibilityIdentifier("reclamation-nouvelle")
        }
    }

    @ViewBuilder private var avis: some View {
        if let erreur = model.erreur {
            InlineNotice(erreur, tone: .error, identifier: "reclamations-action-erreur", announcementID: model.jeton)
        } else if let confirmation = model.confirmation {
            InlineNotice(confirmation, tone: .success, identifier: "reclamations-confirmation", announcementID: model.jeton)
        }
    }

    @ViewBuilder private var contenu: some View {
        switch model.liste {
        case .chargement:
            SkeletonCard(identifier: "reclamations-chargement")
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .error, identifier: "reclamations-erreur")
                if !model.sessionExpiree {
                    JoleneButton(LitigesTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                        .accessibilityIdentifier("reclamations-erreur-reessayer")
                }
            }
        case let .prete(lignes):
            if lignes.isEmpty {
                VStack(spacing: JoleneSpacing.md) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 36))
                        .foregroundStyle(JoleneColor.bubblegum)
                        .accessibilityHidden(true)
                    Text(ReclamationsTextes.vide)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("reclamations-vide")
                    JoleneButton(ReclamationsTextes.signaler, style: .secondary) { model.ouvrirFormulaire() }
                        .accessibilityIdentifier("reclamations-vide-signaler")
                }
                .padding(JoleneSpacing.xl)
                .frame(maxWidth: .infinity)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            } else {
                ForEach(lignes) { carte($0) }
            }
        }
    }

    private func carte(_ reclamation: Reclamation) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(reclamation.sujet)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(ReclamationsTextes.meta(reclamation))
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            StatusPill(ReclamationsTextes.libelleStatut(reclamation.statut), tone: Self.ton(reclamation.statut), size: .sm,
                       identifier: "reclamation-statut-\(reclamation.id)")
            Text(reclamation.details)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            if let reponse = reclamation.reponseAdmin, !reponse.isEmpty {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(ReclamationsTextes.reponseJolene)
                        .font(JoleneFont.caption.weight(.semibold))
                        .foregroundStyle(JoleneColor.rose800)
                    Text(reponse)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.midnight)
                        .fixedSize(horizontal: false, vertical: true)
                    if let date = ReclamationsTextes.dateHeure(reclamation.traiteLe) {
                        Text(date)
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                    }
                }
                .padding(JoleneSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JoleneColor.mauve100)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("reclamation-reponse-\(reclamation.id)")
            }
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reclamation-\(reclamation.id)")
    }

    /// Tons du web (`STATUT_CONFIG[…].color`, l.30-35) : en attente en avertissement, en cours en information, résolue en
    /// succès, fermée neutre ; un statut inconnu s'affiche comme « En attente ».
    private static func ton(_ statut: String) -> StatusPill.Tone {
        switch statut {
        case "EN_COURS": return .info
        case "RESOLUE": return .success
        case "FERMEE": return .neutral
        default: return .warning
        }
    }
}

/// « Signaler un problème » (`MesReclamations.tsx` l.176-223) : catégorie de la liste fermée du serveur, sujet et
/// détails (tous deux non vides après `trim` pour activer l'envoi). Le refus du serveur s'affiche tel quel ; la feuille
/// ne se referme qu'après une relecture qui montre la réclamation.
///
/// Identifiants : `reclamation-formulaire` (défilement), `reclamation-categorie`, `reclamation-sujet`,
/// `reclamation-details`, `reclamation-formulaire-erreur`, `reclamation-envoyer`, `reclamation-annuler`.
struct ReclamationSheet: View {
    @ObservedObject var model: ReclamationsModel
    @FocusState private var sujetActif: Bool
    @FocusState private var detailsActifs: Bool


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                    Text(ReclamationsTextes.signaler)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    categorie
                    sujet
                    details
                    if let erreur = model.erreurFormulaire {
                        InlineNotice(erreur, tone: .error, identifier: "reclamation-formulaire-erreur", announcesOnAppear: true)
                    }
                    VStack(spacing: JoleneSpacing.sm) {
                        JoleneButton(ReclamationsTextes.envoyer, isLoading: model.envoiEnCours) {
                            sujetActif = false
                            detailsActifs = false
                            Task { await model.envoyer() }
                        }
                        .disabled(!model.peutEnvoyer)
                        .accessibilityIdentifier("reclamation-envoyer")
                        JoleneButton(ReclamationsTextes.annuler, style: .secondary) { model.fermerFormulaire() }
                            .disabled(model.envoiEnCours)
                            .accessibilityIdentifier("reclamation-annuler")
                    }
                }
                .padding(JoleneSpacing.lg)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(JoleneColor.lavender.ignoresSafeArea())
            .accessibilityIdentifier("reclamation-formulaire")
        }
        .interactiveDismissDisabled(model.envoiEnCours)
    }

    private var categorie: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(ReclamationsTextes.categorie)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
            Picker(ReclamationsTextes.categorie, selection: Binding(get: { model.categorie }, set: { model.choisir($0) })) {
                ForEach(CategorieReclamation.allCases, id: \.self) { valeur in
                    Text(ReclamationsTextes.libelle(valeur)).tag(valeur)
                }
            }
            .pickerStyle(.menu)
            .tint(JoleneColor.rose800)
            .disabled(model.envoiEnCours)
            .accessibilityIdentifier("reclamation-categorie")
        }
    }

    private var sujet: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(ReclamationsTextes.sujet)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
            TextField(ReclamationsTextes.sujetPlaceholder, text: Binding(get: { model.sujet }, set: { model.saisirSujet($0) }))
                .font(.system(size: 16))
                .focused($sujetActif)
                .submitLabel(.next)
                .onSubmit { detailsActifs = true }
                .padding(JoleneSpacing.md)
                .frame(minHeight: 44)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .disabled(model.envoiEnCours)
                .accessibilityLabel(ReclamationsTextes.sujet)
                .accessibilityIdentifier("reclamation-sujet")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(ReclamationsTextes.details)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
            TextField(ReclamationsTextes.detailsPlaceholder,
                      text: Binding(get: { model.details }, set: { model.saisirDetails($0) }), axis: .vertical)
                .lineLimit(5...10)
                .font(.system(size: 16))
                .focused($detailsActifs)
                .boutonOKClavier($detailsActifs, actif: !model.envoiEnCours)
                .padding(JoleneSpacing.md)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .disabled(model.envoiEnCours)
                .accessibilityLabel(ReclamationsTextes.details)
                .accessibilityIdentifier("reclamation-details")
        }
    }
}
