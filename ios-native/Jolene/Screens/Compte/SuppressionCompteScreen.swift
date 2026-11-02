import SwiftUI
import JoleneCore
import JoleneDesign

/// Section « Suppression de compte » de l'onglet Profil (lot 1, T8 ; Apple 5.1.1), port de
/// `SectionConfidentialite.tsx` l.151-164 : avertissement RGPD verbatim (tutoiement, HARD STOP n°4)
/// et lien vers l'écran de confirmation. Identifiants : `compte-suppression-info`, `compte-supprimer-ouvrir`.
struct SuppressionCompteSection: View {
    let session: SessionStore
    let snapshot: SessionSnapshot
    let finDeCompte: AvisFinDeCompte

    var body: some View {
        Section(CompteSuppression.Textes.sectionTitre) {
            Text(CompteSuppression.Textes.sectionAvertissement)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("compte-suppression-info")
            NavigationLink {
                SuppressionCompteScreen(session: session, snapshot: snapshot, finDeCompte: finDeCompte)
            } label: {
                Label(CompteSuppression.Textes.boutonOuvrir, systemImage: "trash")
                    .foregroundStyle(JoleneColor.rose700)
            }
            .accessibilityIdentifier("compte-supprimer-ouvrir")
        }
    }
}

/// Écran de confirmation, port de la modale `SectionConfidentialite.tsx` l.166-200 : texte RGPD et
/// consigne verbatim web, saisie stricte « SUPPRIMER » (`ConfirmationSheet`), refus serveur verbatim
/// (`compte-supprimer-erreur`). Aucun succès n'est annoncé ici : après la réponse serveur, la racine de
/// l'app remplace l'espace connecté par l'écran « Compte supprimé » (`CompteSupprimeScreen`).
/// Identifiants : `compte-supprimer` (+ `-title`, `-message`, `-input`, `-confirm`, `-cancel`, `-erreur`).
struct SuppressionCompteScreen: View {
    @StateObject private var model: CompteModel
    @Environment(\.dismiss) private var dismiss

    init(session: SessionStore, snapshot: SessionSnapshot, finDeCompte: AvisFinDeCompte) {
        _model = StateObject(wrappedValue: CompteModel(session: session, snapshot: snapshot, avis: finDeCompte))
    }

    static let configuration = ConfirmationSheet.Configuration(
        title: CompteSuppression.Textes.confirmationTitre,
        message: CompteSuppression.Textes.confirmationAvertissement,
        confirmTitle: CompteSuppression.Textes.boutonConfirmer,
        cancelTitle: CompteSuppression.Textes.boutonAnnuler,
        variant: .danger,
        identifier: "compte-supprimer",
        requiredPhrase: CompteSuppression.motConfirmation,
        phrasePrompt: CompteSuppression.Textes.confirmationConsigne,
        phrasePlaceholder: CompteSuppression.Textes.confirmationExemple
    )

    var body: some View {
        ConfirmationSheet(Self.configuration, isLoading: model.enCours,
                          onCancel: { if !model.enCours { dismiss() } },
                          onConfirm: { Task { await model.supprimer() } }) {
            if let message = model.messageRefus {
                InlineNotice(message, tone: .error, identifier: "compte-supprimer-erreur",
                             announcesOnAppear: true, announcementID: model.tentatives)
            }
        }
        .navigationTitle(CompteSuppression.Textes.sectionTitre)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.enCours)
    }
}
