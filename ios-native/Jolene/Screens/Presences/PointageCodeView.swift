import SwiftUI
import JoleneCore
import JoleneDesign

/// Fabrique de la zone de pointage (lot 2, T4b), injectée au-dessus des onglets par `MainTabView`
/// (`.environment(\.fabriqueZonePointage, …)`, point d'extension de T4a dans `BlocPointageView`) avec l'`Appareil` et le
/// scanner d'`AppContainer`. Sans les services de la page (`ServicesPointage`, posés par `PresencesScreen`), aucune zone
/// n'est rendue : jamais un bouton sans effet.
@MainActor
final class FabriqueZonePointageNative: FabriqueZonePointage {
    private let appareil: Appareil
    private let scanner: ModeScannerQR

    init(appareil: Appareil, scanner: ModeScannerQR) {
        self.appareil = appareil
        self.scanner = scanner
    }

    func zone(pour contexte: ZonePointageContexte) -> AnyView {
        guard let services = contexte.services else { return AnyView(EmptyView()) }
        return AnyView(PointageCodeView(contexte: contexte, services: services, appareil: appareil, scanner: scanner))
    }
}

/// Zone de pointage d'une mission (lot 2, T4b ; port de `PointageRotatifSoignant.tsx` l.64-283) : vue du `PointageModel`
/// de la mission (JoleneCore, `PointageModelTests`), qui porte l'envoi unique, le reçu durable, la réconciliation sans
/// renvoi et le suivi de 15 s. La vue n'ajoute aucune règle : textes et issues par `LibellesPresences.Pointage` et
/// `LibellesWeb.Pointage`, position par `LocalisationPointage` après le consentement (`ConsentementGpsModel` de la page),
/// QR par `ScannerQRSheet` (`SessionScanQR`).
///
/// Parcours d'un pointage : six chiffres saisis (`NumericCodeField`) ou lus (QR) → consentement NULL : feuille verbatim
/// (`ConsentementGpsSheet`), puis la réponse relue → consentement vrai : position (`.precisionReduite`, `.refusee`,
/// `.indisponible` : sans coordonnées) → `PointageModel.pointer(code:gps:)` → succès relu : champ vidé, instantané des
/// présences relu (revue fraîche de T4a, m1). Hors ligne (bandeau de la page) : boutons désactivés, aucun appel.
///
/// Session expirée (au scan, pendant la réconciliation, à la lecture de l'état ou du consentement ; revue fraîche de T4b,
/// M1) : la zone montre le bloc « Session à vérifier » du lot 1 (`AffichageZonePointage.sessionAVerifier`, mêmes textes
/// que `PresencesScreen`) et « Vérifier ma session » (`PointageModel.verifierSession` : session revalidée, état relu,
/// reçu gardé réconcilié sans renvoi), jamais « Vérification du pointage… » sans fin ni un « Réessayer » inopérant.
///
/// Consentement (revue fraîche de T4b, m1 et m4) : une seule réponse part (code en attente vidé de façon synchrone,
/// `ConsentementGpsModel.enCours` posé avant tout `await`) ; un échec de l'enregistrement s'affiche aussi dans la zone qui
/// a ouvert la feuille ; le retour du consentement est levé au pointage suivant.
///
/// Cycle de vie (consigne T4b) : `.task { charger(); suivre() }`, `desactiver()` à la disparition, `reconcilier()` au
/// retour au premier plan. Identifiants : `pointage-zone-<mission>`, `pointage-code-<mission>`, `pointage-qr-<mission>`,
/// `pointage-submit-<mission>`, `pointage-message-<mission>`, `pointage-renvoi-web-<mission>`, `pointage-qr-message-<mission>`,
/// `pointage-position-<mission>`, `pointage-en-service-<mission>`, `pointage-segment-<mission>-<n>`,
/// `pointage-chargement-<mission>`, `pointage-etat-indisponible-<mission>`, `pointage-reessayer-<mission>`,
/// `pointage-statut-indisponible-<mission>`, `pointage-session-expired-<mission>`, `pointage-session-check-<mission>`,
/// `pointage-consentement-echec-<mission>`.
struct PointageCodeView: View {
    private typealias L = LibellesPresences.Pointage
    private typealias W = LibellesWeb.Pointage

    let contexte: ZonePointageContexte
    private let appareil: Appareil
    private let scanner: ModeScannerQR
    private let recharger: @MainActor @Sendable () async -> Void
    private let apresIssue: @MainActor @Sendable () async -> Void
    @StateObject private var model: PointageModel
    @ObservedObject private var consentement: ConsentementGpsModel
    @ObservedObject private var reseau: EtatReseauModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    @State private var code = ""
    @State private var preparation = false
    @State private var feuille: Feuille?
    @State private var issueScanner: ScannerQRSheet.Issue?
    @State private var messageQR: String?
    @State private var codeEnAttente: String?
    @State private var derniereObservation: ObservationGps?
    /// Cette zone a ouvert la feuille de consentement : un échec de l'enregistrement y est aussi affiché (m4).
    @State private var consentementDemandeIci = false

