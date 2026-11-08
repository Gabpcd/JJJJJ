import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet Justificatifs de « Mes documents » (lot 2 T7), port de `DocumentsSoignantContent` (`src/pages/DocumentsSoignant.tsx`)
/// sur le modèle de T6 (`DocumentsModel`) : l'écran ne fait que lire ses états et les traduire par
/// `PresentationJustificatifs` (aucune règle locale). Ordre du web : bandeaux de profil, en-tête de progression, expirations
/// proches, incohérence, cartes des exigences (critiques puis optionnelles), documents complémentaires, attestation.
///
/// Cycle (consignes T7 de `docs/mobile-swift/DECISIONS_LOT2.md`) : `charger()` à l'apparition, au tirer-pour-rafraîchir et
/// au retour au premier plan (dossier relu d'abord, puis réconciliation d'un reçu en attente ; sans effet sur un envoi en
/// vol) ; `arreterSuivi()` à la disparition ; l'exigence suivante s'ouvre après un verdict `VERIFIE` (l.272-274) puis est
/// oubliée ; la célébration du dossier complet est oubliée après 2,5 s (l.268-269).
///
/// Non portés (`DECISIONS_LOT2.md`, « T7 — application ») : suppression d'un justificatif (§1.2), boutons vers le profil
/// web, bandeau RCP et textes d'accès des documents complémentaires (HARD STOP n°4, en attente de Gabrielle), encart RIB.
///
/// Identifiants : `documents-justificatifs`, `documents-loading`, `documents-erreur`, `documents-reessayer`,
/// `documents-dossier-a-preparer`, `documents-profil-incomplet`, `documents-entete-titre`, `documents-prochaine-etape`,
/// `documents-progression`, `document-expire-bientot-<id>`, `document-mettre-a-jour-<TYPE>`, `documents-coherence`,
/// `documents-envoi-issue`, `documents-suivi-web`, `documents-session-expired`, `documents-session-check`, cartes
/// `document-exigence-<TYPE>`, `document-statut-<TYPE>`, `document-message-<TYPE>`, `document-fichier-<TYPE>`,
/// `document-televerser-<TYPE>`, `document-voir-<id>`, `document-reverifier-<id>`, `document-revue-<id>`,
/// `document-verification-<id>`, `document-retour-<id>` ; DEBUG : `documents-demo-envois`.
struct JustificatifsView: View {
    private typealias L = LibellesJustificatifs
    private typealias P = PresentationJustificatifs

