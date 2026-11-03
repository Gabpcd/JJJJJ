import Foundation

// Contexte de lecture de l'espace établissement (lot 5, T1 ; `docs/mobile-swift/LOT5_PLAN.md` §2.2, §2.4,
// §2.7). Le serveur reste l'autorité : le natif lit les booléens servis par `fn_mes_permissions_etab`
// (`supabase/schema/public.sql` l.42265) et n'écrit jamais la correspondance rôle → permission
// (`fn_a_permission_etablissement`, l.4905-4934). Clés snake_case explicites (PRINCIPES §2).

/// Rôle d'équipe dans l'établissement courant, tel que servi par `fn_mes_permissions_etab` : les cinq
/// valeurs du CHECK `membres_etablissement_role_check` (`RoleEtab` de `src/hooks/useEtabPermissions.ts`
/// l.5), plus toute autre valeur conservée telle quelle (`ADMIN_PLATEFORME`, servi à un administrateur
/// par `COALESCE(v_role, 'ADMIN_PLATEFORME')` l.42287) : un rôle inconnu n'ouvre jamais l'espace.
public enum RoleEtab: Equatable, Hashable, Sendable {
    case proprietaire
    case adminGroupe
    case rh
    case pointageOnly
    case lectureSeule
    /// Valeur hors des cinq rôles connus, conservée mot pour mot.
    case inconnu(String)

    /// Les cinq rôles connus, dans l'ordre du CHECK.
    public static let connus: [RoleEtab] = [.proprietaire, .adminGroupe, .rh, .pointageOnly, .lectureSeule]

    public init(brut: String) {
        switch brut {
        case "PROPRIETAIRE": self = .proprietaire
        case "ADMIN_GROUPE": self = .adminGroupe
        case "RH": self = .rh
        case "POINTAGE_ONLY": self = .pointageOnly
        case "LECTURE_SEULE": self = .lectureSeule
        default: self = .inconnu(brut)
        }
    }

    /// Valeur serveur exacte.
    public var brut: String {
        switch self {
        case .proprietaire: return "PROPRIETAIRE"
        case .adminGroupe: return "ADMIN_GROUPE"
        case .rh: return "RH"
        case .pointageOnly: return "POINTAGE_ONLY"
        case .lectureSeule: return "LECTURE_SEULE"
        case let .inconnu(valeur): return valeur
        }
    }

    public var estConnu: Bool {
        if case .inconnu = self { return false }
        return true
    }
}

extension RoleEtab: Codable {
    public init(from decoder: Decoder) throws {
        self.init(brut: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(brut)
    }
}

/// Les onze clés exposées par `fn_mes_permissions_etab` (l.42290-42302), identiques à
/// `PERMISSIONS_VIDES` de `src/hooks/useEtabPermissions.ts` (l.21-33), dans le même ordre. Les clés de
/// `docs/EQUIPE_ETAB.md` (`validation_pointage`, `lecture_finances`) n'existent pas (correction 14).
public enum PermissionEtab: String, CaseIterable, Codable, Sendable {
    case gererEquipe = "gerer_equipe"
    case supprimerCompte = "supprimer_compte"
    case profilEtab = "profil_etab"
    case paiement = "paiement"
    case lecturePaiement = "lecture_paiement"
    case missions = "missions"
    case candidatures = "candidatures"
    case contrats = "contrats"
    case pointage = "pointage"
    case rh = "rh"
    case lecture = "lecture"
}

/// Permissions servies pour l'établissement courant. Fail-closed comme le web
/// (`{ ...PERMISSIONS_VIDES, ...perms }`, l.104) et plus strict : une clé absente, nulle ou qui n'est
/// pas un booléen vaut `false` (le web traiterait une chaîne `"true"` comme vraie).
public struct PermissionsEtab: Equatable, Hashable, Sendable {
    public var gererEquipe: Bool
    public var supprimerCompte: Bool
    public var profilEtab: Bool
    public var paiement: Bool
    public var lecturePaiement: Bool
    public var missions: Bool
    public var candidatures: Bool
    public var contrats: Bool
    public var pointage: Bool
    public var rh: Bool
    public var lecture: Bool

    /// Aucune permission (`PERMISSIONS_VIDES`).
    public static let aucune = PermissionsEtab()

    public init(gererEquipe: Bool = false, supprimerCompte: Bool = false, profilEtab: Bool = false, paiement: Bool = false,
                lecturePaiement: Bool = false, missions: Bool = false, candidatures: Bool = false, contrats: Bool = false,
                pointage: Bool = false, rh: Bool = false, lecture: Bool = false) {
        self.gererEquipe = gererEquipe; self.supprimerCompte = supprimerCompte; self.profilEtab = profilEtab
        self.paiement = paiement; self.lecturePaiement = lecturePaiement; self.missions = missions
        self.candidatures = candidatures; self.contrats = contrats; self.pointage = pointage
        self.rh = rh; self.lecture = lecture
    }

