import SwiftUI
import JoleneCore
import JoleneDesign

/// « Créer un compte » soignant (lot 3, T7) : port de `src/pages/InscriptionRapide.tsx` (soignant). Textes
/// verbatim (`InscriptionTextes`, HARD STOP n°4) ; la phrase de consentement porte les liens `/cgu` et
/// `/confidentialite`, ouverts par une feuille locale (`PageWebLocale`) : `SFSafariViewController` en staging et
/// production (pages hors AASA : jamais renvoyées dans l'app), double démo sans réseau en démo, comme les pages
/// légales du hub (L3-TJ, décision TJ3).
///
/// Deux modes (`InscriptionRapideModel.Mode`) : depuis la connexion (adresse, mot de passe, profession,
/// consentement → `signUp`) ; depuis l'aiguillage d'onboarding (« Je suis soignant », session déjà ouverte :
/// profession et consentement → `fn_demarrer_inscription`). La suite (connexion par mot de passe, relecture de la
/// session) est confiée à la racine par `issue`.
///
/// Identifiants : `inscription-scroll`, `inscription-email`, `inscription-password`, `inscription-profession`,
/// `inscription-cgu` (case), `inscription-cgu-texte`, `inscription-<champ>-erreur`, `inscription-submit`,
/// `inscription-confirmation-envoyee`, `inscription-erreur`, `inscription-renvoi-web` (seulement avec le
/// présentateur `.safari` du coordinateur des liens, L3-T3b), `inscription-se-connecter`.
struct InscriptionRapideScreen: View {
    @StateObject private var model: InscriptionRapideModel
    /// « Se connecter » : retour à l'écran de connexion avec l'adresse saisie.
    var seConnecter: ((String) -> Void)?
    let issue: (InscriptionRapideModel.Issue) -> Void

    @Environment(\.presentateurRenvoiWeb) private var presentateur
    @FocusState private var focus: ChampInscription?
    @State private var pageJuridique: PageJuridique?

    /// Inscription web du soignant (renvoi en cas de refus captcha, D25), présentée seulement par le présentateur `.safari`.
    private static let inscriptionWeb = URL(string: "https://jolene.app/inscription/soignant")!

    init(controller: SessionController, mode: InscriptionRapideModel.Mode = .nouveauCompte, profession: String = "",
         seConnecter: ((String) -> Void)? = nil, issue: @escaping (InscriptionRapideModel.Issue) -> Void) {
        _model = StateObject(wrappedValue: InscriptionRapideModel(controller: controller, mode: mode, profession: profession))
        self.seConnecter = seConnecter
        self.issue = issue
    }

    private typealias T = InscriptionTextes

    var body: some View {
        ZStack {
            JoleneColor.softGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                    entete
                    VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                        if model.saisitIdentifiants {
                            identifiants
                        } else if !model.email.isEmpty {
                            Text(model.email)
                                .font(JoleneFont.callout)
                                .foregroundStyle(JoleneColor.midnight)
                                .accessibilityIdentifier("inscription-email-session")
                        }
                        profession
                        consentement
                    }
                    if model.etape == .confirmationEnvoyee {
                        InlineNotice(T.confirmationEnvoyee, tone: .info, identifier: "inscription-confirmation-envoyee",
                                     announcesOnAppear: true)
                    }
                    if let message = model.erreurService {
                        InlineNotice(message, tone: .error, identifier: "inscription-erreur", announcesOnAppear: true)
                        if model.refusCaptcha, let presentateur {
                            JoleneButton(T.creerCompteSoignant, style: .secondary) {
                                presentateur.presenter(.safari(Self.inscriptionWeb))
                            }
                            .accessibilityIdentifier("inscription-renvoi-web")
                        }
                    }
                    JoleneButton(model.libelleBouton, isLoading: model.enCours) { envoyer() }
                        .accessibilityIdentifier("inscription-submit")
                    Text(T.aucunDocument)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .frame(maxWidth: .infinity)
                    if model.saisitIdentifiants, let seConnecter {
                        HStack(spacing: JoleneSpacing.xs) {
                            Text(T.dejaUnCompte)
                                .font(JoleneFont.callout)
                                .foregroundStyle(JoleneColor.midnight)
                            Button(T.seConnecter) { seConnecter(model.email) }
                                .font(JoleneFont.callout.weight(.semibold))
                                .foregroundStyle(JoleneColor.rose700)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("inscription-se-connecter")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(JoleneSpacing.xl)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("inscription-scroll")
        }
        .environment(\.openURL, OpenURLAction { url in
            pageJuridique = PageJuridique(url: url)
            return .handled
        })
        .sheet(item: $pageJuridique) { page in
            PageWebLocale(url: page.url) { pageJuridique = nil }
        }
        .onChange(of: model.champAFocaliser) { champ in
            guard let champ else { return }
            if champ == .email || champ == .motDePasse { focus = champ }
            model.champAFocaliser = nil
        }
        .onDisappear { model.motDePasse = "" }
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(T.titre)
                .font(JoleneFont.title)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            Text(T.sousTitre)
                .font(JoleneFont.body)
                .foregroundStyle(JoleneColor.midnight)
        }
        .padding(.top, JoleneSpacing.xl)
    }

