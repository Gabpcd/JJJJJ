import Foundation
import Combine

/// « Créer une alerte » en un toucher depuis Explorer (L4-T4), port de `creerAlerteRapide` (`RechercheMissions.tsx`
/// l.172-226) : relecture des recherches (`fn_lister_mes_filtres_sauvegardes`), `AlerteRecherche.preparer` (golden T2 :
/// seule une recherche **strictement identique** est réutilisée, jamais une recherche de même nom), puis
/// - recherche identique déjà en alerte toutes les heures : rien n'est écrit (message du web) ;
/// - recherche identique sans alerte, ou en alerte quotidienne / hebdomadaire : `modifier(alerte: true, IMMEDIATE)` —
///   écart assumé au web, qui laisse une alerte quotidienne en place tout en annonçant « vérifiées toutes les heures » :
///   le natif aligne la fréquence sur la promesse de la confirmation ;
/// - sinon : `creer(nom libre, critères d'Explorer, alerte, IMMEDIATE)`.
/// Succès annoncé seulement si la liste relue montre la recherche en alerte toutes les heures (PRINCIPES §3) ; refus
/// serveur verbatim ; appels bornés (décision 14 du lot 1) ; un second appui pendant l'appel est ignoré ; réponse d'un
/// epoch périmé ignorée ; une annulation n'est jamais une erreur.
@MainActor
public final class AlerteRapideModel: ObservableObject {
    public enum Issue: Equatable, Sendable {
        case confirmee(String)
        case echec(String)
    }

    @Published public private(set) var enCours = false
    @Published public private(set) var issue: Issue?
    /// Jeton d'annonce VoiceOver : change à chaque issue.
    @Published public private(set) var jeton = 0

    private let controller: SessionController
    private let snapshot: SessionSnapshot

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    public func effacerIssue() { issue = nil }

    /// `true` si l'alerte est confirmée par relecture (la confirmation se referme) ; sinon l'échec reste affiché.
    @discardableResult
    public func activer(filtres: ExplorerFiltres, profile: SoignantProfile) async -> Bool {
        guard !enCours else { return false }
        enCours = true
        defer { enCours = false }
        issue = nil
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.filtres
        let context = snapshot.context
        let timeout = controller.resolutionTimeout
        let criteres = FiltresSauvegardesEncodage.criteres(filtres)
        let nomBase = FiltresPresentation.nomBaseAlerte(filtres: filtres, profile: profile)

        let existantes: [FiltreSauvegarde]
        do {
            existantes = try await bounded(timeout: timeout) { try await port.lister(context: context) }
        } catch {
            return await terminer(erreur: error, repli: FiltresTextes.alerteVerificationImpossible)
        }
        guard await controller.epoch == snapshot.epoch else { return false }
        let preparation = AlerteRecherche.preparer(criteres: criteres, recherches: existantes, nomBase: nomBase)

        if let deja = preparation.deja, deja.alerteActive, deja.frequence == .immediate {
            return publier(.confirmee(FiltresTextes.alerteDejaActive))
        }
        let repli = preparation.deja == nil ? FiltresTextes.alerteCreationImpossible : FiltresTextes.alerteActivationImpossible
        do {
            let resultat: IssueFiltre
            if let deja = preparation.deja {
                resultat = try await bounded(timeout: timeout) {
                    try await port.modifier(id: deja.id, nom: deja.nom, alerte: true, frequence: .immediate, context: context)
                }
            } else {
                let nom = preparation.nom
                resultat = try await bounded(timeout: timeout) {
                    try await port.creer(nom: nom, filtres: criteres, alerte: true, frequence: .immediate, context: context)
                }
            }
            guard await controller.epoch == snapshot.epoch else { return false }
            switch resultat {
            case let .refusee(message):
                return publier(.echec(message.isEmpty ? repli : message))
            case let .relue(lignes):
                let cle = AlerteRecherche.cle(AlerteRecherche.valeur(criteres))
                let confirmee = lignes.contains { ligne in
                    ligne.alerteActive && ligne.frequence == .immediate
                        && (preparation.deja.map { ligne.id == $0.id } ?? (ligne.nom == preparation.nom))
                        && AlerteRecherche.cle(ligne.filtres) == cle
                }
                guard confirmee else { return publier(.echec(FiltresTextes.alerteNonConfirmee)) }
                return publier(.confirmee(preparation.deja == nil ? FiltresTextes.alerteCreee : FiltresTextes.alerteDejaActive))
            }
        } catch {
            return await terminer(erreur: error, repli: FiltresTextes.alerteEnregistrementImpossible)
        }
    }

    private func terminer(erreur: Error, repli: String) async -> Bool {
        guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
              let message = FiltresModel.message(pour: erreur, repli: repli) else { return false }
        // Le web affiche son message pour tout échec ; une session expirée garde le sien (« Votre session a expiré »).
        return publier(.echec(message.sessionExpiree ? message.message : repli))
    }

    private func publier(_ nouvelle: Issue) -> Bool {
        issue = nouvelle
        jeton += 1
        if case .confirmee = nouvelle { return true }
        return false
    }
}
