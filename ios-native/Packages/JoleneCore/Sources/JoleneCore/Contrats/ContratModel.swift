import Foundation
import Combine

/// Modèle d'un contrat (lot 2, T8 ; écran T9a, signature T9b). Mêmes règles que les modèles du lot 1
/// (`MissionsListModel`) : gateways de l'epoch de la session, chaque appel borné à `resolutionTimeout`, résultat
/// abandonné si l'epoch a changé, annulation jamais affichée en erreur, `.unauthorized` → `sessionExpired`.
///
/// Chargement (`LOT2_PLAN.md` §2.5) : contrat relu, puis son original contrôlé par le port (triple contrôle ; rendu
/// serveur demandé par le port seulement si `ContratRules.renduServeurADemander`, puis contrat relu ici et
/// l'empreinte du rendu comparée à la relecture) ; jamais d'original pour un CDD à préparer (décision 19) ;
/// certificat si une partie a signé (erreur non bloquante) ; admission de recette pour un compte TEST (sans
/// admission : renvoi web, décision 18). La session OTP est indexée sur (contrat, empreinte, original prêt).
///
/// OTP : la session décide si une requête part (une seule à la fois, `SessionSignatureOtp`, epoch vérifié avant
/// chaque requête) ; la gateway relit la preuve (`signatures_contrats`) avant d'annoncer une signature, et seule cette
/// confirmation la publie ; le contrat et le certificat sont relus ici avant la confirmation (T9b), et aussi après un
/// échec de transport, un délai épuisé ou un refus qui ferme la signature (`SignatureOtpPresentation.codesIndisponibles`),
/// chaque relecture sous son propre délai : l'écran montre l'état du serveur, jamais un succès supposé (revue fraîche de
/// T8, mineurs 2 et 9). Après une signature confirmée, une relecture du contrat en échec est relancée une fois, puis
/// l'actualisation est proposée sous la confirmation (`erreurRelecture`, `actualiser()`) ; un jeton refusé pendant une
/// relecture pose `sessionExpired`, une annulation ne publie rien (revue fraîche de T9b, m1). Aucun renvoi automatique,
/// aucune file. Recette STAGING : admission close à `canSend ? expiresAt : otpExpiresAt` (l.311-312) → renvoi web,
/// actions suspendues pendant la relecture de l'admission (`actionsSuspendues`, l.761 ; mineur 8).
@MainActor
public final class ContratModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case charge
        case echec(String)
    }

    /// Signature native : possible, renvoi web (compte TEST sans admission de recette), ou indisponible (zone de
    /// signature masquée par le web, original non contrôlé).
    public enum DisponibiliteSignature: Equatable, Sendable {
        case indisponible
        case renvoiWeb
        case possible
    }

    @Published public private(set) var etat: Etat = .chargement
    @Published public private(set) var contrat: ContratDetail?
    @Published public private(set) var original: OriginalContrat?
    @Published public private(set) var indisponibilite: MotifOriginalIndisponible?
    @Published public private(set) var signatures: [SignatureCertificat] = []
    @Published public private(set) var erreurCertificat: String?
    @Published public private(set) var admission: AdmissionSignatureRecette?
    @Published public private(set) var session: SessionSignatureOtp
    @Published public private(set) var sessionExpired = false
    /// Échec de la préparation du fichier à partager ou imprimer (T9a), `nil` sinon.
    @Published public private(set) var erreurPartage: String?
    /// Relecture de l'admission de recette en cours après un envoi (`actionsSuspendues`, `ContratMission.tsx` l.761) :
    /// formulaire conservé, aucune action (STAGING seulement).
    @Published public private(set) var actionsSuspendues = false
    /// Relecture du contrat en échec après une signature confirmée par la gateway (revue fraîche de T9b, m1) :
    /// `MessagesContrats.indisponible`, avec « Réessayer » (`actualiser()`) sous la confirmation ; `nil` sinon.
    @Published public private(set) var erreurRelecture: String?

    public let contratId: String
    private let controller: SessionController
    private let snapshot: SessionSnapshot
    /// Ports de l'epoch, retenus au chargement : une action OTP démarre sans suspension (un seul envoi en vol).
    private var ports: Gateways?
    private var derniereDemande = 0

    public init(controller: SessionController, snapshot: SessionSnapshot, contratId: String) {
        self.controller = controller
        self.snapshot = snapshot
        self.contratId = contratId
        self.session = SessionSignatureOtp(cle: CleSessionOtp(contratId: contratId, empreinte: nil, documentPret: false))
    }

    /// Horloge des gateways (démo : horloge fixée), seule source du minuteur et du compte à rebours.
    public var horloge: ClockPort { ports?.clock ?? SystemClock() }

    public var signature: DisponibiliteSignature { disponibiliteSignature(maintenant: horloge.now()) }

    /// Disponibilité à l'instant donné : un compte TEST n'a l'OTP qu'avec une admission de recette ouverte (le web la
    /// ferme à son échéance, `ContratMission.tsx` l.311-317, et bascule sur un autre mode ; décision 18 : renvoi web),
    /// original contrôlé ou non ; un compte réel l'a dès que l'original est contrôlé.
    public func disponibiliteSignature(maintenant: Date) -> DisponibiliteSignature {
        guard let contrat, ContratRules.zoneSignatureVisible(contrat) else { return .indisponible }
        if contrat.estCompteTest && !admissionOuverte(maintenant: maintenant) { return .renvoiWeb }
        return original != nil ? .possible : .indisponible
    }

    /// `nouvelEnvoiAutorise` (`ContratMission.tsx` l.762) : compte réel, ou recette admise avec un envoi restant.
    public var nouvelEnvoiAutorise: Bool { nouvelEnvoiAutorise(maintenant: horloge.now()) }

    public func nouvelEnvoiAutorise(maintenant: Date) -> Bool {
        guard let contrat else { return false }
        return !contrat.estCompteTest || (admissionOuverte(maintenant: maintenant) && admission?.peutEnvoyer == true)
    }

    /// Zone « Votre signature » à afficher (`ContratMission.tsx` l.709) : `nil` quand le web la masque (CDD à préparer,
    /// déjà signé, contrat complet, annulé ou expiré), sauf juste après une signature de cette session, dont la
    /// confirmation relue reste affichée ; renvoi web pour un compte TEST sans admission ; sinon la signature OTP
    /// (formulaire désactivé tant que l'original n'est pas contrôlé, comme `documentPret` du web).
    public func zoneSignature(maintenant: Date) -> ZoneSignature? {
        guard let contrat else { return nil }
        let presentation = SignatureOtpPresentation(session: session, maintenant: maintenant,
                                                    nouvelEnvoiAutorise: nouvelEnvoiAutorise(maintenant: maintenant),
                                                    actionsSuspendues: actionsSuspendues, erreurRelecture: erreurRelecture)
        if session.etape == .signe { return .otp(presentation) }
        guard ContratRules.zoneSignatureVisible(contrat) else { return nil }
        if disponibiliteSignature(maintenant: maintenant) == .renvoiWeb {
            return .renvoiWeb(message: ZoneSignature.messageRenvoiWeb, route: ContratPresentation.renvoiSignature(contratId: contrat.id))
        }
        return .otp(presentation)
    }

    /// Admission de recette ouverte : `admittedUntil = canSend ? expiresAt : otpExpiresAt`, close quand cette échéance est
    /// nulle ou passée (`ContratMission.tsx` l.311-312 ; revue fraîche de T9b, m2). Sans envoi possible, c'est donc
    /// l'échéance du code (bornée par la capacité, `AdmissionRecette.interpreter`), jamais la fin de la capacité.
    private func admissionOuverte(maintenant: Date) -> Bool {
        guard let admission, let jusqua = admission.peutEnvoyer ? admission.expireLe : admission.otpExpireLe else { return false }
        return jusqua > maintenant
    }

    // MARK: - Chargement

    public func charger() async {
        derniereDemande += 1
        let demande = derniereDemande
        if contrat == nil { etat = .chargement }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        guard demande == derniereDemande, !Task.isCancelled else { return }
        ports = gateways
        let port = gateways.contrats
        let context = snapshot.context
        let delai = controller.resolutionTimeout
        let id = contratId
        do {
            var detail = try await bounded(timeout: delai) { try await port.contrat(id: id, context: context) }
            var controle: OriginalContrat?
            var motif: MotifOriginalIndisponible?
            if ContratRules.cddSansOriginal(detail) {
                motif = .cddAPreparer
            } else {
                let avant = detail
                do {
                    let lu = try await bounded(timeout: delai) { try await port.original(contrat: avant, context: context) }
                    if (avant.storagePath ?? "").isEmpty {
                        // Rendu serveur : le contrat relu doit porter l'empreinte de l'original contrôlé.
                        detail = try await bounded(timeout: delai) { try await port.contrat(id: id, context: context) }
                    }
                    if lu.empreinte == detail.hashDocument { controle = lu } else { motif = .hashMismatch }
                } catch let refus as ContratOriginalIndisponible {
                    motif = refus.motif
                }
            }
            var lignes: [SignatureCertificat] = []
            var erreurLignes: String?
            if ContratRules.certificatVisible(detail) {
                do {
                    lignes = try await bounded(timeout: delai) { try await port.certificat(contratId: id, context: context) }
                } catch {
                    let erreur = Self.traduire(error)
                    if erreur.kind == .cancelled || erreur.kind == .unauthorized { throw error }
                    erreurLignes = erreur.message
                }
            }
            var recette: AdmissionSignatureRecette?
            if detail.estCompteTest, controle != nil {
                recette = try await bounded(timeout: delai) { try await port.admissionRecette(contratId: id, context: context) }
            }
            guard await controller.epoch == snapshot.epoch, demande == derniereDemande else { return }
            contrat = detail
            original = controle
            indisponibilite = motif
            signatures = lignes
            erreurCertificat = erreurLignes
            admission = recette
            session.changerCle(CleSessionOtp(contratId: id, empreinte: controle?.empreinte, documentPret: controle != nil))
            if detail.estCompteTest { session.reprendre(otpExpireLe: Self.otpCourant(recette), maintenant: gateways.clock.now()) }
            // Contrat relu sous un jeton accepté : plus de session à vérifier ni d'actualisation à proposer.
            sessionExpired = false
            erreurRelecture = nil
            etat = .charge
        } catch {
            guard await controller.epoch == snapshot.epoch, demande == derniereDemande else { return }
            let erreur = Self.traduire(error)
            if erreur.kind == .cancelled { return }
            if erreur.kind == .unauthorized { sessionExpired = true }
            etat = .echec(erreur.message)
        }
    }

    // MARK: - Session OTP

    public func accepter(_ valeur: Bool) {
        session.accepter(valeur)
    }

    public func saisirCode(_ texte: String) {
        session.saisir(texte)
    }

    /// « Recevoir le code SMS pour signer » : une seule requête (epoch vérifié avant), réponse ignorée si la clé a
    /// changé entre-temps ; un refus qui ferme la signature relit le contrat. `actionsSuspendues` est lu après la
    /// suspension de l'epoch (revue fraîche de T9b, m3) : une relecture d'admission commencée pendant cette attente
    /// bloque l'envoi.
    public func envoyerCode() async {
        guard let gateways = ports, await controller.epoch == snapshot.epoch, !actionsSuspendues,
              let demande = session.demanderEnvoi(nouvelEnvoiAutorise: nouvelEnvoiAutorise(maintenant: gateways.clock.now()))
        else { return }
        let port = gateways.contrats
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.envoyerOtp(contratId: demande.contratId, empreinte: demande.empreinte, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            session.terminerEnvoi(issue, demande: demande, maintenant: gateways.clock.now())
            switch issue {
            case .envoye:
                if contrat?.estCompteTest == true { await relireAdmission(gateways) }
            case .refuse(let code, _, _):
                if let code, SignatureOtpPresentation.codesIndisponibles.contains(code) { await publierSiEpoch(relire(gateways)) }
            }
        } catch {
            guard await controller.epoch == snapshot.epoch else { return }
            let erreur = Self.traduire(error)
            if erreur.kind == .unauthorized { sessionExpired = true }
            session.echouerEnvoi(message: erreur.kind == .cancelled ? nil : erreur.message, demande: demande)
        }
    }

    /// « Signer » : code de six chiffres et consentement exigés par la session (epoch vérifié avant la requête,
    /// `actionsSuspendues` lu après lui, m3) ; un succès relu par la gateway est publié avec le contrat et le certificat
    /// relus ici (relecture du contrat relancée une fois, puis actualisation proposée, m1) ; échec de transport, délai
    /// épuisé ou refus qui ferme la signature : état du serveur relu (jamais un succès supposé, jamais un second envoi).
    public func signer() async {
        guard let gateways = ports, await controller.epoch == snapshot.epoch, !actionsSuspendues,
              let demande = session.demanderSignature(maintenant: gateways.clock.now()),
              case .signature(let code) = demande.nature else { return }
        let port = gateways.contrats
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.signer(contratId: demande.contratId, code: code, empreinte: demande.empreinte, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            switch issue {
            case .signee:
                // Preuve relue par la gateway : la signature est acquise, jamais retirée ni renvoyée. Le contrat et le
                // certificat sont relus avant la confirmation ; une lecture du contrat en échec (réseau, délai) est
                // relancée une fois, puis l'actualisation est proposée (revue fraîche de T9b, m1).
                var relu = await relire(gateways)
                if relu.aRelancer { relu = await relire(gateways) }
                guard await controller.epoch == snapshot.epoch else { return }
                publier(relu)
                if relu.aRelancer { erreurRelecture = MessagesContrats.indisponible }
                session.terminerSignature(issue, demande: demande)
            case .refuse(let codeRefus, _, _):
                session.terminerSignature(issue, demande: demande)
                if let codeRefus, SignatureOtpPresentation.codesIndisponibles.contains(codeRefus) { await publierSiEpoch(relire(gateways)) }
            }
        } catch {
            guard await controller.epoch == snapshot.epoch else { return }
            let erreur = Self.traduire(error)
            if erreur.kind == .unauthorized { sessionExpired = true }
            session.echouerSignature(message: erreur.kind == .cancelled ? nil : erreur.message, demande: demande)
            // La signature a pu être appliquée malgré l'échec : l'écran montre l'état relu du serveur. Rien n'est relu
            // avec une session expirée ni après une annulation (écran quitté).
            guard erreur.kind != .unauthorized, erreur.kind != .cancelled else { return }
            await publierSiEpoch(relire(gateways))
        }
    }

    // MARK: - Partage (T9a)

    /// Copie temporaire de l'original contrôlé (`Contrat-<numéro>.html`, `FichierContratTemporaire`), à partager par
    /// la feuille système ; l'écran l'efface à la fermeture de la feuille. Sans original contrôlé (CDD à préparer,
    /// document non figé ou empreinte différente), rien n'est écrit et le message du web est publié (`ContratMission.tsx`
    /// l.427-429) : jamais une reconstitution. Une copie écrite pour un epoch quitté est effacée aussitôt.
    public func preparerPartage() async -> URL? {
        erreurPartage = nil
        guard let original, let gateways = ports else {
            erreurPartage = FichierContratTemporaire.messageIndisponible
            return nil
        }
        let port = gateways.contrats
        let context = snapshot.context
        do {
            let url = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.fichierOriginal(contrat: original, context: context)
            }
            guard await controller.epoch == snapshot.epoch else {
                FichierContratTemporaire.effacer(url)
                return nil
            }
            return url
        } catch {
            guard await controller.epoch == snapshot.epoch else { return nil }
            if error is CancellationError || (error as? JoleneError)?.kind == .cancelled { return nil }
            let erreur = error as? JoleneError
            if erreur?.kind == .unauthorized { sessionExpired = true }
            erreurPartage = erreur?.message ?? FichierContratTemporaire.messageIndisponible
            return nil
        }
    }

    // MARK: - Relectures

    /// « Réessayer » sous la confirmation d'une signature dont le contrat n'a pas pu être relu (revue fraîche de T9b, m1) :
    /// relit le contrat et le certificat (une lecture chacun, bornées), sans démonter l'écran ni toucher à la session OTP.
    public func actualiser() async {
        guard let gateways = ports, await controller.epoch == snapshot.epoch else { return }
        let relu = await relire(gateways)
        guard await controller.epoch == snapshot.epoch else { return }
        publier(relu)
        if relu.aRelancer { erreurRelecture = MessagesContrats.indisponible }
    }

    /// État relu du serveur : contrat, puis certificat si une partie a signé.
    private struct Relecture {
        var contrat: ContratDetail?
        var signatures: [SignatureCertificat]?
        var erreurCertificat: String?
        /// Jeton refusé par l'une des lectures : session à vérifier (`sessionExpired`), rien à relancer.
        var sessionExpiree = false
        /// Lecture annulée par l'appelant : rien n'est publié, aucune erreur (jamais un message vide).
        var annulee = false

        /// Lecture du contrat en échec (réseau, délai, refus) : à relancer ou à proposer.
        var aRelancer: Bool { contrat == nil && !sessionExpiree && !annulee }

        mutating func noter(_ erreur: JoleneError) {
            switch erreur.kind {
            case .cancelled: annulee = true
            case .unauthorized: sessionExpiree = true
            default: break
            }
        }
    }

    /// Relit le contrat et son certificat, chaque lecture sous son propre délai (best-effort : une lecture du contrat en
    /// échec laisse l'état affiché inchangé ; un certificat illisible reste une erreur non bloquante ; jeton refusé →
    /// session à vérifier ; annulation → rien).
    private func relire(_ gateways: Gateways) async -> Relecture {
        let port = gateways.contrats
        let context = snapshot.context
        let id = contratId
        let delai = controller.resolutionTimeout
        var resultat = Relecture()
        let relu: ContratDetail
        do {
            relu = try await bounded(timeout: delai) { try await port.contrat(id: id, context: context) }
        } catch {
            resultat.noter(Self.traduire(error))
            return resultat
        }
        resultat.contrat = relu
        guard ContratRules.certificatVisible(relu) else { return resultat }
        do {
            resultat.signatures = try await bounded(timeout: delai) { try await port.certificat(contratId: id, context: context) }
        } catch {
            let erreur = Self.traduire(error)
            resultat.noter(erreur)
            if erreur.kind != .cancelled, erreur.kind != .unauthorized { resultat.erreurCertificat = erreur.message }
        }
        return resultat
    }

    /// Publie une relecture d'un seul tenant (contrat et certificat ensemble) si l'epoch n'a pas changé.
    private func publierSiEpoch(_ relu: Relecture) async {
        guard await controller.epoch == snapshot.epoch else { return }
        publier(relu)
    }

    private func publier(_ relu: Relecture) {
        if relu.sessionExpiree { sessionExpired = true }
        guard !relu.annulee, let contratRelu = relu.contrat else { return }
        contrat = contratRelu
        erreurRelecture = nil
        if let lignes = relu.signatures {
            signatures = lignes
            erreurCertificat = nil
        } else if let erreur = relu.erreurCertificat {
            erreurCertificat = erreur
        }
    }

    /// Admission relue après un envoi (`onOtpEnvoye` → `relireSmsRecette`, l.765) : budget et échéance du code ; le
    /// formulaire reste affiché, sans action possible, pendant la relecture (`actionsSuspendues`, l.761).
    private func relireAdmission(_ gateways: Gateways) async {
        let port = gateways.contrats
        let context = snapshot.context
        let id = contratId
        actionsSuspendues = true
        defer { actionsSuspendues = false }
        let recette = try? await bounded(timeout: controller.resolutionTimeout) {
            try await port.admissionRecette(contratId: id, context: context)
        }
        guard await controller.epoch == snapshot.epoch else { return }
        admission = recette.flatMap { $0 }
        session.reprendre(otpExpireLe: Self.otpCourant(admission), maintenant: gateways.clock.now())
    }

    /// Échéance du code relu (`otpCourantExpireA`, l.763-764) : seulement si la validation est ouverte.
    private static func otpCourant(_ admission: AdmissionSignatureRecette?) -> Date? {
        guard let admission, admission.peutValider else { return nil }
        return admission.otpExpireLe
    }

    private static func traduire(_ error: Error) -> JoleneError {
        if let jolene = error as? JoleneError { return jolene }
        if error is CancellationError { return JoleneError(.cancelled, "") }
        return JoleneError(.unknown, MessagesContrats.indisponible)
    }
}

