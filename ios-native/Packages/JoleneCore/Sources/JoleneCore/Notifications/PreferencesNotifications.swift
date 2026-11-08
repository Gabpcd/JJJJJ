import Foundation

// Préférences de notifications du soignant (lot 3, T6 ; blueprint `docs/mobile-swift/LOT3_PLAN.md` §3 T6),
// port de `src/pages/PageParametresNotifications.tsx`. Contrat d'échange posé par T1 dans
// `Models/Lot3Results.swift`, déplacé ici avec ses règles (même module, mêmes noms) :
// - catalogue `EVENTS_SOIGNANT` verbatim (l.42-56) et filtre de régime sur `soignants.type_exercice` (l.79-84) ;
// - absence de ligne `par_evenement` = actif (l.194-197), bascule = ligne explicite inversée (l.199-204) ;
// - canal global coupé → case grisée et clic ignoré (l.396-410) ;
// - décodage strict de la réponse (l.117) et de la ligne `soignants` (l.120-131) : jamais de défaut affiché ;
// - seuls les types du catalogue soignant partent vers `fn_modifier_preferences_notifications` (22P02 sinon).
// Préférence, pas un consentement juridique (D18) ; textes verbatim du web (`PreferencesTextes`, HARD STOP n°4).

// MARK: - Contrat d'échange

/// Enum SQL `canal_notification` (`public.sql` l.22-27).
public enum CanalNotification: String, CaseIterable, Sendable {
    case email = "EMAIL"
    case sms = "SMS"
    case push = "PUSH"
    case inApp = "IN_APP"
}

/// Exception par événement (`par_evenement[]` de `fn_obtenir_mes_preferences_notifications`).
public struct PreferenceEvenement: Equatable, Sendable {
    public var typeEvenement: String
    public var canal: CanalNotification
    public var actif: Bool

    public init(typeEvenement: String, canal: CanalNotification, actif: Bool) {
        self.typeEvenement = typeEvenement; self.canal = canal; self.actif = actif
    }
}

/// Préférences relues : les quatre canaux globaux sont exigés (jamais de défaut affiché) ;
/// `smsAlertesActives` vient de `soignants.sms_alertes_actives`, écrit à part de la RPC ; nil =
/// ligne `soignants` non lue (web `profilSmsPresent` faux : alerte ni affichée ni écrite). Seule
/// source de l'alerte SMS pour `NotificationPreferencesPort.enregistrer(_:context:)`.
/// `typeExercice` : `soignants.type_exercice`, relu dans la même requête que l'alerte (web l.122),
/// seule source du filtre de régime ; jamais écrit.
public struct PreferencesNotifications: Equatable, Sendable {
    public var canalEmail: Bool
    public var canalSms: Bool
    public var canalPush: Bool
    public var canalInApp: Bool
    public var parEvenement: [PreferenceEvenement]
    public var smsAlertesActives: Bool?
    public var typeExercice: String?

    public init(canalEmail: Bool, canalSms: Bool, canalPush: Bool, canalInApp: Bool,
                parEvenement: [PreferenceEvenement], smsAlertesActives: Bool? = nil, typeExercice: String? = nil) {
        self.canalEmail = canalEmail; self.canalSms = canalSms; self.canalPush = canalPush; self.canalInApp = canalInApp
        self.parEvenement = parEvenement; self.smsAlertesActives = smsAlertesActives; self.typeExercice = typeExercice
    }
}

// MARK: - Catalogue soignant

/// Régime d'un événement (`EventDef.regime`, l.39) : un soignant purement libéral ne voit jamais un
/// événement salarié, et inversement ; MIXTE ou régime inconnu voit tout.
public enum RegimeEvenement: String, CaseIterable, Sendable {
    case salarie = "SALARIE"
    case liberal = "LIBERAL"
}

/// Ligne du catalogue (`EventDef`, l.32-40).
public struct EvenementNotification: Equatable, Sendable, Identifiable {
    public let type: String
    public let libelle: String
    public let description: String
    public let canaux: [CanalNotification]
    public let regime: RegimeEvenement?

