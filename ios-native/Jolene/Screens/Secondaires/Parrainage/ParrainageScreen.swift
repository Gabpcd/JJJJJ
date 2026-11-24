import SwiftUI
import UIKit
import JoleneCore
import JoleneDesign

/// Parrainage (`/soignant/parrainage`, L4-T6), port de `src/pages/PageParrainage.tsx`, empilé sur le Profil par
/// `SecondaryRouter` une fois son coupe-circuit `ios_natif_parrainage_actif` lu (fail-open). Vue de `ParrainageModel`
/// (JoleneCore) ; textes de `ParrainageTextes`, repris mot pour mot du web.
///
/// - Chargement, échec (« Parrainage indisponible », « Réessayer »), lien « pas encore disponible » (sans code) ;
/// - badge Ambassadeur seulement s'il est débloqué (état serveur, sans sa condition) ;
/// - code, copie du code, QR code et lien (`https://jolene.app/inscription/soignant?ref=<code>`, rien d'autre), copie du
///   lien, feuille de partage du système (`ShareSheet`) avec le message du web ;
/// - compteurs (filleuls inscrits, missions terminées), filleuls avec leur statut serveur ;
/// - **aucun** montant, aucune condition ni promesse de prime : le bloc de conditions est hors de cette tranche (T6-HS,
///   HARD STOP n°4). La page web reste accessible par le renvoi neutre « Voir sur jolene.app » (présentateur `.safari`).
///
/// Identifiants : `parrainage-screen`, `parrainage-chargement`, `parrainage-indisponible`, `parrainage-reessayer`,
/// `parrainage-a-preparer` (+ `-explorer`, `-dossier`), `parrainage-badge`, `parrainage-code`, `parrainage-copier`,
/// `parrainage-qr`, `parrainage-lien`, `parrainage-copier-lien`, `parrainage-partager`, `parrainage-compteur-inscrits`,
/// `parrainage-compteur-missions`, `parrainage-filleuls-vide`, `parrainage-filleul-<id>`, `parrainage-web`.
struct ParrainageScreen: View {
    let contexte: ContexteSecondaire
    @StateObject private var model: ParrainageModel
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    @State private var copie: Copie?

    private enum Copie { case code, lien }

