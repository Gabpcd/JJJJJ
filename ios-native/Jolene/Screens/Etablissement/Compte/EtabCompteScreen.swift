import SwiftUI
import JoleneCore
import JoleneDesign

/// Compte de l'espace établissement (lot 5, T12 ; `LOT5_PLAN.md` §3 T12) : établissement servi, rôle d'équipe servi,
/// renvois web, déconnexion, version. Aucune lecture propre : tout vient de l'instantané de session **courant**
/// (`fn_mon_etablissement_complet`, `fn_mes_permissions_etab`), re-filtré à epoch constant après une relecture des
/// permissions. La table des renvois, ses conditions d'affichage et les textes vivent dans JoleneCore
/// (`RenvoisWebEtab`, `EtabComptePresentation` ; `RenvoisWebEtabTests`, `EtabCompteTests`) ; la vue n'ajoute aucune règle.
///
/// Renvois web (D16) : chaque entrée présente sa route externe par le présentateur `.safari` du coordinateur des liens
/// (`SFSafariViewController`, double sans réseau en démo), jamais par `openURL` — un chemin `/etablissement/*` reviendrait
/// dans l'app par lien universel. L'URL est une constante de la table : aucun jeton, aucune donnée de la session. Sans
/// présentateur (aperçu, test isolé), aucune entrée n'est affichée : jamais un lien sans effet. La suppression du
/// compte est un lien direct vers la page web (D17), offert à tout membre.
///
/// Emblème : celui du web (`MonCompteEtablissement.tsx` l.97-102 affiche une icône de bâtiment, sans le logo) ; aucune
/// image distante n'est chargée.
///
/// Pile non paresseuse : toutes les entrées existent dans l'arbre d'accessibilité, même hors écran (présence et
/// absence par rôle prouvées sans défilement par `DemoEtabCompteTests`).
///
/// Identifiants : `etab-compte-screen`, `etab-compte-nom`, `etab-compte-role`, `etab-compte-email`,
/// `etab-compte-note-web`, `etab-compte-section-<section>`, `etab-compte-web-<clé>` (valeur : URL du renvoi),
/// `logout-button`, `etab-compte-version`, `network-sentinel` (DEBUG).
struct EtabCompteScreen: View {
    private typealias P = EtabComptePresentation

    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                identite
                if let presentateurRenvoiWeb {
                    renvois(presentateurRenvoiWeb)
                }
                JoleneButton(P.seDeconnecter, style: .secondary, isLoading: session.deconnexionEnCours) {
                    Task { await session.signOut() }
                }
                .accessibilityIdentifier("logout-button")
                application
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("etab-compte-screen")
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(EcranNatifEtablissement.compte.titre)
    }

    // MARK: - Identité

    private var identite: some View {
        HStack(alignment: .center, spacing: JoleneSpacing.md) {
            Image(systemName: "building.2")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(JoleneColor.heroGradient)
                .frame(width: 56, height: 56)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                Text(P.nom(snapshot.etablissement))
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("etab-compte-nom")
                Text(P.role(snapshot))
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("etab-compte-role")
                Text(P.email(snapshot.user))
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("etab-compte-email")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Renvois web

    @ViewBuilder
    private func renvois(_ presentateur: any PresentateurRenvoiWeb) -> some View {
        let sections = RenvoisWebEtab.sections(profil: snapshot.etablissement, permissions: snapshot.context.permissions)
        Text(P.noteRenvois)
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.bubblegum)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("etab-compte-note-web")
        ForEach(sections) { section in
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                if let titre = section.section.titre {
                    Text(titre)
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                }
                carte {
                    ForEach(section.entrees) { entree in
                        if entree.id != section.entrees.first?.id { Divider() }
                        Button { presentateur.presenter(entree.route) } label: {
                            HStack(spacing: JoleneSpacing.sm) {
                                Text(entree.libelle)
                                    .font(JoleneFont.body)
                                    .foregroundStyle(JoleneColor.midnight)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: "safari")
                                    .font(JoleneFont.caption)
                                    .foregroundStyle(JoleneColor.bubblegum)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(entree.identifiant)
                        .accessibilityValue(entree.url.absoluteString)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("etab-compte-section-\(section.id)")
        }
    }

    // MARK: - Application

    private var application: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(P.titreApplication)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            carte {
                HStack {
                    Text(P.libelleVersion)
                        .foregroundStyle(JoleneColor.midnight)
                    Spacer()
                    Text("\(JoleneCore.version) · \(container.environment.mode.rawValue)")
                        .foregroundStyle(JoleneColor.bubblegum)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("etab-compte-version")
                }
                .frame(minHeight: 44)
                #if DEBUG
                if let monitor = container.networkSentinel {
                    Divider()
                    NetworkSentinelRow(monitor: monitor)
                        .frame(minHeight: 44)
                }
                #endif
            }
        }
    }

    private func carte<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 0) { contenu() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, JoleneSpacing.md)
            .padding(.vertical, JoleneSpacing.xs)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }
}
