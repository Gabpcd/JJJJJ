import SwiftUI
import JoleneCore
import JoleneDesign

/// Page d'un contrat (lot 2, T9a ; `ContratMission.tsx` l.529-840) : vue de `ContratModel` (JoleneCore, T8), dans
/// l'ordre du web : bandeaux de statut, compte à rebours 72 h dérivé de `cree_le` (horloge des gateways), en-tête
/// « Contrat <numéro> » et statut, CDD à préparer (décision 19), téléchargement (partage du fichier original contrôlé)
/// et impression, lecteur isolé de l'original contrôlé (`ContratReaderView`, décision 17) précédé du « Document
/// officiel figé » et de son empreinte, certificat des signatures (et sa page), section Signatures, zone « Votre
/// signature », « déjà signé », pied de page juridique. Règles : `ContratRules` ; textes : `TextesWeb` (HARD STOP
/// n°4, verbatim) et `LibellesWeb`, assemblés par `ContratPresentation` ; aucune règle ni aucun texte écrit ici.
///
/// Signature : aucune signature native dans T9a. La zone « Votre signature » (`ContratRules.zoneSignatureVisible`,
/// l.709) est un renvoi web vers `/contrat/:id` (décision 18) : bouton seulement quand le présentateur `.safari`
/// (lot 1 T10) est injecté, sinon « Signature non disponible pour le moment » (jamais un bouton sans effet) ; elle
/// porte aussi les erreurs de préparation du document final du web (l.713-717). T9b (HARD STOP n°4) la remplace par
/// `SignatureOtpView` (`ContratModel.session`).
///
/// Partage : copie temporaire `Contrat-<numéro>.html` des octets contrôlés (`ContratModel.preparerPartage`), feuille
/// système, copie effacée à la fermeture de la feuille et à la disparition de l'écran ; toutes les copies sont
/// effacées au changement d'epoch (`MainTabView`). Identifiants : `contrat-screen`, `contrat-chargement`,
/// `contrat-erreur`, `contrat-reessayer`, `contrat-session-expiree`, `contrat-bandeau-<cas>`, `contrat-countdown`,
/// `contrat-titre`, `contrat-statut`, `contrat-cdd-a-preparer`, `contrat-partager`, `contrat-imprimer`,
/// `contrat-partage-erreur`, `contrat-empreinte`, `contrat-lecteur`, `contrat-contenu-indisponible`,
/// `contrat-certificat`, `contrat-certificat-ouvrir`, `contrat-signatures` (+ `-etablissement`, `-soignant`),
/// `contrat-renvoi-web` (+ `-action`, `-indisponible`), `contrat-preparation`, `contrat-deja-signe`,
/// `contrat-pied-de-page`.
struct ContratScreen: View {
    @StateObject private var model: ContratModel
    @ObservedObject private var session: SessionStore
    private let snapshot: SessionSnapshot
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    @State private var lecteur = LecteurContratReference()
    @State private var hauteurLecteur = ContratReaderView.hauteurMinimale
    @State private var partageEnCours = false
    @State private var copiePartagee: URL?
    @State private var erreurPresentation: String?

