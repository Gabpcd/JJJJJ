import Foundation
import JoleneCore

/// Lecture des réponses jsonb des RPC de l'espace établissement (lot 5 §2.5). Mêmes règles que le lot 1
/// (`RPCResponse`) : messages serveur verbatim (HARD STOP n°4), aucun succès supposé, aucune clé exigée
/// sauf celles qui conditionnent une action.
public extension RPCResponse {
    /// Codes renvoyés par `fn_blocage_publication_etab` (`supabase/schema/public.sql` l.20685-20746) sous
    /// la forme `{error: CODE, message: texte}` et relayés tels quels par `fn_creer_mission_multi_jours`
    /// (l.26892, correction 8). Comparés au dump par `RPCResponseEtablissementTests`.
    static let codesBlocagePublication: Set<String> = [
        "ETABLISSEMENT_NON_VERIFIE", "VERIFICATION_INCOMPLETE", "CONTRAT_SERVICE_REQUIS",
        "PUBLICATION_SUSPENDUE", "FACTURES_IMPAYEES",
    ]

    /// Blocage de publication : `error` ∈ `codesBlocagePublication` avec un `message` non vide, sans
    /// `success:true`. La clé `error` porte alors un **code**, jamais à afficher.
    var blocagePublication: (code: String, message: String)? {
        guard success != true, let code = erreur, Self.codesBlocagePublication.contains(code),
              let message = string("message"), !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return (code, message)
    }

    /// Texte à afficher pour un refus : `message` prioritaire quand `error` est un code de blocage de
    /// publication (§2.5), sinon `error` verbatim ; nil sans message.
    var messageRefus: String? {
        blocagePublication?.message ?? erreur
    }

    /// Issue de `fn_traiter_candidature_planning_v1` (§2.5, fiche `CONTRATS_RPC_ETABLISSEMENT.md`), appelée
    /// avec `ListesBlanchesEtablissement.interceptions(rpc:)` :
    /// - « Non authentifié » (refus structuré ou non) → `.unauthorized` levée ;
    /// - refus de droit intercepté (42501 en liste blanche, RBAC compris) → `.accesRefuse` ;
    /// - P0001 de la garde de paiement interceptée (l.63314, l.63317) → `.paiementNonConfigure` verbatim ;
    /// - `PLANNING_A_RECONFIRMER` / `PLANNING_MODIFIE_RECONFIRMER` → `.planningAReconfirmer` ;
    /// - `CADRE_ETUDIANT_A_CONFIRMER` → `.cadreEtudiant` (renvoi web) ; tout autre refus structuré
    ///   (autres `CADRE_ETUDIANT_*`, `[CODE DU TRAVAIL]`, choix de contrat ou documents requis relayés,
    ///   délégué interne) → `.refusee` verbatim ;
    /// - `{error}` sans drapeau (`fn_traiter_candidature`, « Non autorisé », « Cette candidature a déjà
    ///   été traitée. ») → `JoleneError(.unknown)` verbatim, comme le lot 1 ;
    /// - `success:true` → `.acceptee(contratId:)` ou `.refusEnregistre` selon la décision envoyée ;
    /// - toute autre forme → refus de contrat, jamais un succès supposé.
    /// L'issue ne vaut pas confirmation : l'écran relit la lecture habilitée (PRINCIPES §3).
    func issueTraitementCandidature(decision: DecisionCandidature, fallback: String) throws -> TraitementCandidatureOutcome {
        try leverSiErreur(fallback: fallback)
        if estRefus {
            let message = erreur ?? fallback
            if estAccesRefuse { return .accesRefuse(message: message) }
            if estRefusMetier {
                guard ListesBlanchesEtablissement.paiementNonConfigure.contains(message) else {
                    throw JoleneError(.unknown, fallback)
                }
                return .paiementNonConfigure(message: message)
            }
            if let code, Self.codesPlanningAReconfirmer.contains(code) {
                return .planningAReconfirmer(code: code, message: message)
            }
            if let code, code == TraitementCandidatureOutcome.codeCadreEtudiantAConfirmer {
                return .cadreEtudiant(code: code, message: message)
            }
            return .refusee(code: code, message: message, documentsRequisPour: documentsRequisPour)
        }
        guard estSucces else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        switch decision {
        case .acceptee: return .acceptee(contratId: string("contrat_id"))
        case .refusee: return .refusEnregistre
        }
    }
}

public extension ListesBlanchesEtablissement {
    /// Messages P0001 de `fn_trg_gate_assignation_paiement` relayés verbatim avec un renvoi Safari vers la
    /// facturation (correction 16) : les deux refus de paiement de `fn_traiter_candidature_planning_v1`.
    static var paiementNonConfigure: [String] {
        (parRPC["fn_traiter_candidature_planning_v1"] ?? [])
            .filter { $0.sqlstate == "P0001" && $0.traitement == .verbatim }
            .map(\.message)
    }
}
