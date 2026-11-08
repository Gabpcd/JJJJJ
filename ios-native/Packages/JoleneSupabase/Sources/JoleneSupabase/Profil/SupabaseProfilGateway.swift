import Foundation
import JoleneCore
import Supabase

/// `ProfilPort` sur Supabase (lot 3, T9), comme `ProfilSoignant.tsx` l.153-200 et l.246-297 (définitions
/// live relues en lecture seule le 08/11/2026 : corps identiques au dump, `SECURITY DEFINER`, EXECUTE
/// `authenticated`) :
/// - lecture `fn_mon_profil_soignant_complet()` (JWT du soignant) : « Non authentifié » → session
///   expirée, tout autre `{error}` (« Profil introuvable ») → message serveur verbatim ; puis décodage en
///   LISTE BLANCHE (`ProfilComplet.depuis`, garde `validerProfilSoignant`) : une ligne invalide ou d'un
///   autre utilisateur est un refus de contrat, jamais un profil vide ; les clés sensibles
///   (`ProfilComplet.clesSensibles`) ne sont ni décodées ni journalisées ;
/// - écriture `fn_modifier_mon_profil(…)` avec les SEULS paramètres de `ModificationProfil.parametres`
///   (jamais type d'exercice ni attestation de cumul : HARD STOP n°4) ; `{error}` (prénom ou nom vide)
///   → message serveur verbatim ; succès = `{success:true}` puis RELECTURE du profil, rendue à
///   l'appelant (le web affiche son toast sans relire, l.293). Une seule requête, aucun renvoi.
///
/// L'audit de consultation (`DONNEES_PERSO_CONSULTATION`) est écrit par le modèle d'écran
/// (`ProfilEditionModel`, une fois par ouverture), pas par cette gateway, qui sert aussi la relecture.
public struct SupabaseProfilGateway: ProfilPort {
    public static let lectureRPC = "fn_mon_profil_soignant_complet"
    public static let ecritureRPC = "fn_modifier_mon_profil"
    /// Repli d'un refus d'enregistrement sans message serveur (texte natif, `ProfilEdition.Textes`).
    public static let fallbackMessage = ProfilEdition.Textes.enregistrementEchec

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func profil(context: MissionReadContext) async throws -> ProfilComplet {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.lectureRPC, fallback: ProfilEdition.Textes.chargementEchec)
        try reponse.leverSiErreur(fallback: ProfilEdition.Textes.chargementEchec)
        do {
            return try ProfilComplet.depuis(ValeurJSON(reponse.raw), userId: context.userId)
        } catch {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
    }

    public func modifier(_ champs: ModificationProfil, context: MissionReadContext) async throws -> ProfilComplet {
        try MissionQuery.validate(context: context)
        guard !champs.estVide else { return try await profil(context: context) }
        let reponse = try await RPCResponse.appeler(client, Self.ecritureRPC, params: Self.params(champs),
                                                    fallback: Self.fallbackMessage)
        try reponse.leverSiErreur(fallback: Self.fallbackMessage)
        guard reponse.estSucces else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        return try await profil(context: context)
    }

    /// Corps de `fn_modifier_mon_profil` : un paramètre par champ modifié, rien d'autre.
    static func params(_ champs: ModificationProfil) -> JSONObject {
        champs.parametres.mapValues { valeur in
            switch valeur {
            case .texte(let texte): return .string(texte)
            case .entier(let entier): return .integer(entier)
            case .reel(let reel): return .double(reel)
            case .textes(let textes): return .array(textes.map(AnyJSON.string))
            }
        }
    }
}

extension ValeurJSON {
    /// Conversion sans perte de la valeur décodée par le SDK : les nombres entiers et réels deviennent
    /// `.nombre` (comme `typeof x === 'number'` côté web, garde `validerProfilSoignant`).
    init(_ json: AnyJSON) {
        switch json {
        case .null: self = .null
        case .bool(let valeur): self = .booleen(valeur)
        case .integer(let valeur): self = .nombre(Double(valeur))
        case .double(let valeur): self = .nombre(valeur)
        case .string(let valeur): self = .chaine(valeur)
        case .array(let valeurs): self = .tableau(valeurs.map(ValeurJSON.init))
        case .object(let objet): self = .objet(objet.mapValues(ValeurJSON.init))
        }
    }
}
