import SwiftUI
import JoleneCore
import JoleneDesign

/// Route de l'écran « Changer mon mot de passe », empilée sur l'onglet Profil depuis l'entrée du hub
/// (`compte-mdp-ouvrir`, section « Connexion & sécurité ») ; destination enregistrée par `ProfileScreen`.
struct MotDePasseRoute: Hashable {}

/// « Changer mon mot de passe » (lot 3, T11, D13), port de `ChangementMotDePasse.tsx` (formulaire l.112-190,
/// jauge l.210-242) : mot de passe actuel, nouveau mot de passe avec jauge et critères dès la saisie
/// (`PasswordCriteriaList`, critères évalués par `ForceMotDePasse`), confirmation avec sa correspondance,
/// bouton actif seulement sur un formulaire valide. Les toasts du web deviennent des encarts annoncés
/// (`compte-mdp-succes`, `compte-mdp-erreur`). Écart assumé : pas de bouton « Afficher / Cacher » (champs
/// sécurisés iOS, saisie masquée sans exception). Textes : `MotDePasse.Textes` (verbatim web, deux textes natifs
/// listés pour relecture). Identifiants : `compte-mdp-screen`, `compte-mdp-ancien`, `compte-mdp-nouveau`,
/// `compte-mdp-confirmation`, `compte-mdp-force`, `compte-mdp-critere-<cle>`, `compte-mdp-correspondance`,
/// `compte-mdp-submit`, `compte-mdp-succes`, `compte-mdp-erreur`, `compte-mdp-session-verifier`.
struct MotDePasseScreen: View {
    @StateObject private var model: MotDePasseModel

    private typealias Textes = MotDePasse.Textes

    init(session: SessionStore, snapshot: SessionSnapshot) {
        _model = StateObject(wrappedValue: MotDePasseModel(session: session, snapshot: snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                JoleneTextField(Textes.ancien, text: $model.ancien, kind: .motDePasse, identifier: "compte-mdp-ancien")
                VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                    JoleneTextField(Textes.nouveau, text: $model.nouveau, kind: .nouveauMotDePasse, identifier: "compte-mdp-nouveau")
                    if model.afficheJauge {
                        let force = model.force
                        PasswordCriteriaList(criteria: PasswordCriteriaList.criteresWeb(
                            longueur: force.longueur, majuscule: force.majuscule, minuscule: force.minuscule,
                            chiffre: force.chiffre, special: force.special), identifier: "compte-mdp")
                    }
                }
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    JoleneTextField(Textes.confirmation, text: $model.confirmation, kind: .nouveauMotDePasse,
                                    identifier: "compte-mdp-confirmation")
                    correspondance
                }
                issue
                JoleneButton(Textes.soumettre, isLoading: model.enCours) { Task { await model.changer() } }
                    .disabled(!model.peutSoumettre)
                    .accessibilityIdentifier("compte-mdp-submit")
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("compte-mdp-screen")
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(Textes.titre)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.enCours)
    }

    /// « Les mots de passe ne correspondent pas. » (confirmation saisie et différente, l.169-173) ou « Mots de
    /// passe identiques. » (l.174-178) ; rien tant que la confirmation est vide.
    @ViewBuilder private var correspondance: some View {
        if model.afficheNonCorrespondance || model.afficheCorrespondance {
            let identiques = model.afficheCorrespondance
            Label(identiques ? Textes.correspondance : Textes.nonCorrespondance,
                  systemImage: identiques ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(JoleneFont.caption)
                .foregroundStyle(identiques ? JoleneColor.cyan900 : JoleneColor.rose700)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(identiques ? Textes.correspondance : Textes.nonCorrespondance)
                .accessibilityIdentifier("compte-mdp-correspondance")
        }
    }

    @ViewBuilder private var issue: some View {
        if let succes = model.succes {
            InlineNotice(succes, tone: .success, identifier: "compte-mdp-succes", announcesOnAppear: true,
                         announcementID: model.annonces)
        }
        if let erreur = model.erreur {
            InlineNotice(erreur, tone: .error, identifier: "compte-mdp-erreur", announcesOnAppear: true,
                         announcementID: model.annonces)
            if model.sessionExpiree {
                JoleneButton(ProfilEdition.Textes.verifierSession, style: .secondary) { Task { await model.verifierSession() } }
                    .accessibilityIdentifier("compte-mdp-session-verifier")
            }
        }
    }
}
