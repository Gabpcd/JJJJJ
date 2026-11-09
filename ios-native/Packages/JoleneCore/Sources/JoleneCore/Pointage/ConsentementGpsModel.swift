import Combine
import Foundation

/// Consentement à la géolocalisation du soignant (blueprint lot 2 §3 T4b ; décisions 4 et 5, correction 15), partagé par
/// la page Présences (feuille du premier pointage, bandeau après un refus) et le Profil (retrait et réactivation). Aucun
/// texte ici : l'écran lit `TextesWeb.ConsentementGps`, `TextesWeb.BandeauSansGps`, `TextesWeb.ProfilConsentementGps` et
/// `TextesWeb.Presences` (HARD STOP n°4, textes de TL), par `LibellesPresences.Pointage.retourConsentement(_:)`.
///
/// Règles :
/// - lecture `soignants.consentement_gps` (`PointagePort.consentementGps`) ; NULL → feuille de consentement avant le
///   premier pointage (`decision == .recueillir`, parité `PresencesSoignant.tsx` l.310-311) ;
/// - réponse à la feuille (`repondre`) : `fn_consentir_gps(p_accepte)` puis relecture (la valeur relue fait foi, jamais
///   l'hypothèse de l'écran), puis audit `RGPD_CONSENTEMENT_DONNE` best-effort, acceptation comme refus (web l.67-74,
///   l.87-94 ; détails `type: gps`, `consentement`, écrits en texte par `AuditPort`) ; l'autorisation iOS « Lorsque l'app
///   est active » n'est demandée qu'après un consentement relu vrai (décision 4) ; un refus ne bloque jamais le pointage
///   (`decision == .sansGps`) ; un échec de la RPC ne fait aucune hypothèse locale (la feuille reviendra) ;
/// - Profil (`basculer`, `SectionPreferences.tsx` l.137-163) : `fn_consentir_gps(actif)` puis relecture, sans audit
///   client (`GPS_CONSENTEMENT_ACTIVE` / `_RETIRE` absentes du CHECK `journaux_audit_action_check` : la trace serveur
///   `DONNEES_PERSO_MODIFICATION` de `fn_consentir_gps` suffit, correction 15) ;
/// - l'interrupteur du Profil n'est actif que pour un consentement relu VRAI : NULL (aucune réponse) s'affiche éteint, là
///   où le web l'affiche coché (`ProfilSoignant.tsx` l.194, `!== false`) — décision déléguée du 8 novembre 2026
///   (`DECISIONS_LOT2.md`) : un consentement non donné n'est jamais présenté comme donné ;
/// - consentement illisible (lecture en échec) : pointage sans position, sans feuille (jamais un GPS supposé) ;
/// - réponse reçue pour un epoch quitté : abandonnée (rien n'est envoyé ni publié).
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

    @Published public private(set) var etat: Etat = .chargement
    @Published public private(set) var enCours = false
    @Published public private(set) var retour: Retour?
    @Published public private(set) var sessionExpired = false

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

    /// Réponse à la feuille du premier pointage. Rend la valeur relue, nil si rien n'a été enregistré (échec, epoch quitté,
    /// réponse déjà en cours). Après un consentement relu vrai, l'autorisation iOS est demandée (une fois, par `localisation`).
    public func repondre(accepte: Bool, localisation: any LocationPort) async -> Bool? {
        guard !enCours, let relu = await enregistrer(accepte) else { return nil }
        await auditer(relu)
        guard await estCourant() else { return relu }
        retour = relu ? .enregistre : .sansGps
        if relu, await localisation.autorisation() == .nonDeterminee {
            await localisation.demanderAutorisation()
        }
        return relu
    }

    /// Retrait (`false`) ou réactivation (`true`) depuis le Profil, sans audit client.
    public func basculer(_ actif: Bool) async {
        guard !enCours, let relu = await enregistrer(actif), await estCourant() else { return }
        retour = .bascule(actif: relu)
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
    private func enregistrer(_ accepte: Bool) async -> Bool? {
        guard let x = await contexte(), await estCourant() else { return nil }
        enCours = true
        defer { enCours = false }
        retour = nil
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
