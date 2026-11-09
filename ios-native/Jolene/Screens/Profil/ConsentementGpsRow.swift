import SwiftUI
import JoleneCore
import JoleneDesign

/// Consentement GPS du Profil (lot 2, T4b ; correction 15, décision 4), port de `SectionPreferences.tsx` l.128-168 : le
/// texte de consentement promet le retrait « depuis votre profil » (`ConsentementGPS.tsx` l.50). Titre, libellé,
/// explication selon l'état et retours : `TextesWeb.ProfilConsentementGps` (HARD STOP n°4, verbatim, tutoiement du web
/// conservé). Interrupteur → `fn_consentir_gps(actif)` puis relecture (`ConsentementGpsModel.basculer`), sans audit client
/// (`GPS_CONSENTEMENT_*` absentes du CHECK). Un consentement jamais donné (NULL) s'affiche éteint, avec l'explication du
/// retrait ; l'activer présente d'abord la feuille verbatim (`ConsentementGpsSheet` : finalité, durée de conservation,
/// base légale), dont la réponse passe par `repondre` (RPC, relecture, audit `RGPD_CONSENTEMENT_DONNE`) — décision
/// déléguée D-T4b-1 amendée (revue fraîche de T4b, M2).
///
/// États (revue fraîche de T4b, M3 ; `ConsentementGpsModel.ligneProfil`) : indicateur pendant la lecture ; en échec, le
/// message du port et « Réessayer » (le web passe aussi en erreur de chargement, `ProfilSoignant.tsx` l.199-200,
/// l.409-412) ; l'interrupteur et son explication seulement pour une valeur relue (un consentement donné n'est jamais
/// affiché retiré). Identifiants : `profil-gps-consentement` (interrupteur), `profil-gps-explication`, `profil-gps-retour`,
/// `profil-gps-chargement`, `profil-gps-erreur`, `profil-gps-reessayer` ; feuille : `gps-consent-sheet`.
struct ConsentementGpsRow: View {
    private typealias T = TextesWeb.ProfilConsentementGps

    @StateObject private var model: ConsentementGpsModel
    @Environment(\.appareil) private var appareil

    init(session: SessionStore, snapshot: SessionSnapshot) {
        _model = StateObject(wrappedValue: ConsentementGpsModel(controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(T.titre)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            switch model.ligneProfil {
            case .chargement:
                HStack(spacing: JoleneSpacing.sm) {
                    ProgressView().tint(JoleneColor.rose700)
                    Text(T.libelle)
                        .font(JoleneFont.callout.weight(.medium))
                        .foregroundStyle(JoleneColor.midnight)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("profil-gps-chargement")
            case let .indisponible(message):
                InlineNotice(message, tone: .error, identifier: "profil-gps-erreur", announcesOnAppear: true)
                JoleneButton(LibellesWeb.Pointage.reessayer, style: .secondary) { Task { await model.charger() } }
                    .accessibilityIdentifier("profil-gps-reessayer")
            case let .interrupteur(actif):
                interrupteur(actif: actif)
            }
            if let retour = model.retour {
                InlineNotice(LibellesPresences.Pointage.retourConsentement(retour),
                             tone: LibellesPresences.Pointage.tonConsentement(retour).inlineNotice, identifier: "profil-gps-retour",
                             announcesOnAppear: true)
            }
        }
        .padding(.vertical, JoleneSpacing.xs)
        .task { await model.charger() }
        .sheet(isPresented: Binding(get: { model.feuilleRequise }, set: { if !$0 { model.fermerFeuille() } })) {
            ConsentementGpsSheet(enCours: model.enCours, accepter: { repondre(true) }, refuser: { repondre(false) })
        }
    }

    /// Comme le web : libellé et explication à gauche, interrupteur à droite (`aria-label` sur l'interrupteur seul,
    /// l'explication reste un texte distinct, lu après lui). L'explication suit la valeur relue ; l'interrupteur montre le
    /// choix en vol pendant une demande (désactivé, m1).
    private func interrupteur(actif: Bool) -> some View {
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
            Toggle(T.libelleAccessibilite, isOn: Binding(get: { actif }, set: { demande in
                Task { await model.basculer(demande) }
            }))
            .labelsHidden()
            .tint(JoleneColor.rose700)
            .disabled(model.enCours || model.feuilleRequise)
            .accessibilityLabel(T.libelleAccessibilite)
            .accessibilityIdentifier("profil-gps-consentement")
        }
    }

    /// Réponse à la feuille du premier consentement : RPC, relecture, audit, puis autorisation iOS après un « Autoriser »
    /// (`repondre` ferme la feuille ; une seule réponse part, `enCours` posé avant tout `await`).
    private func repondre(_ accepte: Bool) {
        guard !model.enCours else { return }
        let localisation = appareil?.localisation
        Task { _ = await model.repondre(accepte: accepte, localisation: localisation) }
    }
}
