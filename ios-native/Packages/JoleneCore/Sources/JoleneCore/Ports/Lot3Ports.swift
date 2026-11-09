import Foundation

// Ports du lot 3 (blueprint `docs/mobile-swift/LOT3_PLAN.md` §2.3, tranche T1). Tous `Sendable`
// (concurrence stricte). Mêmes règles qu'au lot 1 (`Lot1Ports.swift`) : chaque méthode d'un port
// utilisateur reçoit le `MissionReadContext` de l'epoch courant ; une mutation n'annonce un succès
// qu'après relecture serveur (PRINCIPES §3) ; refus métier = issues de `Models/Lot3Results.swift`,
// erreurs de transport = `JoleneError`. Les treize ports backend sont des champs du bloc « Lot 3 »
// de `Gateways` ; les quatre capacités système (fin de fichier) sont injectées par `AppContainer`,
// avec des doubles en démo et en test. La localisation ponctuelle n'a pas de port au lot 3 : elle
// réutilise `LocationPort` du lot 2 (`Ports/AppareilPorts.swift`, L2-T1), sans variante.

// MARK: - Ports backend (bloc « Lot 3 » de `Gateways`)

/// Enregistrement du token APNs (`fn_upsert_token_push`, `void`) et désactivation à la déconnexion
/// volontaire (`fn_desactiver_mon_token_push`, bornée à 2,5 s par l'appelant, D3) — tranche T4.
public protocol PushRegistrationPort: Sendable {
    /// `token` : hexadécimal minuscule, `p_plateforme = 'IOS'`. Best-effort côté appelant : un
    /// échec n'entraîne jamais de déconnexion.
    func enregistrer(token: String, context: MissionReadContext) async throws
    func desactiver(token: String) async throws -> IssueDesactivationPush
}

/// Centre de notifications (`notifications`, 200 dernières, marquer lue) — tranche T5.
public protocol NotificationsCenterPort: Sendable {
    func liste(context: MissionReadContext) async throws -> [NotificationJolene]
    /// Rend la ligne relue (`lue == true`), jamais une mise à jour locale supposée.
    func marquerLue(id: String, context: MissionReadContext) async throws -> NotificationJolene
}

/// Préférences de notifications (`fn_obtenir_mes_preferences_notifications`,
/// `fn_modifier_preferences_notifications`, `soignants.sms_alertes_actives`) — tranche T6.
public protocol NotificationPreferencesPort: Sendable {
    func lire(context: MissionReadContext) async throws -> PreferencesNotifications
    /// N'envoie que les types du catalogue soignant ; rend les préférences relues après `{success:true}`.
    /// Alerte SMS : `preferences.smsAlertesActives` est sa seule source (État dérivé, aucun second
    /// paramètre qui pourrait diverger) ; non nil → `soignants.sms_alertes_actives` écrit puis relu,
    /// nil → colonne non écrite (parité web `profilSmsPresent`, `PageParametresNotifications.tsx` l.230).
    func enregistrer(_ preferences: PreferencesNotifications,
                     context: MissionReadContext) async throws -> PreferencesNotifications
}

/// Inscription soignant : compte rapide et confirmation (T7), complétion et `register-soignant`
/// (T8). Hors contexte d'epoch : l'utilisateur n'a pas encore de profil soignant.
public protocol InscriptionPort: Sendable {
    func creerCompte(email: String, motDePasse: String, intention: IntentionInscription) async throws -> ResultatCompte
    func confirmer(_ credentials: AuthCallbackCredentials) async throws -> ResultatConfirmation
    func contexte() async throws -> ContexteOnboarding?
    func parcours(userId: String) async throws -> ParcoursInscription?
    func demarrer(intention: IntentionInscription) async throws -> ParcoursInscription
    func enregistrerBrouillon(_ brouillon: FormulaireInscription) async throws -> ParcoursInscription
    /// Contrats autorisés pour la profession (`fn_types_exercice_autorises`, table paramétrée) ; nil = référentiel indisponible.
    func typesExercice(profession: String) async throws -> [String]?
    func finaliser(_ formulaire: FormulaireInscription) async throws -> ResultatFinalisation
    /// Vrai quand la complétion (brouillon, modes d'exercice, finalisation) est livrée (T8). Faux tant que ces trois
    /// appels refusent explicitement (verrou du gap T8, `DemoInscriptionGateway`, `SupabaseInscriptionGateway`, stub
    /// non câblé) : l'édition du profil (T9) tient alors les modes d'exercice pour non câblés, sans « Réessayer la
    /// vérification » (jamais un bouton sans effet ; intégration du lot 3, T7 × T9).
    var completionLivree: Bool { get }
}

