import Foundation
import JoleneCore
import Supabase

/// `CandidaturePort` sur Supabase (lot 1, T6a, `docs/mobile-swift/LOT1_PLAN.md` §3 T6a), sous le JWT du
/// soignant :
/// - POSTULER, ACCEPTER, PROPOSITION : `fn_confirmer_action_planning_v1(p_mission_id, p_action,
///   p_creneaux_confirmes, p_message, p_choix_contrat, p_candidature_id)` (`public.sql` l.24525), avec
///   `p_creneaux_confirmes` = planning exact affiché (`CreneauxConfirmes.pourAction`, T2). Formes de réponse
///   de la fiche `CONTRATS_RPC_SOIGNANT.md`, lues dans l'ordre normatif du §2.4 : mission sortie de l'état
///   `OUVERTE` (messages exacts, `.missionDejaAttribuee`) → `choix_requis` → `code` (planning à reconfirmer,
///   ou refus verbatim) → documents requis avec `error` → refus drapeauté sans code (`.refusee(code: nil)`) →
///   `success:true` → `error` seul → sinon `.contract`. Exception PostgREST `[CODE DU TRAVAIL]` restituée mot
///   pour mot (`.refusee(code: CODE_DU_TRAVAIL)`, HARD STOP n°4) ; toute autre exception → message générique.
/// - PROPOSITION verrouillée hors `LIBERAL` (revue B8 de T6a, M1, décision par délégation) : le web fait
///   compléter l'attestation hebdomadaire des heures avant d'accepter (`CarteProposition.tsx` l.154-256), non
///   portée au lot 1. `choixContrat` porte, pour PROPOSITION, le contrat de la proposition relu par l'écran
///   (`CandidatureRules.contratProposition`) : non `LIBERAL` → `CandidatureVerrou.renvoiWeb`, **aucune
///   requête** ; déclaré `LIBERAL` → contrat relu au serveur (candidature et mission) avant tout envoi, et
///   `p_choix_contrat` envoyé à null comme le web. Gap consigné dans `LOT1_PLAN.md` §3 T6b et §7.
/// - Un succès n'est annoncé qu'après relecture (PRINCIPES §3) : POSTULER relit la candidature créée
///   (`candidature_id`, statut en attente, même mission) ; ACCEPTER et PROPOSITION relisent la mission
///   (`ASSIGNEE`, `soignant_assigne_id` = session) puis écrivent l'audit `MISSION_ASSIGNATION` comme le web
///   (best-effort, décision 5 : son échec n'invalide jamais le succès relu). Une relecture qui ne confirme
///   pas, ou qui échoue (réseau compris), est une erreur au message `relectureMessage`, jamais un succès ;
///   aucun renvoi automatique (un délai ne prouve rien).
/// - Refus d'une proposition : `fn_repondre_proposition(p_candidature_id, p_accepter := false)` (l.54035),
///   puis relecture `REFUSEE`. Non verrouillé : le web ne demande aucune attestation pour refuser.
/// - SWIPE_LIKE (lot 4, T3a, verrou levé : `fn_confirmer_action_planning_v1` l'accepte, contrôle le planning puis délègue à
///   `fn_enregistrer_swipe(p_mission_id, 'LIKE', p_choix_contrat)`) : succès `{ok:true, swipe_id, candidature_id, …}`
///   **sans `success`**, annoncé après relecture de la candidature comme POSTULER ; refus `{ok:false, error}` à code
///   technique traduit par `SwipeRefus`, message rédigé verbatim, `choix_requis` relayé ; `auth_required` →
///   `.unauthorized`. `warning` et `docs_a_completer` ne sont pas portés par `CandidatureOutcome` (écran T3b).
/// - URGENCE (lot 4, T11) : refusée explicitement en citant sa tranche (`CandidatureRules.actionHorsLot1`).
/// - Annulations (T7) : `fn_annuler_candidature_soignant(p_candidature_id, p_motif_categorie, p_texte_libre,
///   p_justificatif_storage_path)` (`public.sql` l.17925 ; refus `{success:false, error_code, error}` → `.refusee`,
///   message serveur verbatim) puis relecture de la candidature `ANNULEE` ; `fn_annuler_mission_soignant(p_mission_id)`
///   (l.18739 ; refus `{error}` seul → `.refusee`) puis relecture de la mission (plus attribuée au soignant) et audit
///   `MISSION_ANNULATION` comme le web (l.903-914, best-effort). Conséquences (`points`, `libre`, `contestable`,
///   `penalite_score`) rendues telles quelles : aucun barème côté client (décision 4).
public struct SupabaseCandidatureGateway: CandidaturePort {
    public static let confirmerRPC = "fn_confirmer_action_planning_v1"
    public static let repondreRPC = "fn_repondre_proposition"
    public static let annulerCandidatureRPC = "fn_annuler_candidature_soignant"
    public static let annulerMissionRPC = "fn_annuler_mission_soignant"
    /// Détails de l'audit client de l'annulation sans candidature (web l.910), jamais affichés.
    public static let motifAuditAnnulation = "Annulation volontaire par le soignant"
    /// Le serveur a répondu mais la relecture ne montre pas l'annulation : rien n'est renvoyé automatiquement.
    public static let relectureAnnulationMessage = "Votre annulation a été envoyée mais n'a pas pu être relue. Vérifiez Mes missions avant de réessayer."
    /// Colonnes de la ligne `candidatures` relue (mêmes que Mes missions, T5).
    public static let candidatureColumns = SupabaseMesMissionsGateway.candidatureColumns
    /// Colonnes de la mission relue après ACCEPTER / PROPOSITION (preuve et détails d'audit).
    public static let attributionColumns = "id,statut,soignant_assigne_id,intitule,debut_le,fin_le,etablissement_id"
    /// Colonnes du contrat d'une proposition (`type_contrat_choisi ?? type_contrat_recherche`).
    public static let contratColumns = "id,type_contrat_recherche"