    init(session: SessionStore, snapshot: SessionSnapshot, contratId: String) {
        self.session = session
        self.snapshot = snapshot
        _model = StateObject(wrappedValue: ContratModel(controller: session.controller, snapshot: snapshot, contratId: contratId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                switch model.etat {
                case .chargement:
                    VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                        SkeletonBlock(size: .lg)
                        SkeletonCard()
                        SkeletonCard()
                    }
                    .accessibilityIdentifier("contrat-chargement")
                case let .echec(message) where model.sessionExpired:
                    EmptyState(systemImage: "person.crop.circle.badge.exclamationmark", title: "Session à vérifier", message: message,
                               identifier: "contrat-session-expiree", actionTitle: "Vérifier ma session",
                               actionIdentifier: "contrat-session-verifier") {
                        Task {
                            await session.start()
                            guard session.state.snapshot?.epoch == snapshot.epoch else { return }
                            await model.charger()
                        }
                    }
                case let .echec(message):
                    EmptyState(systemImage: "questionmark.circle", title: LibellesWeb.Contrat.introuvable, message: message,
                               identifier: "contrat-erreur", actionTitle: LibellesWeb.Contrats.reessayer,
                               actionIdentifier: "contrat-reessayer") { Task { await model.charger() } }
                case .charge:
                    if let contrat = model.contrat { contenu(contrat) }
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(LibellesWeb.Contrat.titrePrefixe)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("contrat-screen")
        // Premier chargement seulement : revenir de la page du certificat ne relit pas le contrat (tirer pour
        // actualiser le relit) ; un chargement interrompu par la navigation reprend au retour.
        .task { if model.contrat == nil { await model.charger() } }
        .refreshable { await model.charger() }
        .onDisappear { effacerCopie() }
    }

    // MARK: - Contenu

    @ViewBuilder private func contenu(_ contrat: ContratDetail) -> some View {
        ForEach(Array(ContratRules.bandeaux(contrat).enumerated()), id: \.offset) { _, bandeau in
            bandeauVue(bandeau)
        }
        if ContratRules.afficheCompteARebours(contrat) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let etat = CompteARebours72h.etat(creeLe: contrat.creeLe, maintenant: model.horloge.now())
                CountdownLabel(texte: TextesWeb.CompteARebours.texte(restantSecondes: etat.restantSecondes), etat: etat,
                               identifier: "contrat-countdown")
            }
        }
        entete(contrat)
        if ContratRules.cddSansOriginal(contrat) {
            carte {
                Text(TextesWeb.Contrat.cddAPreparer)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("contrat-cdd-a-preparer")
            }
        }
        actions
        document(contrat)
        if ContratRules.certificatVisible(contrat) {
            CertificatView(signatures: model.signatures, erreur: model.erreurCertificat, prefixe: "contrat-certificat")
            NavigationLink {
                CertificatScreen(model: model)
            } label: {
                HStack {
                    Label(TextesWeb.Certificat.titrePage, systemImage: "checkmark.shield")
                        .foregroundStyle(JoleneColor.midnight)
                    Spacer(minLength: JoleneSpacing.sm)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(JoleneColor.bubblegum)
                        .accessibilityHidden(true)
                }
                .font(JoleneFont.callout.weight(.semibold))
                .padding(JoleneSpacing.lg)
                .frame(minHeight: 44)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                .contentShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("contrat-certificat-ouvrir")
        }
        signatures(contrat)
        if ContratRules.zoneSignatureVisible(contrat) { zoneSignature(contrat) }
        if ContratRules.dejaSigneParMoi(contrat) {
            Text(TextesWeb.Contrat.dejaSigne)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
                .frame(maxWidth: .infinity)
                .padding(JoleneSpacing.lg)
                .background(JoleneColor.cyan100)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                .accessibilityIdentifier("contrat-deja-signe")
        }
        Text(TextesWeb.Contrat.piedDePage(ContratRules.mentionPiedDePage(contrat)))
            .font(JoleneFont.caption)
            .italic()
            .foregroundStyle(JoleneColor.bubblegum)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("contrat-pied-de-page")
    }

    @ViewBuilder private func bandeauVue(_ bandeau: BandeauContrat) -> some View {
        switch bandeau {
        case .annule:
            InlineNotice(TextesWeb.Contrat.annule, tone: .error, identifier: "contrat-bandeau-annule")
        case .expire:
            InlineNotice(TextesWeb.Contrat.expire, tone: .warning, identifier: "contrat-bandeau-expire")
        case .refuse:
            InlineNotice(TextesWeb.Contrat.refuse, tone: .error, identifier: "contrat-bandeau-refuse")
        case .autrePartieASigne:
            InlineNotice(TextesWeb.Contrat.autrePartieASigneDetail, title: TextesWeb.Contrat.autrePartieASigne, tone: .warning,
                         identifier: "contrat-bandeau-autre-partie")
        }
    }

    private func entete(_ contrat: ContratDetail) -> some View {
        HStack(alignment: .top, spacing: JoleneSpacing.md) {
            Image(systemName: "doc.text")
                .font(JoleneFont.title)
                .foregroundStyle(JoleneColor.rose700)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                Text(LibellesWeb.Contrat.titre(numero: contrat.numeroContrat))
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("contrat-titre")
                Text(LibellesWeb.Contrat.statut(ContratRules.statutAffiche(contrat)))
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("contrat-statut")
            }
        }
    }

