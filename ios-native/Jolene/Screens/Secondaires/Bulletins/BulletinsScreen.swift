import SwiftUI
import JoleneCore
import JoleneDesign

/// Copies officielles des bulletins (`/soignant/mes-gains?tab=bulletins&copie=`, L4-T10), port de `CopiesBulletinsSoignant`
/// (`src/components/CopiesBulletins.tsx` l.22-50) et du composant réellement monté `CopiesBulletinsListe.tsx` (rôle
/// SOIGNANT), empilé sur le Profil par `SecondaryRouter` une fois son coupe-circuit `ios_natif_bulletins_actif` lu
/// (fail-open). Vue de `BulletinsModel` (JoleneCore), qui porte les règles (contrôle d'intégrité, relecture qui confirme,
/// copie retirée, délai, session, epoch) ; la vue n'ajoute aucune logique.
///
/// - En tête, la mention verbatim de l'employeur (`TextesWeb.CopiesBulletins.mentionEmployeur`, HARD STOP n°4) : les PDF
///   sont déposés par l'employeur ; Jolene n'en est pas l'auteur.
/// - Filtre « Employeur » à partir de deux employeurs ; cartes dans l'ordre du web ; copie visée par le lien mise en avant.
/// - « Ouvrir / télécharger le PDF original » : PDF vérifié présenté par `PDFLecteur` (partage d'une copie temporaire
///   protégée) ; copie falsifiée : refus d'intégrité, rien n'est affiché ; copie retirée : aucun bouton.
/// - « Signaler une erreur » : feuille aux trois motifs verbatim ; `DESTINATAIRE` affiche l'avertissement de retrait
///   verbatim (`TextesWeb.CopiesBulletins.avertissementRetrait`) avant la confirmation.
/// - Simulations de paie : renvoi web assumé (D12), par le présentateur `.safari` (jamais `openURL`).
///
/// Identifiants : `bulletins-screen`, `bulletins-mention`, `bulletins-chargement`, `bulletins-erreur` (+ `-reessayer`),
/// `bulletins-vide`, `bulletins-employeur`, `bulletins-copie-indisponible`, `bulletins-action-erreur`,
/// `copie-integrite-erreur`, `bulletins-confirmation`, `bulletins-session-check` ; `copie-<id>`, `copie-statut-<id>`,
/// `copie-ouvrir-<id>`, `copie-retiree-<id>`, `copie-signaler-<id>`, `copie-signalee-<id>` ; `bulletins-simulations-web` ;
/// feuille `copie-signalement` (`copie-motif-<MOTIF>`, `copie-avertissement-retrait`, `copie-signalement-envoyer`,
/// `copie-signalement-annuler`, `copie-signalement-erreur`) ; lecteur `pdf-lecteur`, `pdf-partager`.
struct BulletinsScreen: View {
    private typealias L = LibellesWeb.CopiesBulletins