extension InscriptionPort {
    /// Par défaut, un port qui sert ses appels déclare la complétion livrée ; seuls les ports dont la complétion
    /// refuse encore (T7 avant T8) le contredisent.
    public var completionLivree: Bool { true }
}

/// Profil soignant (`fn_mon_profil_soignant_complet` en liste blanche, `fn_modifier_mon_profil`) — tranche T9.
public protocol ProfilPort: Sendable {
    func profil(context: MissionReadContext) async throws -> ProfilComplet
    /// Rend le profil relu après `{success:true}`.
    func modifier(_ champs: ModificationProfil, context: MissionReadContext) async throws -> ProfilComplet
}

/// Avatar (`jolene-documents/<uid>/avatar-<ts>.jpg`, reçu durable avant l'envoi) — tranche T10.
public protocol AvatarStoragePort: Sendable {
    /// Rend l'URL relue dans `avatar_url` après `fn_modifier_mon_profil(p_avatar_url:)`.
    func televerser(jpeg: Data, context: MissionReadContext) async throws -> URL
}

/// Géocodage inverse best-effort (`api-adresse.data.gouv.fr`, D15) — tranche T10.
public protocol GeocodagePort: Sendable {
    func adresse(lat: Double, lng: Double) async throws -> AdresseGeocodee?
}

/// Changement de mot de passe (ancien vérifié, D13) — tranche T11.
///
/// `identiteCourante` (revue B8 de T11, m2) : garde consultée UNE fois, après la vérification de l'ancien mot de
/// passe et avant la mise à jour. Fausse (l'identité de l'écran est partie : révocation, refresh refusé), aucune
/// mise à jour ne part, la session que la vérification a pu recréer est retirée, et l'appel lève `.cancelled`.
public protocol MotDePassePort: Sendable {
    func changer(ancien: String, nouveau: String, context: MissionReadContext,
                 identiteCourante: @escaping @Sendable () async -> Bool) async throws -> ResultatMotDePasse
}

public extension MotDePassePort {
    /// Sans garde (doubles et tests des ports) : l'identité est tenue pour courante.
    func changer(ancien: String, nouveau: String, context: MissionReadContext) async throws -> ResultatMotDePasse {
        try await changer(ancien: ancien, nouveau: nouveau, context: context, identiteCourante: { true })
    }
}

/// Export RGPD (`fn_rgpd_exporter_rate_limited`) — tranche T11. Un refus `{error}` est levé avec
/// le message serveur verbatim ; aucun fichier n'est écrit.
public protocol ExportRGPDPort: Sendable {
    func exporter(context: MissionReadContext) async throws -> ExportDonneesRGPD
}

/// Revenus en lecture (`fn_mes_revenus_connect`, `fn_mes_paiements_escrow`, missions TERMINEE) — tranche T12.
public protocol RevenusPort: Sendable {
    /// Totaux serveur ; `nil` = section sans objet, là où le web ne rend pas les cartes (`PageStripeConnect.tsx` l.178,
    /// l.300, l.302, l.367 : ni `LIBERAL` ni `MIXTE`, compte de test, compte Connect non complet ;
    /// `ExerciceRevenus.afficheTotaux`, `TotauxRevenus.visibles`), jamais un défaut à zéro.
    func totaux(context: MissionReadContext) async throws -> TotauxRevenus?
    func paiementsRapides(context: MissionReadContext) async throws -> [PaiementRapide]
    func missionsTerminees(context: MissionReadContext, page: Int) async throws -> PageMissionsTerminees
}