    public var id: String { type }

    public init(type: String, libelle: String, description: String, canaux: [CanalNotification], regime: RegimeEvenement? = nil) {
        self.type = type; self.libelle = libelle; self.description = description; self.canaux = canaux; self.regime = regime
    }
}

/// `EVENTS_SOIGNANT` (`PageParametresNotifications.tsx` l.42-56), verbatim et dans l'ordre (garde :
/// `PreferencesNotificationsTests.testCatalogueIdentiqueAEventsSoignantDuWeb` relit le fichier web).
/// Le catalogue établissement (`EVENTS_ETAB`) n'est pas porté : l'app ne sert que le soignant.
public enum CatalogueNotificationsSoignant {
    public static let evenements: [EvenementNotification] = [
        EvenementNotification(type: "NOUVELLE_MISSION_MATCHANT_FILTRE", libelle: "Nouvelles missions matchant mes filtres",
                              description: "Alertes sur les missions correspondant à mes recherches sauvegardées", canaux: [.email, .push]),
        EvenementNotification(type: "CANDIDATURE_ACCEPTEE", libelle: "Ma candidature est acceptée",
                              description: "Confirmation d'assignation à une mission", canaux: [.email, .push, .sms]),
        EvenementNotification(type: "MISSION_ASSIGNEE", libelle: "Proposition de mission directe",
                              description: "Quand un établissement me propose directement une mission", canaux: [.email, .push]),
        EvenementNotification(type: "RAPPEL_J1_MISSION", libelle: "Rappel mission J-1",
                              description: "Rappel la veille du début de mission", canaux: [.email, .push, .sms]),
        EvenementNotification(type: "POINTAGE_MANQUANT", libelle: "Pointage manquant",
                              description: "Si j'ai oublié de pointer mon départ", canaux: [.email, .push]),
        EvenementNotification(type: "FACTURE_EMISE", libelle: "Facture émise",
                              description: "Quand Jolene émet une nouvelle facture en mon nom", canaux: [.email, .push], regime: .liberal),
        EvenementNotification(type: "PAIEMENT_RECU", libelle: "Paiement reçu",
                              description: "Quand un établissement règle ma facture", canaux: [.email, .push], regime: .liberal),
        EvenementNotification(type: "CONTRAT_TRAVAIL_DEPOSE", libelle: "Contrat de travail SALARIE déposé",
                              description: "Quand mon établissement upload mon contrat CDD", canaux: [.email, .push], regime: .salarie),
        EvenementNotification(type: "LITIGE_OUVERT", libelle: "Litige ouvert",
                              description: "Notifications sur les litiges en cours", canaux: [.email, .push, .sms]),
        EvenementNotification(type: "LITIGE_RESOLU", libelle: "Litige résolu",
                              description: "Quand un litige a été clos", canaux: [.email, .push]),
        EvenementNotification(type: "DOCUMENT_EXPIRANT", libelle: "Document expirant bientôt",
                              description: "RCP, diplôme ou autre document arrivant à expiration", canaux: [.email, .push]),
        EvenementNotification(type: "MANDAT_RE_SIGNATURE", libelle: "Re-signature du mandat de facturation",
                              description: "Si une nouvelle version du mandat est publiée", canaux: [.email, .push], regime: .liberal),
        EvenementNotification(type: "SERIE_ONBOARDING", libelle: "Série emails de bienvenue (J0-J7)",
                              description: "Séquence d'emails d'accueil pendant la première semaine", canaux: [.email]),
    ]

    /// Colonnes de la matrice (`['EMAIL','PUSH','SMS']`, l.383-385 et l.395) : In-app n'a qu'un canal global.
    public static let colonnes: [CanalNotification] = [.email, .push, .sms]

    public static func evenement(type: String) -> EvenementNotification? {
        evenements.first { $0.type == type }
    }

