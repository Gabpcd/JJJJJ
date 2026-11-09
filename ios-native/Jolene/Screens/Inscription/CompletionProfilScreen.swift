import SwiftUI
import UIKit
import JoleneCore
import JoleneDesign

/// Complétion du profil soignant (lot 3, T8) : port de `src/pages/InscriptionSoignant.tsx` en mode `parcours`
/// (`/inscription/completer`), monté par l'aiguillage d'onboarding (`OnboardingRootView`) pour un parcours soignant
/// réservé. Écran bloquant (D9) : pas d'exploration avant le profil complet, « Se déconnecter » toujours proposé.
/// Textes verbatim du web (`CompletionTextes`, `ChoixModesExercice.Textes`, `InscriptionTextes`) ; aucune règle de mode
/// d'exercice en dur (modes du référentiel `fn_types_exercice_autorises`, `ChoixModesExerciceSection` partagée avec
/// l'édition du profil) ; « Je suis étudiant(e) en santé » et le parcours étudiant restent sur le web (D11), le bouton
/// n'existe qu'avec le présentateur `.safari` (jamais un bouton sans effet). Pas de champ rayon (correction 21).
///
/// Revue fraîche B8 de T8 : un brouillon déclaré étudiant sur le web (B1, `CompletionProfilModel.parcoursEtudiant`)
/// n'affiche ni formulaire ni « Enregistrer mon profil » : seul le renvoi vers la complétion web est proposé, aucun texte
/// nouveau (sans présentateur : texte web « Votre espace est momentanément indisponible. Réessayez. ») ; au retour d'un
/// renvoi ouvert depuis cet écran (`fermeturesRenvoiWeb`), le rôle est relu (M1) — un profil créé sur le web ouvre
/// l'espace, et un parcours étudiant est relu (le brouillon a pu changer sur le web).
///
/// Identifiants : `completion-screen`, `completion-titre`, `completion-prenom`, `completion-nom`, `completion-telephone`,
/// `completion-telephone-erreur`, `completion-date-naissance`, `completion-date-naissance-renseigner`,
/// `completion-date-naissance-erreur`, `completion-profession`, `completion-profession-erreur`,
/// `completion-etudiant-web`, `completion-etudiant-indisponible`, `completion-mode-*` et `completion-modes-*`
/// (`ChoixModesExerciceSection`), `completion-rpps`, `completion-rpps-aucun`, `completion-type-unique`,
/// `completion-salarie` (`-oui`, `-non`), `completion-exclusivite`, `completion-referentiel-indisponible`,
/// `completion-erreur`, `completion-enregistrer`, `completion-plus-tard`, `logout-button`.
struct CompletionProfilScreen: View {
    @ObservedObject private var session: SessionStore
    @StateObject private var model: CompletionProfilModel
    @Environment(\.presentateurRenvoiWeb) private var presentateur
    /// Renvois affichés puis fermés (revue B8 de T8, M1) : relecture du rôle au retour de la complétion web.
    @Environment(\.fermeturesRenvoiWeb) private var fermeturesRenvoiWeb
    /// Sélecteur ouvert sur une date non renseignée : il affiche `DateNaissance.parDefaut` sans l'écrire.
    @State private var selecteurDateOuvert = false
    /// Compteur `fermeturesRenvoiWeb` au moment où la complétion web a été ouverte depuis cet écran.
    @State private var retourWebAttendu: Int?
    private let recharger: () -> Void
    private let seDeconnecter: () -> Void

    private typealias T = CompletionTextes

    /// Complétion web (parcours étudiant, D11).
    private static let completionWeb = URL(string: "https://jolene.app/inscription/completer")!

    /// - Parameters:
    ///   - annoncerDeconnexion: message affiché à la connexion après une déconnexion locale (503 de `register-soignant`).
    ///   - recharger: relecture du parcours après « Enregistrer et continuer plus tard » (le web rouvre la reprise).
    init(session: SessionStore, parcours: ParcoursInscription, annoncerDeconnexion: @escaping (String) -> Void,
         recharger: @escaping () -> Void, seDeconnecter: @escaping () -> Void) {
        self.session = session
        self.recharger = recharger
        self.seDeconnecter = seDeconnecter
        _model = StateObject(wrappedValue: CompletionProfilModel(session: session, parcours: parcours,
                                                                 annoncerDeconnexion: annoncerDeconnexion))
    }

