import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Litiges sur Supabase (lot 4, T8) — fiches `fn_ouvrir_litige_rate_limited` (« Usage du lot 4 ») et
/// `fn_ajouter_message_litige` de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` :
/// - `litiges` lue par colonnes explicites (jamais `*`), mission jointe, noms par `fn_etablissements_safe` ;
/// - ouverture par trois clés exactes, type `AUTRE` ; refus `{error}` mot pour mot (motif trop court, fenêtre de
///   contestation fermée, doublon, plafond horaire), « Non authentifié » → session expirée ;
/// - succès sans `litige_id`, ou litige jamais relu → contrat (aucun succès fabriqué) ;
/// - message : `message_id` exigé, fil relu qui le contient ; refus mot pour mot ;
/// - une seule requête d'écriture par appel, aucun renvoi.
final class SupabaseLitigesGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let litiges = "/rest/v1/litiges"
    private let messages = "/rest/v1/messages_litige"
    private let missions = "/rest/v1/missions"
    private let etablissements = "/rest/v1/rpc/fn_etablissements_safe"
    private let rpcOuverture = "/rest/v1/rpc/fn_ouvrir_litige_rate_limited"
    private let rpcMessage = "/rest/v1/rpc/fn_ajouter_message_litige"
    private let mission = "5a1b2c3d-0000-4000-8000-00000000000a"
    private let litige = "7f0c8a0e-1111-4b1c-9e0a-7f3c1d2e5a66"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseLitigesGateway { SupabaseLitigesGateway(client: TestClient.make()) }

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

    private var listeJSON: String {
        """
        [{"id":"\(litige)","mission_id":"\(mission)","etablissement_id":"etab-1","statut":"OUVERT","type_litige":"AUTRE",
          "motif":"Désaccord sur les heures","resolution":null,"cree_le":"2026-11-01T04:00:00+00:00",
          "missions":{"id":"\(mission)","intitule":"Remplacement IDE nuit","debut_le":"2026-10-30T07:00:00+00:00"}},
         {"id":"l-2","mission_id":"m-2","etablissement_id":"etab-absent","statut":"RESOLU_ACCORD_PARTIES","type_litige":"AUTRE",
          "motif":"Pause","resolution":"Accord trouvé.","cree_le":"2026-10-10T04:00:00+00:00","missions":null}]
        """
    }

    // MARK: - Lecture

    func testListeParColonnesExplicitesEtNomsParFnEtablissementsSafe() async throws {
        registry.add("GET", litiges, respond: .json(200, listeJSON))
        registry.add("POST", etablissements, respond: .json(200, TestClient.etablissementJSON))
        let liste = try await gateway().lister(context: TestClient.context)
        XCTAssertEqual(liste, [
            Litige(id: litige, missionId: mission, etablissementId: "etab-1", statut: "OUVERT", typeLitige: "AUTRE",
                   motif: "Désaccord sur les heures", creeLe: "2026-11-01T04:00:00+00:00", missionIntitule: "Remplacement IDE nuit",
                   missionDebutLe: "2026-10-30T07:00:00+00:00", etablissementNom: "Clinique des Tests"),
            Litige(id: "l-2", missionId: "m-2", etablissementId: "etab-absent", statut: "RESOLU_ACCORD_PARTIES", typeLitige: "AUTRE",
                   motif: "Pause", resolution: "Accord trouvé.", creeLe: "2026-10-10T04:00:00+00:00"),
        ], "ordre serveur gardé ; nom absent : l'écran affiche « Établissement non disponible »")

        let lecture = try XCTUnwrap(registry.requests(to: litiges).first)
        XCTAssertEqual(lecture.query("select"), SupabaseLitigesGateway.colonnes)
        XCTAssertEqual(lecture.query("select"),
                       "id,mission_id,etablissement_id,statut,type_litige,motif,resolution,cree_le,missions(id,intitule,debut_le)")
        XCTAssertFalse(lecture.query("select")?.contains("*") ?? true, "jamais `select=*`")
        for interdite in ["montant", "payload", "facture", "etablissements"] {
            XCTAssertFalse(lecture.query("select")?.contains(interdite) ?? true, "\(interdite) : ni montant, ni accord, ni embed d'établissement")
        }
        XCTAssertEqual(lecture.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(lecture.query("order"), "cree_le.desc.nullsfirst", "`order(cree_le, desc)` du web")
        let noms = try XCTUnwrap(registry.requests(to: etablissements).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(noms["p_ids"] as? [String], ["etab-1", "etab-absent"])
        XCTAssertEqual(registry.requests.count, 2)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testNomsIndisponiblesNeCachentPasLesLitigesEtSessionExpireeRelevee() async throws {
        registry.add("GET", litiges, respond: .json(200, listeJSON))
        registry.add("POST", etablissements, respond: .json(500, #"{"message":"erreur"}"#))
        let liste = try await gateway().lister(context: TestClient.context)
        XCTAssertEqual(liste.map(\.id), [litige, "l-2"])
        XCTAssertEqual(liste.map(\.etablissementNom), [nil, nil])

        registry.reset()
        registry.add("GET", litiges, respond: .json(200, listeJSON))
        registry.add("POST", etablissements, respond: .json(401, #"{"message":"JWT expired","code":"PGRST301"}"#))
        let expiree = await erreur { _ = try await self.gateway().lister(context: TestClient.context) }
        XCTAssertEqual(expiree?.kind, .unauthorized)

        registry.reset()
        registry.add("GET", litiges, respond: .json(500, #"{"message":"erreur"}"#))
        let lecture = await erreur { _ = try await self.gateway().lister(context: TestClient.context) }
        XCTAssertEqual(lecture?.message, "Impossible de charger les litiges.", "erreur de lecture : jamais une liste vide")
    }

    func testMissionsProposeesSansCellesDejaEnLitige() async throws {
        registry.add("GET", missions, respond: .json(200, """
        [{"id":"\(mission)","intitule":"Remplacement IDE nuit","debut_le":"2026-10-30T07:00:00+00:00",
          "fin_le":"2026-10-30T19:00:00+00:00","etablissement_id":"etab-1"},
         {"id":"m-2","intitule":"Garde","debut_le":"2026-10-20T07:00:00+00:00","fin_le":"2026-10-20T19:00:00+00:00",
          "etablissement_id":"etab-1"}]
        """))
        registry.add("GET", litiges, respond: .json(200, #"[{"mission_id":"m-2"},{"mission_id":null}]"#))
        registry.add("POST", etablissements, respond: .json(200, TestClient.etablissementJSON))
        let proposees = try await gateway().missionsContestables(context: TestClient.context)
        XCTAssertEqual(proposees, [MissionContestable(id: mission, intitule: "Remplacement IDE nuit",
                                                      debutLe: "2026-10-30T07:00:00+00:00", etablissementId: "etab-1",
                                                      etablissementNom: "Clinique des Tests")],
                       "une mission qui a déjà un litige n'est pas proposée")

        let lecture = try XCTUnwrap(registry.requests(to: missions).first)
        XCTAssertEqual(lecture.query("select"), "id,intitule,debut_le,fin_le,etablissement_id")
        XCTAssertEqual(lecture.query("soignant_assigne_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(lecture.query("statut"), "in.(TERMINEE,EN_COURS)")
        XCTAssertEqual(lecture.query("order"), "fin_le.desc.nullsfirst")
        XCTAssertEqual(lecture.query("limit"), "50")
        let enLitige = try XCTUnwrap(registry.requests(to: litiges).first)
        XCTAssertEqual(enLitige.query("select"), "mission_id")
        XCTAssertEqual(enLitige.query("soignant_id"), "eq.\(TestClient.userId)")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    // MARK: - Ouverture

    func testOuvertureParTroisClesTypeAutrePuisRelectureParIdentifiant() async throws {
        registry.add("POST", rpcOuverture, respond: .json(200,
            #"{"success":true,"litige_id":"\#(litige)","est_informatif":false,"facture_id":null}"#))
        registry.add("GET", litiges, respond: .json(200, #"[{"id":"\#(litige)"}]"#))
        let issue = try await gateway().ouvrir(missionId: mission, motif: "  Désaccord sur les heures \n", context: TestClient.context)
        XCTAssertEqual(issue, .ouvert(id: litige, informatif: false))

        let appels = registry.requests(to: rpcOuverture)
        XCTAssertEqual(appels.count, 1, "une seule requête")
        let corps = try XCTUnwrap(appels.first?.bodyJSON as? [String: Any])
        XCTAssertEqual(Set(corps.keys), ["p_mission_id", "p_type_litige", "p_motif"],
                       "trois clés exactes : signature canonique, jamais le wrapper déprécié à deux clés")
        XCTAssertEqual(corps["p_type_litige"] as? String, "AUTRE")
        XCTAssertEqual(corps["p_mission_id"] as? String, mission)
        XCTAssertEqual(corps["p_motif"] as? String, "Désaccord sur les heures", "motif nettoyé comme le web (trim)")
        let relecture = try XCTUnwrap(registry.requests(to: litiges).first)
        XCTAssertEqual(relecture.query("id"), "eq.\(litige)", "litige relu par son identifiant")
        XCTAssertEqual(relecture.query("select"), "id")
        XCTAssertFalse(registry.requests.contains { $0.path.contains("notification") || $0.path.contains("audit") },
                       "ni notification ni audit écrits par le client (triggers et audit serveur)")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testRefusDuServeurMotPourMotSansRelecture() async throws {
        let refus = [
            "Le motif doit contenir entre 10 et 2 000 caractères.",
            "Fenêtre de contestation fermée pour ce type de litige. Contactez le support.",
            "Un litige de ce type est déjà ouvert pour cette mission.",
            "Trop de litiges ouverts récemment. Réessayez plus tard.",
            "Mission introuvable",
            "Vous n'êtes pas partie prenante de cette mission.",
            "Accès refusé",
        ]
        XCTAssertEqual(Set(refus), Set(MessagesLitigesServeur.ouverture))
        for message in refus {
            registry.reset()
            let corps = try JSONSerialization.data(withJSONObject: ["error": message])
            registry.add("POST", rpcOuverture, respond: .json(200, String(decoding: corps, as: UTF8.self)))
            let issue = try await gateway().ouvrir(missionId: mission, motif: "court", context: TestClient.context)
            XCTAssertEqual(issue, .refuse(message: message), "refus du serveur restitué mot pour mot")
            XCTAssertEqual(registry.requests.count, 1, "aucune relecture d'un refus, aucun renvoi")
        }
        registry.reset()
        registry.add("POST", rpcOuverture, respond: .json(200, #"{"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().ouvrir(missionId: self.mission, motif: "Motif assez long", context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)
    }

    func testSuccesSansLitigeIdOuJamaisReluLeveContrat() async {
        for reponse in [#"{"success":true}"#, #"{"success":true,"litige_id":""}"#, #"{"success":true,"litige_id":null}"#,
                        #"{"litige_id":"l-1"}"#, #"{"ok":true,"litige_id":"l-1"}"#, "{}", "null"] {
            registry.reset()
            registry.add("POST", rpcOuverture, respond: .json(200, reponse))
            let contrat = await erreur { _ = try await self.gateway().ouvrir(missionId: self.mission, motif: "Motif assez long", context: TestClient.context) }
            XCTAssertEqual(contrat?.kind, .contract, "\(reponse) : jamais un succès")
        }
        // Litige annoncé mais absent de la relecture : aucun succès fabriqué.
        registry.reset()
        registry.add("POST", rpcOuverture, respond: .json(200, #"{"success":true,"litige_id":"l-1","est_informatif":false}"#))
        registry.add("GET", litiges, respond: .json(200, "[]"))
        let absent = await erreur { _ = try await self.gateway().ouvrir(missionId: self.mission, motif: "Motif assez long", context: TestClient.context) }
        XCTAssertEqual(absent?.kind, .contract)
        XCTAssertEqual(registry.requests(to: rpcOuverture).count, 1, "jamais renvoyé")
    }

    func testErreurDeTransportTraduiteSansRenvoi() async {
        registry.add("POST", rpcOuverture, respond: .networkFailure())
        let reseau = await erreur { _ = try await self.gateway().ouvrir(missionId: self.mission, motif: "Motif assez long", context: TestClient.context) }
        XCTAssertEqual(reseau?.kind, .network)
        XCTAssertEqual(registry.requests(to: rpcOuverture).count, 1, "une seule tentative")

        registry.reset()
        registry.add("POST", rpcOuverture, respond: .json(404, #"{"code":"PGRST202","message":"Could not find the function"}"#))
        let fonction = await erreur { _ = try await self.gateway().ouvrir(missionId: self.mission, motif: "Motif assez long", context: TestClient.context) }
        XCTAssertEqual(fonction?.kind, .contract)

        registry.reset()
        registry.add("POST", rpcOuverture, respond: .json(500, #"{"message":"erreur"}"#))
        let inconnue = await erreur { _ = try await self.gateway().ouvrir(missionId: self.mission, motif: "Motif assez long", context: TestClient.context) }
        XCTAssertEqual(inconnue?.message, "Une erreur est survenue. Réessayez.", "repli du web, vouvoyé")
    }

    // MARK: - Fil

    private var filJSON: String {
        """
        [{"id":"m-1","litige_id":"\(litige)","auteur_id":"\(TestClient.userId)","type_auteur":"SOIGNANT","contenu":"Bonjour, voici le détail.",
          "cree_le":"2026-11-01T05:00:00+00:00"},
         {"id":"m-2","litige_id":"\(litige)","auteur_id":"autre","type_auteur":"ETABLISSEMENT","contenu":"Nous regardons.",
          "cree_le":"2026-11-01T06:00:00+00:00"}]
        """
    }

    func testFilParColonnesExplicitesDansLOrdreChronologique() async throws {
        registry.add("GET", messages, respond: .json(200, filJSON))
        let fil = try await gateway().fil(litigeId: litige, context: TestClient.context)
        XCTAssertEqual(fil.map(\.id), ["m-1", "m-2"])
        XCTAssertEqual(fil.first, MessageLitige(id: "m-1", litigeId: litige, auteurId: TestClient.userId, typeAuteur: "SOIGNANT",
                                                contenu: "Bonjour, voici le détail.", creeLe: "2026-11-01T05:00:00+00:00"))
        let lecture = try XCTUnwrap(registry.requests(to: messages).first)
        XCTAssertEqual(lecture.query("select"), "id,litige_id,auteur_id,type_auteur,contenu,cree_le")
        XCTAssertEqual(lecture.query("litige_id"), "eq.\(litige)")
        XCTAssertEqual(lecture.query("order"), "cree_le.asc.nullslast")
    }

    func testMessageAjoutePuisFilReluQuiLeContient() async throws {
        registry.add("POST", rpcMessage, respond: .json(200, #"{"success":true,"message_id":"m-2"}"#))
        registry.add("GET", messages, respond: .json(200, filJSON))
        let issue = try await gateway().ajouterMessage(litigeId: litige, contenu: "  Nous regardons.  ", context: TestClient.context)
        guard case let .ajoute(fil) = issue else { return XCTFail("fil relu attendu, obtenu \(issue)") }
        XCTAssertEqual(fil.map(\.id), ["m-1", "m-2"])
        let corps = try XCTUnwrap(registry.requests(to: rpcMessage).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(Set(corps.keys), ["p_litige_id", "p_contenu"])
        XCTAssertEqual(corps["p_litige_id"] as? String, litige)
        XCTAssertEqual(corps["p_contenu"] as? String, "Nous regardons.", "contenu nettoyé comme le web (trim)")
        XCTAssertEqual(registry.requests.map(\.path), [rpcMessage, messages], "écriture puis relecture, une requête chacune")
    }

    func testRefusDuMessageMotPourMotEtSuccesNonReluJamaisAnnonce() async throws {
        XCTAssertEqual(MessagesLitigesServeur.message, ["Accès refusé", "Litige introuvable ou accès refusé", "Ce litige est clôturé.",
                                                        "Le message doit contenir entre 10 et 5000 caractères."])
        for message in MessagesLitigesServeur.message {
            registry.reset()
            let corps = try JSONSerialization.data(withJSONObject: ["error": message])
            registry.add("POST", rpcMessage, respond: .json(200, String(decoding: corps, as: UTF8.self)))
            let issue = try await gateway().ajouterMessage(litigeId: litige, contenu: "bonjour", context: TestClient.context)
            XCTAssertEqual(issue, .refuse(message: message))
            XCTAssertEqual(registry.requests.count, 1, "aucune relecture d'un refus")
        }
        registry.reset()
        registry.add("POST", rpcMessage, respond: .json(200, #"{"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().ajouterMessage(litigeId: self.litige, contenu: "bonjour à tous", context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)

        registry.reset()
        registry.add("POST", rpcMessage, respond: .json(200, #"{"success":true}"#))
        let sansId = await erreur { _ = try await self.gateway().ajouterMessage(litigeId: self.litige, contenu: "bonjour à tous", context: TestClient.context) }
        XCTAssertEqual(sansId?.kind, .contract, "succès sans `message_id` : jamais un succès")

        registry.reset()
        registry.add("POST", rpcMessage, respond: .json(200, #"{"success":true,"message_id":"m-9"}"#))
        registry.add("GET", messages, respond: .json(200, filJSON))
        let absent = await erreur { _ = try await self.gateway().ajouterMessage(litigeId: self.litige, contenu: "bonjour à tous", context: TestClient.context) }
        XCTAssertEqual(absent?.kind, .contract, "message annoncé mais absent du fil relu : aucun succès fabriqué")
        XCTAssertEqual(registry.requests(to: rpcMessage).count, 1, "jamais renvoyé")
    }
}

/// Réclamations générales sur Supabase (lot 4, T8) — fiche `fn_soumettre_reclamation` de
/// `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` : `{id, statut}` sans `success` ni `ok` reconnu comme succès puis ligne
/// relue ; « Rôle non autorisé » mot pour mot ; exception `23514` (`reclamations_categorie_check`) → libellé générique,
/// jamais « session expirée » ; erreur de lecture jamais réduite à une liste vide.
final class SupabaseReclamationsGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let reclamations = "/rest/v1/reclamations"
    private let rpc = "/rest/v1/rpc/fn_soumettre_reclamation"
    private let id = "9a8b7c6d-2222-4b1c-9e0a-7f3c1d2e5a66"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseReclamationsGateway { SupabaseReclamationsGateway(client: TestClient.make()) }

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

    private var ligneJSON: String {
        """
        {"id":"\(id)","categorie":"PAIEMENT","sujet":"Montant à vérifier","details":"Le montant affiché diffère.",
         "statut":"EN_ATTENTE","reponse_admin":null,"cree_le":"2026-11-02T00:00:00+00:00","traite_le":null}
        """
    }

    func testListeParColonnesDuWebEtErreurJamaisUneListeVide() async throws {
        registry.add("GET", reclamations, respond: .json(200, "[\(ligneJSON)]"))
        let liste = try await gateway().lister(context: TestClient.context)
        XCTAssertEqual(liste, [Reclamation(id: id, categorie: "PAIEMENT", sujet: "Montant à vérifier",
                                           details: "Le montant affiché diffère.", statut: "EN_ATTENTE",
                                           creeLe: "2026-11-02T00:00:00+00:00")])
        let lecture = try XCTUnwrap(registry.requests(to: reclamations).first)
        XCTAssertEqual(lecture.query("select"), "id,categorie,sujet,details,statut,reponse_admin,cree_le,traite_le")
        XCTAssertEqual(lecture.query("utilisateur_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(lecture.query("order"), "cree_le.desc.nullsfirst")

        registry.reset()
        registry.add("GET", reclamations, respond: .json(500, #"{"message":"erreur"}"#))
        let echec = await erreur { _ = try await self.gateway().lister(context: TestClient.context) }
        XCTAssertEqual(echec?.message, ReclamationsTextes.chargementImpossible, "le web affiche une liste vide : pas le natif")
    }

    func testReponseIdEtStatutSansSuccessReconnueCommeSuccesPuisRelue() async throws {
        registry.add("POST", rpc, respond: .json(200, #"{"id":"\#(id)","statut":"EN_ATTENTE"}"#))
        registry.add("GET", reclamations, respond: .json(200, "[\(ligneJSON)]"))
        let issue = try await gateway().soumettre(categorie: .paiement, sujet: "  Montant à vérifier ", details: " Le montant affiché diffère. ",
                                                  context: TestClient.context)
        guard case let .soumise(reclamation) = issue else { return XCTFail("réclamation relue attendue, obtenu \(issue)") }
        XCTAssertEqual(reclamation.id, id)
        XCTAssertEqual(reclamation.statut, "EN_ATTENTE")

        let appels = registry.requests(to: rpc)
        XCTAssertEqual(appels.count, 1, "une seule requête")
        let corps = try XCTUnwrap(appels.first?.bodyJSON as? [String: Any])
        XCTAssertEqual(Set(corps.keys), ["p_categorie", "p_sujet", "p_details"], "`p_mission_id` jamais envoyé, comme le web")
        XCTAssertEqual(corps["p_categorie"] as? String, "PAIEMENT")
        XCTAssertEqual(corps["p_sujet"] as? String, "Montant à vérifier")
        XCTAssertEqual(corps["p_details"] as? String, "Le montant affiché diffère.")
        let relecture = try XCTUnwrap(registry.requests(to: reclamations).first)
        XCTAssertEqual(relecture.query("id"), "eq.\(id)", "ligne relue par l'identifiant rendu")
        XCTAssertEqual(relecture.query("select"), SupabaseReclamationsGateway.colonnes)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testCategoriesEnvoyeesSontCellesDeLaContrainteServeur() async throws {
        for categorie in CategorieReclamation.allCases {
            registry.reset()
            registry.add("POST", rpc, respond: .json(200, #"{"id":"\#(id)","statut":"EN_ATTENTE"}"#))
            registry.add("GET", reclamations, respond: .json(200, "[\(ligneJSON)]"))
            _ = try await gateway().soumettre(categorie: categorie, sujet: "s", details: "d", context: TestClient.context)
            let corps = try XCTUnwrap(registry.requests(to: rpc).first?.bodyJSON as? [String: Any])
            XCTAssertEqual(corps["p_categorie"] as? String, categorie.rawValue)
            XCTAssertTrue(["MISSION", "PAIEMENT", "TECHNIQUE", "COMPORTEMENT", "AUTRE"].contains(categorie.rawValue))
        }
    }

    func testRoleNonAutoriseMotPourMotEtNonAuthentifie() async throws {
        registry.add("POST", rpc, respond: .json(200, #"{"error":"Rôle non autorisé"}"#))
        let role = try await gateway().soumettre(categorie: .autre, sujet: "s", details: "d", context: TestClient.context)
        XCTAssertEqual(role, .refusee(message: "Rôle non autorisé"))
        XCTAssertEqual(registry.requests.count, 1, "aucune relecture d'un refus")

        registry.reset()
        registry.add("POST", rpc, respond: .json(200, #"{"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().soumettre(categorie: .autre, sujet: "s", details: "d", context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)
    }

    func testException23514LibelleGeneriqueJamaisSessionExpiree() async throws {
        let exception: [String: Any] = [
            "code": "23514", "details": NSNull(), "hint": NSNull(),
            "message": #"new row for relation "reclamations" violates check constraint "reclamations_categorie_check""#,
        ]
        let corps = String(decoding: try JSONSerialization.data(withJSONObject: exception), as: UTF8.self)
        registry.add("POST", rpc, respond: .json(400, corps))
        let issue = try await gateway().soumettre(categorie: .autre, sujet: "s", details: "d", context: TestClient.context)
        XCTAssertEqual(issue, .refusee(message: "Erreur lors de la soumission"),
                       "libellé générique du web : ni le texte PostgreSQL, ni « Votre session a expiré »")
        XCTAssertEqual(registry.requests.count, 1, "aucun renvoi, aucune relecture")

        // Un 42501 reste le comportement du lot 0 (aucune règle déclarée pour cette RPC).
        registry.reset()
        registry.add("POST", rpc, respond: .json(403, #"{"code":"42501","message":"permission denied for function fn_soumettre_reclamation"}"#))
        let privilege = await erreur { _ = try await self.gateway().soumettre(categorie: .autre, sujet: "s", details: "d", context: TestClient.context) }
        XCTAssertEqual(privilege?.kind, .contract, "GRANT manquant : contrat, jamais restitué")
    }

    func testSuccesSansIdOuJamaisReluLeveContrat() async {
        for reponse in [#"{"statut":"EN_ATTENTE"}"#, #"{"id":"","statut":"EN_ATTENTE"}"#, #"{"success":true}"#, "{}", "null"] {
            registry.reset()
            registry.add("POST", rpc, respond: .json(200, reponse))
            let contrat = await erreur { _ = try await self.gateway().soumettre(categorie: .autre, sujet: "s", details: "d", context: TestClient.context) }
            XCTAssertEqual(contrat?.kind, .contract, "\(reponse) : jamais un succès")
        }
        registry.reset()
        registry.add("POST", rpc, respond: .json(200, #"{"id":"\#(id)","statut":"EN_ATTENTE"}"#))
        registry.add("GET", reclamations, respond: .json(200, "[]"))
        let absente = await erreur { _ = try await self.gateway().soumettre(categorie: .autre, sujet: "s", details: "d", context: TestClient.context) }
        XCTAssertEqual(absente?.kind, .contract, "réclamation annoncée mais jamais relue : aucun succès fabriqué")
        XCTAssertEqual(registry.requests(to: rpc).count, 1, "jamais renvoyée")
    }
}

/// Câblage Supabase des litiges et des réclamations (lot 4, T8 ; garde anti-oubli `Lot4Wiring<Domaine>Tests`,
/// `LOT4_PLAN.md` §2.2) : même PR que les fabriques démo, `DemoWorldTests.portsEnAttenteLot4` sans ces deux ports.
final class Lot4WiringLitigesTests: XCTestCase {
    func testSupabaseCableLesLitigesEtLesReclamationsCommeLeMondeDemo() {
        let gateways = SupabaseGateways.make(client: TestClient.make())
        XCTAssertTrue(gateways.litiges is SupabaseLitigesGateway)
        XCTAssertTrue(gateways.reclamations is SupabaseReclamationsGateway)
        for port in ["litiges", "reclamations"] {
            XCTAssertFalse(gateways.unwiredPorts.contains(port), port)
            XCTAssertFalse(DemoWorld.gateways().unwiredPorts.contains(port), port)
        }
    }
}
