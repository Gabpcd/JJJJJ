import SwiftUI
import JoleneCore
import JoleneDesign

/// « Préférences de notifications » (lot 3, T6) : vue de `PreferencesModel` (JoleneCore), port de
/// `src/pages/PageParametresNotifications.tsx`. Règles (case grisée, alerte SMS, relecture concordante,
/// échec partiel, délai dépassé) et textes verbatim testés dans JoleneCore
/// (`PreferencesNotificationsTests`, `PreferencesModelTests`) ; la vue n'ajoute aucune règle.
///
/// Sections, dans l'ordre du web : SMS d'alerte (si la ligne `soignants` a été lue), canaux globaux (+ état
/// d'autorisation de l'appareil, point d'extension `etatAppareil`), matrice par événement (catalogue filtré
/// par régime ; une carte par événement, un interrupteur par canal de l'événement — le « — » du web n'a pas
/// d'interrupteur), notifications d'urgence, puis « Enregistrer » dans une barre fixe au-dessus de la
/// barre d'onglets, avec l'issue de l'enregistrement.
///
/// Identifiants : `prefs-screen`, `prefs-loading`, `prefs-error`, `prefs-retry`, `prefs-session-expired`,
/// `prefs-session-check`, `prefs-sms-alertes` (+ `-avertissement`), `prefs-canal-email|push|sms|inapp`,
/// `prefs-evt-<TYPE>-<CANAL>`, `prefs-urgence`, `prefs-barre-action`, `prefs-enregistrer`, `prefs-enregistre`,
/// `prefs-enregistrement-partiel`, `prefs-enregistrement-erreur`.
///
/// Point d'extension T4 : `EtatNotificationsAppareilRow` (`push-etat-appareil`, `push-ouvrir-reglages`) n'est
/// pas encore sur la base ; il se passe en `etatAppareil` sans autre changement de cet écran.
struct PreferencesScreen<EtatAppareil: View>: View {
    @StateObject private var model: PreferencesModel
    @ObservedObject private var session: SessionStore
    private let etatAppareil: EtatAppareil

    init(session: SessionStore, snapshot: SessionSnapshot, @ViewBuilder etatAppareil: () -> EtatAppareil) {
        self.session = session
        self.etatAppareil = etatAppareil()
        _model = StateObject(wrappedValue: PreferencesModel(controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                switch model.state {
                case .loading:
                    chargement
                case let .failed(message) where model.sessionExpired:
                    EmptyState(systemImage: "person.crop.circle.badge.exclamationmark", title: "Session à vérifier", message: message,
                               identifier: "prefs-session-expired", actionTitle: "Vérifier ma session",
                               actionIdentifier: "prefs-session-check") { Task { await model.verifierSession(session) } }
                case .failed:
                    EmptyState(systemImage: "bell.slash", title: PreferencesTextes.titre,
                               message: PreferencesTextes.chargementImpossible, identifier: "prefs-error",
                               actionTitle: PreferencesTextes.reessayer, actionIdentifier: "prefs-retry") {
                        Task { await model.load() }
                    }
                case let .loaded(preferences):
                    contenu(preferences)
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if model.preferences != nil { barreAction }
        }
        .accessibilityIdentifier("prefs-screen")
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(PreferencesTextes.titre)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.chargerSiNecessaire() }
    }

    // MARK: - États

    private var chargement: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            SkeletonBlock(size: .sm, width: 260)
            SkeletonCard()
            SkeletonCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prefs-loading")
    }

