import Foundation

/// Issue d'une réconciliation du reçu en attente, partagée par toutes les instances qui l'attendent ; chaque
/// `DocumentsModel` l'applique à son propre état (publication, relecture, suivi).
enum ResultatReconciliationDocument: Equatable, Sendable {
    /// Aucun reçu dans le journal.
    case aucunRecu
    /// Reçu `prepared` (marqué `not_sent`) ou terminé, effacé sans aucun appel.
    case efface
    /// Issue relue par la gateway ; reçu effacé, sauf issue incertaine (gardé `started`).
    case issue(IssueEnvoiDocument)
    /// Journal illisible, ou reçu impossible à effacer après l'issue : fail-closed, renvoi web.
    case illisible
    /// Relecture impossible (transport, délai, session) : reçu gardé, réconcilié au prochain passage.
    case echec(sessionExpiree: Bool)
}

/// Essais d'envoi de justificatif en vol, à l'échelle du processus (revue fraîche de T6, M1-bis).
///
/// Le journal de reçus n'a qu'une clé par utilisateur et par domaine (`CleRecu`), partagée par tout le processus, alors
/// qu'un `DocumentsModel` vit avec son écran : plusieurs instances coexistent pour un même utilisateur (écran fermé
/// puis rouvert pendant un upload lent, deux fenêtres sur iPad, nouvel epoch de la même personne). Ce registre est la
/// seule garde du « un seul envoi à la fois » et de « une seule réconciliation à la fois » :
/// - un envoi est inscrit AVANT tout reçu (`prepared`) et retiré par sa propre tâche quand elle se termine ;
/// - aucune instance ne réconcilie tant qu'un envoi est inscrit pour la clé, ni n'en lance un second : elle affiche
///   l'envoi en vol et en reprend l'issue (`Envoi.tache`) ;
/// - une réconciliation inscrite est partagée par tout appelant de la même clé, puis retirée par sa tâche.
///
/// Isolé au main actor, comme `DocumentsModel` : contrôle et inscription se font sans suspension, donc sans
/// entrelacement possible entre deux instances. `DocumentsModel` n'utilise jamais d'autre registre que `processus`.
@MainActor
final class EssaisDocumentsEnVol {
    static let processus = EssaisDocumentsEnVol()

    struct Envoi {
        let typeDocument: String
        /// Corps de l'envoi ; sa valeur est l'état final publié par l'instance qui envoie.
        let tache: Task<DocumentsModel.EtatEnvoi, Never>
    }

    private var envois: [CleRecu: Envoi] = [:]
    private var reconciliations: [CleRecu: Task<ResultatReconciliationDocument, Never>] = [:]

    /// Envoi inscrit pour cette clé, quelle que soit l'instance qui l'a lancé.
    func envoi(_ cle: CleRecu) -> Envoi? { envois[cle] }

    /// Inscrit et lance l'envoi ; nil (rien n'est lancé) si un envoi est déjà inscrit pour la clé.
    func demarrerEnvoi(_ cle: CleRecu, typeDocument: String,
                       _ operation: @escaping @MainActor @Sendable () async -> DocumentsModel.EtatEnvoi)
        -> Task<DocumentsModel.EtatEnvoi, Never>? {
        guard envois[cle] == nil else { return nil }
        let tache = Task { @MainActor in
            let fin = await operation()
            self.envois[cle] = nil
            return fin
        }
        envois[cle] = Envoi(typeDocument: typeDocument, tache: tache)
        return tache
    }

    /// Réconciliation en cours pour cette clé, ou nouvelle réconciliation inscrite et lancée. L'appelant a vérifié
    /// qu'aucun envoi d'une autre instance n'est inscrit (`envoi(_:)`) ; seul l'envoi qui la demande lui-même (étape 1)
    /// peut être inscrit.
    func reconciliation(_ cle: CleRecu,
                        sinon operation: @escaping @MainActor @Sendable () async -> ResultatReconciliationDocument)
        -> Task<ResultatReconciliationDocument, Never> {
        if let enCours = reconciliations[cle] { return enCours }
        let tache = Task { @MainActor in
            let resultat = await operation()
            self.reconciliations[cle] = nil
            return resultat
        }
        reconciliations[cle] = tache
        return tache
    }
}
