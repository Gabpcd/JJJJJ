import Foundation

/// Port de `navigationPathForEvent` (`src/lib/pushNative.ts` l.251-315, avec `valeurTexte`,
/// `segment` et `lienExplicite` l.16-23, l.59-66) : chemin web d'une notification push, que le
/// coordinateur push du lot 3 passe ensuite à `LinkRouter.resolve(link:)`.
///
/// - un lien explicite (`lien`, puis `link`, puis `url`) normalisé par `JoleneLink.normalize`
///   gagne toujours, sauf la racine « / » quand un type permet un repli métier (ancien dispatcher) ;
/// - sinon le type d'événement et le rôle donnent une route déclarée dans `src/App.tsx` ;
/// - seules les chaînes non vides après `trim` comptent ; les identifiants sont encodés comme par
///   `encodeURIComponent`.
///
/// Le rôle est la valeur brute (`SOIGNANT`, `ADMIN_ETABLISSEMENT`, `ETABLISSEMENT`, `ADMIN_PLATEFORME`,
/// `ADMIN`…) : le natif le lit dans le snapshot de session au lieu d'appeler `fn_get_my_role`.
/// Écart connu de la table web conservé à l'identique : `PAIEMENT_RECU` mène à
/// `/soignant/mes-gains?tab=paiements`, onglet absent du web (correction 15 du blueprint) ;
/// c'est l'écran Revenus qui choisit la section.
public enum PushRouting {
    /// Types routés, dans l'ordre des `case` du web (garde de dérive : vecteur `typesRoutes`).
    public static let typesRoutes: [String] = [
        "CONTRAT_A_SIGNER", "CONTRAT_SIGNE", "CONTRAT_REJETE",
        "CANDIDATURE_RECUE", "CANDIDATURE_ANNULEE_SOIGNANT",
        "CANDIDATURE_ACCEPTEE", "CANDIDATURE_REFUSEE", "MISSION_ANNULEE_ETAB",
        "MISSION_ASSIGNEE", "MISSION_URGENTE", "MISSION_RAPPEL", "RAPPEL_MISSION", "RAPPEL_MISSION_J1",
        "MISSION_RAPPEL_J1", "POINTAGE_MANQUANT", "POOL_URGENCE_NOTIFICATIONS_ENVOYEES", "URGENCE", "POOL_URGENCE",
        "MISSION_A_POURVOIR", "NOUVELLE_MISSION_MATCHANT_FILTRE", "FAVORI_NOUVELLE_MISSION",
        "FACTURE_EMISE",
        "PAIEMENT_RECU", "PAIEMENT_RECLAME",
        "LITIGE_OUVERT", "LITIGE_RESOLU", "NOUVEAU_MESSAGE_LITIGE",
        "DPAE_RAPPEL", "DPAE_ANNULATION_RAPPEL", "DPAE_NON_REGULARISEE_POINTAGE",
        "RECLAMATION_SCORE_DECISION",
        "ALERTE_ADMIN",
    ]