    /// Filtre de régime du web (l.79-84), comparaison stricte : `LIBERAL` masque le salarié, `SALARIE` masque
    /// le libéral, toute autre valeur (MIXTE, inconnue, absente) affiche tout.
    public static func visibles(typeExercice: String?) -> [EvenementNotification] {
        switch typeExercice {
        case RegimeEvenement.liberal.rawValue: return evenements.filter { $0.regime != .salarie }
        case RegimeEvenement.salarie.rawValue: return evenements.filter { $0.regime != .liberal }
        default: return evenements
        }
    }
}

/// Concordance de la relecture avec la demande : `generales` (quatre canaux et chaque exception envoyée),
/// `alerteSms` (colonne `sms_alertes_actives`, si elle a été demandée). Seule preuve d'un enregistrement.
public struct ConcordancePreferences: Equatable, Sendable {
    public var generales: Bool
    public var alerteSms: Bool

    public init(generales: Bool, alerteSms: Bool) { self.generales = generales; self.alerteSms = alerteSms }
}

// MARK: - Règles

public extension PreferencesNotifications {
    /// Message de l'erreur de décodage (web l.118) ; l'écran affiche `PreferencesTextes.chargementImpossible`.
    static let messageIndisponible = "Préférences indisponibles"

    func canalGlobalActif(_ canal: CanalNotification) -> Bool {
        switch canal {
        case .email: return canalEmail
        case .sms: return canalSms
        case .push: return canalPush
        case .inApp: return canalInApp
        }
    }

    mutating func definirCanalGlobal(_ canal: CanalNotification, actif: Bool) {
        switch canal {
        case .email: canalEmail = actif
        case .sms: canalSms = actif
        case .push: canalPush = actif
        case .inApp: canalInApp = actif
        }
    }

    /// Valeur d'une case : la dernière ligne explicite (comme la `Map` du web), sinon actif (l.196).
    func estActif(type: String, canal: CanalNotification) -> Bool {
        parEvenement.last { $0.typeEvenement == type && $0.canal == canal }?.actif ?? true
    }

    /// Case présente (type du catalogue, canal de l'événement) et canal global actif (l.401, l.406-407).
    func peutBasculer(type: String, canal: CanalNotification) -> Bool {
        guard let evenement = CatalogueNotificationsSoignant.evenement(type: type) else { return false }
        return evenement.canaux.contains(canal) && canalGlobalActif(canal)
    }

    /// Inverse la case et la rend explicite (une seule ligne par clé) ; rend faux sans rien changer si la
    /// case n'est pas modifiable.
    @discardableResult
    mutating func basculer(type: String, canal: CanalNotification) -> Bool {
        guard peutBasculer(type: type, canal: canal) else { return false }
        let nouvelle = PreferenceEvenement(typeEvenement: type, canal: canal, actif: !estActif(type: type, canal: canal))
        if let premiere = parEvenement.firstIndex(where: { $0.typeEvenement == type && $0.canal == canal }) {
            parEvenement[premiere] = nouvelle
            var index = parEvenement.index(after: premiere)
            while index < parEvenement.endIndex {
                if parEvenement[index].typeEvenement == type && parEvenement[index].canal == canal {
                    parEvenement.remove(at: index)
                } else {
                    index = parEvenement.index(after: index)
                }
            }
        } else {
            parEvenement.append(nouvelle)
        }
        return true
    }

    /// Événements affichés, selon le régime relu.
    var evenementsVisibles: [EvenementNotification] { CatalogueNotificationsSoignant.visibles(typeExercice: typeExercice) }

    /// `p_par_evenement` : lignes explicites (lues ou basculées, comme le web l.211-215) dont le type est au
    /// catalogue soignant — jamais un type inconnu (22P02) ni un type d'un autre espace. Le filtre de régime
    /// n'en retire rien : la RPC met à jour par clé, sans rien supprimer.
    var parEvenementAEnvoyer: [PreferenceEvenement] {
        parEvenement.filter { CatalogueNotificationsSoignant.evenement(type: $0.typeEvenement) != nil }
    }

