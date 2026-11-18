import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurStripe = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                  emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                  appMetadataRole: "SOIGNANT")

/// Stripe Connect (lot 3, T14a, B9 ; liste de tests du blueprint §3 T14a, côté cœur) :
/// - `COMPLET` sans ses trois drapeaux, statut hors des six valeurs → statut indisponible (règle du web l.53-54) ;
/// - `est_compte_test` lu → écran du compte de test **sans** appel d'edge ; salarié → mode salarié sans appel d'edge ;
/// - `TEST_ACCOUNT_PAYMENT_DISABLED` rendu par l'edge → écran du compte de test ;
/// - toute issue du flux hébergé (retour ou fermeture) → statut relu avec `force=true` ;
/// - textes verbatim épinglés à leur ligne web (HARD STOP n°4, T14a-J1).
/// L'en-tête `Origin` et le 403 `ORIGINE_NON_AUTORISEE` sont prouvés côté Supabase (`SupabaseStripeConnectGatewayTests`).
@MainActor
final class StripeConnectTests: XCTestCase {
    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurStripe }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw nonScripte }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    /// Port scripté : exercice fixe, statuts en file, journal des appels.
    private final class ScriptedStripe: StripeConnectPort, @unchecked Sendable {
        private let lock = NSLock()
        private let exerciceLu: ExerciceConnect
        private var statuts: [StatutConnect]
        private let lien: ResultatLienConnect
        private var journal: [String] = []

        init(exercice: ExerciceConnect, statuts: [StatutConnect] = [], lien: ResultatLienConnect = .lien(URL(string: "https://connect.stripe.com/x")!)) {
            exerciceLu = exercice; self.statuts = statuts; self.lien = lien
        }

        var appels: [String] { lock.lock(); defer { lock.unlock() }; return journal }
        private func noter(_ appel: String) { lock.lock(); journal.append(appel); lock.unlock() }

        func exercice(context: MissionReadContext) async throws -> ExerciceConnect {
            noter("exercice")
            return exerciceLu
        }

        func statut(force: Bool, context: MissionReadContext) async throws -> StatutConnect {
            noter("statut force=\(force)")
            guard let suivant = suivant() else { throw nonScripte }
            return suivant
        }

        private func suivant() -> StatutConnect? {
            lock.lock(); defer { lock.unlock() }
            return statuts.isEmpty ? nil : statuts.removeFirst()
        }

        func lienOnboarding(context: MissionReadContext) async throws -> ResultatLienConnect {
            noter("onboard")
            return lien
        }
    }

    private struct FluxScripte: ExternalFlowPort {
        let issue: IssueFlux
        func ouvrir(url: URL, retour: RetourAttendu) async -> IssueFlux {
            XCTAssertEqual(retour, .stripeConnect)
            return issue
        }
    }

    private static let mixte = ExerciceConnect(typeExercice: "MIXTE", estCompteTest: false)

    private static func statut(_ s: StatutOnboardingConnect) -> StatutConnect {
        let complet = s == .complet
        return StatutConnect(statut: s, onboardingComplete: complet, chargesEnabled: complet, payoutsEnabled: complet)
    }

    private func modele(_ port: ScriptedStripe, flux: ExternalFlowPort? = nil) async throws -> StripeConnectModel {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.stripeConnect = port
        let controller = SessionController(gateways: gateways)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return StripeConnectModel(controller: controller, snapshot: snapshot, flux: flux)
    }

    // MARK: - Lecture du statut (`StatutConnect.lire`)

    func testCompletSansLesTroisDrapeauxEstIndisponible() {
        XCTAssertNil(StatutConnect.lire(statut: "COMPLET", onboardingComplete: true, chargesEnabled: true, payoutsEnabled: false))
        XCTAssertNil(StatutConnect.lire(statut: "COMPLET", onboardingComplete: nil, chargesEnabled: true, payoutsEnabled: true))
        let complet = StatutConnect.lire(statut: "COMPLET", onboardingComplete: true, chargesEnabled: true, payoutsEnabled: true,
                                         ibanLast4: "0189")
        XCTAssertEqual(complet?.statut, .complet)
        XCTAssertEqual(complet?.ibanLast4, "0189")
        XCTAssertEqual(StatutConnect.lire(statut: "EN_COURS", onboardingComplete: false, chargesEnabled: false,
                                          payoutsEnabled: false, ibanLast4: "")?.ibanLast4, nil, "`|| null` (l.58)")
    }

    func testStatutHorsDesSixValeursEstIndisponible() {
        for brut in ["INCONNU", "complet", "", nil] as [String?] {
            XCTAssertNil(StatutConnect.lire(statut: brut, onboardingComplete: false, chargesEnabled: false, payoutsEnabled: false),
                         "\(String(describing: brut))")
        }
        let rejete = StatutConnect.lire(statut: "REJETE", onboardingComplete: false, chargesEnabled: false, payoutsEnabled: false,
                                        disabledReason: nil, premiereExigence: "individual.verification.document")
        XCTAssertEqual(rejete?.disabledReason, "individual.verification.document", "motif : première exigence (l.60)")
    }

    // MARK: - Modèle

    func testCompteTestLuSansAppelDEdge() async throws {
        let port = ScriptedStripe(exercice: ExerciceConnect(typeExercice: "LIBERAL", estCompteTest: true))
        let model = try await modele(port)
        await model.charger(force: true)
        XCTAssertEqual(model.etat, .compteTest)
        await model.lancerOnboarding()
        XCTAssertEqual(model.avis, .info(StripeConnectTextes.avisCompteTest))
        await model.actualiser()
        XCTAssertEqual(port.appels, ["exercice"], "compte de test : aucun appel d'edge")
    }

    func testSalarieSansAppelDEdge() async throws {
        let port = ScriptedStripe(exercice: ExerciceConnect(typeExercice: "SALARIE", statutLiberal: "ACTIF", estCompteTest: false))
        let model = try await modele(port)
        await model.charger(force: false)
        XCTAssertEqual(model.etat, .salarie, "`statut_liberal` ne rend pas la section Stripe (l.178)")
        await model.lancerOnboarding()
        XCTAssertEqual(port.appels, ["exercice"])
        XCTAssertTrue(ExerciceConnect(typeExercice: "SALARIE", statutLiberal: "ACTIF").entreeHub, "entrée du hub : l.45-48")
        XCTAssertFalse(ExerciceConnect(typeExercice: "SALARIE").entreeHub)
    }

    func testTestAccountPaymentDisabledMeneALEcranDuCompteTest() async throws {
        let port = ScriptedStripe(exercice: Self.mixte, statuts: [Self.statut(.nonDemande)], lien: .compteTest)
        let model = try await modele(port, flux: FluxScripte(issue: .ferme))
        await model.charger(force: false)
        XCTAssertEqual(model.etat, .statut(Self.statut(.nonDemande)))
        await model.lancerOnboarding()
        XCTAssertEqual(model.etat, .compteTest)
        XCTAssertEqual(model.avis, .info(StripeConnectTextes.avisCompteTest))
        XCTAssertEqual(port.appels, ["exercice", "statut force=false", "onboard"])
    }

    func testToutIssueDuFluxRelitLeStatutAvecForce() async throws {
        for issue in [IssueFlux.ferme, .retour(URL(string: "https://jolene.app/soignant/stripe-connect?success=true")!)] {
            let port = ScriptedStripe(exercice: Self.mixte, statuts: [Self.statut(.nonDemande), Self.statut(.complet)])
            let model = try await modele(port, flux: FluxScripte(issue: issue))
            await model.charger(force: false)
            await model.lancerOnboarding()
            XCTAssertEqual(port.appels, ["exercice", "statut force=false", "onboard", "statut force=true"], "\(issue)")
            XCTAssertEqual(model.etat, .statut(Self.statut(.complet)), "seul le statut relu fait foi")
            XCTAssertFalse(model.enCours)
        }
    }

    func testRetourDeStripeEtActualiserLisentAvecForce() async throws {
        let port = ScriptedStripe(exercice: Self.mixte, statuts: [Self.statut(.enCours), Self.statut(.complet)])
        let model = try await modele(port)
        await model.charger(force: true)
        await model.actualiser()
        XCTAssertEqual(port.appels, ["exercice", "statut force=true", "statut force=true"])
        XCTAssertEqual(model.etat, .statut(Self.statut(.complet)))
        await model.actualiser()
        XCTAssertEqual(model.etat, .statutIndisponible, "statut illisible : jamais un défaut")
    }

    // MARK: - Textes (HARD STOP n°4, T14a-J1)

    /// Chaque texte repris du web est sur sa ligne (balises retirées, lignes jointes par une espace) : une PR web qui
    /// change l'un d'eux rougit ce test.
    func testTextesVerbatimASaLigneWeb() throws {
        let web = try CompteVerbatimTests.lignes("src/pages/PageStripeConnect.tsx")
        func ligne(_ numero: Int) -> String {
            web[numero - 1].replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        typealias T = StripeConnectTextes
        let cas: [(String, [Int])] = [
            (T.titre, [185]), (T.profilIndisponible, [171]), (T.reessayer, [173]), (T.reessayer, [320]),
            (T.statutIndisponible, [317]), (T.salarieTitre, [208]), (T.salarieTexte, [210]), (T.salarieEtapesTitre, [216]),
            (T.salarieEtapes[0], [220]), (T.salarieEtapes[1], [224]), (T.salarieEtapes[2], [228]), (T.salarieEtapes[3], [232]),
            (T.salarieInfoTitre, [289]), (T.salarieInfoTexte, [291, 292]), (T.compteTestTitre, [307]),
            (T.compteTestTexte, [309]), (T.nonDemandeTitre, [328]), (T.nonDemandeTexte, [330]),
            (T.nonDemandeAvantages[0], [333]), (T.nonDemandeAvantages[1], [334]), (T.nonDemandeAvantages[2], [335]),
            (T.connecter, [339]), (T.enCoursTitre, [350]), (T.reprendreInscription, [358]), (T.actualiserStatut, [361]),
            (T.completTitre, [374]), (T.actualiser, [382]), (T.suspenduTitre, [448]), (T.completerProfil, [455]),
            (T.supprimeTitre, [466]), (T.supprimeTexte, [468, 469, 470]), (T.recommencer, [476]), (T.rejeteTitre, [497]),
            (T.reprendreVerification, [510]), (T.avisCompteTest, [125]), (T.avisCompteTest, [138]),
            (T.avisNonLiberal, [129]), (T.avisPasserEnLiberal, [143]), (T.erreurConnexionStripe, [146]),
            (T.lienMesGains, [246]), (T.lienMesGains, [425]), (T.lienMesGainsLiberal, [426]), (T.lienPresences, [257]),
            (T.lienPresencesDetail, [258]), (T.lienContrats, [268]), (T.lienContratsDetail, [269]),
            (T.lienPasserEnLiberal, [279]), (T.lienCharges, [433]), (T.lienChargesDetail, [434]),
        ]
        for (texte, lignes) in cas {
            let source = lignes.map(ligne).joined(separator: " ")
            XCTAssertTrue(source.contains(texte), "« \(texte) » absent de PageStripeConnect.tsx l.\(lignes) : « \(source) »")
        }
        XCTAssertTrue(ligne(376).contains("IBAN ****{ibanLast4}"), "l.376")
        XCTAssertTrue(ligne(504).contains("Motif : {motifRejet}"), "l.504")
        let hub = try CompteVerbatimTests.lignes("src/pages/MonCompteSoignant.tsx")
        XCTAssertTrue(hub[67].contains("'\(T.entreeHub)'"), "MonCompteSoignant.tsx l.68")
        XCTAssertTrue(hub[64].contains("'\(T.sectionHub)'"), "MonCompteSoignant.tsx l.65")
        // « Aucun frais pour le soignant » (l.335) relu contre le circuit live : commission en `application_fee_amount`,
        // ajoutée au débit de l'établissement (T14a-J1).
        let debit = try CompteVerbatimTests.source("supabase/functions/escrow-debit-echeance/index.ts")
        XCTAssertTrue(debit.contains("application_fee_amount: commissionCents,"))
    }
}