    @ViewBuilder
    private func contenu(_ preferences: PreferencesNotifications) -> some View {
        Text(PreferencesTextes.sousTitre)
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.bubblegum)
            .accessibilityIdentifier("prefs-sous-titre")
        if preferences.afficheAlerteSms {
            alerteSms(preferences)
        }
        canauxGlobaux(preferences)
        evenements(preferences)
        InlineNotice(PreferencesTextes.texteUrgence, title: PreferencesTextes.titreUrgence, tone: .warning,
                     identifier: "prefs-urgence")
    }

    // MARK: - Sections

    private func section<Contenu: View>(_ titre: String, identifiant: String, description: String,
                                        @ViewBuilder contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            SectionHeader(titre, identifier: identifiant)
            Text(description)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            contenu()
        }
        .padding(JoleneSpacing.lg)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }

    private func alerteSms(_ preferences: PreferencesNotifications) -> some View {
        section(PreferencesTextes.titreAlerteSms, identifiant: "prefs-section-sms", description: PreferencesTextes.descriptionAlerteSms) {
            if preferences.afficheAvertissementCanalSms {
                Text(PreferencesTextes.avertissementCanalSms)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("prefs-sms-alertes-avertissement")
            }
            ToggleRow(PreferencesTextes.libelleAlerteSms, systemImage: "message",
                      isOn: Binding(get: { preferences.smsAlertesActives ?? false }, set: { model.definirAlerteSms($0) }),
                      isDisabled: !preferences.alerteSmsModifiable || model.estEnregistrementEnCours,
                      identifier: "prefs-sms-alertes")
        }
    }

    private func canauxGlobaux(_ preferences: PreferencesNotifications) -> some View {
        section(PreferencesTextes.titreCanaux, identifiant: "prefs-section-canaux", description: PreferencesTextes.descriptionCanaux) {
            // Ordre du web (l.321-324) : e-mail, push, SMS, in-app.
            ForEach([CanalNotification.email, .push, .sms, .inApp], id: \.self) { canal in
                ToggleRow(PreferencesTextes.libelleCanalGlobal(canal), systemImage: Self.icone(canal),
                          isOn: Binding(get: { preferences.canalGlobalActif(canal) },
                                        set: { model.definirCanalGlobal(canal, actif: $0) }),
                          isDisabled: model.estEnregistrementEnCours,
                          identifier: PreferencesTextes.identifiantCanal(canal))
            }
            etatAppareil
        }
    }

    private func evenements(_ preferences: PreferencesNotifications) -> some View {
        section(PreferencesTextes.titreEvenements, identifiant: "prefs-section-evenements",
                description: PreferencesTextes.descriptionEvenements) {
            ForEach(preferences.evenementsVisibles) { evenement in
                carte(evenement, preferences)
            }
        }
    }

    private func carte(_ evenement: EvenementNotification, _ preferences: PreferencesNotifications) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(evenement.libelle)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(evenement.description)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(CatalogueNotificationsSoignant.colonnes.filter(evenement.canaux.contains), id: \.self) { canal in
                let canalActif = preferences.canalGlobalActif(canal)
                ToggleRow(PreferencesTextes.libelleColonne(canal), systemImage: Self.icone(canal),
                          isOn: Binding(get: { preferences.estActif(type: evenement.type, canal: canal) },
                                        set: { _ in model.basculer(type: evenement.type, canal: canal) }),
                          isDisabled: !canalActif || model.estEnregistrementEnCours,
                          disabledReason: canalActif ? nil : PreferencesTextes.raisonCanalDesactive(canal),
                          isBordered: false,
                          identifier: PreferencesTextes.identifiantEvenement(type: evenement.type, canal: canal))
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(JoleneColor.rose100, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prefs-evt-\(evenement.type)")
    }

    // MARK: - Enregistrement

    private var barreAction: some View {
        VStack(spacing: JoleneSpacing.sm) {
            switch model.enregistrement {
            case .enregistre:
                InlineNotice(PreferencesTextes.enregistre, tone: .success, identifier: "prefs-enregistre", announcesOnAppear: true)
            case let .partiel(message):
                InlineNotice(message, tone: .warning, identifier: "prefs-enregistrement-partiel", announcesOnAppear: true)
            case let .echec(message):
                InlineNotice(message, tone: .error, identifier: "prefs-enregistrement-erreur", announcesOnAppear: true)
            case .aucun, .enCours:
                EmptyView()
            }
            JoleneButton(PreferencesTextes.enregistrer, isLoading: model.estEnregistrementEnCours) {
                Task { await model.enregistrer() }
            }
            .disabled(model.estEnregistrementEnCours)
            .accessibilityIdentifier("prefs-enregistrer")
        }
        .padding(.horizontal, JoleneSpacing.lg)
        .padding(.vertical, JoleneSpacing.sm)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prefs-barre-action")
    }

    /// Icônes du web (`Mail`, `Smartphone`, `MessageSquare`, `Bell`, l.321-324).
    private static func icone(_ canal: CanalNotification) -> String {
        switch canal {
        case .email: return "envelope"
        case .push: return "iphone"
        case .sms: return "message"
        case .inApp: return "bell"
        }
    }
}

extension PreferencesScreen where EtatAppareil == EmptyView {
    /// Sans état d'autorisation de l'appareil tant que T4 (`EtatNotificationsAppareilRow`) n'est pas sur la base.
    init(session: SessionStore, snapshot: SessionSnapshot) {
        self.init(session: session, snapshot: snapshot) { EmptyView() }
    }
}