    /// Exactement les permissions nommées ; toutes les autres valent `false`.
    public init(accordees: Set<PermissionEtab>) {
        self.init()
        for permission in accordees { self[permission] = true }
    }

    public subscript(_ permission: PermissionEtab) -> Bool {
        get {
            switch permission {
            case .gererEquipe: return gererEquipe
            case .supprimerCompte: return supprimerCompte
            case .profilEtab: return profilEtab
            case .paiement: return paiement
            case .lecturePaiement: return lecturePaiement
            case .missions: return missions
            case .candidatures: return candidatures
            case .contrats: return contrats
            case .pointage: return pointage
            case .rh: return rh
            case .lecture: return lecture
            }
        }
        set {
            switch permission {
            case .gererEquipe: gererEquipe = newValue
            case .supprimerCompte: supprimerCompte = newValue
            case .profilEtab: profilEtab = newValue
            case .paiement: paiement = newValue
            case .lecturePaiement: lecturePaiement = newValue
            case .missions: missions = newValue
            case .candidatures: candidatures = newValue
            case .contrats: contrats = newValue
            case .pointage: pointage = newValue
            case .rh: rh = newValue
            case .lecture: lecture = newValue
            }
        }
    }

    /// Permissions accordées, dans l'ordre des clés serveur.
    public var accordees: [PermissionEtab] { PermissionEtab.allCases.filter { self[$0] } }
}

extension PermissionsEtab: Codable {
    private struct Cle: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ permission: PermissionEtab) { stringValue = permission.rawValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Clé absente, `null` ou non booléenne → `false` ; clés inconnues ignorées.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Cle.self)
        self.init()
        for permission in PermissionEtab.allCases {
            let valeur = (try? container.decodeIfPresent(Bool.self, forKey: Cle(permission))) ?? nil
            self[permission] = valeur ?? false
        }
    }

    /// Les onze clés exactes, toujours présentes.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Cle.self)
        for permission in PermissionEtab.allCases {
            try container.encode(self[permission], forKey: Cle(permission))
        }
    }
}

/// Réponse de `fn_mes_permissions_etab(p_etablissement_id)` (HTTP 200, jamais d'exception) :
/// - compte inactif ou sans session → `{success:false, role:null, permissions:{}}` (l.42274) ;
/// - aucun établissement, ou membre révoqué non administrateur → `{success:true, role:null,
///   etablissement_id:null, permissions:{}}` (l.42277, l.42282) ;
/// - sinon `{success:true, role, etablissement_id, permissions{11 clés}}` (l.42285-42302).
///
/// Décodage fail-closed : `success` est exigé (sinon refus de contrat chez l'appelant) ; sans
/// `success:true` ou sans rôle, aucune permission n'est retenue, quoi que porte la réponse ; un rôle
/// ou un identifiant vide vaut `nil`. Aucune interprétation ici (périmètre, divergence de candidat,
/// rôle inconnu) : `EspaceResolution` (T2) décide.
public struct PermissionsEtabResult: Equatable, Sendable {
    public var success: Bool
    public var role: RoleEtab?
    public var etablissementId: String?
    public var permissions: PermissionsEtab

    public init(success: Bool, role: RoleEtab?, etablissementId: String?, permissions: PermissionsEtab) {
        self.success = success; self.role = role; self.etablissementId = etablissementId
        self.permissions = success && role != nil ? permissions : .aucune
    }
}

extension PermissionsEtabResult: Codable {
    enum CodingKeys: String, CodingKey {
        case success, role, permissions
        case etablissementId = "etablissement_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let success = try c.decode(Bool.self, forKey: .success)
        let role = Self.texteNonVide((try? c.decodeIfPresent(String.self, forKey: .role)) ?? nil).map(RoleEtab.init(brut:))
        let etablissementId = Self.texteNonVide((try? c.decodeIfPresent(String.self, forKey: .etablissementId)) ?? nil)
        let permissions = ((try? c.decodeIfPresent(PermissionsEtab.self, forKey: .permissions)) ?? nil) ?? .aucune
        self.init(success: success, role: role, etablissementId: etablissementId, permissions: permissions)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(success, forKey: .success)
        try c.encode(role, forKey: .role)
        try c.encode(etablissementId, forKey: .etablissementId)
        try c.encode(permissions, forKey: .permissions)
    }

    private static func texteNonVide(_ valeur: String?) -> String? {
        guard let valeur, !valeur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return valeur
    }
}

