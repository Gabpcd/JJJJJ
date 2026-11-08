import Foundation
import JoleneCore
import Supabase

/// Constantes et fonctions pures des lectures et de l'appel du pointage (blueprint lot 2 §2.4, §3 T3). Les projections
/// sont imposées : jamais `select=*`, jamais une colonne `code_pointage_*` de `missions` (le code rotatif reste lisible
/// par le soignant assigné en PostgREST direct : gap « B1-ter » nommé par la migration B1), jamais l'embed
/// `etablissements(…)` (noms par `fn_etablissements_safe`), jamais `code_saisi`, `ip_address`, `latitude`, `longitude`
/// de `scans_pointage`.
public enum PointageQuery {
    public static let rpcScanner = "fn_scanner_code_pointage"
    public static let rpcEtat = "fn_etat_pointage_mission"
    public static let rpcConsentement = "fn_consentir_gps"
    public static let rpcDetail = "fn_presences_detail_mission"
    public static let rpcRelance = "fn_relancer_validation_presence"

    /// `PresencesSoignant.tsx` l.121 et l.149 : missions du pointage, puis missions de l'historique.
    public static let statutsActifs = ["ASSIGNEE", "EN_COURS"]
    public static let statutsHistorique = ["TERMINEE", "LITIGE", "ABSENCE"]
    /// `.limit(100)` des deux lectures d'historique (l.144, l.151).
    public static let limiteHistorique = 100

    public static var missionsSelect: String { MissionPresenceLue.selection }
    /// Présences validées (l.126-130) : embed `missions!inner` sans statut.
    public static var presencesValideesSelect: String {
        (PresenceLue.colonnes + ["missions!inner(\(MissionDePresence.colonnes.filter { $0 != "statut" }.joined(separator: ",")))"])
            .joined(separator: ",")
    }
    /// Historique des présences (l.137-141) : embed `missions` avec statut.
    public static var historiqueSelect: String {
        (PresenceLue.colonnes + ["missions(\(MissionDePresence.colonnes.joined(separator: ",")))"]).joined(separator: ",")
    }
    public static let contratsSelect = "id,mission_id,statut,cree_le"
    public static let consentementSelect = "consentement_gps"
    public static var preuvesSelect: String { PreuveScan.selection }

    /// Messages d'échec de lecture (non juridiques). L'état reprend le texte du web (`PointageRotatifSoignant.tsx` l.86).
    public static let fallbackPresences = "Impossible de charger vos présences. Réessayez."
    public static let fallbackEtat = "Impossible de charger son état."
    public static let fallbackScan = "Impossible d'enregistrer le pointage. Réessayez."
    public static let fallbackLocalisation = "Impossible d'enregistrer votre choix de localisation. Réessayez."
    public static let fallbackDetail = "Impossible de charger le détail des présences. Réessayez."
    /// Repli du web quand le serveur ne donne aucun message (`DetailPresencesMission.tsx` l.123), à la place du code
    /// brut que le web afficherait (blueprint §2.4).
    public static let fallbackRelance = "Relance impossible."

    /// Corps de `fn_scanner_code_pointage` : `{"p_code", "p_metadata"}`, clés de `p_metadata` de `MetadonneesScan`
    /// (identiques à `PointageRotatifSoignant.tsx` l.122-126 ; coordonnées seulement si la position est disponible).
    public static func parametresScan(code: String, metadonnees: MetadonneesScan) throws -> JSONObject {
        let donnees = try JSONEncoder().encode(metadonnees)
        guard let objet = try JSONDecoder().decode(AnyJSON.self, from: donnees).objectValue else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return ["p_code": .string(code), "p_metadata": .object(objet)]
    }

    /// Réponse jsonb décodée en liste blanche (`Decodable` du Core) ; nil si la forme ne convient pas.
    static func decoder<T: Decodable>(_ type: T.Type, _ reponse: RPCResponse) -> T? {
        guard let donnees = try? JSONEncoder().encode(reponse.raw) else { return nil }
        return try? JSONDecoder().decode(T.self, from: donnees)
    }
}
