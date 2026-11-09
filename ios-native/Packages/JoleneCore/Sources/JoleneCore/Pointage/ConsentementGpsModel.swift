import Combine
import Foundation

/// Consentement à la géolocalisation du soignant (blueprint lot 2 §3 T4b ; décisions 4 et 5, correction 15), partagé par
/// la page Présences (feuille du premier pointage, bandeau après un refus) et le Profil (retrait et réactivation). Aucun
/// texte ici : l'écran lit `TextesWeb.ConsentementGps`, `TextesWeb.BandeauSansGps`, `TextesWeb.ProfilConsentementGps` et
/// `TextesWeb.Presences` (HARD STOP n°4, textes de TL), par `LibellesPresences.Pointage.retourConsentement(_:)`.
///
/// Règles :
/// - lecture `soignants.consentement_gps` (`PointagePort.consentementGps`) ; NULL → feuille de consentement avant le
///   premier pointage (`decision == .recueillir`, décision 4 du blueprint). Ce n'est pas une parité : sur le web, seuls
///   `pointerArrivee` (`PresencesSoignant.tsx` l.306-313, feuille ouverte l.310-311) et `pointerDepart` (l.386) ouvrent
///   la feuille, et ni l'un ni l'autre n'est appelé ; le flux rotatif vivant (`PointageRotatifSoignant.tsx` l.123) ne la
///   présente jamais et pointe sans GPS tant que le consentement n'est pas vrai. Écart assumé (le natif recueille le
///   consentement que le web vivant ne demande pas), consigné au tableau des écarts T4b de `PARITE_SOIGNANT.md` (seconde
///   revue fraîche de T4b, m4) ;
/// - réponse à la feuille (`repondre`) : `fn_consentir_gps(p_accepte)` puis relecture (la valeur relue fait foi, jamais
///   l'hypothèse de l'écran), puis audit `RGPD_CONSENTEMENT_DONNE` best-effort, acceptation comme refus (web l.67-74,
///   l.87-94 ; détails `type: gps`, `consentement`, écrits en texte par `AuditPort`) ; l'autorisation iOS « Lorsque l'app
///   est active » n'est demandée qu'après un consentement relu vrai (décision 4) ; un refus ne bloque jamais le pointage
///   (`decision == .sansGps`) ; un échec de la RPC ne fait aucune hypothèse locale (la feuille reviendra) ;
/// - Profil (`basculer`, `SectionPreferences.tsx` l.137-163) : `fn_consentir_gps(actif)` puis relecture, sans audit
///   client (`GPS_CONSENTEMENT_ACTIVE` / `_RETIRE` absentes du CHECK `journaux_audit_action_check` : la trace serveur
///   `DONNEES_PERSO_MODIFICATION` de `fn_consentir_gps` suffit, correction 15) ;
/// - l'interrupteur du Profil n'est actif que pour un consentement relu VRAI : NULL (aucune réponse) s'affiche éteint, là
///   où le web l'affiche coché (`ProfilSoignant.tsx` l.194, `!== false`) — décision déléguée D-T4b-1 du 8 novembre 2026
///   (`DECISIONS_LOT2.md`, amendée par la revue fraîche de T4b, M2) : un consentement non donné n'est jamais présenté
///   comme donné, et l'activer depuis NULL présente d'abord la feuille verbatim (`feuilleRequise`, consentement éclairé :
///   finalité, durée de conservation, base légale), puis passe par `repondre` (RPC, relecture, audit
///   `RGPD_CONSENTEMENT_DONNE` du premier consentement) ; une bascule depuis NULL sans feuille (retrait) est auditée de même ;
/// - ligne du Profil (`ligneProfil`, revue fraîche de T4b, M3) : indicateur pendant la lecture, message du port et
///   « Réessayer » en échec, interrupteur seulement pour une valeur relue (jamais un consentement donné affiché retiré) ;
///   session expirée (401 à la lecture ou à la bascule) → « Session à vérifier » et « Vérifier ma session »
///   (`verifierSession` : session revalidée, puis relecture, jamais un rejeu de la bascule ; seconde revue fraîche de
///   T4b, m1), comme la zone de pointage (M1) ;
/// - une seule réponse à la fois : `enCours` est posé de façon synchrone, avant le premier `await` (revue fraîche de T4b,
///   m1, modèle de `PointageModel.envoiEnCours`) : un double toucher ne fait qu'un `fn_consentir_gps` et qu'un audit ;
///   pendant la demande, l'interrupteur montre le choix en vol (`valeurDemandee`), puis la valeur relue ;
/// - consentement illisible (lecture en échec) : pointage sans position, sans feuille (jamais un GPS supposé) ;
/// - réponse reçue pour un epoch quitté, à n'importe quelle étape : abandonnée (rien n'est rendu, envoyé ni publié ; revue
///   fraîche de T4b, m2).
@MainActor
public final class ConsentementGpsModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        /// Valeur relue : nil tant que le soignant n'a pas répondu.
        case lu(Bool?)
        /// Lecture en échec : message du port.
        case indisponible(String)
    }

    /// Conduite au moment d'un pointage.
    public enum Decision: Equatable, Sendable {
        /// Consentement NULL : feuille verbatim avant le pointage.
        case recueillir
        /// Consentement donné : position demandée (`LocalisationPointage.observer`).
        case localiser
        /// Refus, ou consentement illisible : pointage sans position.
        case sansGps
    }

    /// Retour affiché après une réponse ou une bascule (textes de `TextesWeb`, ou message du port).
    public enum Retour: Equatable, Sendable {
        /// « Consentement GPS enregistré. » (`PresencesSoignant.tsx` l.76).
        case enregistre
        /// « Pointage sans GPS activé — … » (l.95).
        case sansGps
        /// Bascule du Profil acceptée (`SectionPreferences.tsx` l.159-162).
        case bascule(actif: Bool)
        /// RPC en échec : message levé par le port, aucune hypothèse locale.
        case echec(String)
    }

    /// Ligne du Profil (revue fraîche de T4b, M3) : l'interrupteur n'existe que pour une valeur relue.
    public enum LigneProfil: Equatable, Sendable {
        /// Lecture en cours : indicateur.
        case chargement
        /// Lecture en échec : message du port et « Réessayer » (`charger()`).
        case indisponible(String)
        /// Interrupteur : choix en vol pendant une demande, sinon la valeur relue (NULL éteint, D-T4b-1).
        case interrupteur(actif: Bool)
        /// Session expirée (401) : bloc « Session à vérifier » du lot 1 et « Vérifier ma session » (`verifierSession`) ; un
        /// « Réessayer » ne réparerait rien (seconde revue fraîche de T4b, m1). L'emporte sur tout autre état.
        case sessionAVerifier
    }

    @Published public private(set) var etat: Etat = .chargement
    @Published public private(set) var enCours = false
    @Published public private(set) var retour: Retour?
    @Published public private(set) var sessionExpired = false
    /// Profil : activation demandée alors que le soignant n'a jamais répondu (NULL) ; la feuille verbatim doit être
    /// présentée, aucune RPC avant sa réponse (D-T4b-1 amendée, revue fraîche de T4b, M2).
    @Published public private(set) var feuilleRequise = false
    /// Choix en vol (bascule du Profil ou réponse à la feuille), affiché par l'interrupteur jusqu'à la relecture (m1).
    @Published public private(set) var valeurDemandee: Bool?

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    /// Seule la dernière lecture publie.
    private var generation = 0

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    public var valeur: Bool? {
        if case let .lu(valeur) = etat { return valeur }
        return nil
    }

    public var decision: Decision {
        switch etat {
        case .lu(nil): return .recueillir
        case .lu(true?): return .localiser
        case .lu(false?), .chargement, .indisponible: return .sansGps
        }
    }

    /// Bandeau « Pointage sans localisation activé » (`consentementGPS === false`, `PresencesSoignant.tsx` l.509).
    public var bandeauSansGps: Bool { etat == .lu(false) }

    /// Interrupteur du Profil : actif seulement pour un consentement relu vrai (NULL éteint, décision déléguée).
    public var interrupteurActif: Bool { etat == .lu(true) }

    public var ligneProfil: LigneProfil {
        if sessionExpired { return .sessionAVerifier }
        switch etat {
        case .chargement: return .chargement
        case let .indisponible(message): return .indisponible(message)
        case .lu: return .interrupteur(actif: valeurDemandee ?? interrupteurActif)
        }
    }

    /// Retour affiché sous la ligne du Profil : aucun pendant « Session à vérifier » (le bloc porte déjà le message).
    public var retourLigneProfil: Retour? {
        ligneProfil == .sessionAVerifier ? nil : retour
    }

    public func charger() async {
        generation += 1
        let courant = generation
        guard let x = await contexte(), generation == courant else { return }
        let port = x.port, context = snapshot.context
        do {
            let valeur = try await bounded(timeout: controller.resolutionTimeout) { try await port.consentementGps(context: context) }
            guard await estCourant(), generation == courant else { return }
            sessionExpired = false
            etat = .lu(valeur)
        } catch {
            guard await estCourant(), generation == courant, !Self.estAnnulation(error) else { return }
            sessionExpired = (error as? JoleneError)?.kind == .unauthorized
            etat = .indisponible(Self.message(error))
        }
    }

    /// Réponse à la feuille (premier pointage, ou première activation depuis le Profil). Rend la valeur relue, nil si rien
    /// n'a été enregistré ou si l'identité a changé en route (échec, epoch quitté, réponse déjà en cours : m1, m2). Après un
    /// consentement relu vrai, l'autorisation iOS est demandée (une fois, par `localisation`). Ferme la feuille du Profil.
    public func repondre(accepte: Bool, localisation: (any LocationPort)?) async -> Bool? {
        // Posé avant le premier `await` : un second toucher ne fait rien (m1).
        guard !enCours else { return nil }
        enCours = true
        valeurDemandee = accepte
        defer {
            enCours = false
            valeurDemandee = nil
            feuilleRequise = false
        }
        guard let relu = await enregistrer(accepte) else { return nil }
        await auditer(relu)
        guard await estCourant() else { return nil }
        retour = relu ? .enregistre : .sansGps
        if relu, let localisation, await localisation.autorisation() == .nonDeterminee {
            await localisation.demanderAutorisation()
        }
        guard await estCourant() else { return nil }
        return relu
    }

    /// Retrait (`false`) ou réactivation (`true`) depuis le Profil, sans audit client. Activer depuis NULL (aucune réponse)
    /// n'appelle rien : la feuille verbatim est demandée (`feuilleRequise`), sa réponse passe par `repondre` (M2). Une
    /// bascule depuis NULL qui n'est pas une activation est une première réponse : auditée comme elle.
    public func basculer(_ actif: Bool) async {
        guard !enCours else { return }
        let premiereReponse = etat == .lu(nil)
        if actif, premiereReponse {
            retour = nil
            feuilleRequise = true
            return
        }
        // Posé avant le premier `await` : une seconde bascule ne fait rien (m1).
        enCours = true
        valeurDemandee = actif
        defer {
            enCours = false
            valeurDemandee = nil
        }
        guard let relu = await enregistrer(actif) else { return }
        if premiereReponse { await auditer(relu) }
        guard await estCourant() else { return }
        retour = .bascule(actif: relu)
    }

    /// « Vérifier ma session » de la ligne du Profil (seconde revue fraîche de T4b, m1 ; règle de
    /// `PresencesModel.verifierSession`) : revalide la session (lot 1 ; une session révoquée ramène à la connexion, nouvel
    /// epoch, et la ligne est reconstruite), puis, si elle reste celle de ce modèle, reprend la lecture (`reprendreApresSession`).
    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await reprendreApresSession()
    }

    /// Après une revalidation de la session pour le même epoch (`verifierSession`, ou celle de la zone de pointage,
    /// `PointageModel.verifierSession`) : un consentement dont la lecture ou l'enregistrement avait expiré est relu, et le
    /// retour d'échec de cet enregistrement est levé (il ne décrit plus l'état). Rien n'est rejoué ; rien à faire sans
    /// session expirée.
    func reprendreApresSession() async {
        guard sessionExpired else { return }
        if case .echec? = retour { retour = nil }
        await charger()
    }

    /// Feuille du Profil fermée sans réponse : rien n'est enregistré.
    public func fermerFeuille() {
        guard !enCours else { return }
        feuilleRequise = false
    }

    public func oublierRetour() {
        retour = nil
    }

    // MARK: - Interne

    private struct Contexte {
        let port: any PointagePort
        let audit: any AuditPort
    }

    private func contexte() async -> Contexte? {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return nil }
        return Contexte(port: gateways.pointage, audit: gateways.audit)
    }

    /// `fn_consentir_gps` puis relecture ; publie la valeur relue, ou le message d'échec sans toucher à la valeur.
    /// `enCours` est tenu par l'appelant (`repondre`, `basculer`).
    private func enregistrer(_ accepte: Bool) async -> Bool? {
        retour = nil
        guard let x = await contexte(), await estCourant() else { return nil }
        let port = x.port, context = snapshot.context
        do {
            let relu = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.enregistrerConsentementGps(accepte, context: context)
            }
            guard await estCourant() else { return nil }
            generation += 1 // une lecture plus ancienne encore en vol ne publie plus
            sessionExpired = false
            etat = .lu(relu)
            return relu
        } catch {
            guard await estCourant(), !Self.estAnnulation(error) else { return nil }
            sessionExpired = (error as? JoleneError)?.kind == .unauthorized
            retour = .echec(Self.message(error))
            return nil
        }
    }

    /// Audit du web après la réponse à la feuille ; best-effort, toute erreur avalée (décision 5 du lot 1).
    private func auditer(_ consentement: Bool) async {
        guard let x = await contexte() else { return }
        let audit = x.audit, context = snapshot.context, userId = snapshot.context.userId
        _ = try? await bounded(timeout: controller.resolutionTimeout) {
            try await audit.ecrire(action: .rgpdConsentementDonne, typeRessource: "soignant", idRessource: userId,
                                   details: ["type": "gps", "consentement": consentement ? "true" : "false"], context: context)
        }
    }

    private func estCourant() async -> Bool {
        guard !Task.isCancelled else { return false }
        return await controller.epoch == snapshot.epoch
    }

    private static func estAnnulation(_ error: Error) -> Bool {
        error is CancellationError || (error as? JoleneError)?.kind == .cancelled
    }

    private static func message(_ error: Error) -> String {
        (error as? JoleneError)?.message ?? SessionController.timeoutMessage
    }
}

/// Position jointe à un pointage quand le consentement est donné (décisions 4 et 5) : autorisation iOS demandée si elle
/// n'est pas encore déterminée (consentement donné ici, sur le web ou depuis le Profil), refus iOS → `.refusee`, précision
/// réduite → `.precisionReduite` (aucune coordonnée, pas de `requestTemporaryFullAccuracyAuthorization`), sinon une
/// position unique bornée au délai du web. Ne lève jamais : toute issue sans coordonnée donne un scan sans GPS.
public enum LocalisationPointage {
    /// `timeout: 15000` du web (`src/lib/platform.ts` l.298).
    public static let delai: TimeInterval = LocationPolicy.delaiPosition

    public static func observer(_ localisation: any LocationPort) async -> ObservationGps {
        var autorisation = await localisation.autorisation()
        if autorisation == .nonDeterminee {
            await localisation.demanderAutorisation()
            autorisation = await localisation.autorisation()
        }
        switch autorisation {
        case .nonDeterminee, .refusee:
            return .refusee
        case .accordee(precise: false):
            return .precisionReduite
        case .accordee(precise: true):
            return await localisation.positionUnique(delai: delai)
        }
    }
}