    init(contexte: ZonePointageContexte, services: ServicesPointage, appareil: Appareil, scanner: ModeScannerQR) {
        self.contexte = contexte
        self.appareil = appareil
        self.scanner = scanner
        self.recharger = services.recharger
        self.apresIssue = services.apresIssue
        _consentement = ObservedObject(wrappedValue: services.consentement)
        _reseau = ObservedObject(wrappedValue: services.reseau)
        _model = StateObject(wrappedValue: PointageModel(missionId: contexte.missionId, finLe: contexte.finLe,
                                                         controller: contexte.session.controller, snapshot: contexte.snapshot,
                                                         appareil: appareil))
    }

    private var missionId: String { contexte.missionId }

    /// Une seule feuille à la fois (scanner, puis éventuellement consentement après sa fermeture).
    private enum Feuille: String, Identifiable {
        case scanner, consentement
        var id: String { rawValue }
    }

    /// Un pointage peut partir : le modèle l'autorise, la connexion n'est pas perdue, aucune position n'est en cours.
    private var peutAgir: Bool {
        model.peutEnvoyer && !reseau.horsLigne && !preparation && !consentement.enCours
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            switch AffichageZonePointage(pointage: model, consentement: consentement) {
            case .sessionAVerifier:
                sessionAVerifier
            case .chargement:
                chargement
            case let .indisponible(message):
                indisponible(message)
            case .statutIndisponible:
                Text(W.statutIndisponible)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pointage-statut-indisponible-\(missionId)")
            case let .saisie(etat):
                saisie(etat)
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: JoleneRadius.card).fill(JoleneColor.cloud))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pointage-zone-\(missionId)")
        .task {
            await model.charger()
            await model.suivre()
        }
        .onDisappear { model.desactiver() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await model.reconcilier() } }
        }
        .onChange(of: model.issue) { issue in
            guard let issue else { return }
            Task { await apresIssue() }
            guard PointageRules.rechargerPresencesApres(issue) else { return }
            code = ""
            Task { await recharger() }
        }
        .sheet(item: $feuille, onDismiss: feuilleFermee) { feuille in
            switch feuille {
            case .scanner:
                ScannerQRSheet(mode: scanner, rendre: { issue in
                    issueScanner = issue
                    self.feuille = nil
                }, fermer: { self.feuille = nil })
            case .consentement:
                ConsentementGpsSheet(enCours: consentement.enCours, accepter: { repondre(true) }, refuser: { repondre(false) })
            }
        }
    }

    // MARK: - États

    private var chargement: some View {
        HStack(spacing: JoleneSpacing.sm) {
            ProgressView().tint(JoleneColor.rose700)
            Text(W.chargement)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pointage-chargement-\(missionId)")
    }

    private func indisponible(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            InlineNotice(message, title: W.indisponibleTitre, tone: .error, identifier: "pointage-etat-indisponible-\(missionId)")
            JoleneButton(W.reessayer, style: .secondary) { Task { await model.charger() } }
                .accessibilityIdentifier("pointage-reessayer-\(missionId)")
        }
    }

    /// Bloc de reconnexion du lot 1 (M1) : la session est revalidée, jamais une relecture qui échouerait de nouveau.
    private var sessionAVerifier: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            InlineNotice(L.messageSessionExpiree, title: L.sessionAVerifier, tone: .warning,
                         identifier: "pointage-session-expired-\(missionId)", announcesOnAppear: true)
            JoleneButton(L.verifierMaSession, style: .secondary) {
                let session = contexte.session, consentement = consentement
                Task { await model.verifierSession(session, consentement: consentement) }
            }
            .accessibilityIdentifier("pointage-session-check-\(missionId)")
        }
    }

    // MARK: - Saisie

    @ViewBuilder
    private func saisie(_ etat: EtatPointage) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(W.titre)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: JoleneSpacing.sm)
            if etat.segmentOuvert == true, let segment = PointageRules.segmentEnCours(etat),
               let enService = L.enService(depuis: segment.debut) {
                Label(enService, systemImage: "clock")
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.cyan700)
                    .accessibilityIdentifier("pointage-en-service-\(missionId)")
            }
        }
        Text(L.consigne(segmentOuvert: etat.segmentOuvert == true))
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.bubblegum)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: JoleneSpacing.sm) {
            NumericCodeField(code: $code, libelle: W.champCode, placeholder: W.placeholderCode,
                             identifier: "pointage-code-\(missionId)")
            Button { ouvrirScanner() } label: {
                Label(W.qr, systemImage: "qrcode")
                    .font(JoleneFont.button)
                    .padding(.horizontal, JoleneSpacing.md)
                    .frame(minWidth: 72, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: JoleneRadius.field).fill(JoleneColor.lavender))
                    .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(JoleneColor.rose700, lineWidth: 1))
                    .foregroundStyle(JoleneColor.rose700)
            }
            .buttonStyle(.plain)
            .disabled(!peutAgir)
            .accessibilityLabel(W.qr)
            .accessibilityIdentifier("pointage-qr-\(missionId)")
        }
        JoleneButton(L.action(PointageRules.action(etat, maintenant: contexte.horloge.now())),
                     isLoading: model.envoiEnCours || preparation) {
            pointer(code)
        }
        .disabled(!peutAgir || !NumericCodeField.estComplet(code))
        .accessibilityIdentifier("pointage-submit-\(missionId)")
        retours
        segments(etat)
    }

    @ViewBuilder private var retours: some View {
        if let messageQR {
            InlineNotice(messageQR, tone: .warning, identifier: "pointage-qr-message-\(missionId)", announcesOnAppear: true)
        }
        // Échec de l'enregistrement du consentement demandé depuis cette zone : affiché ici aussi, pas seulement en tête de
        // page (m4) ; la feuille reviendra au prochain pointage.
        if consentementDemandeIci, case let .echec(message)? = consentement.retour {
            InlineNotice(message, tone: .error, identifier: "pointage-consentement-echec-\(missionId)", announcesOnAppear: true)
        }
        if let issue = model.issue {
            let message = L.message(issue)
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                InlineNotice(message.texte, tone: message.ton.inlineNotice, identifier: "pointage-message-\(missionId)",
                             announcesOnAppear: true)
                if let detail = message.detail {
                    Text(detail)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pointage-message-detail-\(missionId)")
                }
                // Voie de récupération d'un suivi non vérifiable : bouton explicite, rendu seulement avec le présentateur
                // des renvois web (T10), jamais une redirection automatique (consignes T3 et T4b).
                if message.renvoiWeb, let presentateurRenvoiWeb, let route = PresencesRenvois.presences {
                    JoleneButton(L.voirSurJolene, style: .secondary) { presentateurRenvoiWeb.presenter(route) }
                        .accessibilityIdentifier("pointage-renvoi-web-\(missionId)")
                }
            }
        }
        if let encart = L.encartPosition(derniereObservation), model.issue.map(PointageRules.rechargerPresencesApres) == true {
            InlineNotice(encart, tone: .info, identifier: "pointage-position-\(missionId)")
        }
    }

    @ViewBuilder
    private func segments(_ etat: EtatPointage) -> some View {
        let plusieursJours = PointageRules.segmentsSurPlusieursJours(etat.segments)
        if !etat.segments.isEmpty {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                ForEach(Array(etat.segments.enumerated()), id: \.offset) { index, segment in
                    if let ligne = L.segment(numero: index + 1, segment, plusieursJours: plusieursJours) {
                        HStack {
                            Text(ligne.titre)
                            Spacer(minLength: JoleneSpacing.sm)
                            Text(ligne.horaire)
                        }
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("pointage-segment-\(missionId)-\(index + 1)")
                    }
                }
            }
            .padding(.top, JoleneSpacing.xs)
        }
    }

    // MARK: - Actions

    private func ouvrirScanner() {
        guard peutAgir else { return }
        messageQR = nil
        issueScanner = nil
        feuille = .scanner
    }

    /// Feuille fermée : un code lu par le scanner part comme un code saisi ; un refus de la caméra laisse la saisie
    /// manuelle. La feuille de consentement ne se ferme que par ses boutons (rien à faire ici).
    private func feuilleFermee() {
        let issue = issueScanner
        issueScanner = nil
        switch issue {
        case let .code(lu)?:
            pointer(lu)
        case .refus?:
            messageQR = W.scanImpossible
        case nil:
            break
        }
    }

    private func pointer(_ saisie: String) {
        guard peutAgir, let codeValide = PointageRules.codeSaisi(saisie) else { return }
        messageQR = nil
        // Le retour d'un consentement précédent (enregistré, refusé ou en échec) est levé au pointage suivant (m4).
        consentement.oublierRetour()
        consentementDemandeIci = false
        preparation = true
        Task {
            // Consentement non encore lu (ou illisible) : relu avant de décider, jamais supposé.
            if consentement.decision == .sansGps, consentement.valeur == nil { await consentement.charger() }
            switch consentement.decision {
            case .recueillir:
                preparation = false
                codeEnAttente = codeValide
                consentementDemandeIci = true
                feuille = .consentement
            case .localiser:
                await envoyer(codeValide, gps: true)
            case .sansGps:
                await envoyer(codeValide, gps: false)
            }
        }
    }

    /// Réponse à la feuille : le code en attente est pris et vidé de façon synchrone, un second toucher ne fait rien (m1) ;
    /// le modèle ne laisse partir qu'une réponse (`enCours` posé avant tout `await`).
    private func repondre(_ accepte: Bool) {
        guard let code = codeEnAttente, !consentement.enCours else { return }
        codeEnAttente = nil
        Task {
            let relu = await consentement.repondre(accepte: accepte, localisation: appareil.localisation)
            feuille = nil
            // Échec de l'enregistrement ou identité changée : aucune hypothèse locale, rien n'est envoyé (la feuille
            // reviendra) ; l'échec est affiché dans la zone (m4).
            guard let relu else { return }
            preparation = true
            await envoyer(code, gps: relu)
        }
    }

    private func envoyer(_ code: String, gps: Bool) async {
        let observation: ObservationGps? = gps ? await LocalisationPointage.observer(appareil.localisation) : nil
        preparation = false
        derniereObservation = observation
        await model.pointer(code: code, gps: observation)
    }
}
