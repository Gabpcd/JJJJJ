import SwiftUI
import JoleneCore
import JoleneDesign

/// Certificat des signatures, variante « résumé » du soignant (lot 2, T9a ; `CertificatSignature.tsx` l.40-180) :
/// titre, une carte par signataire (rôle, statut, date et heure, OTP validé, RPPS vérifié, PSC actif) et la mention
/// juridique, tous verbatim (`TextesWeb.Certificat`, HARD STOP n°4 ; lignes par `ContratPresentation.signataires`).
/// Les lignes viennent de `ContratModel.signatures` (projection accordée de `signatures_contrats`, correction 22).
/// Sans ligne, rien n'est affiché, comme le web en variante résumé (l.81-82) ; une lecture en échec affiche son
/// message (l.70-75). Identifiants : `<prefixe>` (conteneur), `<prefixe>-<id de signature>`, `<prefixe>-erreur`.
struct CertificatView: View {
    let signatures: [SignatureCertificat]
    let erreur: String?
    let prefixe: String

    var body: some View {
        if let erreur {
            Label(erreur, systemImage: "exclamationmark.circle")
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.rose700)
                .accessibilityIdentifier(prefixe + "-erreur")
        } else if !signatures.isEmpty {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                HStack(spacing: JoleneSpacing.sm) {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(JoleneColor.rose700)
                        .accessibilityHidden(true)
                    Text(TextesWeb.Certificat.titre)
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(ContratPresentation.signataires(signatures)) { signataire in
                    SignataireView(signataire: signataire)
                        .accessibilityIdentifier(prefixe + "-" + signataire.id)
                }
                Text(TextesWeb.Certificat.mention)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(prefixe)
        }
    }
}

/// Carte d'un signataire (l.111-167).
private struct SignataireView: View {
    let signataire: ContratPresentation.Signataire

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(signataire.role)
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                Spacer(minLength: JoleneSpacing.sm)
                JoleneBadge(signataire.statut, tone: signataire.signe ? .success : .info)
            }
            ForEach(signataire.lignes, id: \.libelle) { ligne in
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ligne.libelle).foregroundStyle(JoleneColor.bubblegum)
                        Spacer(minLength: JoleneSpacing.sm)
                        Text(ligne.valeur).foregroundStyle(JoleneColor.midnight)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ligne.libelle).foregroundStyle(JoleneColor.bubblegum)
                        Text(ligne.valeur).foregroundStyle(JoleneColor.midnight)
                    }
                }
                .font(JoleneFont.caption)
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.lavender)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        .accessibilityElement(children: .combine)
    }
}

/// Page `/contrat/:id/certificat` (`CertificatSignaturePage.tsx` l.176-219) : titre, « Contrat <numéro> », certificat
/// résumé, empreinte complète du document signé et son explication, mention de la page. L'export PDF (jsPDF, pied
/// légal) n'est pas porté (`LOT2_PLAN.md` §1.2) : renvoi web vers la page du certificat, bouton seulement quand le
/// présentateur `.safari` est injecté (lot 1 T10 ; jamais un bouton sans effet). Lit le `ContratModel` de l'écran du
/// contrat (aucune relecture) ; le lien de T10 la monte avec son propre modèle (`CertificatRoute`).
/// Identifiants : `certificat-screen`, `certificat-contrat`, `certificat-signatures-<id>`, `certificat-empreinte`,
/// `certificat-explication`, `certificat-export`.
struct CertificatScreen: View {
    @ObservedObject var model: ContratModel
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                if let contrat = model.contrat {
                    Text(LibellesWeb.Certificat.contrat(numero: contrat.numeroContrat, id: contrat.id))
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .accessibilityIdentifier("certificat-contrat")
                    if let presentateur = presentateurRenvoiWeb, let route = ContratPresentation.renvoiCertificat(contratId: contrat.id) {
                        JoleneButton(LibellesWeb.Certificat.telechargerPdf, style: .secondary) { presentateur.presenter(route) }
                            .accessibilityIdentifier("certificat-export")
                    }
                    CertificatView(signatures: model.signatures, erreur: model.erreurCertificat, prefixe: "certificat-signatures")
                    if let empreinte = contrat.hashDocument, !empreinte.isEmpty {
                        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                            Text(TextesWeb.Certificat.empreinteTitre)
                                .font(JoleneFont.headline)
                                .foregroundStyle(JoleneColor.midnight)
                                .accessibilityAddTraits(.isHeader)
                            Text(empreinte)
                                .font(JoleneFont.caption.monospaced())
                                .foregroundStyle(JoleneColor.midnight)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("certificat-empreinte")
                            Text(TextesWeb.Certificat.explicationEmpreinte(storagePath: contrat.storagePath))
                                .font(JoleneFont.caption)
                                .italic()
                                .foregroundStyle(JoleneColor.bubblegum)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("certificat-explication")
                        }
                        .padding(JoleneSpacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(JoleneColor.cloud)
                        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                    }
                    Text(TextesWeb.Certificat.mentionPage)
                        .font(JoleneFont.caption)
                        .italic()
                        .foregroundStyle(JoleneColor.bubblegum)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                } else if case let .echec(message) = model.etat {
                    EmptyState(systemImage: "questionmark.circle", title: LibellesWeb.Contrat.introuvable,
                               message: message, identifier: "certificat-introuvable")
                } else {
                    VStack(spacing: JoleneSpacing.md) {
                        SkeletonBlock(size: .lg)
                        SkeletonCard()
                    }
                    .accessibilityIdentifier("certificat-chargement")
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(TextesWeb.Certificat.titrePage)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("certificat-screen")
    }
}

/// Page du certificat montée par un lien (`/contrat/:id/certificat`, T10) : son propre `ContratModel`, chargé à
/// l'apparition (contrat, original contrôlé, certificat).
struct CertificatRoute: View {
    @StateObject private var model: ContratModel

    init(session: SessionStore, snapshot: SessionSnapshot, contratId: String) {
        _model = StateObject(wrappedValue: ContratModel(controller: session.controller, snapshot: snapshot, contratId: contratId))
    }

    var body: some View {
        CertificatScreen(model: model)
            .task { await model.charger() }
    }
}