    /// Section « SMS d'alerte » affichée seulement si la ligne `soignants` a été lue (l.290).
    var afficheAlerteSms: Bool { smsAlertesActives != nil }
    /// Interrupteur de l'alerte grisé tant que le canal SMS est coupé (l.309).
    var alerteSmsModifiable: Bool { canalSms }
    /// Avertissement « Le canal « SMS » est désactivé… » (l.299-303).
    var afficheAvertissementCanalSms: Bool { !canalSms }

    /// Relecture (`self`) comparée à la demande : aucun enregistrement n'est annoncé sur une relecture qui
    /// ne montre pas ce qui a été envoyé. Le régime, relu mais jamais écrit, est hors comparaison.
    func concordance(avec demande: PreferencesNotifications) -> ConcordancePreferences {
        let canaux = CanalNotification.allCases.allSatisfy { canalGlobalActif($0) == demande.canalGlobalActif($0) }
        let exceptions = demande.parEvenementAEnvoyer.allSatisfy { estActif(type: $0.typeEvenement, canal: $0.canal) == $0.actif }
        let alerte = demande.smsAlertesActives.map { $0 == smsAlertesActives } ?? true
        return ConcordancePreferences(generales: canaux && exceptions, alerteSms: alerte)
    }

    /// Décodage strict de `fn_obtenir_mes_preferences_notifications()` (web l.117) et de la ligne
    /// `soignants.select('sms_alertes_actives, type_exercice')` (l.122-131) :
    /// - `global` objet portant les quatre booléens `canal_*` (clés supplémentaires tolérées), `par_evenement`
    ///   tableau ; sinon erreur d'écran ;
    /// - chaque ligne `par_evenement` lisible (type non vide, canal de l'enum, `actif` booléen), sinon erreur
    ///   d'écran : une ligne illisible n'est jamais lue comme une absence, qui vaudrait « actif » ;
    /// - `soignant` nil ou `null` : ligne absente (alerte ni affichée ni écrite, régime inconnu) ; sinon
    ///   `sms_alertes_actives` booléen, `null`/absent → `true` (`?? true`, l.129), toute autre valeur → erreur.
    /// Erreur levée : `.contract` avec `messageIndisponible`.
    static func decoder(preferences: ValeurJSON, soignant: ValeurJSON?) throws -> PreferencesNotifications {
        let indisponible = JoleneError(.contract, messageIndisponible)
        guard case .objet(let global)? = preferences["global"],
              case .booleen(let email)? = global["canal_email"], case .booleen(let sms)? = global["canal_sms"],
              case .booleen(let push)? = global["canal_push"], case .booleen(let inApp)? = global["canal_in_app"],
              case .tableau(let lignes)? = preferences["par_evenement"] else { throw indisponible }
        let parEvenement = try lignes.map { ligne -> PreferenceEvenement in
            guard case .chaine(let type)? = ligne["type_evenement"], !type.isEmpty,
                  case .chaine(let brut)? = ligne["canal"], let canal = CanalNotification(rawValue: brut),
                  case .booleen(let actif)? = ligne["actif"] else { throw indisponible }
            return PreferenceEvenement(typeEvenement: type, canal: canal, actif: actif)
        }
        var alerte: Bool?
        var regime: String?
        switch soignant {
        case nil, .null?:
            break
        case .objet(let ligne)?:
            switch ligne["sms_alertes_actives"] {
            case .booleen(let valeur)?: alerte = valeur
            case nil, .null?: alerte = true
            default: throw indisponible
            }
            if case .chaine(let valeur)? = ligne["type_exercice"] { regime = valeur }
        default:
            throw indisponible
        }
        return PreferencesNotifications(canalEmail: email, canalSms: sms, canalPush: push, canalInApp: inApp,
                                        parEvenement: parEvenement, smsAlertesActives: alerte, typeExercice: regime)
    }
}

// MARK: - Textes et identifiants

