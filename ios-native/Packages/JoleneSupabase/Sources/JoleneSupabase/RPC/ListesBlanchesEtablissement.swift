import Foundation
import JoleneCore

/// Exception levée par le serveur, telle qu'extraite du dump (`supabase/schema/public.sql`) par
/// `scripts/mobile/check-rpc-contracts.mjs` dans le champ `exceptions` de `ios-native/rpc-contracts.json`,
/// avec son traitement natif (lot 5 §2.5, D12). Le test `ListesBlanchesEtablissementTests` compare chaque
/// paire (SQLSTATE, message) à ce JSON, RPC par RPC et dans l'ordre : une modification serveur rougit le
/// contrat. Un `%` est un joker non vide (`RPCInterception.correspond`).
public struct ExceptionServeur: Equatable, Sendable {
    public enum Traitement: Equatable, Sendable {
        /// Message serveur affiché mot pour mot (refus de droit 42501 ou refus métier).
        case verbatim
        /// Refus de droit 42501 affiché par un message natif neutre (trigger RBAC), puis relecture des permissions.
        case messageNeutre(String)
        /// Non intercepté : message générique de la gateway (texte serveur à suite non garantie, détail
        /// interne possible — PRINCIPES §3 ; revue B8 de T0, mineur 5).
        case generique
        /// Session : `.unauthorized` (28000).
        case session
    }

    public var sqlstate: String
    public var message: String
    public var traitement: Traitement

    public init(_ sqlstate: String, _ message: String, _ traitement: Traitement = .verbatim) {
        self.sqlstate = sqlstate; self.message = message; self.traitement = traitement
    }
}

/// Listes blanches des RPC de l'espace établissement (`RPC_SUIVIES_ETABLISSEMENT`). Les textes sont des
/// **messages serveur verbatim** (HARD STOP n°4 : aucun texte natif, sauf le message neutre du trigger
/// RBAC), chacun annoté de sa ligne dans le dump. Chaque gateway du lot 5 appelle sa RPC avec
/// `interceptions(rpc:)`.
public enum ListesBlanchesEtablissement {
    /// Trigger RBAC `fn_enforce_etablissement_rbac_trigger` (l.32239), `%` instancié par l'argument du trigger.
    private static func rbac(_ permission: String) -> ExceptionServeur {
        ExceptionServeur("42501", "Permission etablissement \(permission) requise", .messageNeutre(RPCInterception.messageRoleInsuffisant))
    }

    /// `dec_bloquer_validation_presence_avant_fin_planning` via `trg_bloquer_validation_presence_avant_fin_planning`
    /// (forme `USING ERRCODE = …, MESSAGE = '…'`), précédée du RBAC `pointage` de `trg_p0_rbac_presences`.
    private static let validationPresence: [ExceptionServeur] = [
        rbac("pointage"),
        ExceptionServeur("23503", "Mission introuvable pour cette présence."), // source: supabase/schema/public.sql l.1052
        ExceptionServeur("P0001", "La présence ne peut être validée avant la fin du dernier créneau planifié."), // source: l.1076
        ExceptionServeur("P0001", "Le planning détaillé doit être terminé avant validation de la présence."), // source: l.1087
        ExceptionServeur("P0001", "Un pointage est encore ouvert pour cette mission."), // source: l.1100
        ExceptionServeur("P0001", "Aucun pointage terminé ne permet de valider cette présence."), // source: l.1114
    ]

