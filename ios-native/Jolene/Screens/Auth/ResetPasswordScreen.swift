import SwiftUI
import JoleneCore
import JoleneDesign

/// Lien `/reset-password` (reste de L1-T10) : port de `src/pages/PageResetPassword.tsx`, présenté par `RootView` en plein
/// écran, au-dessus de tout état, depuis `BoiteLiensInscription.reinitialisation` (coordinateur des liens). Modal
/// bloquant (`interactiveDismissDisabled`) : on n'en sort que par « Retour à la connexion » (abandon : la session de
/// récupération est fermée) ou après le mot de passe enregistré et la session fermée (`ReinitialisationModel`). La
/// session de récupération vit dans un client isolé (`SupabaseRecoveryGateway`) : elle n'ouvre aucun écran de l'app.
///
/// Identifiants : `reset-password-screen` (contenu), `reset-scroll` (défilement), `reset-verification`, `reset-lien-invalide`, `reset-retour-connexion`,
/// `reset-nouveau`, `reset-confirmation`, `reset-non-correspondance`, `reset-erreur`, `reset-submit`, `reset-annuler`,
/// `reset-succes`, `reset-succes-connexion`.
struct ResetPasswordScreen: View {
    @StateObject private var model: ReinitialisationModel
    /// `true` : mot de passe modifié (la racine ferme toute session ouverte et affiche la connexion).
    let terminer: (Bool) -> Void
    @State private var nouveau = ""
    @State private var confirmation = ""

    private typealias T = ReinitialisationTextes

    init(port: @escaping FournisseurRecovery, credentials: AuthCallbackCredentials?, terminer: @escaping (Bool) -> Void) {
        _model = StateObject(wrappedValue: ReinitialisationModel(port: port, credentials: credentials))
        self.terminer = terminer
    }

    var body: some View {
        ZStack {
            JoleneColor.softGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                    Text(T.titre)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    contenu
                }
                .padding(JoleneSpacing.xl)
                .padding(.top, JoleneSpacing.xl)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                // Identifiant de l'écran sur le contenu, conteneur d'accessibilité distinct du défilement : posé sur le
                // `ZStack` (sans élément d'accessibilité propre), il recouvrait celui du `ScrollView`, exposé alors comme
                // `reset-password-screen` sans `reset-scroll` (run 45446351274, iPad paysage, deux tests de
                // DemoReinitialisationTests ; arbre relevé sur simulateur iOS 18.6).
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("reset-password-screen")
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("reset-scroll")
        }
        .interactiveDismissDisabled(true)
        .task { await model.ouvrir() }
        // Disparition sans issue (fermeture par la racine) : la session de récupération est fermée à la libération du
        // modèle (`ReinitialisationModel`), jamais sur `onDisappear`, émis aussi sur cet écran encore affiché.
    }

    @ViewBuilder private var contenu: some View {
        switch model.etat {
        case .verification:
            ProgressView(T.verification)
                .tint(JoleneColor.rose700)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("reset-verification")
        case .lienInvalide:
            Text(T.lienInvalide)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.rose700)
                .accessibilityIdentifier("reset-lien-invalide")
            paragraphe(T.lienInvalideDetail)
            JoleneButton(T.retourConnexion) { abandonner() }
                .accessibilityIdentifier("reset-retour-connexion")
        case .formulaire, .enregistrement:
            formulaire
        case .succes, .succesSessionNonFermee:
            Text(T.modifie)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityIdentifier("reset-succes")
            paragraphe(model.etat == .succes ? T.modifieAvecSucces : T.sessionNonFermee)
            JoleneButton(T.retourConnexion) { terminer(true) }
                .accessibilityIdentifier("reset-succes-connexion")
        }
    }

    @ViewBuilder private var formulaire: some View {
        let enCours = model.etat == .enregistrement
        paragraphe(T.consigne)
        JoleneTextField(T.nouveau, text: $nouveau, kind: .nouveauMotDePasse, placeholder: T.nouveauPlaceholder,
                        identifier: "reset-nouveau")
        JoleneTextField(T.confirmation, text: $confirmation, kind: .nouveauMotDePasse, identifier: "reset-confirmation") {
            enregistrer()
        }
        if ReinitialisationRules.afficherNonCorrespondance(nouveau: nouveau, confirmation: confirmation) {
            Text(T.nonCorrespondance)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.rose700)
                .accessibilityIdentifier("reset-non-correspondance")
        }
        if let erreur = model.erreur {
            Text(erreur)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.rose700)
                .padding(JoleneSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JoleneColor.rose100)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .accessibilityIdentifier("reset-erreur")
        }
        JoleneButton(enCours ? T.miseAJour : T.soumettre, isLoading: enCours) { enregistrer() }
            .disabled(!model.peutEnregistrer(nouveau: nouveau, confirmation: confirmation))
            .accessibilityIdentifier("reset-submit")
        JoleneButton(T.retourConnexion, style: .secondary) { abandonner() }
            .disabled(enCours)
            .accessibilityIdentifier("reset-annuler")
    }

    private func paragraphe(_ texte: String) -> some View {
        Text(texte)
            .font(JoleneFont.body)
            .foregroundStyle(JoleneColor.midnight)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func enregistrer() {
        let saisi = nouveau
        let confirme = confirmation
        Task {
            await model.enregistrer(nouveau: saisi, confirmation: confirme)
            if model.estTermine { nouveau = ""; confirmation = "" }
        }
    }

    private func abandonner() {
        Task {
            await model.abandonner()
            terminer(false)
        }
    }
}