    @ObservedObject var model: DocumentsModel
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot
    let mediaDemo: DemoMediaPicker?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    @State private var televersement: DemandeTeleversement?
    @State private var copieConsultee: URL?
    @State private var reverification: String?
    @State private var demandeRevue: String?
    @State private var retour: RetourAction?
    /// Issue déjà vue dans la feuille, que l'utilisateur a fermée : plus annoncée en tête d'écran.
    @State private var envoiVu: DocumentsModel.EtatEnvoi?
    #if DEBUG
    @State private var compteursDemo: String?
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                if model.sessionExpired { sessionAVerifier }
                switch model.etat {
                case .chargement:
                    chargement
                case let .echec(message):
                    echec(message)
                case let .charge(dossier):
                    contenu(dossier)
                }
                #if DEBUG
                if let compteursDemo { compteurs(compteursDemo) }
                #endif
            }
            .padding(.horizontal, JoleneSpacing.lg)
            .padding(.vertical, JoleneSpacing.md)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("documents-justificatifs")
        .refreshable { await model.charger() }
        .task {
            CopiesConsultees.purgerSiNouvelEpoch(snapshot.epoch)
            await model.charger()
        }
        .onDisappear { model.arreterSuivi() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await model.charger() } }
        }
        .onChange(of: model.exigenceSuivante) { type in
            guard let type else { return }
            if televersement == nil, copieConsultee == nil { televersement = DemandeTeleversement(typeDocument: type) }
            model.oublierExigenceSuivante()
        }
        .onChange(of: model.dossierComplet) { complet in
            guard complet else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                model.oublierDossierComplet()
            }
        }
        .sheet(item: $televersement, onDismiss: {
            if !P.fermeLeTeleversement(model.envoi) { envoiVu = model.envoi }
        }) { demande in
            TeleversementSheet(typeDocument: demande.typeDocument, model: model, mediaDemo: mediaDemo)
        }
        .consultationQuickLook($copieConsultee)
        #if DEBUG
        .task(id: CleCompteurs(envoi: model.envoi, etat: model.etat)) {
            compteursDemo = await Self.compteursDemo(session: session, snapshot: snapshot)
        }
        #endif
    }

    // MARK: - États

    private var chargement: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            SkeletonBlock(size: .lg, width: 240)
            SkeletonCard()
            SkeletonCard()
            SkeletonCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("documents-loading")
    }

    private func echec(_ message: String) -> some View {
        EmptyState(systemImage: "exclamationmark.triangle", title: L.documentsIndisponibles, message: message,
                   identifier: "documents-erreur", actionTitle: L.reessayer, actionIdentifier: "documents-reessayer") {
            Task { await model.charger() }
        }
    }

    private var sessionAVerifier: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            InlineNotice(L.messageSessionExpiree, title: L.sessionAVerifier, tone: .warning, identifier: "documents-session-expired",
                         announcesOnAppear: true)
            JoleneButton(L.verifierMaSession, style: .secondary) { Task { await session.start() } }
                .accessibilityIdentifier("documents-session-check")
        }
    }

    @ViewBuilder
    private func contenu(_ dossier: DossierDocuments) -> some View {
        let maintenant = model.horloge.now()
        if dossier.profil == nil {
            dossierAPreparer
        } else {
            issueEnvoi
            ForEach(Array(P.bandeauxProfil(dossier).enumerated()), id: \.offset) { _, bandeau in
                InlineNotice(bandeau.texte, title: bandeau.titre, tone: .info, identifier: "documents-profil-incomplet")
            }
            if let entete = P.entete(dossier, maintenant: maintenant) { enTete(entete) }
            ForEach(P.expirations(dossier, maintenant: maintenant)) { expiration in
                expirationProche(expiration)
            }
            if let incoherence = P.incoherence(dossier, coherence: model.coherence, maintenant: maintenant) {
                InlineNotice(incoherence, tone: .warning, identifier: "documents-coherence")
            }
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                ForEach(P.cartes(dossier, maintenant: maintenant, enVerification: model.enVerification,
                                 reverification: reverification, demandeRevue: demandeRevue)) { carte in
                    if carte.ouvreLesOptionnels {
                        Divider().padding(.vertical, JoleneSpacing.xs)
                        Text(L.documentsOptionnels)
                            .font(JoleneFont.caption.weight(.semibold))
                            .foregroundStyle(JoleneColor.bubblegum)
                            .textCase(.uppercase)
                            .accessibilityAddTraits(.isHeader)
                    }
                    carteView(carte)
                }
            }
            complementaires(P.complementaires(dossier))
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                Text(L.derniereEtape)
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.bubblegum)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                AttestationSanteView(model: model, dossier: dossier, retour: $retour)
            }
        }
    }

    /// Sans dossier professionnel (`soignants` absent, l.505-518) : texte du web ; ses deux boutons (Explorer, profil web)
    /// ne sont pas repris : aucun écran natif n'y prépare le dossier.
    private var dossierAPreparer: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Image(systemName: "folder").font(JoleneFont.title).foregroundStyle(JoleneColor.rose700).accessibilityHidden(true)
            Text(L.dossierTitre).font(JoleneFont.headline).foregroundStyle(JoleneColor.midnight).accessibilityAddTraits(.isHeader)
            Text(L.dossierTexte).font(JoleneFont.callout).foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("documents-dossier-a-preparer")
    }

    /// Issue du dernier envoi (toasts du web l.419-428 ; textes opérationnels sans équivalent web). Masquée pendant la
    /// feuille (elle l'affiche), après sa fermeture par l'utilisateur sur la même issue, et une fois le verdict relu
    /// (`PresentationJustificatifs.issueAffichee` : le badge de la carte le porte).
    @ViewBuilder private var issueEnvoi: some View {
        if televersement == nil, model.envoi != envoiVu,
           let message = P.issueAffichee(model.envoi, enVerification: model.enVerification) {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message.texte, tone: TonsJustificatifs.notice(message.ton), identifier: "documents-envoi-issue",
                             announcesOnAppear: true)
                if model.envoi == .suiviIllisible, let presentateurRenvoiWeb, let route = AccueilPresentation.renvoiWeb(DocumentsModel.renvoiWeb) {
                    JoleneButton(L.voirSurJoleneApp, style: .secondary) { presentateurRenvoiWeb.presenter(route) }
                        .accessibilityIdentifier("documents-suivi-web")
                }
            }
        }
    }

    private func enTete(_ entete: EnteteJustificatifs) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            switch entete {
            case let .aCompleter(titre, prochaineEtape, bouton, typeProchaine, valides, total, note):
                Text(titre)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("documents-entete-titre")
                if let prochaineEtape {
                    Text(prochaineEtape).font(JoleneFont.callout).foregroundStyle(JoleneColor.bubblegum)
                }
                if let bouton, let typeProchaine {
                    JoleneButton(bouton) { ouvrirTeleversement(typeProchaine) }
                        .disabled(envoiImpossible)
                        .accessibilityIdentifier("documents-prochaine-etape")
                }
                ProgressView(value: Double(valides), total: Double(max(total, 1)))
                    .tint(JoleneColor.rose700)
                    .accessibilityIdentifier("documents-progression")
                Text(note).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            case let .aJour(titre, detail), let .aucuneExigence(titre, detail):
                Text(titre)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("documents-entete-titre")
                Text(detail).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.softGradient)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
    }

    private func expirationProche(_ expiration: ExpirationProche) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(expiration.texte)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("document-expire-bientot-\(expiration.id)")
            lien(L.mettreAJour, identifiant: "document-mettre-a-jour-\(expiration.typeDocument)") {
                ouvrirTeleversement(expiration.typeDocument)
            }
            .disabled(envoiImpossible)
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.rose100)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Cartes

    private func carteView(_ carte: CarteJustificatif) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
                if carte.obligatoire {
                    Text(L.obligatoire)
                        .font(JoleneFont.caption.weight(.semibold))
                        .foregroundStyle(JoleneColor.rose800)
                }
                Text(carte.titre)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if let description = carte.description {
                Text(description).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            }
            if let fichier = carte.fichier {
                Text(fichier)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("document-fichier-\(carte.typeDocument)")
            }
            if let badge = carte.badge {
                StatusBadge(badge.texte, tone: TonsJustificatifs.badge(badge.ton), isInProgress: badge.enCours,
                            identifier: "document-statut-\(carte.typeDocument)",
                            progressIdentifier: carte.document.map { "document-verification-\($0.id)" })
            }
            ForEach(Array(carte.messages.enumerated()), id: \.offset) { index, message in
                Text(message.texte)
                    .font(JoleneFont.caption)
                    .foregroundStyle(message.ton == .erreur ? JoleneColor.rose800 : JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(index == 0 ? "document-message-\(carte.typeDocument)"
                                                        : "document-message-\(carte.typeDocument)-\(index)")
            }
            ForEach(carte.dates, id: \.self) { date in
                Text(date).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            }
            if let retour, let document = carte.document, retour.cible == document.id {
                InlineNotice(retour.texte.texte, tone: TonsJustificatifs.notice(retour.texte.ton),
                             identifier: "document-retour-\(document.id)", announcesOnAppear: true)
            }
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                ForEach(Array(carte.actions.enumerated()), id: \.offset) { _, action in
                    actionView(action, carte: carte)
                }
            }
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document-exigence-\(carte.typeDocument)")
    }

    @ViewBuilder
    private func actionView(_ action: ActionJustificatif, carte: CarteJustificatif) -> some View {
        switch action.genre {
        case .televerser:
            if action.principale {
                JoleneButton(action.libelle) { ouvrirTeleversement(carte.typeDocument) }
                    .disabled(envoiImpossible)
                    .accessibilityIdentifier("document-televerser-\(carte.typeDocument)")
            } else {
                lien(action.libelle, identifiant: "document-televerser-\(carte.typeDocument)") { ouvrirTeleversement(carte.typeDocument) }
                    .disabled(envoiImpossible)
            }
        case .voir:
            if let document = carte.document {
                lien(action.libelle, identifiant: "document-voir-\(document.id)") { consulter(document) }
                    .disabled(model.actionEnCours != nil)
            }
        case .reverifier:
            if let document = carte.document {
                lien(action.libelle, identifiant: "document-reverifier-\(document.id)", enCours: action.enCours) { reverifier(document) }
                    .disabled(model.actionEnCours != nil)
            }
        case .demanderRevue:
            if let document = carte.document {
                lien(action.libelle, identifiant: "document-revue-\(document.id)", enCours: action.enCours) { demanderRevue(document) }
                    .disabled(model.actionEnCours != nil)
            }
        }
    }

    /// Lien d'action du web (`text-primary hover:underline`, cible 44 pt).
    private func lien(_ titre: String, identifiant: String, enCours: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: JoleneSpacing.xs) {
                if enCours { ProgressView().controlSize(.small).tint(JoleneColor.rose700) }
                Text(titre)
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.rose800)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifiant)
    }

    // MARK: - Documents complémentaires

    @ViewBuilder
    private func complementaires(_ cartes: [CarteComplementaire]) -> some View {
        if !cartes.isEmpty {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                Text(L.etudiantInterne)
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.bubblegum)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                ForEach(cartes) { carte in
                    VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                        Text(carte.titre)
                            .font(JoleneFont.callout.weight(.semibold))
                            .foregroundStyle(JoleneColor.midnight)
                            .fixedSize(horizontal: false, vertical: true)
                        if let description = carte.description {
                            Text(description).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let statut = carte.statut {
                            Text(statut)
                                .font(JoleneFont.caption)
                                .foregroundStyle(JoleneColor.midnight)
                                .accessibilityIdentifier("document-statut-\(carte.typeDocument)")
                        }
                        JoleneButton(carte.bouton) { ouvrirTeleversement(carte.typeDocument) }
                            .disabled(envoiImpossible)
                            .accessibilityIdentifier("document-televerser-\(carte.typeDocument)")
                    }
                    .padding(JoleneSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(JoleneColor.cloud)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("document-exigence-\(carte.typeDocument)")
                }
            }
        }
    }

    // MARK: - Actions

    /// Envoi impossible : un envoi en vol (cette instance ou une autre) ou un journal de reçus illisible.
    private var envoiImpossible: Bool {
        switch model.envoi {
        case .enCours, .suiviIllisible: return true
        default: return false
        }
    }

    private func ouvrirTeleversement(_ typeDocument: String) {
        retour = nil
        televersement = DemandeTeleversement(typeDocument: typeDocument)
    }

    private func consulter(_ document: DocumentSoignant) {
        retour = nil
        Task {
            if let copie = await model.consulter(document) {
                copieConsultee = copie
            } else if let message = model.messageAction {
                retour = RetourAction(cible: document.id, texte: TexteJustificatif(texte: message, ton: .erreur))
            }
        }
    }

    /// « Revérifier » : geste manuel seulement, issue annoncée comme les toasts du web (l.317-325).
    private func reverifier(_ document: DocumentSoignant) {
        retour = nil
        reverification = document.id
        Task {
            let verdict = await model.reverifier(documentId: document.id)
            reverification = nil
            if let verdict {
                let motif = model.dossier?.documents.first { $0.id == document.id }?.motifRejet
                retour = RetourAction(cible: document.id, texte: P.messageReverification(verdict, motif: motif))
            } else if let message = model.messageAction {
                retour = RetourAction(cible: document.id, texte: TexteJustificatif(texte: message, ton: .erreur))
            }
        }
    }

    private func demanderRevue(_ document: DocumentSoignant) {
        retour = nil
        demandeRevue = document.id
        Task {
            let envoyee = await model.demanderRevue(documentId: document.id)
            demandeRevue = nil
            if envoyee {
                retour = RetourAction(cible: document.id, texte: TexteJustificatif(texte: L.revueEnvoyee, ton: .succes))
            } else if let message = model.messageAction {
                retour = RetourAction(cible: document.id, texte: TexteJustificatif(texte: message, ton: .erreur))
            }
        }
    }

    // MARK: - Compteurs de démonstration (DEBUG)

    #if DEBUG
    private struct CleCompteurs: Equatable {
        let envoi: DocumentsModel.EtatEnvoi
        let etat: DocumentsModel.Etat
    }

    /// Envois acceptés et appels `verify-document` du monde démo (preuve « une seule fois » des XCUITest) ; nil hors démo.
    private static func compteursDemo(session: SessionStore, snapshot: SessionSnapshot) async -> String? {
        guard let gateways = await session.controller.gateways(for: snapshot.epoch),
              let demo = gateways.documents as? DemoDocumentsGateway else { return nil }
        let envois = await demo.envois
        let verifications = await demo.appelsVerification.count
        return "\(envois) envoi · \(verifications) vérification"
    }

    private func compteurs(_ valeur: String) -> some View {
        HStack {
            Text(verbatim: "Envois de documents (démo)")
            Spacer()
            Text(verbatim: valeur)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("documents-demo-envois")
        }
        .font(JoleneFont.caption)
    }
    #endif
}