    init(contexte: ContexteSecondaire) {
        self.contexte = contexte
        _model = StateObject(wrappedValue: ParrainageModel(controller: contexte.session.controller, snapshot: contexte.snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                contenu
                if let presentateurRenvoiWeb, let url = EcranSecondaire.parrainage.urlWeb {
                    // Renvoi neutre vers la page web (conditions comprises, hors de l'écran natif : T6-HS).
                    JoleneButton(RenvoiWebScreen.bouton, style: .secondary) { presentateurRenvoiWeb.presenter(.safari(url)) }
                        .accessibilityIdentifier("parrainage-web")
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.charger() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(ParrainageTextes.titre)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("parrainage-screen")
        .task { await model.charger() }
    }

    // MARK: - Contenu

    @ViewBuilder private var contenu: some View {
        switch model.etat {
        case .chargement:
            HStack(spacing: JoleneSpacing.sm) {
                ProgressView()
                Text(ParrainageTextes.chargement).font(JoleneFont.callout).foregroundStyle(JoleneColor.midnight)
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("parrainage-chargement")
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                Text(ParrainageTextes.indisponibleTitre)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                InlineNotice(message, tone: .error, identifier: "parrainage-indisponible")
                JoleneButton(ParrainageTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                    .accessibilityIdentifier("parrainage-reessayer")
            }
        case let .pret(etat):
            pret(etat)
        }
    }

    @ViewBuilder private func pret(_ etat: EtatParrainage) -> some View {
        let lien = etat.code.flatMap { ParrainagePresentation.lien(code: $0) }
        if lien == nil { aPreparer(etat) }
        if etat.badgeAmbassadeur { badge }
        if let code = etat.code, let lien { partage(code: code, lien: lien) }
        compteurs(etat.filleuls)
        filleuls(etat.filleuls, partageDisponible: lien != nil)
    }

    /// Sans code : l.139-154.
    private func aPreparer(_ etat: EtatParrainage) -> some View {
        carte(identifiant: "parrainage-a-preparer") {
            Text(ParrainageTextes.aPreparerTitre)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            Text(etat.profilPresent ? ParrainageTextes.aPreparerProfil : ParrainageTextes.aPreparerSansProfil)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            JoleneButton(ParrainageTextes.explorer) { contexte.ouvrir(.explorer) }
                .accessibilityIdentifier("parrainage-a-preparer-explorer")
            if etat.profilPresent {
                JoleneButton(ParrainageTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                    .accessibilityIdentifier("parrainage-reessayer")
            } else {
                JoleneButton(ParrainageTextes.preparerDossier, style: .secondary) { contexte.ouvrir(.profil) }
                    .accessibilityIdentifier("parrainage-a-preparer-dossier")
            }
        }
    }

    /// Badge débloqué (l.163-165) ; sa condition d'obtention n'est pas affichée (T6-HS).
    private var badge: some View {
        carte(identifiant: "parrainage-badge") {
            HStack(spacing: JoleneSpacing.sm) {
                Image(systemName: "shield.fill").foregroundStyle(JoleneColor.rose800).accessibilityHidden(true)
                Text(ParrainageTextes.badgeTitre).font(JoleneFont.headline).foregroundStyle(JoleneColor.midnight)
            }
            Text(ParrainageTextes.badgeDebloque).font(JoleneFont.callout.weight(.semibold)).foregroundStyle(JoleneColor.rose800)
        }
    }

    /// Code, QR code et lien (l.200-252).
    private func partage(code: String, lien: URL) -> some View {
        carte(identifiant: "parrainage-partage") {
            Text(ParrainageTextes.tonCode)
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(JoleneColor.bubblegum)
                .frame(maxWidth: .infinity)
            HStack(spacing: JoleneSpacing.sm) {
                Text(code)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(JoleneColor.rose800)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("parrainage-code")
                Button { copier(code, .code) } label: {
                    Image(systemName: copie == .code ? "checkmark.circle" : "doc.on.doc")
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.rose800)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ParrainageTextes.copierCode)
                .accessibilityValue(copie == .code ? ParrainageTextes.copie : "")
                .accessibilityIdentifier("parrainage-copier")
            }
            .frame(maxWidth: .infinity)
            QRCodeImage(lien.absoluteString, accessibilityLabel: ParrainageTextes.qrCode, identifier: "parrainage-qr")
                .frame(maxWidth: .infinity)
            Text(lien.absoluteString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(JoleneColor.bubblegum)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("parrainage-lien")
            JoleneButton(copie == .lien ? ParrainageTextes.copie : ParrainageTextes.copierLien) { copier(lien.absoluteString, .lien) }
                .accessibilityIdentifier("parrainage-copier-lien")
            JoleneButton(ParrainageTextes.partager, style: .secondary) {
                ShareSheet.presenter(elements: [ParrainagePresentation.messagePartage(lien: lien)]) {}
            }
            .accessibilityIdentifier("parrainage-partager")
        }
    }

    /// Compteurs (l.281-290).
    private func compteurs(_ filleuls: [Filleul]) -> some View {
        let valides = ParrainagePresentation.valides(filleuls)
        return HStack(spacing: JoleneSpacing.md) {
            compteur(filleuls.count, libelle: ParrainagePresentation.compteurInscrits(filleuls.count),
                     identifiant: "parrainage-compteur-inscrits")
            compteur(valides, libelle: ParrainagePresentation.compteurMissions(valides), identifiant: "parrainage-compteur-missions")
        }
    }

    private func compteur(_ nombre: Int, libelle: String, identifiant: String) -> some View {
        VStack(spacing: JoleneSpacing.xs) {
            Text("\(nombre)").font(.system(.title, design: .rounded).weight(.heavy)).foregroundStyle(JoleneColor.rose800)
            Text(libelle).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum).multilineTextAlignment(.center)
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifiant)
    }

    /// « Mes filleuls » (l.306-384), sans la colonne « Vers la prime » (T6-HS).
    private func filleuls(_ filleuls: [Filleul], partageDisponible: Bool) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(ParrainageTextes.mesFilleuls)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            if filleuls.isEmpty {
                Text(partageDisponible ? ParrainageTextes.aucunFilleul : ParrainageTextes.filleulsAVenir)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .multilineTextAlignment(.center)
                    .padding(JoleneSpacing.xl)
                    .frame(maxWidth: .infinity)
                    .background(JoleneColor.cloud)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                    .accessibilityIdentifier("parrainage-filleuls-vide")
            } else {
                ForEach(filleuls) { ligne($0) }
            }
        }
    }

    private func ligne(_ filleul: Filleul) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                Text(filleul.prenom).font(JoleneFont.headline).foregroundStyle(JoleneColor.midnight)
                Text("\(ParrainageTextes.colonneInscription) : \(ParrainagePresentation.dateInscription(filleul.creeLe))")
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
            }
            Spacer(minLength: 0)
            Text(ParrainagePresentation.statut(filleul))
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(JoleneColor.rose800)
                .padding(.horizontal, JoleneSpacing.sm)
                .padding(.vertical, JoleneSpacing.xs)
                .background(JoleneColor.mauve100)
                .clipShape(Capsule())
                .accessibilityLabel("\(ParrainageTextes.colonneStatut) : \(ParrainagePresentation.statut(filleul))")
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("parrainage-filleul-\(filleul.id)")
    }

    // MARK: - Outils

    private func carte<Contenu: View>(identifiant: String, @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) { contenu() }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifiant)
    }

    /// Copie dans le presse-papiers, confirmation pendant 2 s (l.96-105).
    private func copier(_ texte: String, _ cible: Copie) {
        UIPasteboard.general.string = texte
        copie = cible
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copie == cible { copie = nil }
        }
    }
}
