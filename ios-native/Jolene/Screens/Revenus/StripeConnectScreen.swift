import SwiftUI
import JoleneCore
import JoleneDesign

/// Route par valeur de l'écran Stripe Connect (lot 3, T14a), empilée sur l'onglet Profil : entrée du hub (`force` faux :
/// lecture du cache serveur, comme le web hors retour) ou cible d'un lien, d'un tap push ou du centre
/// (`MainTabView.presenter`, jetonnée) ; `force` toujours vrai pour cette seconde voie (revue B8 de #1144, m2 : retour de
/// Stripe ou fermeture du flux par la navigation, relecture `force=true`, correction 17).
struct StripeConnectRoute: Hashable {
    let force: Bool
}

/// Écran `/soignant/stripe-connect` (lot 3, T14a, B9) : vue de `StripeConnectModel` (JoleneCore), port de
/// `src/pages/PageStripeConnect.tsx`. États : chargement, profil indisponible, mode salarié (`stripe-non-eligible`),
/// compte de test (`stripe-compte-test`), statut indisponible (`stripe-erreur`), et les six statuts
/// (`stripe-statut-<STATUT>`). Onboarding hébergé par le flux externe (`ExternalFlowPort`, `ExternalFlowPresenter`) ;
/// toute issue relit le statut avec `force=true`. Raccourcis (Mes gains, Mes présences, Mes contrats, Passer en libéral,
/// Mes charges) par la cible de l'espace : écran natif s'il est livré (Mes présences et Mes contrats empilés au-dessus de
/// cet écran, revue B8 de #1144, m3), renvoi web sinon (seulement avec le présentateur `.safari` du coordinateur des
/// liens : jamais un bouton sans effet).
///
/// Non portés (écarts consignés, `DECISIONS_LOT3.md`, section T14a) : cartes des revenus d'un compte connecté (servies par
/// l'onglet Revenus), « Derniers versements Stripe » (`SuiviVersementsConnect`), « Contacter le support » et « Besoin
/// d'aide ? » (modale web `ModalContacterJolene`, sans équivalent natif).
struct StripeConnectScreen: View {
    @StateObject private var model: StripeConnectModel
    private let force: Bool
    private let ouvrir: (CibleNotification) -> Void
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(session: SessionStore, snapshot: SessionSnapshot, flux: ExternalFlowPort?, force: Bool,
         ouvrir: @escaping (CibleNotification) -> Void) {
        self.force = force
        self.ouvrir = ouvrir
        _model = StateObject(wrappedValue: StripeConnectModel(controller: session.controller, snapshot: snapshot, flux: flux))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(StripeConnectTextes.sousTitre)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                if let avis = model.avis {
                    InlineNotice(avis.texte, tone: Self.ton(avis), identifier: "stripe-avis", announcesOnAppear: true,
                                 announcementID: model.numeroAvis)
                }
                contenu
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("stripe-screen")
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(StripeConnectTextes.titre)
        .task { await model.charger(force: force) }
    }

    private static func ton(_ avis: StripeConnectModel.Avis) -> InlineNotice.Tone {
        if case .erreur = avis { return .error }
        return .info
    }

    // MARK: - États

    @ViewBuilder
    private var contenu: some View {
        switch model.etat {
        case .chargement:
            ProgressView()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("stripe-chargement")
        case .profilIndisponible:
            carte(StripeConnectTextes.profilIndisponible, StripeConnectTextes.profilIndisponibleDetail,
                  identifiant: "stripe-profil-indisponible") {
                JoleneButton(StripeConnectTextes.reessayer, style: .secondary) { Task { await model.charger(force: false) } }
                    .accessibilityIdentifier("stripe-profil-reessayer")
            }
        case .salarie:
            salarie
        case .compteTest:
            carte(StripeConnectTextes.compteTestTitre, StripeConnectTextes.compteTestTexte, identifiant: "stripe-compte-test") {
                EmptyView()
            }
        case .statutIndisponible:
            carte(StripeConnectTextes.statutIndisponible, StripeConnectTextes.statutIndisponibleDetail,
                  identifiant: "stripe-erreur") {
                JoleneButton(StripeConnectTextes.reessayer, style: .secondary, isLoading: model.enCours) {
                    Task { await model.actualiser() }
                }
                .disabled(model.enCours)
                .accessibilityIdentifier("stripe-reessayer")
            }
        case .statut(let statut):
            carteStatut(statut)
        }
    }