    /// Chemin web d'un payload dont seules les valeurs textuelles sont fournies.
    public static func path(data: [String: String], role: String?) -> String? {
        let type = valeurTexte(data["type_evenement"])
        if let lien = lienExplicite(data, type: type) { return lien }

        let missionId = segment(data["mission_id"])
        let contratId = segment(data["contrat_id"])
        let factureId = segment(data["facture_id"])
        let litigeId = segment(data["litige_id"])
        let estEtab = role == "ADMIN_ETABLISSEMENT" || role == "ETABLISSEMENT"
        let estAdmin = role == "ADMIN_PLATEFORME" || role == "ADMIN"

        guard let type else { return nil }
        switch type {
        case "CONTRAT_A_SIGNER", "CONTRAT_SIGNE", "CONTRAT_REJETE":
            if let contratId { return "/contrat/\(contratId)" }
            return estEtab ? "/etablissement/contrats" : "/soignant/mes-documents?tab=contrats"
        case "CANDIDATURE_RECUE", "CANDIDATURE_ANNULEE_SOIGNANT":
            return missionId.map { "/etablissement/missions/\($0)" } ?? "/etablissement/missions"
        case "CANDIDATURE_ACCEPTEE", "CANDIDATURE_REFUSEE", "MISSION_ANNULEE_ETAB":
            return missionId.map { "/soignant/missions/\($0)" } ?? "/soignant/missions"
        case "MISSION_ASSIGNEE", "MISSION_URGENTE", "MISSION_RAPPEL", "RAPPEL_MISSION", "RAPPEL_MISSION_J1",
             "MISSION_RAPPEL_J1", "POINTAGE_MANQUANT", "POOL_URGENCE_NOTIFICATIONS_ENVOYEES", "URGENCE", "POOL_URGENCE":
            return missionId.map { "/soignant/missions/\($0)" } ?? "/soignant/missions"
        case "MISSION_A_POURVOIR", "NOUVELLE_MISSION_MATCHANT_FILTRE", "FAVORI_NOUVELLE_MISSION":
            return missionId.map { "/soignant/missions/\($0)" } ?? "/soignant/recherche-missions"
        case "FACTURE_EMISE":
            if estEtab { return factureId.map { "/etablissement/facturation/\($0)" } ?? "/etablissement/facturation" }
            return "/soignant/mes-gains?tab=factures"
        case "PAIEMENT_RECU", "PAIEMENT_RECLAME":
            return estEtab ? "/etablissement/facturation" : "/soignant/mes-gains?tab=paiements"
        case "LITIGE_OUVERT", "LITIGE_RESOLU", "NOUVEAU_MESSAGE_LITIGE":
            let base = estAdmin ? "/admin/litiges" : estEtab ? "/etablissement/litiges" : "/soignant/litiges"
            return litigeId.map { "\(base)#\($0)" } ?? base
        case "DPAE_RAPPEL", "DPAE_ANNULATION_RAPPEL", "DPAE_NON_REGULARISEE_POINTAGE":
            if let contratId { return "/contrat/\(contratId)" }
            return estEtab ? "/etablissement/contrats" : "/soignant/mes-documents?tab=dpae"
        case "RECLAMATION_SCORE_DECISION":
            return estEtab ? "/etablissement/mes-reclamations" : "/soignant/litiges?tab=reclamations"
        case "ALERTE_ADMIN":
            return "/admin/reclamations?tab=score"
        default:
            return nil
        }
    }

    /// Variante `userInfo` d'APNs : seules les clés et valeurs textuelles sont lues (`aps` et toute
    /// valeur non textuelle sont ignorées, comme `valeurTexte` côté web).
    public static func path(userInfo: [AnyHashable: Any], role: String?) -> String? {
        var data: [String: String] = [:]
        for (cle, valeur) in userInfo {
            guard let cle = cle as? String, let texte = valeur as? String else { continue }
            data[cle] = texte
        }
        return path(data: data, role: role)
    }

    /// `lienExplicite` : la racine « / » n'est retenue que sans type d'événement.
    static func lienExplicite(_ data: [String: String], type: String?) -> String? {
        guard let lien = valeurTexte(data["lien"]) ?? valeurTexte(data["link"]) ?? valeurTexte(data["url"]),
              let normalise = JoleneLink.normalize(lien) else { return nil }
        return normalise != "/" || type == nil ? normalise : nil
    }

    /// `valeurTexte` : texte non vide après `trim`, rendu sans ses espaces.
    static func valeurTexte(_ valeur: String?) -> String? {
        guard let valeur else { return nil }
        let texte = PrimitivesJS.trim(valeur)
        return texte.isEmpty ? nil : texte
    }

    /// `segment` : `valeurTexte` encodé par `encodeURIComponent`.
    static func segment(_ valeur: String?) -> String? {
        valeurTexte(valeur).map(PrimitivesJS.encodeURIComponent)
    }
}