/// Textes de l'écran, verbatim `PageParametresNotifications.tsx` (HARD STOP n°4 ; garde :
/// `PreferencesNotificationsTests.testTextesVerbatimDuWeb`). Seuls écarts : le vouvoiement des deux textes
/// tutoyés (décision 9 du lot 1, textes non juridiques) et l'emoji « ⚠️ » du titre d'urgence, porté par
/// l'icône du ton « Attention » de `InlineNotice`.
public enum PreferencesTextes {
    /// `usePageTitle` (l.70), titres l.256 et l.282.
    public static let titre = "Préférences de notifications"
    public static let sousTitre = "Choisissez par canal et par type d'événement"                                   // l.284
    public static let titreAlerteSms = "SMS d'alerte"                                                               // l.293
    /// l.296-297, vouvoyé (« Tu peux » → « Vous pouvez »).
    public static let descriptionAlerteSms =
        "Recevoir un SMS pour les missions urgentes et le rappel mission J-1. Coût supporté par Jolene. Vous pouvez désactiver à tout moment."
    /// l.301, vouvoyé (« active-le » → « activez-le »).
    public static let avertissementCanalSms =
        "Le canal « SMS » est désactivé dans les canaux globaux ci-dessous : activez-le pour recevoir ces alertes."
    public static let libelleAlerteSms = "Recevoir les alertes par SMS"                                             // l.306
    public static let titreCanaux = "Canaux globaux"                                                                // l.316
    public static let descriptionCanaux =
        "Désactiver un canal ici coupe TOUTES les notifications de ce canal, peu importe les préférences par événement." // l.318
    public static let titreEvenements = "Par type d'événement"                                                      // l.374
    public static let descriptionEvenements =
        "Pour chaque type d'événement, choisissez les canaux activés. Les notifications d'urgence (sécurité, danger) sont toujours envoyées et non désactivables." // l.376
    /// l.428 sans l'emoji.
    public static let titreUrgence = "Notifications d'urgence"
    public static let texteUrgence =
        "Les notifications d'urgence critique (incident sécurité, litige sécurité, alerte fraude) sont toujours envoyées sur tous les canaux configurés et ne peuvent pas être désactivées. C'est une exigence de sécurité." // l.429
    public static let enregistrer = "Enregistrer"                                                                   // l.434
    public static let chargementImpossible =
        "Impossible de charger vos préférences. Vos choix enregistrés sont conservés."                               // l.257
    public static let reessayer = "Réessayer"                                                                       // l.258
    public static let enregistre = "Préférences enregistrées"                                                       // l.242
    public static let echecPartielAlerteSms = "Préférences générales enregistrées, mais flag SMS d'alerte non sauvegardé." // l.237
    /// Repli du web quand l'erreur n'a pas de message (`err?.message || 'Erreur enregistrement'`, l.244).
    public static let echecEnregistrement = "Erreur enregistrement"

    /// Libellés des canaux globaux (l.321-324).
    public static func libelleCanalGlobal(_ canal: CanalNotification) -> String {
        switch canal {
        case .email: return "Email"
        case .push: return "Notifications push (mobile / web)"
        case .sms: return "SMS (urgences uniquement par défaut)"
        case .inApp: return "In-app (cloche en haut de l'écran)"
        }
    }

    /// En-têtes des colonnes de la matrice (l.383-385).
    public static func libelleColonne(_ canal: CanalNotification) -> String {
        switch canal {
        case .email: return "Email"
        case .push: return "Push"
        case .sms: return "SMS"
        case .inApp: return "In-app"
        }
    }

    /// Raison d'une case grisée (`title`, l.409), affichée et vocalisée par `ToggleRow`.
    public static func raisonCanalDesactive(_ canal: CanalNotification) -> String {
        "Canal \(canal.rawValue) désactivé dans les canaux globaux"
    }

    /// `prefs-canal-email|sms|push|inapp` (blueprint §3 T6).
    public static func identifiantCanal(_ canal: CanalNotification) -> String {
        switch canal {
        case .email: return "prefs-canal-email"
        case .sms: return "prefs-canal-sms"
        case .push: return "prefs-canal-push"
        case .inApp: return "prefs-canal-inapp"
        }
    }

    /// `prefs-evt-<TYPE>-<CANAL>` (blueprint §3 T6).
    public static func identifiantEvenement(type: String, canal: CanalNotification) -> String {
        "prefs-evt-\(type)-\(canal.rawValue)"
    }
}
