import Combine
import Foundation

/// Modèle des justificatifs (lot 2 T6, blueprint §2.5 « Justificatif », décision 14). Données et pipeline d'envoi ;
/// l'écran (T7) ne fait que lire ces états et traduire les issues en textes.
///
/// - Lecture : dossier relu sous l'epoch de la session, borné à `SessionController.resolutionTimeout` ; cohérence des
///   noms en best-effort (le web avale l'erreur) ; un reçu laissé par un essai précédent est réconcilié AVANT la lecture,
///   jamais pendant un envoi en vol, et une seule réconciliation à la fois (revue fraîche de T6, M1).
/// - Envoi, un seul à la fois (drapeau privé `envoiEnVol`, posé du début de `envoyer` jusqu'à sa fin) : reçu `prepared`
///   puis `started` journalisés (`ReceiptJournal<RecuDocument>`, domaine `document`) AVANT l'unique upload ; issue relue
///   par la gateway ; reçu effacé après un succès, un refus ou un « non envoyé » ; gardé `started` sur une issue
///   incertaine, réconciliée aussitôt puis à chaque chargement — jamais de renvoi, ni de l'upload ni de
///   `verify-document`. Aucun octet n'est conservé.
/// - Délais : upload, réconciliation, revérification et consultation sont bornés par `delaiTransfert(octets:)` (au moins
///   120 s, proportionnel à la taille), jamais par `resolutionTimeout` ; `verify-document` est lancé par la gateway sans
///   être attendu (amendement de PRINCIPES l.107-114, `docs/mobile-swift/DECISIONS_LOT2.md`).
/// - Verdict en ligne : relecture du dossier toutes les 5 s pendant 60 s au plus (`DocumentsSoignant.tsx` l.250-255),
///   arrêtée dès que la pièce quitte `EN_ATTENTE`, par `arreterSuivi()` ou à la disparition du modèle (l.254) ; un
///   verdict `VERIFIE` enchaîne sur la prochaine exigence critique (`exigenceSuivante`) ou signale un dossier complet
///   (l.258-276) ; une revue manuelle relue, ou une vérification jamais engagée après 60 s, donne `.enregistre`
///   (« Document téléversé. Vérification manuelle en attente. », l.416-419).
/// - Journal illisible (`RecuErreur.illisible`) : envoi bloqué, reçu jamais réécrit ni effacé, renvoi web
///   `renvoiWeb` (consigne T6 de `docs/mobile-swift/DECISIONS_LOT2.md`).
@MainActor
public final class DocumentsModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case charge(DossierDocuments)
        case echec(String)
    }

    public enum EtatEnvoi: Equatable, Sendable {
        case inactif
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
    /// Toutes les pièces critiques sont valides après un verdict (l.266-270).
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
    private var generation = 0
    /// Envoi en vol, du début de `envoyer` jusqu'à sa fin (relecture et suivi lancés) : seule garde du « un seul envoi à
    /// la fois », indépendante de l'état publié `envoi` (revue fraîche de T6, M1).
    private var envoiEnVol = false
    /// Réconciliation en cours, partagée par tout appelant (un seul passage à la fois).
    private var reconciliation: Task<Bool, Never>?
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

    /// Apparition, tirer-pour-rafraîchir, retour au premier plan (T7). Pendant un envoi, aucune réconciliation : le reçu
    /// en vol est celui de l'envoi courant.
    public func charger() async {
        guard let gateways = await gatewaysCourantes() else { return }
        horloge = gateways.clock
        if dossier == nil { etat = .chargement }
        if !envoiEnVol { await reconcilierEnAttente(gateways) }
        await relireDossier(gateways, signalerEchec: true)
        guard let dossier, !dossier.documents.isEmpty else { return }
        let port = gateways.documents
        let context = snapshot.context
        let lue = try? await bounded(timeout: controller.resolutionTimeout) { try await port.coherence(context: context) }
        guard await controller.epoch == snapshot.epoch else { return }
        coherence = lue
    }

    // MARK: - Envoi

    /// Envoie un fichier préparé (`FichierDocument.preparer`) pour un type proposé par l'écran
    /// (`DossierDocuments.peutEnvoyer`). Un seul envoi à la fois : un geste pendant un envoi est ignoré.
    public func envoyer(typeDocument: String, fichier: FichierPret, libelle: String?) async {
        guard !envoiEnVol, envoi != .suiviIllisible else { return }
        guard let dossier, dossier.peutEnvoyer(typeDocument: typeDocument, maintenant: horloge.now()) else {
            envoi = .refuseAvantEnvoi(message: MessagesDocuments.enregistrementImpossible)
            return
        }
        envoiEnVol = true
        defer { envoiEnVol = false }
        envoi = .enCours(typeDocument: typeDocument)
        guard let gateways = await gatewaysCourantes() else { envoi = .inactif; return }
        let port = gateways.documents
        let context = snapshot.context

        // 1. Un reçu d'un essai précédent est réconcilié d'abord (sans publier son issue au milieu de cet envoi) ; tant
        //    qu'il reste en vol, aucun nouvel envoi.
        guard await reconcilierEnAttente(gateways) else {
            if envoi != .suiviIllisible { envoi = .recuEnCours }
            return
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
            envoi = erreur == .illisible ? .suiviIllisible : .termine(.refuse(code: Self.codeMetadonneesInvalides))
            return
        } catch {
            envoi = .erreur(message(de: error))
            return
        }
        guard await controller.epoch == snapshot.epoch else { envoi = .inactif; return }

        // 3. Journal AVANT l'upload : `prepared`, puis `started` juste avant l'unique requête.
        do {
            try await journal.ecrire(recu)
            recu = try recu.demarrer()
            try await journal.ecrire(recu)
        } catch RecuErreur.recuEnCours {
            envoi = .recuEnCours
            return
        } catch {
            envoi = .suiviIllisible
            return
        }

        // 4. Une seule requête d'envoi, bornée par la taille ; transport incertain → réconciliation immédiate.
        var issue: IssueEnvoiDocument
        do {
            let demarre = recu
            issue = try await bounded(timeout: borneTransfert(octets: fichier.octets.count)) {
                try await port.envoyer(recu: demarre, octets: fichier.octets, context: context)
            }
        } catch let erreur as JoleneError where erreur.kind == .unauthorized {
            sessionExpired = true
            envoi = .erreur(erreur.message)
            return
        } catch {
            // Délai, transport, reçu refusé par les contrôles de la gateway : rien ne prouve l'absence d'effet.
            issue = .incertain
        }
        if issue == .incertain {
            issue = await reconcilier(recu, gateways: gateways) ?? .incertain
        }
        await terminer(recu, issue: issue, gateways: gateways, depuisEnvoi: true)
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

    // MARK: - Interne

    private func gatewaysCourantes() async -> Gateways? {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return nil }
        guard await controller.epoch == snapshot.epoch else { return nil }
        return gateways
    }

    /// Borne d'un transfert, jamais plus courte que `resolutionTimeout`.
    private func borneTransfert(octets: Int?) -> TimeInterval {
        max(controller.resolutionTimeout, Self.delaiTransfert(octets: octets))
    }

    /// Relit le dossier ; un échec n'efface jamais un dossier déjà affiché (seul le premier chargement échoue).
    private func relireDossier(_ gateways: Gateways, signalerEchec: Bool) async {
        generation += 1
        let courant = generation
        let port = gateways.documents
        let context = snapshot.context
        do {
            let lu = try await bounded(timeout: controller.resolutionTimeout) { try await port.dossier(context: context) }
            guard await controller.epoch == snapshot.epoch, generation == courant else { return }
            sessionExpired = false
            etat = .charge(lu)
        } catch {
            guard await controller.epoch == snapshot.epoch, generation == courant, !estAnnulation(error) else { return }
            if let jolene = error as? JoleneError, jolene.kind == .unauthorized { sessionExpired = true }
            if signalerEchec, dossier == nil { etat = .echec(message(de: error)) }
        }
    }

    /// Réconcilie le reçu en attente, une seule fois à la fois : un appelant qui arrive pendant une réconciliation en
    /// attend l'issue au lieu d'en lancer une seconde (même reçu, même rejeu idempotent, une seule vérification). Vrai si
    /// plus rien n'est en vol.
    @discardableResult
    private func reconcilierEnAttente(_ gateways: Gateways) async -> Bool {
        if let enCours = reconciliation { return await enCours.value }
        let tache = Task { await self.reconcilierUneFois(gateways) }
        reconciliation = tache
        let resultat = await tache.value
        reconciliation = nil
        return resultat
    }

    /// `prepared` : rien n'est parti (sortie sûre `not_sent`, aucun appel) ; terminé : effacé ; sinon relecture serveur,
    /// jamais de renvoi.
    private func reconcilierUneFois(_ gateways: Gateways) async -> Bool {
        let enAttente: RecuDocument?
        do {
            enAttente = try await journal.lire(userId: snapshot.context.userId)
        } catch {
            envoi = .suiviIllisible
            return false
        }
        guard let recu = enAttente else { return true }
        if recu.estTermine || recu.phase == .prepared {
            do {
                if recu.phase == .prepared { try await journal.ecrire(try recu.marquerNonEnvoye()) }
                try await journal.effacer(recu)
            } catch {
                envoi = .suiviIllisible
                return false
            }
            return true
        }
        guard let issue = await reconcilier(recu, gateways: gateways) else { return false }
        await terminer(recu, issue: issue, gateways: gateways, depuisEnvoi: false)
        return issue != .incertain
    }

    /// Une relecture par la gateway (bornée comme un transfert : le rejeu de l'enregistrement peut suivre) ; nil si elle
    /// n'a pas pu avoir lieu (transport, délai, session).
    private func reconcilier(_ recu: RecuDocument, gateways: Gateways) async -> IssueEnvoiDocument? {
        let port = gateways.documents
        let context = snapshot.context
        do {
            return try await bounded(timeout: borneTransfert(octets: recu.tailleOctets)) {
                try await port.reconcilier(recu: recu, context: context)
            }
        } catch let erreur as JoleneError where erreur.kind == .unauthorized {
            sessionExpired = true
            return nil
        } catch {
            return nil
        }
    }

    /// Issue relue : reçu effacé sauf issue incertaine (gardé `started`), dossier relu, suivi du verdict. L'issue d'une
    /// réconciliation n'est publiée que hors d'un envoi en vol : elle ne remplace jamais `.enCours`.
    private func terminer(_ recu: RecuDocument, issue: IssueEnvoiDocument, gateways: Gateways, depuisEnvoi: Bool) async {
        if issue != .incertain {
            do {
                try await journal.effacer(recu)
            } catch {
                envoi = .suiviIllisible
                return
            }
        }
        guard await controller.epoch == snapshot.epoch else { return }
        if depuisEnvoi || !envoiEnVol { envoi = .termine(issue) }
        guard issue != .incertain else { return }
        await relireDossier(gateways, signalerEchec: false)
        if case let .verificationDemandee(documentId) = issue {
            suivre(documentId)
        }
    }

    private func suivre(_ documentId: String) {
        enVerification.insert(documentId)
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

    /// Action ponctuelle : une requête bornée (`delai`, `resolutionTimeout` par défaut), refus affiché (`messageAction`),
    /// relecture du dossier après succès.
    private func action<T: Sendable>(_ cible: String, relire: Bool = true, delai: TimeInterval? = nil,
                                     _ appel: @escaping @Sendable (any DocumentsPort, MissionReadContext) async throws -> T) async -> T? {
        guard actionEnCours == nil, let gateways = await gatewaysCourantes() else { return nil }
        actionEnCours = cible
        messageAction = nil
        defer { actionEnCours = nil }
        let port = gateways.documents
        let context = snapshot.context
        do {
            let resultat = try await bounded(timeout: delai ?? controller.resolutionTimeout) { try await appel(port, context) }
            guard await controller.epoch == snapshot.epoch else { return nil }
            if relire { await relireDossier(gateways, signalerEchec: false) }
            return resultat
        } catch {
            guard await controller.epoch == snapshot.epoch, !estAnnulation(error) else { return nil }
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