/// Paiements déclarés (`fn_confirmer_paiement_soignant`, `fn_contester_paiement_soignant` après B3) — tranche T13.
public protocol PaiementsDeclaresPort: Sendable {
    func aConfirmer(context: MissionReadContext) async throws -> [PaiementDeclare]
    func confirmer(id: String, context: MissionReadContext) async throws -> IssuePaiement
    func contester(id: String, motif: String, context: MissionReadContext) async throws -> IssuePaiement
}

/// IBAN (`fn_consulter_mon_iban`, `fn_enregistrer_mon_iban`) — tranche T14b.
public protocol IbanPort: Sendable {
    func consulter(context: MissionReadContext) async throws -> ConsultationIban
    func enregistrer(iban: String, titulaire: String, context: MissionReadContext) async throws -> ResultatIban
}

/// Stripe Connect (`stripe-connect-status`, `stripe-connect-onboard`) — tranche T14a.
public protocol StripeConnectPort: Sendable {
    /// `force` : contourne le cache serveur de 5 min (`?force=true`) au retour de Stripe et sur « Actualiser ».
    func statut(force: Bool, context: MissionReadContext) async throws -> StatutConnect
    func lienOnboarding(context: MissionReadContext) async throws -> ResultatLienConnect
}

// MARK: - Capacités système (hors `Gateways`, injectées par `AppContainer`)

/// Autorisation des notifications (`UNUserNotificationCenter`) — T4, T5. `demander()` n'est jamais
/// appelé sans tap de l'utilisateur (D1).
public protocol PushPermissionPort: Sendable {
    func etat() async -> AutorisationPush
    func demander() async throws -> Bool
}

/// Enregistrement APNs de l'appareil (`UIApplication.registerForRemoteNotifications`) — T4.
public protocol PushRegistrarPort: Sendable {
    /// Token APNs brut (démo : token fixe).
    func enregistrer() async throws -> Data
    func desinscrire() async
}

/// Flux hébergé (Stripe Connect) : `ASWebAuthenticationSession` dès iOS 17.4, `SFSafariViewController`
/// en dessous (D7) — T14a.
public protocol ExternalFlowPort: Sendable {
    func ouvrir(url: URL, retour: RetourAttendu) async -> IssueFlux
}

/// Rapport de crash (Sentry, cible app seulement ; jamais initialisé en démo) — T15.
public protocol CrashReportingPort: Sendable {
    func demarrer(environnement: JoleneMode, release: String)
    /// Identifiant seul (aucune autre donnée personnelle) ; nil à la déconnexion.
    func utilisateur(id: String?)
}

// MARK: - Ports « non câblés » du lot 3

private enum Lot3 {
    static func erreur(_ port: String, _ tranche: String) -> JoleneError {
        UnwiredPorts.erreur(port: port, tranche: tranche, lot: 3)
    }
}

public struct UnwiredPushRegistrationPort: PushRegistrationPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot3.erreur("push", "T4") }
    public func enregistrer(token: String, context: MissionReadContext) async throws { throw erreur }
    public func desactiver(token: String) async throws -> IssueDesactivationPush { throw erreur }
}

public struct UnwiredNotificationsCenterPort: NotificationsCenterPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot3.erreur("centre de notifications", "T5") }
    public func liste(context: MissionReadContext) async throws -> [NotificationJolene] { throw erreur }
    public func marquerLue(id: String, context: MissionReadContext) async throws -> NotificationJolene { throw erreur }
}

public struct UnwiredNotificationPreferencesPort: NotificationPreferencesPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot3.erreur("préférences de notifications", "T6") }
    public func lire(context: MissionReadContext) async throws -> PreferencesNotifications { throw erreur }
    public func enregistrer(_ preferences: PreferencesNotifications,
                            context: MissionReadContext) async throws -> PreferencesNotifications { throw erreur }
}