    var body: some View {
        ZStack {
            JoleneColor.softGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                    entete
                    if model.professionValide && model.parcoursEtudiant {
                        completionWebEtudiant
                    } else if model.professionValide {
                        formulaire
                    } else {
                        // Parcours sans profession du catalogue : contrat rompu (`fn_demarrer_inscription` l'exige).
                        InlineNotice(InscriptionTextes.espaceIndisponible, tone: .error, identifier: "completion-profession-erreur",
                                     announcesOnAppear: true)
                    }
                    JoleneButton(InscriptionTextes.seDeconnecter, style: .secondary, isLoading: session.deconnexionEnCours) {
                        seDeconnecter()
                    }
                    .disabled(session.deconnexionEnCours || model.enCours)
                    .accessibilityIdentifier("logout-button")
                }
                .padding(JoleneSpacing.xl)
                .padding(.top, JoleneSpacing.lg)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("completion-screen")
        }
        .task { if model.modes == .inactif && !model.parcoursEtudiant { await model.verifierModes() } }
        .onChange(of: fermeturesRenvoiWeb) { fermetures in
            guard let depart = retourWebAttendu, fermetures > depart else { return }
            retourWebAttendu = nil
            let model = self.model
            let etudiant = model.parcoursEtudiant
            let recharger = self.recharger
            Task {
                // Profil créé sur le web : l'espace s'ouvre ; sinon un parcours étudiant relit le brouillon serveur.
                if await model.relireApresRenvoiWeb() == nil, etudiant { recharger() }
            }
        }
    }

    // MARK: - Sections

    private var entete: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(T.titre)
                .font(JoleneFont.title)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("completion-titre")
            Text(T.sousTitre)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var formulaire: some View {
        carte {
            JoleneTextField(T.prenom, text: $model.prenom, kind: .prenom, identifier: "completion-prenom")
            JoleneTextField(T.nom, text: $model.nom, kind: .nom, identifier: "completion-nom")
            JoleneTextField(T.telephone, text: $model.telephone, kind: .telephone, placeholder: T.telephonePlaceholder,
                            identifier: "completion-telephone")
            if let erreur = model.erreurTelephone {
                messageChamp(erreur, identifiant: "completion-telephone-erreur")
            }
            legende(T.telephoneAide)
            dateNaissance
            lectureSeule(T.profession, valeur: MissionPresentation.professionLabel(model.profession),
                         identifiant: "completion-profession")
        }
        boutonCompletionWeb(style: .secondary)
        carte {
            ChoixModesExerciceSection(choix: model.choixModes, prefixe: "completion",
                                      basculer: { model.basculerMode($0, selectionne: $1) }, reessayer: reessaiModes)
        }
        carte { rpps }
        carte { typeExercice }
        enregistrement
    }

    /// Brouillon déclaré étudiant (B1, D11) : la complétion se termine sur le web, aucun formulaire natif.
    @ViewBuilder private var completionWebEtudiant: some View {
        if presentateur != nil {
            boutonCompletionWeb(style: .primary)
        } else {
            InlineNotice(InscriptionTextes.espaceIndisponible, tone: .error, identifier: "completion-etudiant-indisponible",
                         announcesOnAppear: true)
        }
    }

    /// « 🎓 Je suis étudiant(e) en santé » : complétion web (`/inscription/completer`) par le présentateur `.safari` ;
    /// absent sans présentateur (jamais un bouton sans effet). Le retour est suivi (`retourWebAttendu`).
    @ViewBuilder private func boutonCompletionWeb(style: JoleneButton.Style) -> some View {
        if let presentateur {
            JoleneButton(T.etudiant, style: style) {
                retourWebAttendu = fermeturesRenvoiWeb
                presentateur.presenter(.safari(Self.completionWeb))
            }
            .disabled(model.enCours || model.enregistrementEnCours)
            .accessibilityIdentifier("completion-etudiant-web")
        }
    }

    @ViewBuilder private var dateNaissance: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            if model.dateNaissance.flatMap(DateNaissance.date) != nil || selecteurDateOuvert {
                // Le sélecteur AFFICHE `parDefaut` sans l'écrire (principe « État dérivé ») ; borne haute : 18 ans
                // révolus (`max`, l.554), calculée en UTC comme le sélecteur (revue B8 de T8, m8). L'âge reste contrôlé
                // par `register-soignant` (`UNDERAGE`, verbatim).
                DatePicker(T.dateNaissance, selection: DateNaissance.liaison($model.dateNaissance),
                           in: ...CompletionRules.dateMaximale(maintenant: Date(), calendrier: CompletionRules.calendrierUTC),
                           displayedComponents: .date)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.midnight)
                    .environment(\.locale, Locale(identifier: "fr_FR"))
                    .environment(\.timeZone, DateNaissance.fuseau)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("completion-date-naissance")
            } else {
                Button {
                    selecteurDateOuvert = true
                } label: {
                    Label(T.dateNaissance, systemImage: "calendar")
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(JoleneColor.rose800)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("completion-date-naissance-renseigner")
            }
            if let erreur = model.erreurDateNaissance {
                messageChamp(erreur, identifiant: "completion-date-naissance-erreur")
            }
        }
    }

    @ViewBuilder private var rpps: some View {
        if model.afficheRpps {
            Text(T.numeroRpps + (model.rppsObligatoire ? T.suffixeObligatoire : ""))
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
            if let aide = CompletionRules.aideRpps(profession: model.profession) {
                legende(aide)
            }
            legende(T.aideRppsAnnuaire)
            TextField(model.rppsObligatoire ? T.rppsPlaceholderObligatoire : T.rppsPlaceholderOptionnel, text: $model.rpps)
                .font(.system(size: 16))
                .keyboardType(.numberPad)
                .textContentType(nil)
                .autocorrectionDisabled()
                .padding(.horizontal, JoleneSpacing.lg)
                .frame(minHeight: 48)
                .background(JoleneColor.cloud)
                .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field)
                    .strokeBorder(JoleneColor.bubblegum.opacity(0.35), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .accessibilityLabel(T.numeroRpps)
                .accessibilityIdentifier("completion-rpps")
        } else {
            Text(T.aucunRpps)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("completion-rpps-aucun")
        }
    }

    /// `ExerciceTypeSection` (l.53-99) : affichage seul, la réponse n'est jamais transmise (correction 21).
    @ViewBuilder private var typeExercice: some View {
        if let phrase = model.phraseTypeUnique {
            Text(T.typeExercice)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            Text(phrase)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("completion-type-unique")
        } else {
            Text(T.questionSalarie)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
            SegmentedChoice(T.questionSalarie,
                            options: [.init(id: "oui", title: T.oui), .init(id: "non", title: T.non)],
                            selection: reponseSalarie, identifier: "completion-salarie")
            if model.estSalarieEtablissement == true {
                Text(T.exclusivite)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("completion-exclusivite")
            }
            if model.modes == .indisponible {
                Text(T.referentielIndisponible)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.butter800)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("completion-referentiel-indisponible")
            }
        }
    }

    private var enregistrement: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            if let erreur = model.erreur {
                InlineNotice(erreur, tone: .error, identifier: "completion-erreur", announcesOnAppear: true,
                             announcementID: model.annonces)
            }
            JoleneButton(model.enCours ? T.enregistrement : T.enregistrerMonProfil, isLoading: model.enCours) {
                Task { _ = await model.finaliser() }
            }
            .disabled(model.enCours || model.enregistrementEnCours)
            .accessibilityIdentifier("completion-enregistrer")
            JoleneButton(T.enregistrerPlusTard, style: .secondary, isLoading: model.enregistrementEnCours) {
                Task { if await model.enregistrerPlusTard() { recharger() } }
            }
            .disabled(model.enCours || model.enregistrementEnCours)
            .accessibilityIdentifier("completion-plus-tard")
        }
    }

    // MARK: - Briques

    /// « Réessayer la vérification » seulement quand une nouvelle lecture peut aboutir.
    private var reessaiModes: (() -> Void)? {
        guard model.reessaiModesPossible else { return nil }
        let model = self.model
        return { Task { await model.verifierModes() } }
    }

    private var reponseSalarie: Binding<String> {
        Binding(get: {
            switch model.estSalarieEtablissement {
            case true?: return "oui"
            case false?: return "non"
            case nil: return ""
            }
        }, set: { model.estSalarieEtablissement = $0 == "oui" ? true : ($0 == "non" ? false : nil) })
    }

    private func carte<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) { contenu() }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }

    private func legende(_ texte: String) -> some View {
        Text(texte)
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.bubblegum)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func messageChamp(_ texte: String, identifiant: String) -> some View {
        Text(texte)
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.rose700)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifiant)
    }

    private func lectureSeule(_ libelle: String, valeur: String, identifiant: String) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(libelle).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            Text(valeur)
                .font(JoleneFont.body)
                .foregroundStyle(JoleneColor.midnight)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifiant)
    }
}
