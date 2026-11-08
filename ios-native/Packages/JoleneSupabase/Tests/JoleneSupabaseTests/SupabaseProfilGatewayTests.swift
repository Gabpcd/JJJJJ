import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Gateway du profil (lot 3, T9 ; fiches `fn_mon_profil_soignant_complet` et `fn_modifier_mon_profil` de
/// `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`, définitions live relues le 08/11/2026 : corps identiques
/// au dump) : lecture décodée en liste blanche (aucune clé sensible restituée), refus `{error}` verbatim,
/// écriture limitée aux paramètres du blueprint puis RELECTURE ; une seule requête par appel, aucun renvoi.
final class SupabaseProfilGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let lecture = "/rest/v1/rpc/fn_mon_profil_soignant_complet"
    private let ecriture = "/rest/v1/rpc/fn_modifier_mon_profil"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseProfilGateway { SupabaseProfilGateway(client: TestClient.make()) }

    /// Ligne de `fn_mon_profil_soignant_complet` (colonnes du dump l.44667-44679), clés sensibles comprises :
    /// le serveur les renvoie, le décodeur ne les lit pas. Valeurs fictives assemblées (aucun identifiant réel).
    private func ligne(prenom: String = "Léa", ville: String? = "Lyon", rppsVerifie: Bool = false) -> String {
        let secu = ["1", String(repeating: "9", count: 12)].joined()
        let villeJSON = ville.map { #""\#($0)""# } ?? "null"
        return """
        {"id":"\(TestClient.userId)","prenom":"\(prenom)","nom":"Martin","email":"\(TestClient.email)",
         "telephone":"0600000000","date_naissance":"1990-05-14","profession":"IDE","numero_rpps":null,
         "numero_adeli":null,"numero_secu":"\(secu)","type_contrat":"CDD","type_exercice":"SALARIE",
         "adresse_rue":null,"adresse_ville":null,"adresse_code_postal":null,"adresse_lat":45.75,"adresse_lng":4.85,
         "rayon_deplacement_km":40,"score_fiabilite":80,"note_moyenne":4.5,"nb_evaluations":2,
         "total_missions_terminees":3,"heures_cumulees":120,"statut_liberal":null,"siret_liberal":"SIRET-FICTIF",
         "code_ape":"APE-FICTIF","assujetti_tva":false,"numero_tva":"TVA-FICTIVE","tous_documents_valides":true,
         "rpps_verifie":\(rppsVerifie),"identite_verifiee":true,"diplome_verifie":true,"disponible_urgence":false,
         "urgence_rayon_km":15,"bio":"Bonjour","annees_experience":7,"specialites":["Urgences"],
         "types_contrat_acceptes":"CDD,LIBERAL","avatar_url":null,"stripe_account_id":"acct_fictif",
         "iban_last4":"0189","attestation_cumul_activite":false,"taux_horaire_minimum":32.5,
         "badge_ambassadeur":false,"ville_recherche":\(villeJSON),"ville_urgence":null,"consentement_gps":true,
         "cree_le":"2026-01-10T09:00:00+00:00","modifie_le":"2026-11-01T09:00:00+00:00"}
        """
    }

    private func corps(_ path: String) throws -> NSDictionary {
        let requete = try XCTUnwrap(registry.requests(to: path).first, "aucun appel à \(path)")
        return try XCTUnwrap(requete.bodyJSON as? NSDictionary)
    }

    private func erreur(_ operation: @escaping () async throws -> Void) async -> JoleneError? {
        do {
            try await operation()
            return nil
        } catch let jolene as JoleneError {
            return jolene
        } catch {
            XCTFail("erreur non traduite : \(error)")
            return nil
        }
    }

    func testNomsDesRPC() {
        XCTAssertEqual(SupabaseProfilGateway.lectureRPC, "fn_mon_profil_soignant_complet")
        XCTAssertEqual(SupabaseProfilGateway.ecritureRPC, "fn_modifier_mon_profil")
    }

    // MARK: - Lecture

    func testLectureDecodeLaListeBlancheSansAucuneCleSensible() async throws {
        registry.add("POST", lecture, respond: .json(200, ligne()))
        let profil = try await gateway().profil(context: TestClient.context)
        XCTAssertEqual(profil.id, TestClient.userId)
        XCTAssertEqual(profil.prenom, "Léa")
        XCTAssertEqual(profil.villeRecherche, "Lyon")
        XCTAssertEqual(profil.rayonDeplacementKm, 40)
        XCTAssertEqual(profil.tauxHoraireMinimum, 32.5)
        XCTAssertEqual(profil.anneesExperience, 7)
        XCTAssertEqual(profil.typesContratAcceptes, ["CDD", "LIBERAL"])
        XCTAssertEqual(profil.dateNaissance, "1990-05-14")
        XCTAssertEqual(profil.adresseLat, 45.75)
        let rendu = [String(describing: profil), String(reflecting: profil)].joined()
        for sensible in ["999999999999", "SIRET-FICTIF", "APE-FICTIF", "TVA-FICTIVE", "acct_fictif", "0189"] {
            XCTAssertFalse(rendu.contains(sensible), "valeur sensible « \(sensible) » restituée par le décodeur")
        }
        XCTAssertEqual(registry.requests(to: lecture).count, 1)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testLectureRefusVerbatimEtSessionExpiree() async {
        registry.add("POST", lecture, respond: .json(200, #"{"error":"Profil introuvable"}"#))
        var e = await erreur { _ = try await self.gateway().profil(context: TestClient.context) }
        XCTAssertEqual(e, JoleneError(.unknown, "Profil introuvable"), "l.44681, message serveur verbatim")
        registry.reset()
        registry.add("POST", lecture, respond: .json(200, #"{"error":"Non authentifié"}"#))
        e = await erreur { _ = try await self.gateway().profil(context: TestClient.context) }
        XCTAssertEqual(e?.kind, .unauthorized, "l.44665 : session expirée")
    }

    func testLigneDUnAutreUtilisateurOuInvalideEstUnRefusDeContratJamaisUnProfilVide() async {
        let autre = ligne().replacingOccurrences(of: TestClient.userId, with: "autre-utilisateur")
        let typeIncompatible = ligne().replacingOccurrences(of: #""rayon_deplacement_km":40"#, with: #""rayon_deplacement_km":"40""#)
        for corps in [autre, typeIncompatible, "[]", "null"] {
            registry.reset()
            registry.add("POST", lecture, respond: .json(200, corps))
            let e = await erreur { _ = try await self.gateway().profil(context: TestClient.context) }
            XCTAssertEqual(e, JoleneError(.contract, SupabaseErrorMapping.contractMessage), corps)
        }
    }

    func testLectureRefuseUnContexteIncoherentAvantToutAppel() async {
        let contexte = MissionReadContext(userId: TestClient.userId, email: nil,
                                          profile: SoignantProfile(id: "autre-profil", profession: "IDE"))
        let e = await erreur { _ = try await self.gateway().profil(context: contexte) }
        XCTAssertEqual(e?.kind, .unauthorized)
        XCTAssertTrue(registry.requests.isEmpty, "aucun appel réseau")
    }

    // MARK: - Écriture

    func testSeulsLesParametresDeLaModificationPartentPuisLeProfilEstRelu() async throws {
        registry.add("POST", ecriture, respond: .json(200, #"{"success":true}"#))
        registry.add("POST", lecture, respond: .json(200, ligne(ville: "Grenoble")))
        let modification = ModificationProfil(rayonDeplacementKm: 25, villeRecherche: "Grenoble",
                                              tauxHoraireMinimum: 30, typesContratAcceptes: ["CDD"], anneesExperience: 8)
        let relu = try await gateway().modifier(modification, context: TestClient.context)
        XCTAssertEqual(relu.villeRecherche, "Grenoble", "profil RELU, jamais la saisie renvoyée telle quelle")
        let envoye = try corps(ecriture)
        XCTAssertEqual(envoye, [
            "p_rayon_deplacement_km": 25, "p_ville_recherche": "Grenoble", "p_taux_horaire_minimum": 30,
            "p_types_contrat": ["CDD"], "p_annees_experience": 8,
        ] as NSDictionary)
        XCTAssertEqual(registry.requests.map(\.path), [ecriture, lecture], "écriture puis relecture, une fois chacune")
    }

    func testToutLeFormulaireNEnvoieJamaisUnParametreInterdit() async throws {
        registry.add("POST", ecriture, respond: .json(200, #"{"success":true}"#))
        registry.add("POST", lecture, respond: .json(200, ligne()))
        let complete = ModificationProfil(prenom: "Lou", nom: "Bernard", telephone: "0611111111", dateNaissance: "1991-01-02",
                                          numeroRpps: "10101010101", rayonDeplacementKm: 60, villeRecherche: "Nice",
                                          tauxHoraireMinimum: 35, typesContratAcceptes: ["CDD", "LIBERAL"], bio: "Bio",
                                          anneesExperience: 9)
        _ = try await gateway().modifier(complete, context: TestClient.context)
        let cles = Set(try corps(ecriture).allKeys.compactMap { $0 as? String })
        XCTAssertEqual(cles.count, 11)
        XCTAssertTrue(cles.isSubset(of: Set(ModificationProfil.parametresAutorises)))
        for interdit in ["p_type_exercice", "p_attestation_cumul_activite", "p_est_cumul_activite", "p_est_salarie_etablissement",
                         "p_consentement_gps", "p_disponible_urgence", "p_urgence_rayon_km", "p_ville_urgence",
                         "p_specialites", "p_profession", "p_numero_adeli", "p_types_contrat_acceptes"] {
            XCTAssertFalse(cles.contains(interdit), "\(interdit) envoyé (HARD STOP n°4 / hors périmètre)")
        }
        XCTAssertEqual(try corps(ecriture)["p_date_naissance"] as? String, "1991-01-02")
    }

    /// Refus CERTAIN levé par `modifier` (le serveur a répondu sans rien appliquer).
    private func refus(_ operation: @escaping () async throws -> Void) async -> RefusEnregistrementProfil? {
        do {
            try await operation()
            return nil
        } catch let refus as RefusEnregistrementProfil {
            return refus
        } catch {
            XCTFail("refus certain attendu, obtenu : \(error)")
            return nil
        }
    }

    /// Exception PostgREST (corps d'erreur de `PostgrestError`), message brut de PostgreSQL.
    private func exception(_ sqlstate: String, message: String, details: String? = nil) -> String {
        let detail = details.map { #""\#($0)""# } ?? "null"
        return #"{"code":"\#(sqlstate)","details":\#(detail),"hint":null,"message":"\#(message)"}"#
    }

    func testPrenomVideRefuseVerbatimSansRelecture() async {
        // l.43906 : `{error:'Le prénom ne peut pas être vide'}` en HTTP 200 ; le message serveur est restitué tel quel,
        // en refus CERTAIN (`RefusEnregistrementProfil`, revue B8 de T9 : distinct d'une issue ambiguë, que le modèle relit).
        for (champ, message) in [(ModificationProfil(prenom: ""), "Le prénom ne peut pas être vide"),
                                 (ModificationProfil(nom: " "), "Le nom ne peut pas être vide")] {
            registry.reset()
            registry.add("POST", ecriture, respond: .json(200, #"{"error":"\#(message)"}"#))
            let r = await refus { _ = try await self.gateway().modifier(champ, context: TestClient.context) }
            XCTAssertEqual(r, RefusEnregistrementProfil(message))
            XCTAssertTrue(registry.requests(to: lecture).isEmpty, "\(message) : aucun succès relu")
            XCTAssertEqual(registry.requests(to: ecriture).count, 1, "\(message) : aucun renvoi")
        }
    }

    // MARK: - Exceptions métier de l'UPDATE (revue B8 de T9 ; définitions live relues le 08/11/2026)

    func testTelephoneHorsFormat23514TexteWebSansRelecture() async {
        // `chk_telephone_format` (`public.sql` l.68090) : téléphone en saisie libre (« 06/12/34/56/78 »). PostgREST
        // répond 400 ; `extraireMessageErreur` (src/lib/erreurs.ts l.513-514) affiche le texte web.
        let message = #"new row for relation \"soignants\" violates check constraint \"chk_telephone_format\""#
        registry.add("POST", ecriture, respond: .json(400, exception("23514", message: message,
                                                                       details: "Failing row contains (…).")))
        let r = await refus {
            _ = try await self.gateway().modifier(ModificationProfil(telephone: "06/12/34/56/78", bio: "Bonjour"),
                                                  context: TestClient.context)
        }
        XCTAssertEqual(r, RefusEnregistrementProfil("La valeur saisie est hors des limites autorisées."))
        XCTAssertEqual(registry.requests(to: ecriture).count, 1, "une seule requête, aucun renvoi")
        XCTAssertTrue(registry.requests(to: lecture).isEmpty, "UPDATE entier annulé : aucune relecture")
    }

    func testRppsDejaPorte23505TexteWebSansRelecture() async {
        // `soignants_numero_rpps_key` (l.73502) : 409 ; texte web l.510. Une autre contrainte unique → l.511.
        for (contrainte, attendu) in [("soignants_numero_rpps_key", "Ce numéro RPPS est déjà enregistré."),
                                      ("soignants_email_key", "Cette valeur existe déjà dans le système.")] {
            registry.reset()
            let message = #"duplicate key value violates unique constraint \"\#(contrainte)\""#
            registry.add("POST", ecriture, respond: .json(409, exception("23505", message: message,
                                                                           details: "Key (numero_rpps)=(…) already exists.")))
            let r = await refus {
                _ = try await self.gateway().modifier(ModificationProfil(numeroRpps: "10101010101"), context: TestClient.context)
            }
            XCTAssertEqual(r, RefusEnregistrementProfil(attendu), contrainte)
            XCTAssertEqual(registry.requests(to: ecriture).count, 1, "\(contrainte) : une seule requête")
            XCTAssertTrue(registry.requests(to: lecture).isEmpty, "\(contrainte) : aucune relecture")
        }
    }

    func testAgeMinimumP0001MessageServeurVerbatimSansRelecture() async {
        // Trigger `dec_age_minimum` → `dec_verifier_age_minimum` (l.3887-3895) : P0001, 400. Message serveur verbatim
        // (le web affiche son message générique : écart consigné dans DECISIONS_LOT3.md).
        let message = "Vous devez avoir au moins 18 ans pour vous inscrire."
        registry.add("POST", ecriture, respond: .json(400, exception("P0001", message: message)))
        let r = await refus {
            _ = try await self.gateway().modifier(ModificationProfil(dateNaissance: "2015-01-01"), context: TestClient.context)
        }
        XCTAssertEqual(r, RefusEnregistrementProfil(message))
        XCTAssertEqual(registry.requests(to: ecriture).count, 1)
        XCTAssertTrue(registry.requests(to: lecture).isEmpty)
        XCTAssertEqual(SupabaseProfilGateway.exceptionsMetier, ["23514", "23505", "P0001"])
    }

    func testErreurServeurAmbigueResteUneErreurJamaisUnRefusCertain() async {
        // HTTP 5xx / passerelle : issue inconnue (l'UPDATE a pu passer) → `.unknown` avec le repli, que le modèle relit.
        // Une exception non déclarée garde le comportement du lot 1 (message générique, jamais restituée).
        for reponse in [StubResponse.json(500, exception("XX000", message: "internal error")),
                        StubResponse.json(504, #"{"message":"upstream request timeout"}"#),
                        StubResponse.json(400, exception("22P02", message: "invalid input syntax for type date"))] {
            registry.reset()
            registry.add("POST", ecriture, respond: reponse)
            let e = await erreur { _ = try await self.gateway().modifier(ModificationProfil(bio: "x"), context: TestClient.context) }
            XCTAssertEqual(e, JoleneError(.unknown, ProfilEdition.Textes.enregistrementEchec))
            XCTAssertEqual(registry.requests(to: ecriture).count, 1, "aucun renvoi automatique")
        }
    }

    func testReponseSansSuccesNEstJamaisUnSucces() async {
        registry.add("POST", ecriture, respond: .json(200, "{}"))
        let e = await erreur { _ = try await self.gateway().modifier(ModificationProfil(bio: "x"), context: TestClient.context) }
        XCTAssertEqual(e, JoleneError(.contract, SupabaseErrorMapping.contractMessage))
        XCTAssertTrue(registry.requests(to: lecture).isEmpty)
    }

    func testEcritureSessionExpireeReseauEtFonctionIntrouvable() async {
        registry.add("POST", ecriture, respond: .json(200, #"{"error":"Non authentifié"}"#))
        var e = await erreur { _ = try await self.gateway().modifier(ModificationProfil(bio: "x"), context: TestClient.context) }
        XCTAssertEqual(e?.kind, .unauthorized)
        registry.reset()
        registry.add("POST", ecriture, respond: .networkFailure())
        e = await erreur { _ = try await self.gateway().modifier(ModificationProfil(bio: "x"), context: TestClient.context) }
        XCTAssertEqual(e?.kind, .network)
        XCTAssertEqual(registry.requests(to: ecriture).count, 1, "aucun renvoi automatique")
        registry.reset()
        registry.add("POST", ecriture, respond: .json(404, #"{"code":"PGRST202","details":null,"hint":null,"message":"x"}"#))
        e = await erreur { _ = try await self.gateway().modifier(ModificationProfil(bio: "x"), context: TestClient.context) }
        XCTAssertEqual(e?.kind, .contract)
    }

    func testModificationVideNAppelleQueLaLecture() async throws {
        registry.add("POST", lecture, respond: .json(200, ligne()))
        _ = try await gateway().modifier(ModificationProfil(), context: TestClient.context)
        XCTAssertTrue(registry.requests(to: ecriture).isEmpty)
        XCTAssertEqual(registry.requests(to: lecture).count, 1)
    }

    func testRepliDuMessageDEnregistrementPartageAvecLeModele() {
        XCTAssertEqual(SupabaseProfilGateway.fallbackMessage, ProfilEdition.Textes.enregistrementEchec)
    }
}
