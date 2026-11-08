import Foundation

extension DemoFixtures {
    /// `demo-preferences.json` (lot 3, T6) : corps de `fn_obtenir_mes_preferences_notifications` du profil
    /// fictif (`preferences`, défauts serveur + 3 exceptions) et sa ligne `soignants`
    /// (`sms_alertes_actives`, `type_exercice` du profil démo). Valeurs brutes (`ValeurJSON`) : décodées par
    /// la même règle stricte que la réponse Supabase (`PreferencesNotifications.decoder`).
    public struct PreferencesFile: Decodable, Sendable {
        public var fixedNow: String
        public var preferences: ValeurJSON
        public var soignant: ValeurJSON?

        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", preferences, soignant }
    }

    public static func loadPreferences() throws -> PreferencesFile { try load("demo-preferences") }
}

/// Préférences du compte démo : en mémoire, perdues au relancement, jamais envoyées. Chargées depuis la
/// fixture à la première lecture.
actor DemoPreferencesStore {
    private var courantes: PreferencesNotifications?

    func lire() throws -> PreferencesNotifications {
        if let courantes { return courantes }
        let fichier = try DemoFixtures.loadPreferences()
        let initiales = try PreferencesNotifications.decoder(preferences: fichier.preferences, soignant: fichier.soignant)
        courantes = initiales
        return initiales
    }

    /// Même sémantique que le serveur : canaux remplacés (`fn_modifier_preferences_notifications`, l.44111-44121),
    /// exceptions du catalogue mises à jour ou ajoutées par (type, canal), jamais supprimées (l.44124-44136) ;
    /// alerte SMS écrite seulement si elle est demandée et que la ligne existe (`PATCH soignants`).
    func enregistrer(_ demande: PreferencesNotifications) throws {
        var etat = try lire()
        for canal in CanalNotification.allCases {
            etat.definirCanalGlobal(canal, actif: demande.canalGlobalActif(canal))
        }
        for ligne in demande.parEvenementAEnvoyer {
            if let index = etat.parEvenement.firstIndex(where: { $0.typeEvenement == ligne.typeEvenement && $0.canal == ligne.canal }) {
                etat.parEvenement[index].actif = ligne.actif
            } else {
                etat.parEvenement.append(ligne)
            }
        }
        if let alerte = demande.smsAlertesActives, etat.smsAlertesActives != nil {
            etat.smsAlertesActives = alerte
        }
        courantes = etat
    }
}

/// Préférences de notifications du monde démo (blueprint lot 3 §2.7) : aucun réseau, enregistrement
/// réellement consigné dans l'acteur puis relu (aucun succès fabriqué). Comme les autres gateways démo,
/// refuse tout contexte qui n'est pas celui du profil fictif.
public struct DemoPreferencesGateway: NotificationPreferencesPort {
    private let store = DemoPreferencesStore()

    public init() {}

    public func lire(context: MissionReadContext) async throws -> PreferencesNotifications {
        try Self.verifier(context)
        return try await store.lire()
    }

    public func enregistrer(_ preferences: PreferencesNotifications,
                            context: MissionReadContext) async throws -> PreferencesNotifications {
        try Self.verifier(context)
        try await store.enregistrer(preferences)
        // Relecture après mutation.
        return try await store.lire()
    }

    static func verifier(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}

/// Préférences démo en échec forcé, pour la recette de l'état d'erreur dans l'interface
/// (`DemoPreferencesTests.testPreferencesErreurPuisReprise`) : installé seulement par la surcharge DEBUG
/// `JOLENE_FORCE_PREFERENCES_ECHEC` de `AppContainer`, jamais en Release. Les `echecs` premières lectures
/// non annulées échouent comme un délai dépassé (`SessionController.timeoutMessage`) ; la suite délègue au
/// port démo. Même refus que le port démo pour tout autre utilisateur.
public actor DemoPreferencesEchecGateway: NotificationPreferencesPort {
    private let relais: DemoPreferencesGateway
    private var echecsRestants: Int

    public init(echecs: Int = 1, relais: DemoPreferencesGateway = DemoPreferencesGateway()) {
        self.echecsRestants = max(0, echecs)
        self.relais = relais
    }

    public func lire(context: MissionReadContext) async throws -> PreferencesNotifications {
        try DemoPreferencesGateway.verifier(context)
        try Task.checkCancellation()
        if echecsRestants > 0 {
            echecsRestants -= 1
            throw JoleneError(.network, SessionController.timeoutMessage)
        }
        return try await relais.lire(context: context)
    }

    public func enregistrer(_ preferences: PreferencesNotifications,
                            context: MissionReadContext) async throws -> PreferencesNotifications {
        try await relais.enregistrer(preferences, context: context)
    }
}