    public static let fallbackMessage = "Impossible de traiter votre réponse à cette mission. Réessayez."
    /// Le serveur a répondu mais la relecture ne le confirme pas : rien n'est renvoyé automatiquement.
    public static let relectureMessage = "Votre réponse a été envoyée mais n'a pas pu être relue. Vérifiez Mes missions avant de réessayer."
    public static let planningRequisMessage = "Le planning exact doit être confirmé avant de répondre à cette mission."
    public static let identifiantInvalideMessage = "Identifiant de mission ou de candidature invalide."

    private let client: SupabaseClient
    private let audit: any AuditPort

    public init(client: SupabaseClient, audit: (any AuditPort)? = nil) {
        self.client = client
        self.audit = audit ?? SupabaseAuditGateway(client: client)
    }

    // MARK: - Confirmer

    public func confirmer(action: ActionPlanning, missionId: String, creneaux: [CreneauConfirmePayload], message: String?,
                          choixContrat: String?, candidatureId: String?, context: MissionReadContext) async throws -> CandidatureOutcome {
        try MissionQuery.validate(context: context)
        // Lot 1 : trois actions ; lot 4 (T3a) : SWIPE_LIKE, relu comme POSTULER. URGENCE (T11) reste refusée ici.
        guard action == .postuler || action == .accepter || action == .proposition || action == .swipeLike else {
            throw CandidatureRules.actionHorsLot1(action)
        }
        guard let mission = Self.uuid(missionId) else { throw JoleneError(.contract, Self.identifiantInvalideMessage) }
        var proposition: String?
        if action == .proposition {
            guard let id = candidatureId.flatMap(Self.uuid) else { throw JoleneError(.contract, Self.identifiantInvalideMessage) }
            // Verrou de l'attestation hebdomadaire (M1) : contrat déclaré non libéral → aucune requête.
            guard !CandidatureRules.propositionVerrouillee(contrat: choixContrat) else {
                throw CandidatureVerrou.renvoiWeb(chemin: CandidatureVerrou.cheminProposition)
            }
            proposition = id
        }
        // Fail-closed : un planning non exact n'est jamais envoyé (`CreneauxConfirmes` rend nil, l'écran bloque).
        guard !creneaux.isEmpty else { throw JoleneError(.contract, Self.planningRequisMessage) }
        if let proposition {
            // Contrat relu au serveur, lecture seule : une déclaration libérale erronée ne contourne pas le verrou.
            try await verifierContratLiberal(candidatureId: proposition, missionId: mission, context: context)
        }

        let params: JSONObject = [
            "p_mission_id": .string(mission),
            "p_action": .string(action.rawValue),
            "p_creneaux_confirmes": .array(creneaux.map { .object(["debut": .string($0.debut), "fin": .string($0.fin)]) }),
            "p_message": Self.texteOuNul(message),
            // PROPOSITION : null comme le web (`CarteProposition.tsx` l.274) ; le contrat déclaré ne sert qu'au verrou.
            "p_choix_contrat": proposition == nil ? Self.texteOuNul(choixContrat) : .null,
            "p_candidature_id": proposition.map(AnyJSON.string) ?? .null,
        ]
        let reponse = try await RPCResponse.appeler(client, Self.confirmerRPC, params: params, fallback: Self.fallbackMessage)
        if action == .swipeLike { return try await confirmerSwipeLike(reponse, missionId: mission, context: context) }
        if let erreur = reponse.erreur, reponse.code == nil, !reponse.choixRequis, CandidatureRules.estMissionDejaAttribuee(erreur) {
            return .missionDejaAttribuee(message: erreur)
        }
        if let refus = reponse.issueCandidatureRefusee(fallback: Self.fallbackMessage) { return refus }
        try reponse.leverSiErreur(fallback: Self.fallbackMessage)
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }

        if action == .postuler {
            let id = try reponse.requiredString("candidature_id")
            let relue = try await relireCandidature(id: id, context: context)
            guard CandidatureRules.candidaturePoseeRelue(relue, id: id, missionId: mission) else {
                throw JoleneError(.contract, Self.relectureMessage)
            }
            return .confirmed(candidatureId: id, contratId: nil)
        }
        let contrat = try reponse.requiredString("contrat_id")
        let relue = try await relireAttribution(missionId: mission)
        guard let relue, relue.id == mission,
              CandidatureRules.assignationRelue(statut: relue.statut, soignantAssigneId: relue.soignantAssigneId,
                                                userId: context.userId) else {
            throw JoleneError(.contract, Self.relectureMessage)
        }
        await auditerAssignation(relue, context: context)
        return .confirmed(candidatureId: proposition, contratId: contrat)
    }

    /// SWIPE_LIKE (T3a) : refus du wrapper (accès, mission fermée, planning, conflit) puis de `fn_enregistrer_swipe`, dans
    /// l'ordre de `confirmer` ; succès `ok:true` (jamais `success`) relu par `candidature_id`.
    private func confirmerSwipeLike(_ reponse: RPCResponse, missionId: String, context: MissionReadContext) async throws -> CandidatureOutcome {
        // Branche défensive, inatteignable avec le wrapper live (revue B8 de #1165, m4) : sans `auth.uid()`,
        // `fn_confirmer_action_planning_v1` refuse d'abord par « Accès réservé aux soignants authentifiés. »
        // (`success:false, ok:false`), restitué verbatim comme pour POSTULER au lot 1, et ne délègue jamais à
        // `fn_enregistrer_swipe`. Gardée pour qu'un `auth_required` de la RPC déléguée, si le wrapper changeait, ne
        // s'affiche jamais comme un code brut : session expirée, comme pour ✕ / ⭐ (`SupabaseSwipeGateway`).
        if reponse.erreur == PaquetSwipe.erreurNonAuthentifie {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        if let erreur = reponse.erreur, reponse.code == nil, !reponse.choixRequis, CandidatureRules.estMissionDejaAttribuee(erreur) {
            return .missionDejaAttribuee(message: erreur)
        }
        if let refus = reponse.issueCandidatureRefusee(fallback: Self.fallbackMessage) {
            // Code technique de `fn_enregistrer_swipe` (`mission_deja_swipee`…) : libellé `SwipeRefus`, code conservé.
            guard case .refusee(nil, let texte, let documents) = refus else { return refus }
            let traduit = SwipeRefus.traduire(texte)
            return .refusee(code: traduit.code, message: traduit.message, documentsRequisPour: documents)
        }
        try reponse.leverSiErreur(fallback: Self.fallbackMessage)
        guard reponse.ok == true, reponse.erreur == nil else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        let id = try reponse.requiredString("candidature_id")
        let relue = try await relireCandidature(id: id, context: context)
        guard CandidatureRules.candidaturePoseeRelue(relue, id: id, missionId: missionId) else {
            throw JoleneError(.contract, Self.relectureMessage)
        }
        return .confirmed(candidatureId: id, contratId: nil)
    }

    // MARK: - Proposition refusée

    public func refuserProposition(candidatureId: String, context: MissionReadContext) async throws {
        try MissionQuery.validate(context: context)
        guard let id = Self.uuid(candidatureId) else { throw JoleneError(.contract, Self.identifiantInvalideMessage) }
        let reponse = try await RPCResponse.appeler(client, Self.repondreRPC,
                                                    params: ["p_candidature_id": .string(id), "p_accepter": .bool(false)],
                                                    fallback: Self.fallbackMessage)
        try reponse.leverSiErreur(fallback: Self.fallbackMessage)
        // `fn_repondre_proposition` ne pose aucun refus structuré : un drapeau faux n'est jamais un succès.
        if reponse.estRefus { throw JoleneError(.unknown, reponse.erreur ?? Self.fallbackMessage) }
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        guard CandidatureRules.refusRelu(try await relireCandidature(id: id, context: context), id: id) else {
            throw JoleneError(.contract, Self.relectureMessage)
        }
    }

    // MARK: - Lecture

    /// Candidature la plus récente du soignant sur cette mission (RLS + filtre explicite sur la session),
    /// relue côté serveur : l'écran ne transporte jamais un identifiant de candidature par la route.
    public func candidature(missionId: String, context: MissionReadContext) async throws -> CandidatureRecord? {
        try MissionQuery.validate(context: context)
        guard let mission = Self.uuid(missionId) else { return nil }
        let lignes: [CandidatureRecord]
        do {
            lignes = try await client.from("candidatures")
                .select(Self.candidatureColumns)
                .eq("mission_id", value: mission)
                .eq("soignant_id", value: context.userId)
                .order("cree_le", ascending: false, nullsFirst: true) // NULLS FIRST de PostgreSQL, comme le web
                .limit(1)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.fallbackMessage)
        }
        guard let ligne = lignes.first else { return nil }
        guard ligne.missionId.caseInsensitiveCompare(mission) == .orderedSame else {
            throw JoleneError(.contract, "La candidature retournée ne correspond pas à la mission demandée.")
        }
        return ligne
    }

    // MARK: - Annulations (T7)

    public func annulerCandidature(id: String, motif: String, texte: String, justificatifPath: String?,
                                   context: MissionReadContext) async throws -> AnnulationOutcome {
        try MissionQuery.validate(context: context)
        guard let candidature = Self.uuid(id) else { throw JoleneError(.contract, Self.identifiantInvalideMessage) }
        if let justificatifPath {
            // Seul un chemin de reçu de cette candidature et de cet utilisateur est transmis.
            guard RecuJustificatif.cheminValide(justificatifPath, userId: context.userId, candidatureId: id)
                    || RecuJustificatif.cheminValide(justificatifPath, userId: context.userId, candidatureId: candidature) else {
                throw JoleneError(.contract, "Chemin de justificatif invalide.")
            }
        }
        let params: JSONObject = [
            "p_candidature_id": .string(candidature),
            "p_motif_categorie": .string(motif),
            "p_texte_libre": .string(texte),
            "p_justificatif_storage_path": justificatifPath.map(AnyJSON.string) ?? .null,
        ]
        let reponse = try await RPCResponse.appeler(client, Self.annulerCandidatureRPC, params: params,
                                                    fallback: LibellesAnnulation.erreurAnnulation)
        // « Non authentifié » (`NON_AUTHENTIFIE`) → session expirée ; `{error}` sans drapeau → `.unknown` verbatim.
        try reponse.leverSiErreur(fallback: LibellesAnnulation.erreurAnnulation)
        if reponse.estRefus {
            return .refusee(code: reponse.codeErreur, message: reponse.erreur ?? LibellesAnnulation.erreurAnnulation)
        }
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        guard AnnulationRules.candidatureAnnuleeRelue(try await relireCandidature(id: candidature, context: context), id: candidature) else {
            throw JoleneError(.contract, Self.relectureAnnulationMessage)
        }
        return .annulee(points: reponse.int("points"), libre: reponse.bool("libre"), contestable: reponse.bool("contestable"))
    }

    public func annulerMission(id: String, motif: String?, context: MissionReadContext) async throws -> AnnulationOutcome {
        try MissionQuery.validate(context: context)
        guard let mission = Self.uuid(id) else { throw JoleneError(.contract, Self.identifiantInvalideMessage) }
        var params: JSONObject = ["p_mission_id": .string(mission)]
        if let motif, !motif.isEmpty { params["p_motif"] = .string(motif) }
        let reponse = try await RPCResponse.appeler(client, Self.annulerMissionRPC, params: params,
                                                    fallback: LibellesAnnulation.erreurAnnulation)
        // Refus `{error}` seuls (l.18749-18756), affichés verbatim comme le web (`toast.error(data.error)`).
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) { throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage) }
            return .refusee(code: nil, message: erreur)
        }
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        let relue = try await relireAttribution(missionId: mission)
        guard AnnulationRules.missionAnnuleeRelue(soignantAssigneId: relue?.soignantAssigneId,
                                                  userId: context.userId, ligneLue: relue != nil) else {
            throw JoleneError(.contract, Self.relectureAnnulationMessage)
        }
        _ = try? await audit.ecrire(action: .missionAnnulation, typeRessource: "mission", idRessource: mission,
                                    details: ["motif": Self.motifAuditAnnulation], context: context)
        return .annulee(points: reponse.int("penalite_score"), libre: nil, contestable: nil)
    }

    // MARK: - Interne

    /// Contrat relu d'une proposition déclarée libérale : la proposition (PROPOSEE, de cette mission) et le
    /// contrat recherché de la mission. Non `LIBERAL` → verrou, sans aucun envoi ; proposition illisible → le
    /// serveur tranchera (« Proposition introuvable. »), la lecture ne remplace pas ses contrôles.
    private func verifierContratLiberal(candidatureId: String, missionId: String, context: MissionReadContext) async throws {
        struct ContratMission: Decodable {
            var id: String
            var typeContratRecherche: String?
            enum CodingKeys: String, CodingKey { case id, typeContratRecherche = "type_contrat_recherche" }
        }
        let candidature = try await lire(fallback: Self.fallbackMessage) { () async throws -> [CandidatureRecord] in
            try await client.from("candidatures").select(Self.candidatureColumns)
                .eq("id", value: candidatureId).eq("soignant_id", value: context.userId).limit(1).execute().value
        }.first
        let mission = try await lire(fallback: Self.fallbackMessage) { () async throws -> [ContratMission] in
            try await client.from("missions").select(Self.contratColumns).eq("id", value: missionId).limit(1).execute().value
        }.first
        let contrat = CandidatureRules.contratProposition(typeContratChoisi: candidature?.typeContratChoisi,
                                                          typeContratRecherche: mission?.typeContratRecherche)
        guard !CandidatureRules.propositionVerrouillee(contrat: contrat) else {
            throw CandidatureVerrou.renvoiWeb(chemin: CandidatureVerrou.cheminProposition)
        }
    }

    /// Lecture PostgREST ; erreurs traduites par `SupabaseErrorMapping` avec `fallback`.
    private func lire<T>(fallback: String, _ requete: () async throws -> T) async throws -> T {
        do {
            return try await requete()
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: fallback)
        }
    }

    /// Erreur d'une relecture après une écriture acceptée (revue B8 de T6a, m3) : la nature de l'erreur est
    /// gardée (réseau, session expirée…), le message dit toujours que la réponse est partie et qu'il faut
    /// vérifier Mes missions avant de réessayer.
    private static func erreurRelecture(_ error: any Error) -> JoleneError {
        JoleneError(SupabaseErrorMapping.map(error, fallback: relectureMessage).kind, relectureMessage)
    }

    private func relireCandidature(id: String, context: MissionReadContext) async throws -> CandidatureRecord? {
        let lignes: [CandidatureRecord]
        do {
            lignes = try await client.from("candidatures")
                .select(Self.candidatureColumns)
                .eq("id", value: id)
                .eq("soignant_id", value: context.userId)
                .limit(1)
                .execute()
                .value
        } catch {
            throw Self.erreurRelecture(error)
        }
        return lignes.first
    }

    /// Mission relue après une attribution.
    struct Attribution: Decodable, Equatable {
        var id: String
        var statut: String?
        var soignantAssigneId: String?
        var intitule: String?
        var debutLe: String?
        var finLe: String?
        var etablissementId: String?

        enum CodingKeys: String, CodingKey {
            case id, statut, intitule
            case soignantAssigneId = "soignant_assigne_id"
            case debutLe = "debut_le"
            case finLe = "fin_le"
            case etablissementId = "etablissement_id"
        }
    }

    private func relireAttribution(missionId: String) async throws -> Attribution? {
        let lignes: [Attribution]
        do {
            lignes = try await client.from("missions")
                .select(Self.attributionColumns)
                .eq("id", value: missionId)
                .limit(1)
                .execute()
                .value
        } catch {
            throw Self.erreurRelecture(error)
        }
        return lignes.first
    }

    /// `MISSION_ASSIGNATION` comme le web (`DetailMissionSoignant.tsx` l.824-836) : `p_details = {intitule,
    /// etablissement, debut, fin}`, établissement par `fn_etablissements_safe` (jamais `fn_etablissement_public`).
    /// Best-effort : toute erreur est avalée (l'attribution relue reste un succès, `AuditPort`).
    private func auditerAssignation(_ mission: Attribution, context: MissionReadContext) async {
        var details: [String: String] = [:]
        if let intitule = mission.intitule { details["intitule"] = intitule }
        if let debut = mission.debutLe { details["debut"] = debut }
        if let fin = mission.finLe { details["fin"] = fin }
        if let etablissementId = mission.etablissementId,
           let nom = try? await SupabaseMissionsGateway(client: client).etablissements(ids: [etablissementId])[etablissementId]?.nom {
            details["etablissement"] = nom
        }
        _ = try? await audit.ecrire(action: .missionAssignation, typeRessource: "mission", idRessource: mission.id,
                                    details: details, context: context)
    }

    /// Uuid canonique en minuscules ; nil pour une valeur vide ou invalide (binding uuid PostgREST).
    static func uuid(_ valeur: String) -> String? {
        UUID(uuidString: valeur.trimmingCharacters(in: .whitespacesAndNewlines))?.uuidString.lowercased()
    }

    /// `|| null` du web : un texte vide ou absent est envoyé à null, tout autre texte tel quel.
    static func texteOuNul(_ valeur: String?) -> AnyJSON {
        guard let valeur, !valeur.isEmpty else { return .null }
        return .string(valeur)
    }
}