    // MARK: - Partage et impression

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) { boutons }
        if let message = erreurPresentation ?? model.erreurPartage {
            InlineNotice(message, tone: .error, identifier: "contrat-partage-erreur", announcesOnAppear: true)
        }
    }

    @ViewBuilder private var boutons: some View {
        JoleneButton(LibellesWeb.Contrat.telecharger, style: .secondary, isLoading: partageEnCours) { partager() }
            .disabled(model.original == nil || partageEnCours)
            .accessibilityIdentifier("contrat-partager")
        if let original = model.original {
            JoleneButton(LibellesWeb.Contrat.imprimer, style: .secondary) {
                lecteur.imprimer(nomTache: FichierContratTemporaire.nomFichier(numero: original.numeroContrat,
                                                                                contratId: original.contratId))
            }
            .accessibilityIdentifier("contrat-imprimer")
        }
    }

    private func partager() {
        guard !partageEnCours else { return }
        partageEnCours = true
        erreurPresentation = nil
        Task {
            defer { partageEnCours = false }
            guard let url = await model.preparerPartage() else { return }
            effacerCopie()
            copiePartagee = url
            let presentee = ShareSheet.presenter(fichier: url) {
                FichierContratTemporaire.effacer(url)
            }
            if !presentee {
                FichierContratTemporaire.effacer(url)
                copiePartagee = nil
                erreurPresentation = FichierContratTemporaire.messageIndisponible
            }
        }
    }

    private func effacerCopie() {
        if let copiePartagee { FichierContratTemporaire.effacer(copiePartagee) }
        copiePartagee = nil
    }

    // MARK: - Document

    private func document(_ contrat: ContratDetail) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            if let fige = ContratPresentation.documentFige(contrat) {
                Label(fige, systemImage: "lock.shield")
                    .font(JoleneFont.caption)
                    .italic()
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(fige)
                    .accessibilityIdentifier("contrat-empreinte")
            }
            if let original = model.original {
                ContratReaderView(html: original.html, reference: lecteur, hauteur: $hauteurLecteur)
                    .frame(height: hauteurLecteur)
                    .frame(maxWidth: .infinity)
            } else if let message = ContratPresentation.messageContenu(motif: model.indisponibilite, contrat: contrat) {
                Text(message)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, JoleneSpacing.xl)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("contrat-contenu-indisponible")
            }
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        // Feuille blanche en mode sombre aussi, comme le document : l'original n'a pas de thème sombre.
        .environment(\.colorScheme, .light)
    }

    // MARK: - Signatures

    private func signatures(_ contrat: ContratDetail) -> some View {
        carte {
            Text(LibellesWeb.Contrat.signaturesTitre)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            ForEach(ContratPresentation.lignesSignatures(contrat), id: \.texte) { ligne in
                HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
                    Image(systemName: ligne.signee ? "checkmark.circle.fill" : "clock")
                        .foregroundStyle(ligne.signee ? JoleneColor.cyan900 : JoleneColor.butter800)
                        .accessibilityHidden(true)
                    Text(ligne.texte)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.midnight)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(ligne.partie == .etablissement ? "contrat-signatures-etablissement" : "contrat-signatures-soignant")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contrat-signatures")
    }

    /// Zone « Votre signature » (l.708-817) en renvoi web jusqu'à T9b.
    private func zoneSignature(_ contrat: ContratDetail) -> some View {
        carte {
            Text(LibellesWeb.Contrat.votreSignature)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            if let preparation = ContratPresentation.messagePreparation(motif: model.indisponibilite) {
                InlineNotice(preparation, tone: .warning, identifier: "contrat-preparation")
            }
            if let presentateur = presentateurRenvoiWeb, let route = ContratPresentation.renvoiSignature(contratId: contrat.id) {
                JoleneButton(LibellesWeb.Contrats.signerLeContrat) { presentateur.presenter(route) }
                    .accessibilityIdentifier("contrat-renvoi-web-action")
            } else {
                Text(LibellesWeb.SignatureOtp.signatureNonDisponible)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("contrat-renvoi-web-indisponible")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contrat-renvoi-web")
    }

    private func carte<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md, content: contenu)
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }
}
