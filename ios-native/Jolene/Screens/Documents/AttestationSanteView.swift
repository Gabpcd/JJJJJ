import SwiftUI
import JoleneCore
import JoleneDesign

/// Retour d'une action ponctuelle (revérification, revue, consultation, attestation), affiché dans sa carte : les toasts du
/// web (`DocumentsSoignant.tsx` l.317-359, l.51-56), ou le message d'erreur levé par le port.
struct RetourAction: Equatable {
    /// Identifiant de la pièce, ou `cibleAttestation`.
    let cible: String
    let texte: TexteJustificatif

    static let cibleAttestation = "attestation"
}

/// Attestation de santé sur l'honneur (lot 2 T7, décision 15), port de `AttestationSante` (`DocumentsSoignant.tsx`
/// l.27-135). HARD STOP n°4 : tous les textes viennent de `TextesWeb.AttestationSante` (TL, verbatim, tutoiement du web
/// conservé en attente de Gabrielle) ; badge, état d'envoi : `LibellesWeb.AttestationSante`. Signature par
/// `DocumentsModel.signerAttestation()` (valeur serveur relue, jamais une seconde fois : web `canSign = … && !signedAt`).
///
/// Identifiants : `attestation-vaccins`, `attestation-medecine`, `attestation-signer`, `attestation-signee`,
/// `attestation-badge`, `attestation-retour`.
struct AttestationSanteView: View {
    private typealias T = TextesWeb.AttestationSante

    @ObservedObject var model: DocumentsModel
    let dossier: DossierDocuments
    @Binding var retour: RetourAction?
    @State private var vaccins = false
    @State private var medecine = false

    private var signee: String? { PresentationJustificatifs.attestationSigneeLe(dossier) }
    private var signatureEnCours: Bool { model.actionEnCours == RetourAction.cibleAttestation }

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
                Text(verbatim: "📋").accessibilityHidden(true)
                Text(T.titre)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if signee != nil {
                    StatusBadge(LibellesWeb.AttestationSante.signee, tone: .success, identifier: "attestation-badge")
                }
            }
            caseACocher(T.vaccinations, cochee: signee != nil || vaccins, identifiant: "attestation-vaccins") { vaccins.toggle() }
            caseACocher(T.medecineDuTravail, cochee: signee != nil || medecine, identifiant: "attestation-medecine") { medecine.toggle() }
            Text(T.faussesDeclarations)
                .font(JoleneFont.caption.italic())
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            if let signee {
                Text(signee)
                    .font(JoleneFont.callout.weight(.medium))
                    .foregroundStyle(JoleneColor.midnight)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(JoleneSpacing.md)
                    .background(JoleneColor.cyan100)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                    .accessibilityIdentifier("attestation-signee")
            } else {
                JoleneButton(signatureEnCours ? LibellesWeb.AttestationSante.signatureEnCours : T.signer, isLoading: signatureEnCours) {
                    signer()
                }
                .disabled(!(vaccins && medecine) || model.actionEnCours != nil)
                .accessibilityIdentifier("attestation-signer")
            }
            if let retour, retour.cible == RetourAction.cibleAttestation {
                InlineNotice(retour.texte.texte, tone: TonsJustificatifs.notice(retour.texte.ton), identifier: "attestation-retour",
                             announcesOnAppear: true)
            }
            Text(T.documentsOriginaux)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("attestation-sante")
    }

    /// Case à cocher du web (`<input type="checkbox">`, désactivée une fois signée) : trait « sélectionné » vocalisé.
    private func caseACocher(_ texte: String, cochee: Bool, identifiant: String, basculer: @escaping () -> Void) -> some View {
        Button(action: basculer) {
            HStack(alignment: .top, spacing: JoleneSpacing.md) {
                Image(systemName: cochee ? "checkmark.square.fill" : "square")
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.rose700)
                    .accessibilityHidden(true)
                Text(texte)
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
        .disabled(signee != nil || signatureEnCours)
        .accessibilityAddTraits(cochee ? .isSelected : [])
        .accessibilityIdentifier(identifiant)
    }

    private func signer() {
        Task {
            if await model.signerAttestation() {
                retour = RetourAction(cible: RetourAction.cibleAttestation,
                                      texte: TexteJustificatif(texte: T.succes, ton: .succes))
            } else if let message = model.messageAction {
                retour = RetourAction(cible: RetourAction.cibleAttestation, texte: TexteJustificatif(texte: message, ton: .erreur))
            }
        }
    }
}
