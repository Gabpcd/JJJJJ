import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Publication d'une mission sur Supabase (lot 5, T9 ; `LOT5_PLAN.md` §3 T9) : corps exact de
/// `fn_creer_mission_multi_jours_v4` (les seize paramètres de la signature SQL versionnée, aucun de plus, valeurs du
/// périmètre natif D8), une seule requête, `{success:true}` jamais tenu pour confirmé sans relecture égale à l'envoi,
/// relecture divergente ou impossible → jamais un succès, blocages de publication (`message` mot pour mot), refus du
/// serveur mot pour mot (`PLAFOND_48H_HEBDO`, `CREATION_MISSION_INDISPONIBLE`), `28000` → session, brouillon hors
/// périmètre refusé avant tout appel.
final class SupabaseEtabPublicationGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let etab = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let missionId = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
    private let rpc = "/rest/v1/rpc/fn_creer_mission_multi_jours_v4"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseEtabPublicationGateway { SupabaseEtabPublicationGateway(client: TestClient.make()) }

    private func contexte() -> EtablissementReadContext {
        EtablissementReadContext(userId: TestClient.userId, etablissementId: etab, roleEtab: .rh,
                                 permissions: PermissionsEtab(accordees: [.lecture, .missions, .candidatures]), epoch: 1)
    }

    private let envoi = [CreneauConfirme(debut: "2026-11-25T06:00:00Z", fin: "2026-11-25T18:00:00Z"),
                         CreneauConfirme(debut: "2026-11-26T06:00:00Z", fin: "2026-11-26T18:00:00Z")]

    private func brouillon(profession: String = "IDE", urgente: Bool = true, description: String? = "Renfort [SERIE_ID:x]",
                           creneaux: [CreneauConfirme]? = nil) -> PublicationMission {
        PublicationMission(intitule: "IDE de nuit", description: description, professionRequise: profession, service: "Urgences",
                           tauxHoraireBase: 30.5, estUrgente: urgente, creneaux: creneaux ?? envoi, niveauUrgence: 2,
                           modeAttribution: .candidature)
    }

    private func exception(_ sqlstate: String, _ message: String) -> String {
        #"{"code":"\#(sqlstate)","details":null,"hint":null,"message":"\#(message)"}"#
    }

    private func succesJSON(mission: String? = nil) -> String {
        #"{"success":true,"mission_id":"\#(mission ?? missionId)","nb_creneaux":2,"total_heures":24,"type_contrat_recherche":"SALARIE","mode_remuneration":"TAUX_HORAIRE","retrocession_pct":null,"nature_tva_prestation":null,"statut_validation_tva":"NON_REQUISE","accepte_internes":false}"#
    }

    /// Relecture servie : mission et créneaux tels que PostgREST les rend (`+00:00`, ordre du serveur).
    private func stubRelecture(statut: String = "OUVERTE", contrat: String = "SALARIE", nbCreneaux: Int = 2,
                               creneaux: [(String, String)]? = nil) {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, """
        {"id":"\(missionId)","etablissement_id":"\(etab)","statut":"\(statut)","nb_creneaux":\(nbCreneaux),
         "debut_le":"2026-11-25T06:00:00+00:00","fin_le":"2026-11-26T18:00:00+00:00","type_contrat_recherche":"\(contrat)"}
        """))
        let lignes = (creneaux ?? [("2026-11-25T06:00:00+00:00", "2026-11-25T18:00:00+00:00"),
                                   ("2026-11-26T06:00:00+00:00", "2026-11-26T18:00:00+00:00")])
            .enumerated().map { rang, c in TestClient.slotJSON(id: "c-\(rang)", missionId: missionId, debut: c.0, fin: c.1) }
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(
            200, "[\(lignes.joined(separator: ","))]", headers: ["Content-Range": "0-\(max(lignes.count - 1, 0))/\(lignes.count)"]))
    }

    private func echec(_ appel: () async throws -> Void) async -> JoleneError? {
        do {
            try await appel()
            XCTFail("attendu : erreur levée")
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
            return nil
        }
    }

    // MARK: - Charge

    /// Paramètres de la signature SQL versionnée (`ios-native/rpc-contracts.json`, extraite du dump par
    /// `check-rpc-contracts.mjs`) : une signature qui change côté serveur rougit ce test.
    func testSeizeClesDeLaSignatureSQL() throws {
        let json = try JSONSerialization.jsonObject(with: Depot.donnees("ios-native/rpc-contracts.json")) as? [String: Any]
        let rpcs = try XCTUnwrap(json?["rpcs"] as? [[String: Any]])
        let contrat = try XCTUnwrap(rpcs.first { $0["name"] as? String == SupabaseEtabPublicationGateway.rpc })
        let signature = try XCTUnwrap((contrat["sql"] as? [[String: Any]])?.first?["signature"] as? String)
        let expression = try NSRegularExpression(pattern: "\"(p_[a-z_]+)\" ")
        let parametres = expression.matches(in: signature, range: NSRange(signature.startIndex..., in: signature)).compactMap {
            Range($0.range(at: 1), in: signature).map { String(signature[$0]) }
        }
        XCTAssertEqual(parametres.count, 16)
        XCTAssertEqual(PublicationPayload.cles, parametres, "les seize paramètres de la signature SQL, dans l'ordre")
        XCTAssertEqual(contrat["statut"] as? String, "consommee", "RPC consommée par T9")
    }

    func testCorpsExactUneSeuleRequeteEtRelectureEgale() async throws {
        registry.add("POST", rpc, respond: .json(200, succesJSON()))
        stubRelecture()
        let issue = try await gateway().publier(brouillon(), context: contexte())
        XCTAssertEqual(issue, .publiee(missionId: missionId))

        XCTAssertEqual(registry.requests(to: rpc).count, 1, "une seule requête, aucun renvoi")
        let corps = try XCTUnwrap(registry.requests(to: rpc).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(Set(corps.keys), Set(PublicationPayload.cles), "exactement les seize paramètres, aucun de plus")
        XCTAssertEqual(corps["p_intitule"] as? String, "IDE de nuit")
        XCTAssertEqual(corps["p_description"] as? String, "Renfort", "balise de série purgée, aucune balise de contrat envoyée")
        XCTAssertEqual(corps["p_profession_requise"] as? String, "IDE")
        XCTAssertEqual(corps["p_service"] as? String, "Urgences")
        XCTAssertEqual(corps["p_taux_horaire_base"] as? Double, 30.5)
        XCTAssertEqual(corps["p_est_urgente"] as? Bool, true)
        XCTAssertEqual(corps["p_niveau_urgence"] as? Int, 2)
        XCTAssertEqual(corps["p_mode_attribution"] as? String, "CANDIDATURE")
        XCTAssertEqual(corps["p_accepte_non_specialises"] as? Bool, true)
        XCTAssertEqual(corps["p_type_contrat_recherche"] as? String, "SALARIE")
        XCTAssertEqual(corps["p_mode_remuneration"] as? String, "TAUX_HORAIRE")
        XCTAssertEqual(corps["p_accepte_internes"] as? Bool, false)
        for nul in ["p_specialite_medicale_requise", "p_retrocession_pct", "p_nature_tva_prestation"] {
            XCTAssertTrue(corps[nul] is NSNull, "\(nul) : null explicite")
        }
        XCTAssertEqual(corps["p_creneaux"] as? [[String: String]], [
            ["debut": "2026-11-25T06:00:00Z", "fin": "2026-11-25T18:00:00Z"],
            ["debut": "2026-11-26T06:00:00Z", "fin": "2026-11-26T18:00:00Z"],
        ], "créneaux {debut, fin} seulement, UTC sans fraction")
        XCTAssertNil(corps["p_etablissement_id"], "le serveur agit sur mon_etablissement_id()")

        let lecture = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(lecture.query("select"), "id,etablissement_id,statut,nb_creneaux,debut_le,fin_le,type_contrat_recherche",
                       "relecture sans aucun montant")
        XCTAssertEqual(lecture.query("id"), "eq.\(missionId)")
        XCTAssertEqual(lecture.query("etablissement_id"), "eq.\(etab)", "établissement confirmé")
        XCTAssertEqual(try XCTUnwrap(registry.requests(to: "/rest/v1/mission_creneaux").first).query("type_creneau"), "eq.PREVISIONNEL")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testNonUrgenteEtSpecialisationExacte() async throws {
        registry.add("POST", rpc, respond: .json(200, succesJSON()))
        stubRelecture()
        _ = try await gateway().publier(brouillon(profession: "IADE", urgente: false, description: nil), context: contexte())
        let corps = try XCTUnwrap(registry.requests(to: rpc).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["p_est_urgente"] as? Bool, false)
        XCTAssertEqual(corps["p_niveau_urgence"] as? Int, 0)
        XCTAssertEqual(corps["p_accepte_non_specialises"] as? Bool, false, "IADE : spécialisation exacte")
        XCTAssertTrue(corps["p_description"] is NSNull)
    }

    // MARK: - Relecture

    func testRelectureDivergenteJamaisUnSucces() async throws {
        let divergences: [(String, () -> Void)] = [
            ("type de contrat modifié côté serveur", { self.stubRelecture(contrat: "TOUS") }),
            ("statut inattendu", { self.stubRelecture(statut: "ANNULEE_PAR_ETABLISSEMENT") }),
            ("nombre de créneaux", { self.stubRelecture(nbCreneaux: 3) }),
            ("créneau différent", { self.stubRelecture(creneaux: [("2026-11-25T06:00:00+00:00", "2026-11-25T18:00:00+00:00"),
                                                                    ("2026-11-26T06:00:00+00:00", "2026-11-26T17:00:00+00:00")]) }),
            ("créneau manquant", { self.stubRelecture(creneaux: [("2026-11-25T06:00:00+00:00", "2026-11-25T18:00:00+00:00")]) }),
        ]
        for (cas, stub) in divergences {
            registry.reset()
            registry.add("POST", rpc, respond: .json(200, succesJSON()))
            stub()
            let issue = try await gateway().publier(brouillon(), context: contexte())
            XCTAssertEqual(issue, .nonConfirmee(missionId: missionId), cas)
            XCTAssertEqual(registry.requests(to: rpc).count, 1, "\(cas) : aucun renvoi")
        }
    }

    func testRelectureImpossibleOuMissionIllisibleJamaisUnSucces() async throws {
        // Lecture en panne après la création : la mission existe peut-être, jamais « publiée ».
        registry.add("POST", rpc, respond: .json(200, succesJSON()))
        registry.add("GET", "/rest/v1/missions", respond: .json(500, #"{"message":"panne"}"#))
        let panne = try await gateway().publier(brouillon(), context: contexte())
        XCTAssertEqual(panne, .nonConfirmee(missionId: missionId))

        // Planning invérifiable (compte absent).
        registry.reset()
        registry.add("POST", rpc, respond: .json(200, succesJSON()))
        registry.add("GET", "/rest/v1/missions", respond: .json(200, """
        {"id":"\(missionId)","etablissement_id":"\(etab)","statut":"OUVERTE","nb_creneaux":2,
         "debut_le":"2026-11-25T06:00:00+00:00","fin_le":"2026-11-26T18:00:00+00:00","type_contrat_recherche":"SALARIE"}
        """))
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, "[]"))
        let sansPlanning = try await gateway().publier(brouillon(), context: contexte())
        XCTAssertEqual(sansPlanning, .nonConfirmee(missionId: missionId))

        // Mission d'un autre établissement rendue par la relecture.
        registry.reset()
        registry.add("POST", rpc, respond: .json(200, succesJSON()))
        registry.add("GET", "/rest/v1/missions", respond: .json(200, """
        {"id":"\(missionId)","etablissement_id":"00000000-1111-4222-8333-444444444444","statut":"OUVERTE","nb_creneaux":2,
         "debut_le":"2026-11-25T06:00:00+00:00","fin_le":"2026-11-26T18:00:00+00:00","type_contrat_recherche":"SALARIE"}
        """))
        let autre = try await gateway().publier(brouillon(), context: contexte())
        XCTAssertEqual(autre, .nonConfirmee(missionId: missionId))
        XCTAssertTrue(registry.requests(to: "/rest/v1/mission_creneaux").isEmpty)
    }

    func testSuccesSansIdentifiantExploitableRefusDeContrat() async throws {
        for corps in [#"{"success":true}"#, #"{"success":true,"mission_id":"pas-un-uuid"}"#, "null", "[]"] {
            registry.reset()
            registry.add("POST", rpc, respond: .json(200, corps))
            let erreur = await echec { _ = try await self.gateway().publier(self.brouillon(), context: self.contexte()) }
            XCTAssertEqual(erreur?.kind, .contract, corps)
            XCTAssertTrue(registry.requests(to: "/rest/v1/missions").isEmpty, "aucune relecture sans identifiant")
        }
    }

    // MARK: - Refus du serveur

    func testBlocagesDePublicationMessagePrioritaire() async throws {
        let blocages = [
            ("ETABLISSEMENT_NON_VERIFIE", "Votre établissement doit être vérifié avant de publier des missions."),
            ("VERIFICATION_INCOMPLETE", "Les contrôles SIRET, FINESS, identité et habilitation du représentant doivent être validés."),
            ("CONTRAT_SERVICE_REQUIS", "Le contrat de service Jolene doit être signé avant de publier des missions."),
            ("PUBLICATION_SUSPENDUE", "Publication suspendue en raison d obligations de paiement à régulariser."),
            ("FACTURES_IMPAYEES", "Vous avez des factures impayées à régulariser."),
        ]
        XCTAssertEqual(Set(blocages.map(\.0)), RPCResponse.codesBlocagePublication)
        for (code, message) in blocages {
            registry.reset()
            registry.add("POST", rpc, respond: .json(200, #"{"error":"\#(code)","message":"\#(message)","siret_verifie":false}"#))
            let issue = try await gateway().publier(brouillon(), context: contexte())
            XCTAssertEqual(issue, .blocageEtablissement(code: code, message: message), "le code n'est jamais le texte affiché")
            XCTAssertTrue(registry.requests(to: "/rest/v1/missions").isEmpty, "aucune relecture d'une publication bloquée")
        }
    }

    func testRefusMotPourMot() async throws {
        let cas: [(String, PublicationOutcome)] = [
            (#"{"success":false,"error":"Le planning dépasse 48 h pour la semaine du 23/11/2026.","code":"PLAFOND_48H_HEBDO","semaine_du":"2026-11-23","heures":60}"#,
             .refusee(code: "PLAFOND_48H_HEBDO", message: "Le planning dépasse 48 h pour la semaine du 23/11/2026.")),
            (#"{"success":false,"error":"La création de la mission est temporairement indisponible.","code":"CREATION_MISSION_INDISPONIBLE"}"#,
             .refusee(code: "CREATION_MISSION_INDISPONIBLE", message: "La création de la mission est temporairement indisponible.")),
            (#"{"success":false,"error":"La mission ne peut pas commencer dans le passé."}"#,
             .refusee(code: nil, message: "La mission ne peut pas commencer dans le passé.")),
            (#"{"success":false,"error":"Deux créneaux de la mission se chevauchent."}"#,
             .refusee(code: nil, message: "Deux créneaux de la mission se chevauchent.")),
            // `fn_blocage_publication_etab` sans code de blocage : refus sans drapeau, texte serveur.
            (#"{"error":"Établissement introuvable"}"#, .refusee(code: nil, message: "Établissement introuvable")),
            (#"{"success":false}"#, .refusee(code: nil, message: SupabaseEtabPublicationGateway.fallback)),
        ]
        for (json, attendu) in cas {
            registry.reset()
            registry.add("POST", rpc, respond: .json(200, json))
            let issue = try await gateway().publier(brouillon(), context: contexte())
            XCTAssertEqual(issue, attendu, json)
            XCTAssertEqual(registry.requests(to: rpc).count, 1)
            XCTAssertTrue(registry.requests(to: "/rest/v1/missions").isEmpty, "aucune relecture d'un refus")
        }
    }

    func testNonAuthentifieSessionJamaisUnRefusMetier() async throws {
        registry.add("POST", rpc, respond: .json(400, exception("28000", "Non authentifié")))
        let exceptionLevee = await echec { _ = try await self.gateway().publier(self.brouillon(), context: self.contexte()) }
        XCTAssertEqual(exceptionLevee?.kind, .unauthorized, "28000 de la liste blanche")

        registry.reset()
        registry.add("POST", rpc, respond: .json(200, #"{"success":false,"error":"Non authentifié."}"#))
        let refus = await echec { _ = try await self.gateway().publier(self.brouillon(), context: self.contexte()) }
        XCTAssertEqual(refus?.kind, .unauthorized)
    }

    // MARK: - Avant tout appel

    func testBrouillonHorsPerimetreRefuseAvantReseau() async throws {
        let invalides = [brouillon(profession: "MEDECIN"), brouillon(profession: ""), brouillon(creneaux: []),
                         PublicationMission(intitule: "ab", description: nil, professionRequise: "IDE", service: nil,
                                            tauxHoraireBase: 30, estUrgente: false, creneaux: envoi),
                         PublicationMission(intitule: "IDE de nuit", description: nil, professionRequise: "IDE", service: nil,
                                            tauxHoraireBase: 0, estUrgente: false, creneaux: envoi),
                         PublicationMission(intitule: "IDE de nuit", description: nil, professionRequise: "IDE", service: nil,
                                            tauxHoraireBase: 30, estUrgente: true, creneaux: envoi, niveauUrgence: 4)]
        for invalide in invalides {
            let erreur = await echec { _ = try await self.gateway().publier(invalide, context: self.contexte()) }
            XCTAssertEqual(erreur?.kind, .contract)
        }
        let contexteInvalide = EtablissementReadContext(userId: TestClient.userId, etablissementId: " ", roleEtab: .rh,
                                                        permissions: .aucune, epoch: 1)
        let session = await echec { _ = try await self.gateway().publier(self.brouillon(), context: contexteInvalide) }
        XCTAssertEqual(session?.kind, .unauthorized)
        XCTAssertTrue(registry.requests.isEmpty, "aucun appel pour un brouillon hors périmètre natif (D8)")
    }
}