public struct UnwiredInscriptionPort: InscriptionPort, UnwiredPort {
    public init() {}
    public var completionLivree: Bool { false }
    private var compte: JoleneError { Lot3.erreur("inscription", "T7") }
    private var completion: JoleneError { Lot3.erreur("complétion de l'inscription", "T8") }
    public func creerCompte(email: String, motDePasse: String, intention: IntentionInscription) async throws -> ResultatCompte {
        throw compte
    }
    public func confirmer(_ credentials: AuthCallbackCredentials) async throws -> ResultatConfirmation { throw compte }
    public func contexte() async throws -> ContexteOnboarding? { throw compte }
    public func parcours(userId: String) async throws -> ParcoursInscription? { throw compte }
    public func demarrer(intention: IntentionInscription) async throws -> ParcoursInscription { throw compte }
    public func enregistrerBrouillon(_ brouillon: FormulaireInscription) async throws -> ParcoursInscription { throw completion }
    public func typesExercice(profession: String) async throws -> [String]? { throw completion }
    public func finaliser(_ formulaire: FormulaireInscription) async throws -> ResultatFinalisation { throw completion }
}

public struct UnwiredProfilPort: ProfilPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot3.erreur("profil", "T9") }
    public func profil(context: MissionReadContext) async throws -> ProfilComplet { throw erreur }
    public func modifier(_ champs: ModificationProfil, context: MissionReadContext) async throws -> ProfilComplet { throw erreur }
}

public struct UnwiredAvatarStoragePort: AvatarStoragePort, UnwiredPort {
    public init() {}
    public func televerser(jpeg: Data, context: MissionReadContext) async throws -> URL { throw Lot3.erreur("avatar", "T10") }
}

public struct UnwiredGeocodagePort: GeocodagePort, UnwiredPort {
    public init() {}
    public func adresse(lat: Double, lng: Double) async throws -> AdresseGeocodee? { throw Lot3.erreur("géocodage", "T10") }
}

public struct UnwiredMotDePassePort: MotDePassePort, UnwiredPort {
    public init() {}
    public func changer(ancien: String, nouveau: String, context: MissionReadContext,
                        identiteCourante: @escaping @Sendable () async -> Bool) async throws -> ResultatMotDePasse {
        throw Lot3.erreur("mot de passe", "T11")
    }
}

public struct UnwiredExportRGPDPort: ExportRGPDPort, UnwiredPort {
    public init() {}
    public func exporter(context: MissionReadContext) async throws -> ExportDonneesRGPD { throw Lot3.erreur("export RGPD", "T11") }
}

public struct UnwiredRevenusPort: RevenusPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot3.erreur("revenus", "T12") }
    public func totaux(context: MissionReadContext) async throws -> TotauxRevenus? { throw erreur }
    public func paiementsRapides(context: MissionReadContext) async throws -> [PaiementRapide] { throw erreur }
    public func missionsTerminees(context: MissionReadContext, page: Int) async throws -> PageMissionsTerminees { throw erreur }
}

public struct UnwiredPaiementsDeclaresPort: PaiementsDeclaresPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot3.erreur("paiements déclarés", "T13") }
    public func aConfirmer(context: MissionReadContext) async throws -> [PaiementDeclare] { throw erreur }
    public func confirmer(id: String, context: MissionReadContext) async throws -> IssuePaiement { throw erreur }
    public func contester(id: String, motif: String, context: MissionReadContext) async throws -> IssuePaiement { throw erreur }
}

public struct UnwiredIbanPort: IbanPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot3.erreur("IBAN", "T14b") }
    public func consulter(context: MissionReadContext) async throws -> ConsultationIban { throw erreur }
    public func enregistrer(iban: String, titulaire: String, context: MissionReadContext) async throws -> ResultatIban {
        throw erreur
    }
}

public struct UnwiredStripeConnectPort: StripeConnectPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot3.erreur("Stripe Connect", "T14a") }
    public func statut(force: Bool, context: MissionReadContext) async throws -> StatutConnect { throw erreur }
    public func lienOnboarding(context: MissionReadContext) async throws -> ResultatLienConnect { throw erreur }
}