    /// RPC → exceptions, dans l'ordre d'extraction (corps, fonctions appelées, triggers nommés).
    public static let parRPC: [String: [ExceptionServeur]] = [
        "fn_mes_permissions_etab": [],
        "fn_mon_etablissement_complet": [],
        "fn_stats_dashboard_etablissement": [],
        "fn_soignant_pour_etablissement": [],
        "fn_lire_candidatures_mission_habilitee": [
            ExceptionServeur("42501", "Mission indisponible ou accès refusé"), // source: supabase/schema/public.sql l.39533, l.39542, l.39553
        ],
        "fn_traiter_candidature_planning_v1": [
            ExceptionServeur("P0001", "Notification d'acceptation impossible : %", .generique), // source: l.61834 (fn_traiter_candidature)
            // source: l.63314 et l.63317 (fn_trg_gate_assignation_paiement, correction 16)
            ExceptionServeur("P0001", "Cette mission ne peut pas être attribuée : l'établissement doit d'abord configurer un mode de paiement (Paramètres → Facturation)."),
            ExceptionServeur("P0001", "Cette mission ne peut pas être attribuée : le mandat SEPA de l'établissement n'est pas encore posé (IBAN à ajouter dans Paramètres → Facturation)."),
            rbac("missions"), rbac("contrats"), rbac("candidatures"),
        ],
        "fn_contrat_signe_pour_pointage": [
            ExceptionServeur("42501", "Lecture du pointage non autorisée."), // source: l.25874, l.25880, l.25887
        ],
        "fn_valider_presence": validationPresence,
        "fn_valider_presences_lot": validationPresence,
        "fn_contester_presence": [rbac("pointage")],
        "fn_creer_notation_mission": [
            ExceptionServeur("P0001", "La notation n’a pas pu être enregistrée. Veuillez réessayer."), // source: l.27425, l.27439
        ],
        "fn_declarer_fin_retroactive": [
            ExceptionServeur("P0002", "Mission % introuvable ou dans un statut incompatible."), // source: l.28687
            ExceptionServeur("42501", "Vous n'êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission."), // source: l.28696
            ExceptionServeur("P0002", "Aucun créneau effectif ouvert à fermer pour cette mission."), // source: l.28709
            ExceptionServeur("23514", "L'heure de fin (%) doit être postérieure au début du créneau (%)."), // source: l.28713
            rbac("pointage"), rbac("missions"),
        ],
        "fn_creer_mission_multi_jours_v4": [
            ExceptionServeur("28000", "Non authentifié", .session), // source: l.27258
        ],
        "fn_obtenir_conversation": [
            ExceptionServeur("28000", "Non authentifié", .session), // source: l.45636
            ExceptionServeur("22023", "Interlocuteur invalide"), // source: l.45640
            ExceptionServeur("42501", "Conversation non autorisée"), // source: l.45679
        ],
    ]

    /// Interceptions d'une RPC du lot 5 : celle du lot 1 (`[CODE DU TRAVAIL]`) d'abord, puis la liste
    /// blanche. Une RPC inconnue n'a que l'interception du lot 1 (comportement inchangé).
    public static func interceptions(rpc: String) -> [RPCInterception] {
        var resultat = RPCInterception.parDefaut
        let exceptions = parRPC[rpc] ?? []
        // 42501 : un groupe par message affiché (serveur, puis chaque message neutre).
        let acces = exceptions.filter { $0.sqlstate == RPCInterception.sqlstateAccesRefuse }
        let accesVerbatim = acces.filter { $0.traitement == .verbatim }.map(\.message)
        if !accesVerbatim.isEmpty {
            resultat.append(.accesRefuse(messagesExacts: accesVerbatim))
        }
        var neutres: [(texte: String, messages: [String])] = []
        for exception in acces {
            guard case let .messageNeutre(texte) = exception.traitement else { continue }
            if let rang = neutres.firstIndex(where: { $0.texte == texte }) {
                neutres[rang].messages.append(exception.message)
            } else {
                neutres.append((texte, [exception.message]))
            }
        }
        for neutre in neutres {
            resultat.append(.accesRefuse(messagesExacts: neutre.messages, messageAffiche: neutre.texte))
        }
        // Refus métier verbatim, un groupe par SQLSTATE dans l'ordre de première apparition.
        let metier = exceptions.filter { $0.sqlstate != RPCInterception.sqlstateAccesRefuse && $0.traitement == .verbatim }
        var sqlstates: [String] = []
        for exception in metier where !sqlstates.contains(exception.sqlstate) {
            sqlstates.append(exception.sqlstate)
        }
        for sqlstate in sqlstates {
            resultat.append(.refusMetier(sqlstate: sqlstate, messagesExacts: metier.filter { $0.sqlstate == sqlstate }.map(\.message)))
        }
        // Session : SQLSTATE seul (28000 signifie toujours une autorisation invalide).
        for exception in exceptions where exception.traitement == .session {
            let interception = RPCInterception.nonAuthentifie(sqlstate: exception.sqlstate)
            if !resultat.contains(interception) { resultat.append(interception) }
        }
        return resultat
    }
}
