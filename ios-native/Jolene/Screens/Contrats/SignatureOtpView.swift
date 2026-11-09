import SwiftUI
import JoleneCore
import JoleneDesign

/// Signature OTP d'un contrat (lot 2, T9b ; `SignerContratOtp.tsx` l.209-354, décision 18) : vue de
/// `SignatureOtpPresentation`, elle-même rendue depuis la session OTP de T8 (`ContratModel.session`). La vue ne décide
/// rien : elle appelle `accepter(_:)`, `saisirCode(_:)`, `envoyerCode()` et `signer()` ; la session refuse toute
/// requête qu'elle n'autorise pas (une seule à la fois : anti double envoi), la gateway relit avant d'annoncer une
/// signature, le modèle relit le contrat et le certificat avant de publier la confirmation. Le code saisi vit dans la
/// session (mémoire) et dans le champ UIKit, jamais ailleurs ; aucun journal. Textes : `TextesWeb.SignatureOtp`
/// (HARD STOP n°4, verbatim) et `LibellesWeb.SignatureOtp`, assemblés par `SignatureOtpPresentation`.
///
/// Identifiants : `contrat-signature-otp`, `contrat-otp-titre`, `contrat-otp-explication`, `contrat-otp-erreur`,
/// `contrat-otp-envoye`, `contrat-otp-suspendu`, `contrat-consentement`, `contrat-otp-envoyer`,
/// `contrat-otp-destinataire`, `contrat-otp-sms-restants`, `contrat-otp-minuteur`, `contract-otp` (`OTPField` du
/// lot 0), `contrat-otp-tentatives`, `contrat-otp-renvoyer`, `contrat-signer`, `contrat-signe`,
/// `contrat-signature-indisponible`.
struct SignatureOtpView: View {
    @ObservedObject var model: ContratModel
    let presentation: SignatureOtpPresentation

    var body: some View {
        switch presentation.mode {
        case let .signee(confirmation, mention):
            HStack(alignment: .top, spacing: JoleneSpacing.md) {
                Image(systemName: "checkmark.shield.fill")
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.cyan900)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(confirmation)
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(JoleneColor.midnight)
                    Text(mention)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.midnight)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(JoleneSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cyan100)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("contrat-signe")
        case let .indisponible(titre, message):
            InlineNotice(message, title: titre, tone: .warning, identifier: "contrat-signature-indisponible",
                         announcesOnAppear: true)
        case let .formulaire(formulaire):
            contenu(formulaire)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("contrat-signature-otp")
        }
    }

    // MARK: - Formulaire

    private func contenu(_ f: SignatureOtpPresentation.Formulaire) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                Image(systemName: "message")
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.rose700)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(f.titre)
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("contrat-otp-titre")
                    Text(f.explication)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("contrat-otp-explication")
                }
            }

            if let alerte = f.alerte {
                InlineNotice(alerte, tone: .error, identifier: "contrat-otp-erreur", announcesOnAppear: true)
            }
            if let retour = f.retour {
                switch retour {
                case .erreur(let message):
                    InlineNotice(message, tone: .error, identifier: "contrat-otp-erreur", announcesOnAppear: true)
                case .succes(let message):
                    InlineNotice(message, tone: .success, identifier: "contrat-otp-envoye", announcesOnAppear: true)
                }
            }
            if let suspension = f.suspension {
                HStack(spacing: JoleneSpacing.sm) {
                    ProgressView()
                    Text(suspension)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("contrat-otp-suspendu")
            }

            consentement(f)

            if let recevoir = f.recevoir {
                JoleneButton(recevoir.libelle, isLoading: f.enCours) { Task { await model.envoyerCode() } }
                    .disabled(!recevoir.actif)
                    .accessibilityIdentifier("contrat-otp-envoyer")
            }
            if let code = f.codeEnvoye { codeEnvoye(code, enCours: f.enCours) }
        }
    }

    /// Case à cocher du web (l.267-278) : un bouton qui bascule le consentement, état exposé par le trait `isSelected`.
    private func consentement(_ f: SignatureOtpPresentation.Formulaire) -> some View {
        Button { model.accepter(!f.accepte) } label: {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                Image(systemName: f.accepte ? "checkmark.square.fill" : "square")
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.rose700)
                    .accessibilityHidden(true)
                Text(f.consentement)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.midnight)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!f.consentementActif)
        .accessibilityLabel(f.consentement)
        .accessibilityAddTraits(f.accepte ? [.isSelected] : [])
        .accessibilityIdentifier("contrat-consentement")
    }

    // MARK: - Code envoyé

    @ViewBuilder private func codeEnvoye(_ code: SignatureOtpPresentation.CodeEnvoye, enCours: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                Text(code.destinataire)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("contrat-otp-destinataire")
                if let restants = code.smsRestants {
                    Text(restants)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .accessibilityIdentifier("contrat-otp-sms-restants")
                }
            }
            Spacer(minLength: JoleneSpacing.sm)
            HStack(spacing: JoleneSpacing.xs) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text(code.minuteur)
                    .monospacedDigit()
                    .accessibilityIdentifier("contrat-otp-minuteur")
            }
            .font(JoleneFont.caption)
            .foregroundStyle(code.expire ? JoleneColor.rose700 : JoleneColor.bubblegum)
            .fixedSize()
        }

        OTPField(code: Binding(get: { model.session.code }, set: { model.saisirCode($0) }), identifier: "contract-otp",
                 accessibilityLabel: LibellesWeb.SignatureOtp.champCodeAccessibilite)
            .frame(maxWidth: .infinity, minHeight: 52)
            .disabled(!code.champActif)
            .opacity(code.champActif ? 1 : 0.5)

        if let tentatives = code.tentatives {
            Label(tentatives, systemImage: "exclamationmark.circle")
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.butter800)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tentatives)
                .accessibilityIdentifier("contrat-otp-tentatives")
        }

        ViewThatFits(in: .horizontal) {
            HStack(spacing: JoleneSpacing.sm) { boutons(code, enCours: enCours) }
            VStack(spacing: JoleneSpacing.sm) { boutons(code, enCours: enCours) }
        }
    }

    @ViewBuilder private func boutons(_ code: SignatureOtpPresentation.CodeEnvoye, enCours: Bool) -> some View {
        let renvoi = JoleneButton(code.renvoi.libelle, style: .secondary) { Task { await model.envoyerCode() } }
            .disabled(!code.renvoi.actif)
            .accessibilityIdentifier("contrat-otp-renvoyer")
        if let infobulle = code.renvoi.infobulle {
            renvoi.help(infobulle).accessibilityHint(infobulle)
        } else {
            renvoi
        }
        JoleneButton(code.signer.libelle, isLoading: enCours) { Task { await model.signer() } }
            .disabled(!code.signer.actif)
            .accessibilityIdentifier("contrat-signer")
    }
}