/// Contexte de lecture d'un écran établissement, propre à un epoch de session : utilisateur,
/// établissement **confirmé par le serveur** (`fn_mes_permissions_etab(NULL)`, D2 — jamais le repli
/// `user.id`), rôle et permissions servis. Chaque port du lot 5 le reçoit ; la gateway refuse un
/// contexte incohérent avant tout appel réseau, le monde démo tout autre utilisateur.
public struct EtablissementReadContext: Equatable, Sendable {
    public var userId: String
    public var etablissementId: String
    public var roleEtab: RoleEtab
    public var permissions: PermissionsEtab
    public var epoch: Int

    public init(userId: String, etablissementId: String, roleEtab: RoleEtab, permissions: PermissionsEtab, epoch: Int) {
        self.userId = userId; self.etablissementId = etablissementId; self.roleEtab = roleEtab
        self.permissions = permissions; self.epoch = epoch
    }

    public static let contexteInvalideMessage = "La session de votre établissement ne correspond plus. Reconnectez-vous."

    /// Contexte exploitable : identifiants non vides, rôle connu (un rôle inconnu n'ouvre jamais
    /// l'espace, §2.2). Sinon `.unauthorized`, sans aucune valeur dans le message.
    public func verifier() throws {
        let utilisateur = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let etablissement = etablissementId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !utilisateur.isEmpty, !etablissement.isEmpty, roleEtab.estConnu else {
            throw JoleneError(.unauthorized, Self.contexteInvalideMessage)
        }
    }
}

/// Sous-ensemble de `fn_mon_etablissement_complet()` (l.44594-44645) décodé par le natif (§2.2).
/// **Jamais décodé** (correction 4, D15) : identifiants Stripe, IBAN, RIB, SIRET, FINESS, commissions,
/// paliers, groupe, raisons de blocage (montants dus), notes ; le modèle n'a aucune propriété pour eux
/// (test `EtablissementProfilDecodingTests`). Colonnes NULLables du schéma gardées optionnelles : une
/// valeur absente n'est jamais remplacée par un défaut qui ouvrirait une action.
public struct EtablissementProfil: Equatable, Sendable, Identifiable {
    public var id: String
    public var nom: String
    public var logoUrl: String?
    /// `type_etablissement` (texte, `et.type::text`).
    public var type: String?
    public var peutPublierMissions: Bool?
    public var statutVerification: String?
    /// Horodatage serveur ISO 8601 du blocage automatique, ou nil.
    public var bloqueAutoLe: String?
    public var contratServiceSigne: Bool
    public var estSecteurPublic: Bool?

    public init(id: String, nom: String, logoUrl: String? = nil, type: String? = nil, peutPublierMissions: Bool? = nil,
                statutVerification: String? = nil, bloqueAutoLe: String? = nil, contratServiceSigne: Bool = false,
                estSecteurPublic: Bool? = nil) {
        self.id = id; self.nom = nom; self.logoUrl = logoUrl; self.type = type
        self.peutPublierMissions = peutPublierMissions; self.statutVerification = statutVerification
        self.bloqueAutoLe = bloqueAutoLe; self.contratServiceSigne = contratServiceSigne; self.estSecteurPublic = estSecteurPublic
    }
}

extension EtablissementProfil: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, nom, type
        case logoUrl = "logo_url"
        case peutPublierMissions = "peut_publier_missions"
        case statutVerification = "statut_verification"
        case bloqueAutoLe = "bloque_auto_le"
        case contratServiceSigne = "contrat_service_signe"
        case estSecteurPublic = "est_secteur_public"
    }

    /// Les seules clés lues dans la réponse serveur.
    public static var clesDecodees: [String] { CodingKeys.allCases.map(\.rawValue) }

    /// `id` exigé (non vide) ; autres clés tolérantes (absentes, nulles ou d'un autre type → nil,
    /// `contrat_service_signe` → `false`, `nom` → vide).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "identifiant d'établissement vide")
        }
        func texte(_ cle: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: cle)) ?? nil }
        func booleen(_ cle: CodingKeys) -> Bool? { (try? c.decodeIfPresent(Bool.self, forKey: cle)) ?? nil }
        self.init(id: id, nom: texte(.nom) ?? "", logoUrl: texte(.logoUrl), type: texte(.type),
                  peutPublierMissions: booleen(.peutPublierMissions), statutVerification: texte(.statutVerification),
                  bloqueAutoLe: texte(.bloqueAutoLe), contratServiceSigne: booleen(.contratServiceSigne) ?? false,
                  estSecteurPublic: booleen(.estSecteurPublic))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(nom, forKey: .nom)
        try c.encode(logoUrl, forKey: .logoUrl)
        try c.encode(type, forKey: .type)
        try c.encode(peutPublierMissions, forKey: .peutPublierMissions)
        try c.encode(statutVerification, forKey: .statutVerification)
        try c.encode(bloqueAutoLe, forKey: .bloqueAutoLe)
        try c.encode(contratServiceSigne, forKey: .contratServiceSigne)
        try c.encode(estSecteurPublic, forKey: .estSecteurPublic)
    }
}
