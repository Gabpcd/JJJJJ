import Foundation
import Combine

/// Parcours du ❤️ de la vue Swipe (lot 4, T3b ; `LOT4_PLAN.md` §2.5), port de `handleSwipe('LIKE')`,
/// `confirmerRecapitulatif`, `confirmerPremiereCandidature` et `confirmerChoixContrat` de `VueSwipeMissions.tsx`.
/// Seul chemin de l'app vers `SwipeModel.candidater` (garde `SwipeSourcesAppTests`) :
///
/// 1. ❤️ (bouton, geste vers la droite, « Vérifier et postuler » du détail) → **récapitulatif exact**, toujours ;
///    rien n'est envoyé.
/// 2. « Envoyer ma candidature » du récapitulatif : planning non exact → rien (le bouton est désactivé, la règle est
///    revérifiée ici) ; première candidature du compte (`SwipeMarqueurs.premiereCandidatureVue` faux) → **feuille
///    « première candidature »** (HARD STOP n°4, `TextesWeb.PremiereCandidature`), rien n'est envoyé ; sinon envoi.
/// 3. « J'ai compris — envoyer ma candidature » : le marqueur est posé **puis** la candidature est envoyée ; « Pas
///    maintenant » ne pose rien, la feuille reviendra (revue B8 de #1165, m3 : obligatoire avant le premier ❤️ envoyé).
/// 4. Choix de contrat demandé par le serveur → étape `choixContrat` ; l'action est rejouée avec l'option, sans
///    repasser par le récapitulatif ni par la feuille (déjà confirmés pour cette mission, comme le web).
///
/// L'étape reste affichée pendant l'envoi (`envoiEnCours`, feuille non refermable), puis se ferme quelle que soit
/// l'issue, sauf choix de contrat : la candidature relue, le refus ou l'erreur sont publiés par `SwipeModel`
/// (`annonce`, `message`). L'écran rend ainsi tout le parcours dans **une seule feuille**, sans enchaîner deux
/// présentations. L'envoi lui-même (planning exact fail-closed, relecture, refus verbatim, délai, epoch) reste celui
/// de `SwipeModel`.
@MainActor
public final class ParcoursCandidatureSwipe: ObservableObject {
    public enum Etape: Equatable, Sendable {
        case aucune
        /// Récapitulatif exact de la mission (`RecapitulatifCandidatureDialog`).
        case recapitulatif(missionId: String)
        /// Feuille « première candidature », une seule fois par compte.
        case premiereCandidature(missionId: String)
        /// Mode de contrat demandé par le serveur (`ChoixContratDialog`), options dans `SwipeModel.optionsContrat`.
        case choixContrat(missionId: String)

        /// Mission du parcours ouvert, `nil` sans parcours.
        public var missionId: String? {
            switch self {
            case .aucune: return nil
            case let .recapitulatif(missionId), let .premiereCandidature(missionId), let .choixContrat(missionId): return missionId
            }
        }
    }

    public let model: SwipeModel
    @Published public private(set) var etape: Etape = .aucune
    /// Candidature en cours d'envoi depuis ce parcours : boutons en attente, feuille non refermable.
    @Published public private(set) var envoiEnCours = false
    private let marqueurs: SwipeMarqueurs

    public init(model: SwipeModel, marqueurs: SwipeMarqueurs) {
        self.model = model
        self.marqueurs = marqueurs
    }

    /// ❤️ : ouvre le récapitulatif de la carte si elle est encore dans le paquet, qu'aucune action n'est en vol et
    /// qu'aucun parcours n'est déjà ouvert.
    public func demander(_ missionId: String) {
        guard etape == .aucune, model.actionEnCours == nil, model.carteDuPaquet(missionId) != nil else { return }
        model.effacerMessage()
        etape = .recapitulatif(missionId: missionId)
    }

    /// Planning exact de la carte (bouton de confirmation du récapitulatif).
    public func planningExact(_ missionId: String) -> Bool {
        guard let carte = model.carteDuPaquet(missionId) else { return false }
        return PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(mission: carte.mission)).exact
    }

    /// « Envoyer ma candidature » du récapitulatif.
    public func confirmerRecapitulatif() async {
        guard !envoiEnCours, case let .recapitulatif(missionId) = etape, planningExact(missionId) else { return }
        guard marqueurs.premiereCandidatureVue else {
            etape = .premiereCandidature(missionId: missionId)
            return
        }
        await envoyer(missionId, choixContrat: nil)
    }

    /// « J'ai compris — envoyer ma candidature » : marqueur posé, puis envoi.
    public func confirmerPremiereCandidature() async {
        guard !envoiEnCours, case let .premiereCandidature(missionId) = etape else { return }
        marqueurs.marquerPremiereCandidatureVue()
        await envoyer(missionId, choixContrat: nil)
    }

    /// Option de contrat choisie : ❤️ rejoué avec l'option, parmi celles que le serveur a proposées.
    public func choisirContrat(_ valeur: String) async {
        guard !envoiEnCours, case let .choixContrat(missionId) = etape, model.missionChoixContrat == missionId,
              model.optionsContrat.contains(where: { $0.value == valeur }) else { return }
        await envoyer(missionId, choixContrat: valeur)
    }

    /// « Annuler » du récapitulatif, « Pas maintenant » de la feuille, choix de contrat refermé : rien n'est envoyé ni
    /// mémorisé, la carte reste dans le paquet. Sans effet pendant un envoi.
    public func abandonner() {
        guard !envoiEnCours else { return }
        if case .choixContrat = etape { model.annulerChoixContrat() }
        etape = .aucune
    }

    /// Envoi par `SwipeModel.candidater`, étape conservée pendant l'appel ; ensuite : choix de contrat demandé pour cette
    /// mission → étape `choixContrat`, sinon le parcours se ferme (candidature relue, refus ou erreur : `SwipeModel`).
    private func envoyer(_ missionId: String, choixContrat: String?) async {
        envoiEnCours = true
        await model.candidater(missionId, choixContrat: choixContrat)
        envoiEnCours = false
        if model.missionChoixContrat == missionId, !model.optionsContrat.isEmpty {
            etape = .choixContrat(missionId: missionId)
        } else {
            etape = .aucune
        }
    }
}
