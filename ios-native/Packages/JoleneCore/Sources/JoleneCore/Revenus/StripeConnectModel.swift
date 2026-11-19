import Foundation
import Combine

/// Modèle de l'écran Stripe Connect (`/soignant/stripe-connect`, lot 3, T14a, B9), port de `src/pages/PageStripeConnect.tsx`.
///
/// Règles (blueprint §2.5 « Stripe Connect », D6, D7, correction 17 ; PRINCIPES §3) :
/// - l'exercice (`soignants`) est lu d'abord ; un salarié (`isLiberal` faux, l.178) voit le mode salarié et un compte de
///   test la carte « Stripe désactivé sur ce compte de test » (l.302-314), **sans aucun appel d'edge** ; une lecture en
///   échec donne « Profil de paiement indisponible » (l.167-176), jamais un mode d'exercice déduit (l.93) ;
/// - le statut vient de `stripe-connect-status` seul, forcé (`force=true`) au retour de Stripe (lien `?success=` ou
///   `?refresh=` reçu), sur « Actualiser » et après **toute** issue du flux hébergé : l'issue du flux n'est jamais un
///   succès, seul le statut relu fait foi ;
/// - « Connecter » / « Reprendre » : `stripe-connect-onboard` puis le flux hébergé (`ExternalFlowPort`) ; une seule
///   action à la fois (`enCours`, posé avant tout `await`) ; `TEST_ACCOUNT_PAYMENT_DISABLED` → écran du compte de test ;
///   refus « libéral » → avis du web l.143 ; autre refus → texte serveur ; erreur de transport → message de l'erreur ;
///   aucun nouveau lien n'est demandé sans tap (lien `?refresh=true` compris) ;
/// - lecture bornée au délai de la session, epoch vérifié avant toute publication ; une annulation n'est jamais une erreur.
@MainActor
public final class StripeConnectModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case profilIndisponible
        /// Ni `LIBERAL` ni `MIXTE` (`isLiberal` faux) : mode salarié, sans appel d'edge.
        case salarie
        /// `est_compte_test` lu, ou `TEST_ACCOUNT_PAYMENT_DISABLED` rendu par l'edge.
        case compteTest
        case statutIndisponible
        case statut(StatutConnect)
    }

    /// Avis d'une action (toasts du web) : information ou erreur, texte affiché tel quel.
    public enum Avis: Equatable, Sendable {
        case info(String)
        case erreur(String)

        public var texte: String {
            switch self {
            case .info(let texte), .erreur(let texte): return texte
            }
        }
    }

    @Published public private(set) var etat: Etat = .chargement
    @Published public private(set) var enCours = false
    @Published public private(set) var avis: Avis?
    /// Jeton d'annonce de l'avis (un même avis répété est réannoncé).
    @Published public private(set) var numeroAvis = 0

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private let flux: ExternalFlowPort?
    private var exercice: ExerciceConnect?
    private var generation = 0

    /// `flux` nil (aperçus, tests sans flux) : « Connecter » reste sans effet visible autre qu'un avis d'erreur.
    public init(controller: SessionController, snapshot: SessionSnapshot, flux: ExternalFlowPort?) {
        self.controller = controller
        self.snapshot = snapshot
        self.flux = flux
    }

    // MARK: - Lecture

    /// Apparition de l'écran (ou retour par lien) : exercice, puis statut pour un libéral hors compte de test ; forcé au
    /// retour de Stripe (`chargerStatut(retourStripe)`, l.107-109).
    public func charger(force: Bool) async {
        generation += 1
        let courant = generation
        etat = .chargement
        guard let gateways = await controller.gateways(for: snapshot.epoch), generation == courant else { return }
        let port = gateways.stripeConnect
        let context = snapshot.context
        let lu: ExerciceConnect
        do {
            lu = try await bounded(timeout: controller.resolutionTimeout) { try await port.exercice(context: context) }
        } catch {
            guard await memeEpoch(), generation == courant, !Self.estAnnulation(error) else { return }
            etat = .profilIndisponible
            return
        }
        guard await memeEpoch(), generation == courant else { return }
        exercice = lu
        if !lu.estLiberal {
            etat = .salarie
        } else if lu.compteTest {
            etat = .compteTest
        } else {
            await lireStatut(force: force, generation: courant)
        }
    }

    /// « Actualiser », « Actualiser le statut » et « Réessayer » du statut indisponible : relecture forcée (l.156-164).
    public func actualiser() async {
        guard !enCours, let exercice, exercice.estLiberal, !exercice.compteTest else { return }
        enCours = true
        defer { enCours = false }
        generation += 1
        await lireStatut(force: true, generation: generation)
    }

    // MARK: - Onboarding hébergé

    /// « Connecter mon compte bancaire », « Reprendre l'inscription Stripe », « Compléter mon profil Stripe »,
    /// « Recommencer l'onboarding », « Reprendre ma vérification » (`lancerOnboarding`, l.123-154).
    public func lancerOnboarding() async {
        guard !enCours, let exercice else { return }
        if exercice.compteTest {
            publier(.info(StripeConnectTextes.avisCompteTest))
            return
        }
        guard exercice.estLiberal else {
            publier(.info(StripeConnectTextes.avisNonLiberal))
            return
        }
        enCours = true
        avis = nil
        defer { enCours = false }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.stripeConnect
        let context = snapshot.context
        do {
            let resultat = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.lienOnboarding(context: context)
            }
            guard await memeEpoch() else { return }
            switch resultat {
            case .lien(let url):
                guard let flux else {
                    publier(.erreur(StripeConnectTextes.erreurConnexionStripe))
                    return
                }
                // Le flux dure le temps de l'utilisateur : jamais borné. Son issue (retour ou fermeture) n'est jamais un
                // succès : le statut est relu, forcé, dans tous les cas.
                _ = await flux.ouvrir(url: url, retour: .stripeConnect)
                guard await memeEpoch() else { return }
                generation += 1
                await lireStatut(force: true, generation: generation)
            case .compteTest:
                etat = .compteTest
                publier(.info(StripeConnectTextes.avisCompteTest))
            case .nonEligible:
                publier(.info(StripeConnectTextes.avisPasserEnLiberal))
            case .refuse(_, let message):
                publier(.erreur(message))
            }
        } catch {
            guard await memeEpoch(), !Self.estAnnulation(error) else { return }
            publier(.erreur((error as? JoleneError)?.message ?? StripeConnectTextes.erreurConnexionStripe))
        }
    }

    // MARK: - Interne

    private func lireStatut(force: Bool, generation courant: Int) async {
        guard let gateways = await controller.gateways(for: snapshot.epoch), generation == courant else { return }
        let port = gateways.stripeConnect
        let context = snapshot.context
        do {
            let statut = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.statut(force: force, context: context)
            }
            guard await memeEpoch(), generation == courant else { return }
            etat = .statut(statut)
        } catch {
            guard await memeEpoch(), generation == courant, !Self.estAnnulation(error) else { return }
            etat = .statutIndisponible
        }
    }

    private func publier(_ nouveau: Avis) {
        avis = nouveau
        numeroAvis += 1
    }

    private func memeEpoch() async -> Bool { await controller.epoch == snapshot.epoch }

    private static func estAnnulation(_ error: Error) -> Bool {
        error is CancellationError || (error as? JoleneError)?.kind == .cancelled
    }
}