    @ViewBuilder
    private func carteStatut(_ statut: StatutConnect) -> some View {
        let identifiant = "stripe-statut-\(statut.statut.rawValue)"
        switch statut.statut {
        case .nonDemande:
            carte(StripeConnectTextes.nonDemandeTitre, StripeConnectTextes.nonDemandeTexte, identifiant: identifiant) {
                puces(StripeConnectTextes.nonDemandeAvantages, identifiant: "stripe-avantages")
                onboarding(StripeConnectTextes.connecter, style: .primary)
            }
        case .enCours:
            carte(StripeConnectTextes.enCoursTitre, StripeConnectTextes.enCoursTexte, identifiant: identifiant) {
                onboarding(StripeConnectTextes.reprendreInscription, style: .secondary)
                actualiser(StripeConnectTextes.actualiserStatut)
            }
        case .complet:
            carte(StripeConnectTextes.completTitre, statut.ibanLast4.map(StripeConnectTextes.iban), identifiant: identifiant) {
                actualiser(StripeConnectTextes.actualiser)
            }
            raccourcis(RaccourciConnect.complet)
        case .suspendu:
            carte(StripeConnectTextes.suspenduTitre, StripeConnectTextes.suspenduTexte, identifiant: identifiant) {
                onboarding(StripeConnectTextes.completerProfil, style: .destructive)
            }
        case .supprime:
            carte(StripeConnectTextes.supprimeTitre, StripeConnectTextes.supprimeTexte, identifiant: identifiant) {
                onboarding(StripeConnectTextes.recommencer, style: .destructive)
            }
        case .rejete:
            carte(StripeConnectTextes.rejeteTitre, StripeConnectTextes.rejeteTexte, identifiant: identifiant) {
                if let motif = statut.disabledReason {
                    Text(StripeConnectTextes.motif(motif))
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("stripe-motif")
                }
                onboarding(StripeConnectTextes.reprendreVerification, style: .destructive)
            }
        }
    }

    @ViewBuilder
    private var salarie: some View {
        carte(StripeConnectTextes.salarieTitre, StripeConnectTextes.salarieTexte, identifiant: "stripe-non-eligible") {
            Text(StripeConnectTextes.salarieEtapesTitre)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
            puces(StripeConnectTextes.salarieEtapes, identifiant: "stripe-etapes-salarie")
        }
        raccourcis(RaccourciConnect.salarie)
        InlineNotice(StripeConnectTextes.salarieInfoTexte, title: StripeConnectTextes.salarieInfoTitre, tone: .info,
                     identifier: "stripe-info-liberal")
    }

    // MARK: - Briques

    private func carte<Actions: View>(_ titre: String, _ texte: String?, identifiant: String,
                                      @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                Text(titre)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("\(identifiant)-titre")
                if let texte {
                    Text(texte)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            actions()
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifiant)
    }

    private func puces(_ lignes: [String], identifiant: String) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            ForEach(lignes, id: \.self) { ligne in
                Label(ligne, systemImage: "checkmark.circle")
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifiant)
    }

    private func onboarding(_ titre: String, style: JoleneButton.Style) -> some View {
        JoleneButton(titre, style: style, isLoading: model.enCours) { Task { await model.lancerOnboarding() } }
            .disabled(model.enCours)
            .accessibilityIdentifier("stripe-onboarding")
    }

    private func actualiser(_ titre: String) -> some View {
        JoleneButton(titre, style: .secondary, isLoading: model.enCours) { Task { await model.actualiser() } }
            .disabled(model.enCours)
            .accessibilityIdentifier("stripe-actualiser")
    }

    @ViewBuilder
    private func raccourcis(_ liste: [RaccourciConnect]) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            ForEach(liste) { raccourci in
                if let cible = cible(raccourci.lien) {
                    Button { ouvrir(cible) } label: {
                        HStack(spacing: JoleneSpacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(raccourci.titre)
                                    .font(JoleneFont.callout.weight(.semibold))
                                    .foregroundStyle(JoleneColor.midnight)
                                Text(raccourci.detail)
                                    .font(JoleneFont.caption)
                                    .foregroundStyle(JoleneColor.bubblegum)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(JoleneColor.bubblegum)
                        }
                        .padding(JoleneSpacing.md)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(JoleneColor.cloud)
                        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(raccourci.identifiant)
                }
            }
        }
    }

    /// Cible présentable d'un raccourci (renvoi web seulement avec le présentateur `.safari`), nil sinon.
    private func cible(_ lien: String) -> CibleNotification? {
        guard let destination = DestinationLien(link: lien) else { return nil }
        let cible = CibleNotification(destination)
        return cible.estPresentable(renvoiWebDisponible: presentateurRenvoiWeb != nil) ? cible : nil
    }
}

/// Ligne « Compte de paiement (Stripe) » du hub, première de la section unique « Paiements & facturation »
/// (`PaiementsFacturationSection`, `MonCompteSoignant.tsx` l.64-68), montée par le hub seulement si la règle web
/// `estLiberal` (l.45-48 : `LIBERAL`, `MIXTE` ou `statut_liberal = 'ACTIF'`) est vraie à la lecture de l'exercice
/// (`estVisible`) ; une lecture en échec ne montre rien (le web n'affiche l'entrée qu'avec un profil lu). Lien par valeur
/// (`StripeConnectRoute`, destination enregistrée par `MainTabView` sur la pile du Profil).
struct StripeConnectEntreeLigne: View {
    var body: some View {
        NavigationLink(value: StripeConnectRoute(force: false)) {
            Label(StripeConnectTextes.entreeHub, systemImage: "creditcard")
                .font(JoleneFont.body)
                .foregroundStyle(JoleneColor.midnight)
                .frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("profile-stripe-connect")
    }

    /// Exercice lu pour l'epoch de l'espace, borné au délai de la session ; faux en échec.
    @MainActor
    static func estVisible(session: SessionStore, snapshot: SessionSnapshot) async -> Bool {
        let controller = session.controller
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.stripeConnect
        let context = snapshot.context
        let exercice = try? await bounded(timeout: controller.resolutionTimeout) { try await port.exercice(context: context) }
        return exercice?.entreeHub == true
    }
}