    let copieId: String?
    let contexte: ContexteSecondaire
    @StateObject private var model: BulletinsModel
    @ObservedObject private var session: SessionStore
    @State private var aSignaler: CopieBulletin?
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(copieId: String?, contexte: ContexteSecondaire) {
        self.copieId = copieId
        self.contexte = contexte
        self.session = contexte.session
        _model = StateObject(wrappedValue: BulletinsModel(controller: contexte.session.controller, snapshot: contexte.snapshot,
                                                          copieCible: copieId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(TextesWeb.CopiesBulletins.mentionEmployeur)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("bulletins-mention")
                if aSignaler == nil { avis }
                if model.sessionExpiree {
                    JoleneButton("Vérifier ma session", style: .secondary) { Task { await model.verifierSession(session) } }
                        .accessibilityIdentifier("bulletins-session-check")
                }
                contenu
                simulations
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.charger() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(L.titre)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("bulletins-screen")
        .task { await model.charger() }
        .sheet(item: $aSignaler) { copie in
            SignalementCopieSheet(copie: copie, model: model) { aSignaler = nil }
        }
        .fullScreenCover(item: $model.pdfOuvert, onDismiss: { FichierCopieBulletinTemporaire.effacerTout() }) { ouvert in
            PDFLecteur(titre: L.titrePartage, pdf: ouvert.pdf) { model.fermerPDF() }
        }
    }

    // MARK: - Messages

    @ViewBuilder private var avis: some View {
        if let erreur = model.erreur {
            InlineNotice(erreur, tone: .error, identifier: model.erreurIntegrite ? "copie-integrite-erreur" : "bulletins-action-erreur",
                         announcementID: model.jeton)
        } else if let message = model.message {
            InlineNotice(message, tone: .success, identifier: "bulletins-confirmation", announcementID: model.jeton)
        }
        if model.copieCibleIndisponible {
            InlineNotice(L.copieDemandeeIndisponible, tone: .info, identifier: "bulletins-copie-indisponible")
        }
    }

    // MARK: - Liste

    @ViewBuilder private var contenu: some View {
        switch model.liste {
        case .chargement:
            SkeletonCard(identifier: "bulletins-chargement")
                .accessibilityLabel(L.chargement)
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .error, identifier: "bulletins-erreur")
                if !model.sessionExpiree {
                    JoleneButton(L.reessayer, style: .secondary) { Task { await model.charger() } }
                        .accessibilityIdentifier("bulletins-erreur-reessayer")
                }
            }
        case .prete:
            if model.employeurs.count > 1 { filtreEmployeur }
            let copies = model.copiesAffichees
            if copies.isEmpty {
                Text(L.vide)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .padding(JoleneSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(JoleneColor.cloud)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                    .accessibilityIdentifier("bulletins-vide")
            } else {
                ForEach(copies) { carte($0) }
            }
        }
    }

    private var filtreEmployeur: some View {
        HStack {
            Text(L.employeur)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
            Spacer(minLength: JoleneSpacing.sm)
            Picker(L.employeur, selection: $model.employeur) {
                Text(L.tousLesEmployeurs).tag(String?.none)
                ForEach(model.employeurs) { employeur in
                    Text(employeur.nom).tag(String?.some(employeur.id))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("bulletins-employeur")
        }
    }

    private func carte(_ copie: CopieBulletin) -> some View {
        let occupe = model.enCours != nil
        let cible = copieId == copie.id
        return VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(copie.employeurNom ?? "")
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    Text(BulletinsPresentation.periode(copie))
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.midnight)
                }
                Spacer(minLength: 0)
                StatusPill(BulletinsPresentation.statut(copie.statut), tone: copie.statut == .publiee ? .success : .neutral,
                           identifier: "copie-statut-\(copie.id)")
            }
            Text(BulletinsPresentation.meta(copie))
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            if let motif = BulletinsPresentation.motifRemplacement(copie) {
                Text(motif)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
            }
            if copie.signalee {
                Text(L.erreurSignalee)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityIdentifier("copie-signalee-\(copie.id)")
            }
            if copie.statut == .remplacee {
                Text(L.ancienneVersion)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
            }
            if copie.statut == .retiree {
                Text(L.pdfPlusAccessible)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("copie-retiree-\(copie.id)")
            }
            if model.telechargeable(copie) {
                JoleneButton(model.enCours == copie.id && aSignaler == nil ? L.ouverture : L.ouvrir, style: .secondary,
                             isLoading: model.enCours == copie.id && aSignaler == nil) {
                    Task { await model.ouvrir(copie) }
                }
                .disabled(occupe)
                .accessibilityIdentifier("copie-ouvrir-\(copie.id)")
                JoleneButton(L.signaler, style: .secondary) {
                    model.effacerMessages()
                    aSignaler = copie
                }
                .disabled(occupe)
                .accessibilityIdentifier("copie-signaler-\(copie.id)")
            }
        }
        .padding(JoleneSpacing.lg)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.card)
            .stroke(cible ? JoleneColor.rose800 : Color.clear, lineWidth: 2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(BulletinsPresentation.accessibilite(copie))
        .accessibilityIdentifier("copie-\(copie.id)")
    }

    // MARK: - Simulations (renvoi web)

    @ViewBuilder private var simulations: some View {
        if let presentateurRenvoiWeb, let url = URL(string: "https://jolene.app" + RevenusPresentation.lienBulletins) {
            WebHandoffCard(title: L.simulations, message: RenvoiWebScreen.message, url: url,
                           identifier: "bulletins-simulations", actionIdentifier: "bulletins-simulations-web") {
                presentateurRenvoiWeb.presenter(.safari(url))
            }
        }
    }
}

/// Feuille « Signaler une erreur » (`CopiesBulletinsListe.tsx` l.80-95) : trois motifs (défaut « Le contenu contient une
/// erreur », l.77), avertissement verbatim de retrait pour `DESTINATAIRE` (l.90), fermeture seulement après une relecture
/// qui confirme ; erreur affichée dans la feuille.
private struct SignalementCopieSheet: View {
    private typealias L = LibellesWeb.CopiesBulletins

    let copie: CopieBulletin
    @ObservedObject var model: BulletinsModel
    let fermer: () -> Void
    @State private var motif: MotifSignalementCopie = .contenu

    private var occupe: Bool { model.enCours != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                    Text(L.signalementDescription)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L.signalementQuestion)
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                    ForEach(BulletinsPresentation.motifs, id: \.self) { code in
                        Button { motif = code } label: {
                            HStack(spacing: JoleneSpacing.sm) {
                                Image(systemName: motif == code ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(JoleneColor.rose800)
                                    .accessibilityHidden(true)
                                Text(BulletinsPresentation.motif(code))
                                    .font(JoleneFont.body)
                                    .foregroundStyle(JoleneColor.midnight)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(occupe)
                        .accessibilityAddTraits(motif == code ? .isSelected : [])
                        .accessibilityIdentifier("copie-motif-\(code.rawValue)")
                    }
                    if motif == .destinataire {
                        Text(TextesWeb.CopiesBulletins.avertissementRetrait)
                            .font(JoleneFont.callout)
                            .foregroundStyle(JoleneColor.midnight)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("copie-avertissement-retrait")
                    }
                    if let erreur = model.erreur {
                        InlineNotice(erreur, tone: .error, identifier: "copie-signalement-erreur", announcementID: model.jeton)
                    }
                    JoleneButton(occupe ? L.enregistrement : L.envoyerSignalement, isLoading: occupe) {
                        Task { if await model.signaler(copie, motif: motif) { fermer() } }
                    }
                    .disabled(occupe)
                    .accessibilityIdentifier("copie-signalement-envoyer")
                    JoleneButton(L.annuler, style: .secondary) { fermer() }
                        .disabled(occupe)
                        .accessibilityIdentifier("copie-signalement-annuler")
                }
                .padding(JoleneSpacing.lg)
            }
            .background(JoleneColor.lavender.ignoresSafeArea())
            .navigationTitle(L.signaler)
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(occupe)
        .accessibilityIdentifier("copie-signalement")
    }
}