    @ViewBuilder private var identifiants: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            JoleneTextField(T.email, text: $model.email, kind: .email, identifier: "inscription-email") { focus = .motDePasse }
                .focused($focus, equals: .email)
            erreur(.email, identifiant: "inscription-email-erreur")
        }
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            JoleneTextField(T.motDePasse, text: $model.motDePasse, kind: .nouveauMotDePasse,
                            identifier: "inscription-password") { focus = nil }
                .focused($focus, equals: .motDePasse)
            Text(T.aideMotDePasse)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
            erreur(.motDePasse, identifiant: "inscription-password-erreur")
        }
    }

    private var profession: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(T.profession).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            Picker(T.profession, selection: $model.profession) {
                Text(T.choisirProfession).tag("")
                ForEach(MissionPresentation.professions, id: \.valeur) { option in
                    Text(option.label).tag(option.valeur)
                }
            }
            .pickerStyle(.menu)
            .tint(JoleneColor.rose700)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .disabled(model.enCours)
            .accessibilityIdentifier("inscription-profession")
            erreur(.profession, identifiant: "inscription-profession-erreur")
        }
    }

    /// Case à cocher et phrase verbatim ; la case est vocalisée avec la phrase entière (état « sélectionné »),
    /// les deux liens restent atteignables dans le texte.
    private var consentement: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                Button {
                    model.cgu.toggle()
                } label: {
                    Image(systemName: model.cgu ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(JoleneColor.rose700)
                        .frame(width: 44, height: 44)
                }
                .disabled(model.enCours)
                .accessibilityLabel(T.cguPhrase)
                .accessibilityAddTraits(model.cgu ? .isSelected : [])
                .accessibilityIdentifier("inscription-cgu")
                Text(Self.phraseConsentement)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.midnight)
                    .tint(JoleneColor.rose700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, JoleneSpacing.sm)
                    .accessibilityIdentifier("inscription-cgu-texte")
            }
            erreur(.cgu, identifiant: "inscription-cgu-erreur")
        }
    }

    /// `J’accepte les{" "}<a href="/cgu">CGU</a>{" "}et la{" "}<a href="/confidentialite">politique de confidentialité</a>.`
    /// Liens posés par la syntaxe Markdown (fragments verbatim, mêmes espaces que le JSX) ; texte brut sans lien si
    /// l'analyse échouait, jamais un texte différent.
    private static var phraseConsentement: AttributedString {
        let source = "\(T.cguDebut) [\(T.cguLienCGU)](\(T.urlCGU.absoluteString)) \(T.cguMilieu) "
            + "[\(T.cguLienConfidentialite)](\(T.urlConfidentialite.absoluteString))\(T.cguFin)"
        return (try? AttributedString(markdown: source)) ?? AttributedString(T.cguPhrase)
    }

    @ViewBuilder private func erreur(_ champ: ChampInscription, identifiant: String) -> some View {
        if let message = model.erreurs[champ] {
            Text(message)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.rose700)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifiant)
        }
    }

    private func envoyer() {
        focus = nil
        Task {
            if let suite = await model.soumettre() { issue(suite) }
        }
    }
}

/// Page web juridique ouverte depuis la phrase de consentement.
private struct PageJuridique: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