/// Liste des contrats (onglet Contrats de Mes documents, « Mes contrats » du Profil ; écran T9a) : lecture bornée,
/// filtre local comme le web (`ListeContrats.tsx` l.93), filtre initial depuis `?statut=`.
@MainActor
public final class ContratsListeModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case charge([ContratResume])
        case echec(String)
    }

    @Published public private(set) var etat: Etat = .chargement
    @Published public private(set) var filtre: FiltreContrat
    @Published public private(set) var sessionExpired = false

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var derniereDemande = 0

    public init(controller: SessionController, snapshot: SessionSnapshot, filtreInitial: FiltreContrat = .tous) {
        self.controller = controller
        self.snapshot = snapshot
        self.filtre = filtreInitial
    }

    public var contrats: [ContratResume] {
        if case .charge(let contrats) = etat { return contrats }
        return []
    }

    /// Cartes du filtre courant, dans l'ordre serveur.
    public var affiches: [ContratResume] { ContratRules.filtrer(contrats, filtre: filtre) }

    public func choisir(_ nouveau: FiltreContrat) {
        filtre = nouveau
    }

    public func charger() async {
        derniereDemande += 1
        let demande = derniereDemande
        guard let gateways = await controller.gateways(for: snapshot.epoch), demande == derniereDemande, !Task.isCancelled else { return }
        let port = gateways.contrats
        let context = snapshot.context
        do {
            let liste = try await bounded(timeout: controller.resolutionTimeout) { try await port.contrats(context: context) }
            guard await controller.epoch == snapshot.epoch, demande == derniereDemande else { return }
            etat = .charge(liste)
        } catch {
            guard await controller.epoch == snapshot.epoch, demande == derniereDemande else { return }
            if error is CancellationError || (error as? JoleneError)?.kind == .cancelled { return }
            let erreur = (error as? JoleneError) ?? JoleneError(.unknown, MessagesContrats.indisponible)
            if erreur.kind == .unauthorized { sessionExpired = true }
            etat = .echec(erreur.message)
        }
    }
}
