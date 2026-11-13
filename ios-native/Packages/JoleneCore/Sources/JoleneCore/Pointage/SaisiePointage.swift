import Combine
import Foundation

/// Session d'un scanner de QR (blueprint lot 2 §3 T4b, décision 3) : un code n'est remis qu'une fois par session, quel que
/// soit le nombre de détections (anti-rejeu serveur de 2 min, `public.sql` l.55710-55713 ; tests web
/// `PointageRotatifSoignant.qr.test.tsx`) ; un payload qui n'est pas exactement six chiffres après `trim`
/// (`PayloadQR.codePointage`) est signalé une fois, puis la caméra continue (la saisie manuelle reste disponible).
public struct SessionScanQR: Sendable {
    public enum Resultat: Equatable, Sendable {
        /// Premier code lisible : à envoyer, la session est close.
        case code(String)
        /// Nouveau payload illisible : « QR non reconnu… », caméra conservée.
        case illisible
        /// Détection sans effet (code déjà remis, payload illisible déjà signalé).
        case ignore
    }

    public private(set) var remis: String?
    private var illisibles: Set<String> = []

    public init() {}

    public mutating func recevoir(_ payload: String) -> Resultat {
        guard remis == nil else { return .ignore }
        if let code = PayloadQR.codePointage(depuis: payload) {
            remis = code
            return .code(code)
        }
        return illisibles.insert(payload).inserted ? .illisible : .ignore
    }
}

/// État du réseau suivi par la page Présences (`NetworkPathPort`, décision 2) : hors ligne, le bouton de pointage est
/// désactivé et le bandeau affiché ; aucun scan n'est mis en file. `nil` tant que le port n'a pas répondu (aucun bandeau
/// supposé ; `PointageModel` relit lui-même le réseau avant tout envoi).
@MainActor
public final class EtatReseauModel: ObservableObject {
    @Published public private(set) var enLigne: Bool?

    public init() {}

    public var horsLigne: Bool { enLigne == false }

    /// État courant puis chaque changement, jusqu'à la fin du flux ou l'annulation de la tâche (disparition de l'écran).
    public func suivre(_ port: any NetworkPathPort) async {
        enLigne = await port.estEnLigne()
        for await valeur in port.changements() {
            guard !Task.isCancelled else { return }
            enLigne = valeur
        }
    }
}

/// Contenu de la zone de pointage d'une mission (T4b ; revue fraîche de T4b, M1), dérivé du modèle du bloc et du
/// consentement de la page : la vue n'ajoute aucune règle. Une session expirée (au scan, pendant la réconciliation, à la
/// lecture de l'état ou du consentement) l'emporte sur tout autre état : bloc « Session à vérifier » du lot 1 et action
/// « Vérifier ma session » (`PointageModel.verifierSession`), jamais « Vérification du pointage… » sans fin ni un
/// « Réessayer » qui ne peut rien réparer (consigne T4b de `DECISIONS_LOT2.md` : « `sessionExpired` → écran de
/// reconnexion du lot 1 »).
public enum AffichageZonePointage: Equatable, Sendable {
    case sessionAVerifier
    case chargement
    /// `{error}` serveur verbatim ou message de transport, avec « Réessayer ».
    case indisponible(String)
    /// Statut de mission non pointable (`LibellesWeb.Pointage.statutIndisponible`).
    case statutIndisponible
    case saisie(EtatPointage)

    public init(chargement: PointageModel.Chargement, sessionExpiree: Bool) {
        if sessionExpiree {
            self = .sessionAVerifier
            return
        }
        switch chargement {
        case .chargement:
            self = .chargement
        case let .indisponible(message):
            self = .indisponible(message)
        case let .pret(etat):
            self = PointageRules.pointageDisponible(statut: etat.statut) ? .saisie(etat) : .statutIndisponible
        }
    }

    @MainActor
    public init(pointage: PointageModel, consentement: ConsentementGpsModel?) {
        self.init(chargement: pointage.chargement,
                  sessionExpiree: pointage.sessionExpired || consentement?.sessionExpired == true)
    }
}

extension PointageRules {
    /// Instantané des présences relu après un pointage enregistré (revue fraîche de T4a, m1) : le web invalide
    /// `presences-soignant` après chaque succès (`PointageRotatifSoignant.tsx` l.145-149) ; un scan relu sur une autre
    /// mission change le bloc de celle-ci (consigne T4b). Jamais après un refus ni pendant une vérification.
    public static func rechargerPresencesApres(_ issue: PointageModel.Issue) -> Bool {
        switch issue {
        case .enregistre, .enregistreSurAutreMission: return true
        case .refuse, .horsLigne, .verification, .nonRecu, .recuEnCours, .suiviIllisible, .erreur: return false
        }
    }
}
