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
/// OTP : la session décide si une requête part (une seule à la fois, `SessionSignatureOtp`) ; la gateway relit
/// avant d'annoncer une signature ; après une signature, le contrat et le certificat sont relus. Aucun renvoi
/// automatique, aucune file.
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

    public var signature: DisponibiliteSignature {
        guard let contrat, original != nil, ContratRules.zoneSignatureVisible(contrat) else { return .indisponible }
        return contrat.estCompteTest && admission == nil ? .renvoiWeb : .possible
    }

    /// `nouvelEnvoiAutorise` (`ContratMission.tsx` l.762) : compte réel, ou recette admise avec un envoi restant.
    public var nouvelEnvoiAutorise: Bool {
        guard let contrat else { return false }
        return !contrat.estCompteTest || admission?.peutEnvoyer == true
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

    /// « Recevoir le code SMS pour signer » : une seule requête, réponse ignorée si la clé a changé entre-temps.
    public func envoyerCode() async {
        guard let gateways = ports, let demande = session.demanderEnvoi(nouvelEnvoiAutorise: nouvelEnvoiAutorise) else { return }
        let port = gateways.contrats
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.envoyerOtp(contratId: demande.contratId, empreinte: demande.empreinte, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            session.terminerEnvoi(issue, demande: demande, maintenant: gateways.clock.now())
            if case .envoye = issue, contrat?.estCompteTest == true { await relireAdmission(gateways) }
        } catch {
            guard await controller.epoch == snapshot.epoch else { return }
            let erreur = Self.traduire(error)
            if erreur.kind == .unauthorized { sessionExpired = true }
            session.echouerEnvoi(message: erreur.kind == .cancelled ? nil : erreur.message, demande: demande)
        }
    }

    /// « Signer » : code de six chiffres et consentement exigés par la session ; succès relu par la gateway, puis
    /// contrat et certificat relus ici.
    public func signer() async {
        guard let gateways = ports, let demande = session.demanderSignature(maintenant: gateways.clock.now()),
              case .signature(let code) = demande.nature else { return }
        let port = gateways.contrats
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.signer(contratId: demande.contratId, code: code, empreinte: demande.empreinte, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            session.terminerSignature(issue, demande: demande)
            if case .signee = issue { await relireApresSignature(gateways) }
        } catch {
            guard await controller.epoch == snapshot.epoch else { return }
            let erreur = Self.traduire(error)
            if erreur.kind == .unauthorized { sessionExpired = true }
            session.echouerSignature(message: erreur.kind == .cancelled ? nil : erreur.message, demande: demande)
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

    private func relireApresSignature(_ gateways: Gateways) async {
        let port = gateways.contrats
        let context = snapshot.context
        let id = contratId
        let delai = controller.resolutionTimeout
        guard let relu = try? await bounded(timeout: delai, { try await port.contrat(id: id, context: context) }),
              await controller.epoch == snapshot.epoch else { return }
        contrat = relu
        guard ContratRules.certificatVisible(relu) else { return }
        do {
            let lignes = try await bounded(timeout: delai) { try await port.certificat(contratId: id, context: context) }
            guard await controller.epoch == snapshot.epoch else { return }
            signatures = lignes
            erreurCertificat = nil
        } catch {
            erreurCertificat = Self.traduire(error).message
        }
    }

    /// Admission relue après un envoi (`onOtpEnvoye` → `relireSmsRecette`, l.765) : budget et échéance du code.
    private func relireAdmission(_ gateways: Gateways) async {
        let port = gateways.contrats
        let context = snapshot.context
        let id = contratId
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
