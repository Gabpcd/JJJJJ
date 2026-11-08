import Foundation

/// Autorisation des notifications du monde démo (blueprint §2.7) : aucune feuille système. État initial
/// `nonDemandee` (appareil neuf) ou celui de `-JOLENE_PUSH_AUTORISATION` (DEBUG, `PushLancement`).
/// `demander()` simule l'acceptation d'une première demande ; un refus n'est jamais renversé (comme iOS).
/// Réutilisé en DEBUG STAGING (`-JOLENE_PUSH_TOKEN_FACTICE`) avec l'état `accordee`.
public actor DemoPushPermission: PushPermissionPort {
    private var courant: AutorisationPush

    public init(etat: AutorisationPush = .nonDemandee) {
        courant = etat
    }

    public func etat() async -> AutorisationPush { courant }

    public func demander() async throws -> Bool {
        if courant == .nonDemandee { courant = .accordee }
        return courant.permetEnregistrement
    }
}

/// Enregistrement APNs du monde démo : token fixe de 32 octets (`tokenDemo`, 64 caractères
/// hexadécimaux), compteurs d'appels. Réutilisé en DEBUG STAGING avec le token factice de la preuve T16.
public actor DemoPushRegistrar: PushRegistrarPort {
    /// Octets 0x00…0x1f : calculés, jamais un littéral qui ressemblerait à un secret.
    public static let tokenDemo = Data((0..<32).map { UInt8($0) })

    private let token: Data
    public private(set) var enregistrements = 0
    public private(set) var desinscriptions = 0

    public init(token: Data = DemoPushRegistrar.tokenDemo) {
        self.token = token
    }

    public func enregistrer() async throws -> Data {
        enregistrements += 1
        return token
    }

    public func desinscrire() async {
        desinscriptions += 1
    }
}
