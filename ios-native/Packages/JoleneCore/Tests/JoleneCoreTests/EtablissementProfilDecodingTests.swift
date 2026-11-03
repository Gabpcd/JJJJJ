import XCTest
@testable import JoleneCore

/// Sous-ensemble de `fn_mon_etablissement_complet` (lot 5 T1, §2.2) : le modèle n'expose aucune
/// colonne Stripe, bancaire, de commission, de blocage chiffré ni de note (correction 4, D15). Le test
/// échoue si une propriété de ce type apparaît.
final class EtablissementProfilDecodingTests: XCTestCase {
    /// Colonnes de `row_to_json` (l.44606-44645) jamais décodées par le natif.
    static let jamaisDecodees = ["siret", "finess", "stripe_customer_id", "stripe_account_id", "taux_commission_negocie",
                                 "taux_commission_effectif", "rib_s3_key", "rib_ia_coherent", "iban_last4",
                                 "paliers_commission", "groupes_sante", "groupe_sante_id", "bloque_auto_raisons",
                                 "note_moyenne", "nb_evaluations", "email_contact", "telephone_contact", "mode_facturation",
                                 "mode_paiement_commission", "palier_commission_id", "rist_taux_base_horaire"]

    /// Ligne complète telle que servie par le serveur (valeurs fictives).
    static let ligneComplete = """
    {"id":"6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b","nom":"Clinique des Tests","siret":"00000000000000","finess":"690000000",
     "type":"CLINIQUE","groupe_sante_id":null,"adresse_rue":"1 rue","adresse_ville":"Lyon","adresse_code_postal":"69003",
     "adresse_departement":"69","adresse_lat":45.76,"adresse_lng":4.85,"email_contact":"contact@example.test",
     "telephone_contact":"0000000000","stripe_customer_id":"cus_fictif","stripe_account_id":"acct_fictif",
     "taux_commission_negocie":12,"taux_commission_effectif":12,"mode_facturation":"MENSUELLE",
     "mode_paiement_commission":"SEPA_DEBIT","palier_commission_id":null,"missions_mois_precedent":3,
     "palier_recalcule_le":null,"chorus_pro_actif":false,"chorus_pro_identifiant":null,"delai_paiement_jours":30,
     "formule_abonnement":null,"convention_collective":null,"couleur_theme":null,"logo_url":"https://example.test/logo.png",
     "contrat_url":null,"contrat_uploade_le":null,"contrat_valide":true,"contrat_service_signe":true,
     "contrat_service_signe_le":"2026-01-10T09:00:00+00:00","rib_s3_key":"rib/fictif.pdf","rib_ia_coherent":true,
     "iban_last4":"0000","sms_actif":false,"taux_majoration_nuit_pourcent":10,"taux_majoration_dimanche_pourcent":20,
     "taux_majoration_ferie_pourcent":30,"est_secteur_public":false,"peut_publier_missions":true,
     "statut_verification":"VERIFIE","note_moyenne":4.5,"nb_evaluations":12,"description":null,"horaires_ouverture":null,
     "rist_plafond_actif":false,"rist_taux_base_horaire":null,"bloque_auto_le":null,
     "bloque_auto_raisons":{"montant_du":1200},"cree_le":"2026-01-01T00:00:00+00:00","modifie_le":"2026-10-01T00:00:00+00:00",
     "paliers_commission":null,"groupes_sante":{"id":"g-1","nom":"Groupe","taux_commission_negocie":10}}
    """

    private func decoder(_ json: String) throws -> EtablissementProfil {
        try JSONDecoder().decode(EtablissementProfil.self, from: Data(json.utf8))
    }

    func testSousEnsembleDecodeDepuisLaLigneComplete() throws {
        let profil = try decoder(Self.ligneComplete)
        XCTAssertEqual(profil, EtablissementProfil(id: "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b", nom: "Clinique des Tests",
                                                   logoUrl: "https://example.test/logo.png", type: "CLINIQUE",
                                                   peutPublierMissions: true, statutVerification: "VERIFIE", bloqueAutoLe: nil,
                                                   contratServiceSigne: true, estSecteurPublic: false))
    }

    func testAucuneColonneSensibleNEstExposeeParLeModele() throws {
        XCTAssertEqual(EtablissementProfil.clesDecodees,
                       ["id", "nom", "type", "logo_url", "peut_publier_missions", "statut_verification", "bloque_auto_le",
                        "contrat_service_signe", "est_secteur_public"])
        // Réencodage : seules les neuf clés du sous-ensemble sortent du modèle.
        let encode = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try decoder(Self.ligneComplete))) as? [String: Any]
        XCTAssertEqual(encode?.keys.sorted(), EtablissementProfil.clesDecodees.sorted())
        for cle in Self.jamaisDecodees {
            XCTAssertFalse(EtablissementProfil.clesDecodees.contains(cle), cle)
        }
        // Introspection : aucune propriété dont le nom évoque un identifiant de paiement, bancaire ou une note.
        let proprietes = Mirror(reflecting: try decoder(Self.ligneComplete)).children.compactMap(\.label).map { $0.lowercased() }
        XCTAssertEqual(proprietes.count, 9)
        for interdit in ["stripe", "iban", "rib", "siret", "finess", "commission", "palier", "groupe", "raison", "note",
                         "evaluation", "telephone", "email"] {
            XCTAssertFalse(proprietes.contains { $0.contains(interdit) }, "propriété « \(interdit) » exposée par le modèle")
        }
    }

    func testColonnesNullablesGardeesOptionnellesEtTolerantes() throws {
        let profil = try decoder(#"{"id":"e-1","nom":"X","peut_publier_missions":null,"est_secteur_public":"oui","bloque_auto_le":"2026-11-01T07:00:00+00:00"}"#)
        XCTAssertNil(profil.peutPublierMissions, "NULL serveur → nil, jamais un défaut qui ouvrirait la publication")
        XCTAssertNil(profil.estSecteurPublic, "type inattendu → nil")
        XCTAssertNil(profil.statutVerification)
        XCTAssertFalse(profil.contratServiceSigne, "colonne NOT NULL absente → false (fail-closed)")
        XCTAssertEqual(profil.bloqueAutoLe, "2026-11-01T07:00:00+00:00")
        XCTAssertEqual(try decoder(#"{"id":"e-1"}"#).nom, "")
    }

    func testIdentifiantExige() {
        XCTAssertThrowsError(try decoder(#"{"nom":"Sans identifiant"}"#))
        XCTAssertThrowsError(try decoder(#"{"id":"  ","nom":"Vide"}"#))
        XCTAssertThrowsError(try decoder(#"{"id":null,"nom":"Nul"}"#))
    }
}
