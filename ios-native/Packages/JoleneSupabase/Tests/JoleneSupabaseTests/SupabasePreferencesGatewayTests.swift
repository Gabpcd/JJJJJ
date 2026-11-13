import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Préférences de notifications sur Supabase (lot 3, T6) — fiches `fn_obtenir_mes_preferences_notifications`
/// et `fn_modifier_preferences_notifications` de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`, parité
/// `PageParametresNotifications.tsx` :
/// - lecture : RPC (crée la ligne par défaut, idempotente) + `soignants.select('sms_alertes_actives, type_exercice')`
///   de l'utilisateur de la session (l.122) ; `{error}` jamais un succès ; décodage strict (l.117) ;
/// - écriture : RPC à cinq paramètres, `p_par_evenement` limité au catalogue soignant ; `{success:true}` seul
///   succès ; 22P02 → contrat ; alerte SMS écrite à part (`PATCH soignants`, `return=minimal`) seulement si
///   lue ; puis relecture complète, rendue même si la colonne n'a pas pris (le modèle annonce l'échec partiel) ;
/// - une seule requête par appel, aucun renvoi.
final class SupabasePreferencesGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let lecture = "/rest/v1/rpc/fn_obtenir_mes_preferences_notifications"
    private let ecriture = "/rest/v1/rpc/fn_modifier_preferences_notifications"
    private let soignants = "/rest/v1/soignants"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabasePreferencesGateway { SupabasePreferencesGateway(client: TestClient.make()) }

    private static let preferencesJSON = """
    {"global":{"canal_email":true,"canal_sms":false,"canal_push":true,"canal_in_app":true,
               "cree_le":"2026-10-01T08:00:00+00:00","mis_a_jour_le":"2026-10-02T08:00:00+00:00"},
     "par_evenement":[{"type_evenement":"LITIGE_RESOLU","canal":"PUSH","actif":false}]}
    """
    private static let soignantJSON = #"{"sms_alertes_actives":true,"type_exercice":"SALARIE"}"#

    private static let attendues = PreferencesNotifications(
        canalEmail: true, canalSms: false, canalPush: true, canalInApp: true,
        parEvenement: [PreferenceEvenement(typeEvenement: "LITIGE_RESOLU", canal: .push, actif: false)],
        smsAlertesActives: true, typeExercice: "SALARIE")

    private func stubLecture(preferences: String = preferencesJSON, soignant: StubResponse = .json(200, soignantJSON)) {
        registry.add("POST", lecture, respond: .json(200, preferences))
        registry.add("GET", soignants, respond: soignant)
    }

    private func erreur(_ operation: () async throws -> Void) async -> JoleneError? {
        do {
            try await operation()
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
            return nil
        }
    }

    // MARK: - Lecture

    func testLectureRPCPuisLigneSoignantDeLaSession() async throws {
        stubLecture()
        let lu = try await gateway().lire(context: TestClient.context)
        XCTAssertEqual(lu, Self.attendues)
        let rpc = try XCTUnwrap(registry.requests(to: lecture).first)
        XCTAssertEqual(rpc.method, "POST")
        XCTAssertEqual(registry.requests(to: lecture).count, 1)
        let ligne = try XCTUnwrap(registry.requests(to: soignants).first)
        XCTAssertEqual(ligne.query("select"), "sms_alertes_actives,type_exercice", "colonnes du web (l.122)")
        XCTAssertEqual(ligne.query("id"), "eq.\(TestClient.userId)", "utilisateur de la session, jamais un autre")
        XCTAssertEqual(ligne.header("Accept"), "application/vnd.pgrst.object+json", "maybeSingle")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testLigneSoignantAbsenteAlerteNonAffichee() async throws {
        stubLecture(soignant: .json(406, """
        {"code":"PGRST116","details":"The result contains 0 rows","hint":null,"message":"JSON object requested, multiple (or no) rows returned"}
        """))
        let lu = try await gateway().lire(context: TestClient.context)
        XCTAssertNil(lu.smsAlertesActives, "`profilSmsPresent` faux (l.130)")
        XCTAssertNil(lu.typeExercice)
    }

    func testNonAuthentifieEstUneSessionExpiree() async {
        stubLecture(preferences: #"{"error":"Non authentifié"}"#)
        let e = await erreur { _ = try await self.gateway().lire(context: TestClient.context) }
        XCTAssertEqual(e?.kind, .unauthorized)
    }

    func testReponseIllisibleOuLigneSoignantEnEchecSontDesErreursDEcran() async {
        stubLecture(preferences: #"{"global":{"canal_email":true,"canal_sms":false,"canal_push":true},"par_evenement":[]}"#)
        let illisible = await erreur { _ = try await self.gateway().lire(context: TestClient.context) }
        XCTAssertEqual(illisible, JoleneError(.contract, PreferencesNotifications.messageIndisponible))

        registry.reset()
        stubLecture(soignant: .json(500, #"{"code":"XX000","details":null,"hint":null,"message":"panne"}"#))
        let ligne = await erreur { _ = try await self.gateway().lire(context: TestClient.context) }
        XCTAssertNotNil(ligne, "la ligne soignants en échec fait échouer l'écran (web l.123)")
        XCTAssertEqual(registry.requests(to: soignants).count, 1, "aucun renvoi d'une erreur 500")
    }

    func testFonctionIntrouvableEstUnRefusDeContrat() async {
        registry.add("POST", lecture, respond: .json(404, """
        {"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.fn_obtenir_mes_preferences_notifications in the schema cache"}
        """))
        registry.add("GET", soignants, respond: .json(200, Self.soignantJSON))
        let e = await erreur { _ = try await self.gateway().lire(context: TestClient.context) }
        XCTAssertEqual(e?.kind, .contract)
        XCTAssertEqual(registry.requests(to: lecture).count, 1)
    }

    func testContexteIncoherentRefuseSansRequete() async {
        let autre = MissionReadContext(userId: TestClient.userId, email: nil, profile: SoignantProfile(id: "autre", profession: "IDE"))
        let e = await erreur { _ = try await self.gateway().lire(context: autre) }
        XCTAssertEqual(e?.kind, .unauthorized)
        XCTAssertTrue(registry.requests.isEmpty)
    }

    // MARK: - Écriture

    private func stubEcriture(_ reponse: StubResponse = .json(200, #"{"success":true}"#),
                              patch: StubResponse = StubResponse(status: 204, headers: [:], body: Data(), failure: nil)) {
        registry.add("POST", ecriture, respond: reponse)
        registry.add("PATCH", soignants, respond: patch)
    }

    func testEnregistrementCorpsExactPuisAlerteSmsPuisRelecture() async throws {
        var demande = Self.attendues
        demande.canalSms = true
        demande.basculer(type: "CANDIDATURE_ACCEPTEE", canal: .sms)
        demande.smsAlertesActives = false
        demande.parEvenement.append(PreferenceEvenement(typeEvenement: "URGENCE", canal: .email, actif: false))
        stubEcriture()
        stubLecture(preferences: """
        {"global":{"canal_email":true,"canal_sms":true,"canal_push":true,"canal_in_app":true},
         "par_evenement":[{"type_evenement":"LITIGE_RESOLU","canal":"PUSH","actif":false},
                          {"type_evenement":"CANDIDATURE_ACCEPTEE","canal":"SMS","actif":false},
                          {"type_evenement":"URGENCE","canal":"EMAIL","actif":true}]}
        """, soignant: .json(200, #"{"sms_alertes_actives":false,"type_exercice":"SALARIE"}"#))

        let relu = try await gateway().enregistrer(demande, context: TestClient.context)

        let rpc = try XCTUnwrap(registry.requests(to: ecriture).first)
        let corps = try XCTUnwrap(rpc.bodyJSON as? [String: Any])
        XCTAssertEqual(Set(corps.keys), ["p_canal_email", "p_canal_sms", "p_canal_push", "p_canal_in_app", "p_par_evenement"])
        XCTAssertEqual(corps["p_canal_email"] as? Bool, true)
        XCTAssertEqual(corps["p_canal_sms"] as? Bool, true)
        XCTAssertEqual(corps["p_canal_push"] as? Bool, true)
        XCTAssertEqual(corps["p_canal_in_app"] as? Bool, true)
        let lignes = try XCTUnwrap(corps["p_par_evenement"] as? [[String: Any]])
        XCTAssertEqual(lignes.map { "\($0["type_evenement"] as? String ?? "?"):\($0["canal"] as? String ?? "?"):\($0["actif"] as? Bool ?? true)" },
                       ["LITIGE_RESOLU:PUSH:false", "CANDIDATURE_ACCEPTEE:SMS:false"], "seuls les types du catalogue soignant")
        XCTAssertTrue(lignes.allSatisfy { $0.count == 3 })

        let patch = try XCTUnwrap(registry.requests(to: soignants).first { $0.method == "PATCH" })
        XCTAssertEqual(patch.query("id"), "eq.\(TestClient.userId)")
        XCTAssertEqual((patch.bodyJSON as? [String: Any])?.keys.sorted(), ["sms_alertes_actives"], "colonne accordée seule (GRANT l.85758)")
        XCTAssertEqual((patch.bodyJSON as? [String: Any])?["sms_alertes_actives"] as? Bool, false)
        XCTAssertEqual(patch.header("Prefer"), "return=minimal", "comme supabase-js : aucune ligne renvoyée")

        let ordre = registry.requests.map { "\($0.method) \($0.path)" }
        XCTAssertEqual(ordre, ["POST \(ecriture)", "PATCH \(soignants)", "POST \(lecture)", "GET \(soignants)"],
                       "RPC, puis colonne, puis relecture ; aucun renvoi")
        XCTAssertEqual(relu.smsAlertesActives, false)
        XCTAssertFalse(relu.estActif(type: "CANDIDATURE_ACCEPTEE", canal: .sms))
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testAlerteNonLueJamaisEcrite() async throws {
        var demande = Self.attendues
        demande.smsAlertesActives = nil
        stubEcriture()
        stubLecture()
        _ = try await gateway().enregistrer(demande, context: TestClient.context)
        XCTAssertFalse(registry.requests.contains { $0.method == "PATCH" }, "web l.230 : `profilSmsPresent` faux")
    }

    func testRefusServeurVerbatimSansColonneNiRelecture() async {
        stubEcriture(.json(200, #"{"error":"Préférences verrouillées"}"#))
        let e = await erreur { _ = try await self.gateway().enregistrer(Self.attendues, context: TestClient.context) }
        XCTAssertEqual(e, JoleneError(.unknown, "Préférences verrouillées"))
        XCTAssertEqual(registry.requests.map(\.path), [ecriture], "ni colonne ni relecture après un refus")
    }

    func testNonAuthentifieALEcriture() async {
        stubEcriture(.json(200, #"{"error":"Non authentifié"}"#))
        let e = await erreur { _ = try await self.gateway().enregistrer(Self.attendues, context: TestClient.context) }
        XCTAssertEqual(e?.kind, .unauthorized)
    }

    func testReponseSansSuccesVraiNEstJamaisUnSucces() async {
        for corps in ["{}", #"{"success":false}"#, #"{"success":"true"}"#, "null"] {
            registry.reset()
            stubEcriture(.json(200, corps))
            let e = await erreur { _ = try await self.gateway().enregistrer(Self.attendues, context: TestClient.context) }
            XCTAssertEqual(e, JoleneError(.unknown, PreferencesTextes.echecEnregistrement), corps)
            XCTAssertEqual(registry.requests.map(\.path), [ecriture], corps)
        }
    }

    func testValeurHorsEnum22P02EstUnRefusDeContrat() async {
        stubEcriture(.json(400, #"{"code":"22P02","details":null,"hint":null,"message":"invalid input value for enum type_evenement_notification: \"X\""}"#))
        let e = await erreur { _ = try await self.gateway().enregistrer(Self.attendues, context: TestClient.context) }
        XCTAssertEqual(e, JoleneError(.contract, SupabaseErrorMapping.contractMessage))
        XCTAssertFalse(e?.message.contains("invalid input") ?? true, "aucun détail technique affiché")
        XCTAssertEqual(registry.requests.map(\.path), [ecriture])
    }

    func testColonneEnEchecRelitQuandMemeEtRendLEtatServeur() async throws {
        var demande = Self.attendues
        demande.smsAlertesActives = false
        stubEcriture(patch: .json(500, #"{"code":"XX000","details":null,"hint":null,"message":"panne"}"#))
        stubLecture()
        let relu = try await gateway().enregistrer(demande, context: TestClient.context)
        XCTAssertEqual(relu.smsAlertesActives, true, "valeur serveur relue : le modèle annonce l'échec partiel")
        XCTAssertEqual(relu.concordance(avec: demande), ConcordancePreferences(generales: true, alerteSms: false))
        XCTAssertEqual(registry.requests(to: soignants).filter { $0.method == "PATCH" }.count, 1, "aucun renvoi")
    }

    func testErreurReseauALEcriture() async {
        stubEcriture(.networkFailure())
        let e = await erreur { _ = try await self.gateway().enregistrer(Self.attendues, context: TestClient.context) }
        XCTAssertEqual(e?.kind, .network)
        XCTAssertEqual(registry.requests(to: ecriture).count, 1, "aucun renvoi d'une mutation")
    }

    func testCableDansLeMondeSupabase() {
        XCTAssertTrue(SupabaseGateways.make(client: TestClient.make()).preferences is SupabasePreferencesGateway)
    }
}
