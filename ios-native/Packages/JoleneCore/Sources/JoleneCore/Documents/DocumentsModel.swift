import Combine
import Foundation

/// Modèle des justificatifs (lot 2 T6, blueprint §2.5 « Justificatif », décision 14). Données et pipeline d'envoi ;
/// l'écran (T7) ne fait que lire ces états et traduire les issues en textes.
///
/// - Plusieurs instances (écran rouvert pendant un upload, deux fenêtres sur iPad, nouvel epoch du même utilisateur)
///   partagent le registre du processus `EssaisDocumentsEnVol` (revue fraîche de T6, M1-bis) : un seul envoi et une
///   seule réconciliation à la fois par utilisateur, quelle que soit l'instance ; aucune ne réconcilie l'essai en vol
///   d'une autre ni n'en lance un second : elle l'affiche `.enCours` puis en reprend l'issue.
/// - Lecture : dossier relu sous l'epoch de la session, borné à `SessionController.resolutionTimeout`, AVANT la
///   réconciliation du reçu laissé par un essai précédent (l'écran quitte `.chargement` sans l'attendre, m-b) ; cohérence
///   des noms en best-effort (le web avale l'erreur).
/// - Envoi : reçu `prepared` puis `started` journalisés (`ReceiptJournal<RecuDocument>`, domaine `document`) AVANT
///   l'unique upload ; issue relue par la gateway ; reçu effacé après un succès, un refus ou un « non envoyé » ; gardé
///   `started` sur une issue incertaine, réconciliée aussitôt puis à chaque chargement — jamais de renvoi, ni de l'upload
///   ni de `verify-document`. Aucun octet n'est conservé.
/// - Délais : upload, revérification et consultation sont bornés par `delaiTransfert(octets:)` (au moins 120 s,
///   proportionnel à la taille) ; une réconciliation (ligne, HEAD, rejeu, nettoyage) par `requetesReconciliation` fois
///   `resolutionTimeout` ; `verify-document` est lancé par la gateway sans être attendu, son issue est observée hors du
///   chemin critique (m-d) (amendement de PRINCIPES l.107-114, `docs/mobile-swift/DECISIONS_LOT2.md`).
/// - Verdict en ligne : relecture du dossier toutes les 5 s pendant 60 s au plus (`DocumentsSoignant.tsx` l.250-255),
///   aussitôt après la réponse de `verify-document` (l.420), arrêtée dès que la pièce quitte `EN_ATTENTE`, par
///   `arreterSuivi()` ou à la disparition du modèle (l.254) ; un verdict `VERIFIE` enchaîne sur la prochaine exigence
///   critique (`exigenceSuivante`) ou signale un dossier complet (l.258-276) ; une erreur de `verify-document`, une
///   revue manuelle relue ou une vérification jamais engagée après 60 s donne `.enregistre` (« Document téléversé.
///   Vérification manuelle en attente. », l.413-425).
/// - Journal illisible (`RecuErreur.illisible`) : envoi bloqué, reçu jamais réécrit ni effacé, renvoi web
///   `renvoiWeb` (consigne T6 de `docs/mobile-swift/DECISIONS_LOT2.md`).
/// - Epoch : aucun état d'erreur ni de session n'est publié pour une identité quittée (m-f) ; un modèle périmé revient
///   à `.inactif`.
@MainActor
public final class DocumentsModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case charge(DossierDocuments)
        case echec(String)
    }

    public enum EtatEnvoi: Equatable, Sendable {
        case inactif
        /// Envoi en vol pour cet utilisateur, lancé par cette instance ou par une autre (écran rouvert, autre fenêtre).
        case enCours(typeDocument: String)
        /// Issue relue (T7 la traduit avec les messages du web).
        case termine(IssueEnvoiDocument)
        /// Refusé avant tout reçu et tout envoi (fichier, type non proposé).
        case refuseAvantEnvoi(message: String)
        /// Un reçu d'un autre essai reste à réconcilier : aucun nouvel envoi.
        case recuEnCours
        /// Journal de reçus illisible : envoi bloqué, renvoi web (`renvoiWeb`).
        case suiviIllisible
        /// Erreur de transport ou de session avant l'issue ; le reçu `started` éventuel reste journalisé.
        case erreur(String)
    }

    public static let intervalleSuivi: TimeInterval = 5
    public static let dureeSuivi: TimeInterval = 60
    /// Voie de récupération d'un journal illisible : l'envoi web n'utilise pas ce journal.
    public static let renvoiWeb = "/soignant/mes-documents?tab=justificatifs"
    /// Code de refus restitué pour un nom ou un libellé hors bornes (message du web, `DocumentsSoignant.tsx` l.400-402).
    public static let codeMetadonneesInvalides = "METADONNEES_DOCUMENT_INVALIDES"

    /// Plancher de la borne des transferts et de la vérification (revue fraîche de T6, M2) : `verify-document` sonde
    /// 10 s puis appelle l'IA 20 s (`verify-document/index.ts` l.286-287, l.625-626), le web annonce « ~30 s » ; un upload
    /// de 3 Mo à 1,5 Mbit/s prend déjà 16 s.
    public nonisolated static let delaiTransfertMinimum: TimeInterval = 120
    /// Débit plancher supposé (≈ 400 kbit/s) : 10 Mo ≈ 240 s.
    public nonisolated static let debitPlancherOctetsParSeconde: Double = 50_000
    /// Requêtes successives d'une réconciliation au plus — ligne relue, objet relu (HEAD), rejeu de l'enregistrement,
    /// nettoyage best-effort —, chacune de la taille d'une lecture : la réconciliation est bornée à autant de fois
    /// `resolutionTimeout` (revue fraîche de T6, m-b). Aucun transfert de fichier, et `verify-document` n'est jamais
    /// attendu.
    public nonisolated static let requetesReconciliation = 4

    /// Borne d'un transfert de `octets` (upload, téléchargement) ou d'une vérification : 30 s de latence plus la durée au
    /// débit plancher, au moins `delaiTransfertMinimum`. Taille inconnue : celle du plafond (10 Mo).
    public nonisolated static func delaiTransfert(octets: Int?) -> TimeInterval {
        let taille = Double(max(0, octets ?? ClassementDocument.tailleMaxParDefaut))
        return max(delaiTransfertMinimum, 30 + taille / debitPlancherOctetsParSeconde)
    }

    @Published public private(set) var etat: Etat = .chargement
    @Published public private(set) var envoi: EtatEnvoi = .inactif
    /// Pièces dont le verdict est attendu en ligne.
    @Published public private(set) var enVerification: Set<String> = []
    @Published public private(set) var coherence: CoherenceDocuments?
    /// Exigence à proposer après un verdict `VERIFIE` (l.272-274) ; l'écran l'oublie quand il l'ouvre.
    @Published public private(set) var exigenceSuivante: String?
    /// Toutes les pièces critiques sont valides après un verdict (l.266-270) ; l'écran l'oublie après la célébration
    /// (`oublierDossierComplet()`, 2,5 s sur le web, l.268-269).
    @Published public private(set) var dossierComplet = false
    @Published public private(set) var sessionExpired = false
    /// Pièce visée par une action en cours (revérification, revue, consultation) ; « attestation » pour la signature.
    @Published public private(set) var actionEnCours: String?
    /// Dernier refus d'une action (message du web ou du serveur).
    @Published public private(set) var messageAction: String?

    /// Horloge des gateways de la session (démo : horloge fixée).
    public private(set) var horloge: any ClockPort = SystemClock()

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private let journal: ReceiptJournal<RecuDocument>
    private let attendre: @Sendable (TimeInterval) async throws -> Void
    /// Clé du journal de cet utilisateur ; nil si l'identifiant est inutilisable (journal illisible).
    private let cle: CleRecu?
    /// Registre du processus, jamais un autre (M1-bis).
    private let registre: EssaisDocumentsEnVol
    private var generation = 0
    /// Envoi lancé par CETTE instance (inscrit au registre du processus).
    private var envoiPropre: Task<EtatEnvoi, Never>?
    /// Envoi d'une autre instance du même utilisateur, affiché ici jusqu'à sa fin.
    private var envoiObserve: Task<EtatEnvoi, Never>?
    private var suivi: Task<Void, Never>?
    private var numeroSuivi = 0
    /// Copie de la tâche de suivi, annulable depuis `deinit` (non isolé).
    private let annulationSuivi = AnnulationSuivi()

    public init(controller: SessionController, snapshot: SessionSnapshot, recus: any ReceiptStorePort,
                attendre: @escaping @Sendable (TimeInterval) async throws -> Void = { try await DocumentsModel.attendreParDefaut($0) }) {
        self.controller = controller
        self.snapshot = snapshot
        self.journal = ReceiptJournal<RecuDocument>(store: recus)
        self.attendre = attendre
        self.cle = CleRecu(domaine: RecuDocument.domaine, userId: snapshot.context.userId)
        self.registre = .processus
    }

    deinit {
        annulationSuivi.annuler()
    }

    public nonisolated static func attendreParDefaut(_ secondes: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, secondes) * 1_000_000_000))
    }

    public var dossier: DossierDocuments? {
        if case let .charge(dossier) = etat { return dossier }
        return nil
    }

    // MARK: - Chargement

    /// Apparition, tirer-pour-rafraîchir, retour au premier plan (T7). Le dossier est lu d'abord ; puis, si aucun envoi
    /// n'est en vol pour cet utilisateur (dans cette instance ou une autre), le reçu en attente est réconcilié ; sinon
    /// l'envoi en vol est affiché, jamais réconcilié.
    public func charger() async {
        guard let gateways = await gatewaysCourantes() else { return }
        horloge = gateways.clock
        if dossier == nil { etat = .chargement }
        await relireDossier(gateways, signalerEchec: true)
        if let cle, let enVol = registre.envoi(cle) {
            suivreEnvoi(enVol)
        } else {
            await reconcilierEnAttente(gateways)
        }
        guard let dossier, !dossier.documents.isEmpty else { return }
        let port = gateways.documents
        let context = snapshot.context
        let lue = try? await bounded(timeout: controller.resolutionTimeout) { try await port.coherence(context: context) }
        guard await courant() else { return }
        coherence = lue
    }

    // MARK: - Envoi

    /// Envoie un fichier préparé (`FichierDocument.preparer`) pour un type proposé par l'écran
    /// (`DossierDocuments.peutEnvoyer`). Un seul envoi à la fois par utilisateur, dans tout le processus : un geste
    /// pendant un envoi est ignoré ; pendant l'envoi d'une autre instance, celui-ci est affiché ici.
    public func envoyer(typeDocument: String, fichier: FichierPret, libelle: String?) async {
        guard envoi != .suiviIllisible else { return }
        guard let cle else { envoi = .suiviIllisible; return }
        if let enVol = registre.envoi(cle) {
            suivreEnvoi(enVol)
            return
        }
        guard let dossier, dossier.peutEnvoyer(typeDocument: typeDocument, maintenant: horloge.now()) else {
            envoi = .refuseAvantEnvoi(message: MessagesDocuments.enregistrementImpossible)
            return
        }
        // Contrôle et inscription sans suspension : aucune autre instance ne peut s'intercaler.
        guard let tache = registre.demarrerEnvoi(cle, typeDocument: typeDocument, { [self] in
            await self.executerEnvoi(typeDocument: typeDocument, fichier: fichier, libelle: libelle)
        }) else { return }
        envoiPropre = tache
        envoi = .enCours(typeDocument: typeDocument)
        _ = await tache.value
        if envoiPropre == tache { envoiPropre = nil }
    }

    /// Attend la fin du suivi de vérification en cours (tests, fermeture de l'écran).
    public func attendreFinDuSuivi() async {
        await suivi?.value
    }

    /// Arrête le suivi du verdict (fermeture de l'écran, T7 ; parité du démontage web, l.254). Le prochain envoi le
    /// relance.
    public func arreterSuivi() {
        suivi?.cancel()
        annulationSuivi.annuler()
        enVerification = []
    }

    public func oublierExigenceSuivante() {
        exigenceSuivante = nil
    }

    /// La célébration du dossier complet a été montrée (le web l'éteint après 2,5 s, l.268-269).
    public func oublierDossierComplet() {
        dossierComplet = false
    }

    // MARK: - Actions sur une pièce

    /// « Revérifier » : geste manuel seulement (jamais automatique, l.297-332), puis relecture du dossier. L'appel IA est
    /// attendu : borne des transferts.
    public func reverifier(documentId: String) async -> VerdictDocument? {
        let taille = dossier?.documents.first(where: { $0.id == documentId })?.tailleOctets
        return await action(documentId, delai: borneTransfert(octets: taille)) { port, context in
            try await port.reverifier(documentId: documentId, context: context)
        }
    }

    /// « Demander une revue humaine » (l.336-358), puis relecture.
    public func demanderRevue(documentId: String) async -> Bool {
        await action(documentId) { port, context in
            try await port.demanderRevue(documentId: documentId, context: context)
        } != nil
    }

    /// Signature de l'attestation santé : valeur serveur relue par la gateway, puis relecture du dossier. Une attestation
    /// déjà signée ne l'est jamais une seconde fois (`fn_signer_attestation_sante` réécrirait sa date, `public.sql`
    /// l.56329-56332 ; web : `canSign = … && !signedAt`, l.69) : faux, sans appel.
    public func signerAttestation() async -> Bool {
        guard let dossier, dossier.attestationSanteSigneeLe == nil else { return false }
        return await action("attestation") { port, context in
            _ = try await port.signerAttestationSante(context: context)
        } != nil
    }

    /// Copie temporaire protégée de la pièce (QuickLook, T7) ; jamais une URL distante. Téléchargement : borne des
    /// transferts.
    public func consulter(_ document: DocumentSoignant) async -> URL? {
        await action(document.id, relire: false, delai: borneTransfert(octets: document.tailleOctets)) { port, context in
            try await port.consulter(document: document, context: context)
        }
    }

    // MARK: - Interne : envoi

    /// Corps de l'envoi inscrit au registre ; rend l'état final (repris par les autres instances), publié ici seulement
    /// sous l'epoch de l'écran.
    private func executerEnvoi(typeDocument: String, fichier: FichierPret, libelle: String?) async -> EtatEnvoi {
        guard let gateways = await gatewaysCourantes() else { return await publier(.inactif) }
        let port = gateways.documents
        let context = snapshot.context

        // 1. Un reçu d'un essai précédent est réconcilié d'abord (sans publier son issue au milieu de cet envoi) ; tant
        //    qu'il reste en vol, ou si le journal est illisible, aucun nouvel envoi.
        guard await reconcilierEnAttente(gateways) else {
            return await publier(envoi == .suiviIllisible ? .suiviIllisible : .recuEnCours)
        }

        // 2. Reçu `prepared` à la clé déterministe, daté de l'epoch de cet écran.
        let libelleSaisi = libelle.flatMap { $0.isEmpty ? nil : $0 }
        var recu: RecuDocument
        do {
            recu = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.preparerEnvoi(type: typeDocument, fichier: fichier.fichier, libelle: libelleSaisi, context: context)
            }
            recu.epoch = snapshot.epoch
            try recu.valider()
        } catch let erreur as RecuErreur {
            return await publier(erreur == .illisible ? .suiviIllisible : .termine(.refuse(code: Self.codeMetadonneesInvalides)))
        } catch {
            return await publier(.erreur(message(de: error)))
        }
        guard await courant() else { return await publier(.inactif) }

        // 3. Journal AVANT l'upload : `prepared`, puis `started` juste avant l'unique requête.
        do {
            try await journal.ecrire(recu)
            recu = try recu.demarrer()
            try await journal.ecrire(recu)
        } catch RecuErreur.recuEnCours {
            return await publier(.recuEnCours)
        } catch {
            return await publier(.suiviIllisible)
        }

        // 4. Une seule requête d'envoi, bornée par la taille ; transport incertain → réconciliation immédiate.
        var issue: IssueEnvoiDocument
        do {
            let demarre = recu
            issue = try await bounded(timeout: borneTransfert(octets: fichier.octets.count)) {
                try await port.envoyer(recu: demarre, octets: fichier.octets, context: context)
            }
        } catch let erreur as JoleneError where erreur.kind == .unauthorized {
            if await courant() { sessionExpired = true }
            return await publier(.erreur(erreur.message))
        } catch {
            // Délai, transport, reçu refusé par les contrôles de la gateway : rien ne prouve l'absence d'effet.
            issue = .incertain
        }
        if issue == .incertain {
            let relue = await relire(recu, port: port)
            if relue.sessionExpiree, await courant() { sessionExpired = true }
            issue = relue.issue ?? .incertain
        }

        // 5. Reçu effacé sauf issue incertaine (gardé `started`), issue publiée, dossier relu, suivi du verdict.
        if issue != .incertain {
            do { try await journal.effacer(recu) } catch { return await publier(.suiviIllisible) }
        }
        guard await courant() else { return await publier(.termine(issue)) }
        envoi = .termine(issue)
        if issue != .incertain { await apresIssue(issue, gateways: gateways) }
        return .termine(issue)
    }

    /// Publie `etat` si l'epoch est toujours celui de l'écran, sinon `.inactif` : aucun état d'une identité quittée
    /// (revue fraîche de T6, m-f). Rend `etat`, repris par les autres instances du même utilisateur.
    private func publier(_ etat: EtatEnvoi) async -> EtatEnvoi {
        envoi = await courant() ? etat : .inactif
        return etat
    }

    /// Envoi inscrit pour cet utilisateur : celui de cette instance (geste ignoré) ou celui d'une autre (écran rouvert,
    /// autre fenêtre ; M1-bis), affiché `.enCours` ici puis repris à sa fin — jamais réconcilié, jamais doublé.
    private func suivreEnvoi(_ enVol: EssaisDocumentsEnVol.Envoi) {
        guard enVol.tache != envoiPropre, enVol.tache != envoiObserve else { return }
        envoiObserve = enVol.tache
        envoi = .enCours(typeDocument: enVol.typeDocument)
        let tache = enVol.tache
        Task { [weak self] in
            let fin = await tache.value
            await self?.reprendre(fin, de: tache)
        }
    }

    /// Fin de l'envoi d'une autre instance : son issue est reprise (dossier relu, suivi du verdict) ; tout autre état
    /// final rend l'envoi possible ici, sauf un journal illisible.
    private func reprendre(_ fin: EtatEnvoi, de tache: Task<EtatEnvoi, Never>) async {
        guard envoiObserve == tache else { return }
        envoiObserve = nil
        guard let gateways = await gatewaysCourantes() else { envoi = .inactif; return }
        switch fin {
        case let .termine(issue):
            envoi = .termine(issue)
            if issue != .incertain { await apresIssue(issue, gateways: gateways) }
        case .suiviIllisible:
            envoi = .suiviIllisible
        default:
            envoi = .inactif
            await relireDossier(gateways, signalerEchec: false)
        }
    }

    // MARK: - Interne : réconciliation

    /// Réconcilie le reçu en attente : une seule réconciliation à la fois pour cet utilisateur, partagée par toute
    /// instance qui la demande pendant qu'elle tourne (même reçu, même rejeu idempotent, une seule vérification). Vrai si
    /// plus rien n'est en vol.
    @discardableResult
    private func reconcilierEnAttente(_ gateways: Gateways) async -> Bool {
        guard let cle else {
            if await courant() { envoi = .suiviIllisible }
            return false
        }
        let port = gateways.documents
        let tache = registre.reconciliation(cle, sinon: { [self] in await self.reconciliationPartagee(port: port) })
        return await appliquer(await tache.value, gateways: gateways)
    }

    /// Journal et gateway seulement, aucun état publié : `prepared` → `not_sent` puis effacé (rien n'est parti, aucun
    /// appel) ; terminé → effacé ; sinon relecture serveur, jamais de renvoi, et reçu effacé après une issue certaine.
    private func reconciliationPartagee(port: any DocumentsPort) async -> ResultatReconciliationDocument {
        let enAttente: RecuDocument?
        do {
            enAttente = try await journal.lire(userId: snapshot.context.userId)
        } catch {
            return .illisible
        }
        guard let recu = enAttente else { return .aucunRecu }
        if recu.estTermine || recu.phase == .prepared {
            do {
                if recu.phase == .prepared { try await journal.ecrire(try recu.marquerNonEnvoye()) }
                try await journal.effacer(recu)
            } catch {
                return .illisible
            }
            return .efface
        }
        let relue = await relire(recu, port: port)
        guard let issue = relue.issue else { return .echec(sessionExpiree: relue.sessionExpiree) }
        if issue != .incertain {
            // Un reçu qui ne s'efface pas reste en vol : fail-closed, jamais « plus rien en vol » (m-f).
            do { try await journal.effacer(recu) } catch { return .illisible }
        }
        return .issue(issue)
    }

    /// Résultat partagé appliqué à CETTE instance. L'issue n'est jamais publiée pendant un envoi de cette instance ni
    /// pendant l'affichage de celui d'une autre : elle ne remplace pas `.enCours`.
    private func appliquer(_ resultat: ResultatReconciliationDocument, gateways: Gateways) async -> Bool {
        switch resultat {
        case .aucunRecu, .efface:
            return true
        case .illisible:
            if await courant() { envoi = .suiviIllisible }
            return false
        case let .echec(sessionExpiree):
            if sessionExpiree, await courant() { self.sessionExpired = true }
            return false
        case let .issue(issue):
            guard await courant() else { return issue != .incertain }
            if envoiPropre == nil, envoiObserve == nil { envoi = .termine(issue) }
            if issue != .incertain { await apresIssue(issue, gateways: gateways) }
            return issue != .incertain
        }
    }

    /// Une relecture par la gateway (ligne, objet, rejeu de l'enregistrement), bornée à `requetesReconciliation` fois
    /// `resolutionTimeout` ; issue nil si elle n'a pas pu avoir lieu (transport, délai, session).
    private func relire(_ recu: RecuDocument, port: any DocumentsPort) async -> (issue: IssueEnvoiDocument?, sessionExpiree: Bool) {
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: borneReconciliation) { try await port.reconcilier(recu: recu, context: context) }
            return (issue, false)
        } catch let erreur as JoleneError where erreur.kind == .unauthorized {
            return (nil, true)
        } catch {
            return (nil, false)
        }
    }

    /// Après une issue relue : dossier relu, puis suivi du verdict d'une vérification demandée.
    private func apresIssue(_ issue: IssueEnvoiDocument, gateways: Gateways) async {
        await relireDossier(gateways, signalerEchec: false)
        if case let .verificationDemandee(documentId) = issue {
            suivre(documentId, port: gateways.documents)
        }
    }

    // MARK: - Interne : suivi du verdict

    private func suivre(_ documentId: String, port: any DocumentsPort) {
        enVerification.insert(documentId)
        observerVerification(documentId, port: port)
        if let suivi, !suivi.isCancelled { return }
        numeroSuivi += 1
        let numero = numeroSuivi
        let attendre = self.attendre
        // Aucune référence forte au modèle pendant l'attente : sa disparition annule le suivi (`deinit`).
        let tache = Task { [weak self] in
            var ecoule: TimeInterval = 0
            while ecoule < DocumentsModel.dureeSuivi {
                do { try await attendre(DocumentsModel.intervalleSuivi) } catch { break }
                if Task.isCancelled { break }
                ecoule += DocumentsModel.intervalleSuivi
                guard let modele = self else { break }
                let continuer = await modele.releverSuivi(final: ecoule >= DocumentsModel.dureeSuivi)
                if !continuer || Task.isCancelled { break }
            }
            self?.finSuivi(numero)
        }
        suivi = tache
        annulationSuivi.poser(tache)
    }

    /// Issue de `verify-document`, attendue hors du chemin critique (revue fraîche de T6, m-d), comme le `.then` du web
    /// (l.413-425) : une erreur (429, 403, 503…) donne aussitôt « vérification manuelle en attente » ; une réponse
    /// donne aussitôt une relecture (`charger()`, l.420). Inconnue (port sans suivi, démo) : rien, le suivi relit.
    private func observerVerification(_ documentId: String, port: any DocumentsPort) {
        Task { [weak self] in
            guard let echec = await port.verificationEchouee(documentId: documentId) else { return }
            await self?.issueVerification(documentId, echec: echec)
        }
    }

    private func issueVerification(_ documentId: String, echec: Bool) async {
        guard enVerification.contains(documentId), await courant() else { return }
        guard echec else {
            _ = await releverSuivi(final: false)
            return
        }
        enVerification.remove(documentId)
        verificationManuelle(documentId)
        if let gateways = await gatewaysCourantes() { await relireDossier(gateways, signalerEchec: false) }
    }

    /// Une relecture du suivi ; vrai tant qu'une pièce suivie reste `EN_ATTENTE`.
    private func releverSuivi(final: Bool) async -> Bool {
        guard !enVerification.isEmpty, let gateways = await gatewaysCourantes() else { return false }
        await relireDossier(gateways, signalerEchec: false)
        guard !Task.isCancelled else { return false }
        guard let dossier else { return true }
        let termines = dossier.documents.filter { enVerification.contains($0.id) && $0.statutVerification != "EN_ATTENTE" }
        if !termines.isEmpty {
            enVerification.subtract(termines.map(\.id))
            for document in termines where document.statutVerification == VerdictDocument.revueManuelleRequise.rawValue {
                verificationManuelle(document.id)
            }
            if termines.contains(where: { $0.statutVerification == VerdictDocument.verifie.rawValue }) {
                if let prochaine = dossier.prochaineExigence(maintenant: horloge.now()) {
                    exigenceSuivante = exigenceSuivante ?? prochaine.typeDocument
                } else {
                    dossierComplet = true
                }
            }
        }
        if final {
            // 60 s sans tentative relue (`verify-document` refusé avant de la poser : 429, 403) : vérification manuelle.
            for document in dossier.documents where enVerification.contains(document.id)
                && document.statutVerification == "EN_ATTENTE" && document.verificationAttemptId == nil {
                verificationManuelle(document.id)
            }
        }
        return !enVerification.isEmpty
    }

    /// L'issue publiée de cet envoi devient « enregistré, vérification manuelle » (l.416-419), si elle le concerne encore.
    private func verificationManuelle(_ documentId: String) {
        guard envoi == .termine(.verificationDemandee(documentId: documentId)) else { return }
        envoi = .termine(.enregistre(documentId: documentId))
    }

    /// Fin d'une boucle de suivi : seule la plus récente libère l'état (un suivi relancé après `arreterSuivi()` garde le
    /// sien).
    private func finSuivi(_ numero: Int) {
        guard numero == numeroSuivi else { return }
        suivi = nil
        enVerification = []
    }

    // MARK: - Interne : lectures et actions

    private func gatewaysCourantes() async -> Gateways? {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return nil }
        guard await courant() else { return nil }
        return gateways
    }

    private func courant() async -> Bool {
        await controller.epoch == snapshot.epoch
    }

    /// Borne d'un transfert, jamais plus courte que `resolutionTimeout`.
    private func borneTransfert(octets: Int?) -> TimeInterval {
        max(controller.resolutionTimeout, Self.delaiTransfert(octets: octets))
    }

    private var borneReconciliation: TimeInterval {
        controller.resolutionTimeout * Double(Self.requetesReconciliation)
    }

    /// Relit le dossier ; un échec n'efface jamais un dossier déjà affiché (seul le premier chargement échoue).
    private func relireDossier(_ gateways: Gateways, signalerEchec: Bool) async {
        generation += 1
        let numero = generation
        let port = gateways.documents
        let context = snapshot.context
        do {
            let lu = try await bounded(timeout: controller.resolutionTimeout) { try await port.dossier(context: context) }
            guard await courant(), generation == numero else { return }
            sessionExpired = false
            etat = .charge(lu)
        } catch {
            guard await courant(), generation == numero, !estAnnulation(error) else { return }
            if let jolene = error as? JoleneError, jolene.kind == .unauthorized { sessionExpired = true }
            if signalerEchec, dossier == nil { etat = .echec(message(de: error)) }
        }
    }

    /// Action ponctuelle : une requête bornée (`delai`, `resolutionTimeout` par défaut), refus affiché (`messageAction`),
    /// relecture du dossier après succès. Une seule à la fois : la garde est posée AVANT toute suspension (revue fraîche
    /// de T6, m-a), un second geste déjà en file est ignoré.
    private func action<T: Sendable>(_ cible: String, relire: Bool = true, delai: TimeInterval? = nil,
                                     _ appel: @escaping @Sendable (any DocumentsPort, MissionReadContext) async throws -> T) async -> T? {
        guard actionEnCours == nil else { return nil }
        actionEnCours = cible
        defer { actionEnCours = nil }
        guard let gateways = await gatewaysCourantes() else { return nil }
        messageAction = nil
        let port = gateways.documents
        let context = snapshot.context
        do {
            let resultat = try await bounded(timeout: delai ?? controller.resolutionTimeout) { try await appel(port, context) }
            guard await courant() else { return nil }
            if relire { await relireDossier(gateways, signalerEchec: false) }
            return resultat
        } catch {
            guard await courant(), !estAnnulation(error) else { return nil }
            if let jolene = error as? JoleneError, jolene.kind == .unauthorized { sessionExpired = true }
            messageAction = message(de: error)
            return nil
        }
    }

    private func message(de error: Error) -> String {
        if let jolene = error as? JoleneError { return jolene.message }
        return MessagesDocuments.erreurGenerique
    }

    private func estAnnulation(_ error: Error) -> Bool {
        error is CancellationError || (error as? JoleneError)?.kind == .cancelled
    }
}

/// Tâche de suivi du verdict, annulable depuis le `deinit` non isolé de `DocumentsModel`.
private final class AnnulationSuivi: @unchecked Sendable {
    private let verrou = NSLock()
    private var tache: Task<Void, Never>?

    func poser(_ nouvelle: Task<Void, Never>) {
        verrou.lock(); tache = nouvelle; verrou.unlock()
    }

    func annuler() {
        verrou.lock()
        let courante = tache
        verrou.unlock()
        courante?.cancel()
    }
}
