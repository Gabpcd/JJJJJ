import SwiftUI
import JoleneCore
import JoleneDesign

/// Consentement GPS du Profil (lot 2, T4b ; correction 15, décision 4), port de `SectionPreferences.tsx` l.128-168 : le
/// texte de consentement promet le retrait « depuis votre profil » (`ConsentementGPS.tsx` l.50). Titre, libellé,
/// explication selon l'état et retours : `TextesWeb.ProfilConsentementGps` (HARD STOP n°4, verbatim, tutoiement du web
/// conservé). Interrupteur → `fn_consentir_gps(actif)` puis relecture (`ConsentementGpsModel.basculer`), sans audit client
/// (`GPS_CONSENTEMENT_*` absentes du CHECK). Un consentement jamais donné (NULL) s'affiche éteint, avec l'explication du
/// retrait (décision déléguée du 8 novembre 2026). Identifiants : `profil-gps-consentement` (interrupteur),
/// `profil-gps-explication`, `profil-gps-retour`.
struct ConsentementGpsRow: View {
    private typealias T = TextesWeb.ProfilConsentementGps

    @StateObject private var model: ConsentementGpsModel

    init(session: SessionStore, snapshot: SessionSnapshot) {
        _model = StateObject(wrappedValue: ConsentementGpsModel(controller: session.controller, snapshot: snapshot))
    }

    private var lu: Bool {
        if case .lu = model.etat { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(T.titre)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            // Comme le web : libellé et explication à gauche, interrupteur à droite (`aria-label` sur l'interrupteur seul,
            // l'explication reste un texte distinct, lu après lui).
            HStack(alignment: .center, spacing: JoleneSpacing.md) {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(T.libelle)
                        .font(JoleneFont.callout.weight(.medium))
                        .foregroundStyle(JoleneColor.midnight)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                    Text(T.explication(consentementActif: model.interrupteurActif))
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profil-gps-explication")
                }
                Spacer(minLength: 0)
                Toggle(T.libelleAccessibilite,
                       isOn: Binding(get: { model.interrupteurActif }, set: { actif in Task { await model.basculer(actif) } }))
                    .labelsHidden()
                    .tint(JoleneColor.rose700)
                    .disabled(model.enCours || !lu)
                    .accessibilityLabel(T.libelleAccessibilite)
                    .accessibilityIdentifier("profil-gps-consentement")
            }
            if let retour = model.retour {
                InlineNotice(LibellesPresences.Pointage.retourConsentement(retour),
                             tone: LibellesPresences.Pointage.tonConsentement(retour).inlineNotice, identifier: "profil-gps-retour",
                             announcesOnAppear: true)
            }
        }
        .padding(.vertical, JoleneSpacing.xs)
        .task { await model.charger() }
    }
}
