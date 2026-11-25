import Foundation
import JoleneCore
import Supabase

/// `SeriePort` sur Supabase (lot 4, T12 ; `docs/mobile-swift/LOT4_PLAN.md` §3 T12), sous le JWT du soignant.
///
/// - Lecture : même requête que le web (`DetailSerieSoignant.tsx` l.90-95), `missions` filtrées par
///   `description ILIKE '%[SERIE_ID:<id>]%'`, ordre `debut_le` croissant, colonnes de `MissionQuery.missionSelect`.
///   Visibilité, exclusions et cohortes TEST restent dans la RLS. L'identifiant doit avoir la forme que le web écrit
///   et relit (`CarteSerie.tsx` l.27, `SERIE_<horodatage>_<suffixe>`) : toute autre valeur rend `[]` sans requête, si
///   bien qu'aucun joker (`%`) venu d'un lien n'élargit le filtre ; les `_` du motif sont échappés. Chaque ligne relue
///   est contrôlée (elle porte le marqueur de la série, et toutes viennent du même établissement, sinon « Pack
///   introuvable ») puis enrichie comme Explorer (établissements par `fn_etablissements_safe`, créneaux
///   prévisionnels hors pauses avec compte exact) : un planning qui ne peut pas être chargé fait échouer la lecture,
///   jamais un planning présenté comme exact.
/// - Acceptation : `CandidaturePort.confirmer(action: .accepter, …)` du lot 1 (`SupabaseCandidatureGateway` :
///   `fn_confirmer_action_planning_v1`, `p_message`, `p_choix_contrat` et `p_candidature_id` à null comme le web
///   l.295-302, relecture de l'attribution, audit `MISSION_ASSIGNATION`). Aucune règle ici : l'issue est rendue
///   telle quelle, refus du serveur mot pour mot.
public struct SupabaseSerieGateway: SeriePort {
    /// Forme d'un identifiant de série (`extraireSerieId`, `src/components/CarteSerie.tsx` l.27).
    public static let motifIdentifiant = #"^SERIE_[0-9]{10,15}_[a-z0-9]{4,8}$"#
    public static let ligneHorsSerieMessage = "Une mission retournée n'appartient pas à la série demandée."

    private let client: SupabaseClient
    private let lecture: SupabaseMissionsGateway
    private let enrich: MissionQuery.Enricher
    private let candidature: any CandidaturePort

    public init(client: SupabaseClient, candidature: (any CandidaturePort)? = nil, clock: any ClockPort = SystemClock(),
                enrich: @escaping MissionQuery.Enricher = MissionQuery.defaultEnrich) {
        self.client = client
        self.lecture = SupabaseMissionsGateway(client: client, clock: clock, enrich: enrich)
        self.enrich = enrich
        self.candidature = candidature ?? SupabaseCandidatureGateway(client: client)
    }

    public static func identifiantValide(_ serieId: String) -> Bool {
        serieId.range(of: motifIdentifiant, options: .regularExpression) != nil
    }

    /// Marqueur écrit dans `missions.description` par le web.
    public static func marqueur(_ serieId: String) -> String { "[SERIE_ID:\(serieId)]" }

    /// Motif ILIKE « contient » du texte, ses jokers échappés (revue B8 sécurité de la vague D, m2) : `\`, `%` et `_`
    /// (échappement par défaut de Postgres) ; sans cela, le `_` du marqueur et de l'identifiant vaudrait n'importe quel
    /// caractère, et une description voisine ferait échouer la lecture de la série.
    public static func motifILike(_ texte: String) -> String {
        let echappe = texte.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(echappe)%"
    }

    public func missions(serieId: String, context: MissionReadContext) async throws -> [Mission] {
        try MissionQuery.validate(context: context)
        guard Self.identifiantValide(serieId) else { return [] }
        let marqueur = Self.marqueur(serieId)
        let lignes: [MissionRecord]
        do {
            lignes = try await client.from("missions")
                .select(MissionQuery.missionSelect)
                .ilike("description", pattern: Self.motifILike(marqueur))
                .order("debut_le", ascending: true)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: SupabaseMissionsGateway.missionsFallbackMessage)
        }
        guard lignes.allSatisfy({ ($0.description ?? "").range(of: marqueur, options: .caseInsensitive) != nil }) else {
            throw JoleneError(.contract, Self.ligneHorsSerieMessage)
        }
        // Revue B8 sécurité de la vague D (M1) : le marqueur est du texte libre que le serveur ne nettoie pas ; une série
        // dont les lignes ne viennent pas toutes du même établissement n'est pas un pack (fermé par défaut, « Pack
        // introuvable », web l.234-242) : aucune mission d'un autre établissement n'est présentée ni acceptable.
        guard SerieRegles.unSeulEtablissement(lignes.map(\.etablissementId)) else { return [] }
        // Comme les autres lectures : une fixture Playwright n'existe pas pour un compte ordinaire.
        let visibles = MissionBusiness.estComptePlaywright(email: context.email)
            ? lignes : lignes.filter { !MissionBusiness.estMissionPlaywright(intitule: $0.intitule) }
        guard !visibles.isEmpty else { return [] }
        async let etablissements = lecture.etablissements(ids: visibles.map(\.etablissementId))
        async let creneaux = lecture.slots(missionIds: visibles.map(\.id))
        return try await enrich(context, visibles, etablissements, creneaux)
    }

    public func accepter(missionId: String, creneaux: [CreneauConfirmePayload],
                         context: MissionReadContext) async throws -> CandidatureOutcome {
        try await candidature.confirmer(action: .accepter, missionId: missionId, creneaux: creneaux, message: nil,
                                        choixContrat: nil, candidatureId: nil, context: context)
    }
}
