import SwiftUI
import JoleneCore
import JoleneDesign

/// Fil de discussion d'un litige déplié (L4-T8), port de `FilDiscussionLitige.tsx` sans les accords amiables : vue de
/// `LitigeFilModel` (JoleneCore). Bandeau de revue admin ou de clôture (texte de clôture du serveur tel quel), messages
/// dans l'ordre chronologique, champ de message tant que le litige n'est pas résolu (`LitigesPresentation.peutEcrire`),
/// puis le renvoi « Accord amiable sur jolene.app » tant que le web propose un accord (`accordSurLeWeb`, D9), présenté
/// par le présentateur `.safari` (jamais `openURL`). **Aucun texte de délai** : le bandeau de médiation du web
/// (« … 7 jours … ») et son compte à rebours ne sont pas portés. Un refus du serveur s'affiche mot pour mot.
///
/// Identifiants : `litige-fil-<id>` ; `litige-revue-admin`, `litige-cloture`, `litige-resolution` ;
/// `litige-fil-chargement`, `litige-fil-erreur` (+ `-reessayer`), `litige-fil-vide`, `litige-fil-message-<id>` ;
/// `litige-message-input`, `litige-message-envoyer`, `litige-message-erreur` ; `litige-accord-web` (carte, bouton
/// `litige-accord-web-ouvrir`).
struct LitigeFilView: View {
    let litige: Litige
    /// Relecture de la liste après un message (`onUpdate` du web) : le statut du litige a pu changer.
    let apresEnvoi: () async -> Void
    @StateObject private var model: LitigeFilModel
    @FocusState private var saisieActive: Bool
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(litige: Litige, session: SessionStore, snapshot: SessionSnapshot, apresEnvoi: @escaping () async -> Void) {
        self.litige = litige
        self.apresEnvoi = apresEnvoi
        _model = StateObject(wrappedValue: LitigeFilModel(litigeId: litige.id, controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            bandeaux
            messages
            if LitigesPresentation.peutEcrire(statut: litige.statut) { composeur }
            accordWeb
        }
        .task { await model.charger() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("litige-fil-\(litige.id)")
    }

    // MARK: - Bandeaux

    @ViewBuilder private var bandeaux: some View {
        if litige.statut == "REVUE_ADMIN" {
            InlineNotice(LitigesTextes.revueAdmin, tone: .warning, identifier: "litige-revue-admin")
        }
        if StatutLitige.estResolu(litige.statut) {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                Text(LitigesTextes.litigeCloture)
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityIdentifier("litige-cloture")
                if let resolution = litige.resolution, !resolution.isEmpty {
                    Text(resolution)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.midnight)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("litige-resolution")
                }
            }
            .padding(JoleneSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cyan100)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        }
    }

    // MARK: - Messages

    @ViewBuilder private var messages: some View {
        switch model.fil {
        case .chargement:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("litige-fil-chargement")
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .error, identifier: "litige-fil-erreur")
                if !model.sessionExpiree {
                    JoleneButton(LitigesTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                        .accessibilityIdentifier("litige-fil-erreur-reessayer")
                }
            }
        case let .prete(lignes):
            if lignes.isEmpty {
                Text(LitigesTextes.aucunMessage)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("litige-fil-vide")
            } else {
                ForEach(lignes) { ligne($0) }
            }
        }
    }

    /// Message (`FilDiscussionLitige.tsx` l.156-171) : auteur, date, contenu tel quel, jamais tronqué.
    private func ligne(_ message: MessageLitige) -> some View {
        let auteur = LitigesPresentation.auteur(message, userId: model.userId)
        let date = LitigesPresentation.heureMessage(message.creeLe)
        return VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            HStack(spacing: JoleneSpacing.sm) {
                Text(auteur)
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                if let date {
                    Text(date)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                }
            }
            Text(message.contenu)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.lavender)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("litige-fil-message-\(message.id)")
    }

    // MARK: - Composeur

    private var composeur: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            TextField(LitigesTextes.messagePlaceholder,
                      text: Binding(get: { model.saisie }, set: { model.saisir($0) }), axis: .vertical)
                .lineLimit(2...6)
                .font(.system(size: 16))
                .focused($saisieActive)
                .boutonOKClavier($saisieActive, actif: !model.envoiEnCours)
                .padding(JoleneSpacing.md)
                .background(JoleneColor.lavender)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(JoleneColor.rose100, lineWidth: 1))
                .disabled(model.envoiEnCours)
                .accessibilityLabel(LitigesTextes.messagePlaceholder)
                .accessibilityIdentifier("litige-message-input")
            if let erreur = model.erreur {
                InlineNotice(erreur, tone: .error, identifier: "litige-message-erreur", announcementID: model.jeton)
            }
            JoleneButton(model.envoiEnCours ? LitigesTextes.envoi : LitigesTextes.envoyer, style: .secondary,
                         isLoading: model.envoiEnCours) {
                saisieActive = false
                Task {
                    if await model.envoyer() { await apresEnvoi() }
                }
            }
            .disabled(!model.peutEnvoyer)
            .accessibilityIdentifier("litige-message-envoyer")
        }
    }

    // MARK: - Renvoi des accords amiables

    @ViewBuilder private var accordWeb: some View {
        if LitigesPresentation.accordSurLeWeb(statut: litige.statut), let presentateurRenvoiWeb,
           let url = EcranSecondaire.litiges(onglet: nil, litigeId: litige.id).urlWeb {
            WebHandoffCard(title: LitigesTextes.accordWebTitre, message: LitigesTextes.accordWebMessage, url: url,
                           identifier: "litige-accord-web", actionIdentifier: "litige-accord-web-ouvrir") {
                presentateurRenvoiWeb.presenter(.safari(url))
            }
        }
    }
}