/// « Mot de passe oublié ? » (reste de L1-T10) : demande d'un lien depuis l'écran de connexion, port de
/// `PageConnexion.tsx` l.339-400. Même texte que le compte existe ou non ; 60 s entre deux envois.
///
/// Identifiants : `reset-request-sheet`, `reset-request-email`, `reset-request-envoye`, `reset-request-annonce`,
/// `reset-request-erreur`, `reset-request-submit`, `reset-request-retour`.
struct ResetRequestSheet: View {
    @StateObject private var model: DemandeReinitialisationModel
    /// Fermeture : l'adresse saisie revient à l'écran de connexion.
    let fermer: (String) -> Void

    private typealias T = ReinitialisationTextes

    init(email: String, port: @escaping FournisseurRecovery, fermer: @escaping (String) -> Void) {
        _model = StateObject(wrappedValue: DemandeReinitialisationModel(email: email, port: port))
        self.fermer = fermer
    }

    var body: some View {
        ZStack {
            JoleneColor.softGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                    Text(T.motDePasseOublie)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    JoleneTextField(T.emailDuCompte, text: $model.email, kind: .email, placeholder: T.emailPlaceholder,
                                    identifier: "reset-request-email") { envoyer() }
                    if let envoye = model.messageEnvoye {
                        Text(envoye)
                            .font(JoleneFont.callout)
                            .foregroundStyle(JoleneColor.midnight)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("reset-request-envoye")
                    }
                    if let annonce = model.annonce {
                        Text(annonce)
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.mauve700)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("reset-request-annonce")
                    }
                    if let erreur = model.erreur {
                        Text(erreur)
                            .font(JoleneFont.callout)
                            .foregroundStyle(JoleneColor.rose700)
                            .padding(JoleneSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(JoleneColor.rose100)
                            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                            .accessibilityIdentifier("reset-request-erreur")
                    }
                    JoleneButton(model.libelleBouton, isLoading: model.envoiEnCours) { envoyer() }
                        .disabled(!model.peutEnvoyer)
                        .accessibilityIdentifier("reset-request-submit")
                    JoleneButton(T.retourConnexion, style: .secondary) { fermer(model.email) }
                        .accessibilityIdentifier("reset-request-retour")
                }
                .padding(JoleneSpacing.xl)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .accessibilityIdentifier("reset-request-sheet")
        // Minuteur du délai de renvoi (web l.58-65), arrêté avec la feuille.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                model.seconde()
            }
        }
    }

    private func envoyer() {
        Task { await model.envoyer() }
    }
}
