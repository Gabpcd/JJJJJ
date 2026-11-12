import XCTest
@testable import JoleneCore

/// Décodage de `fn_mon_profil_soignant_complet` en liste blanche (lot 3, T9 ; correction 7) : la garde
/// du web (`valider-profil-soignant.json`, rejoué par `RulesValidationProfilTests`) s'applique AVANT tout
/// décodage ; aucune clé sensible n'a de propriété ; les valeurs d'affichage suivent `ProfilSoignant.tsx`.
final class ProfilCompletTests: XCTestCase {
    private func ligne(_ champs: [String: ValeurJSON] = [:]) -> ValeurJSON {
        var base: [String: ValeurJSON] = ["id": .chaine("u-1"), "prenom": .chaine("Léa"), "nom": .chaine("Martin"),
                                          "email": .chaine("lea@example.invalid"), "profession": .chaine("IDE")]
        base.merge(champs) { _, nouveau in nouveau }
        return .objet(base)
    }

    func testChaqueVecteurGoldenAccepteOuRefuseCommeLaGardeDuWeb() throws {
        // Même verdict que `validerProfilSoignant` sur chacun des vecteurs exportés du web.
        let vecteurs = try Golden.charger("valider-profil-soignant").filter { $0.input["fonction"]?.string == "validerProfilSoignant" }
        XCTAssertGreaterThan(vecteurs.count, 250)
        for vecteur in vecteurs {
            let donnees = try (vecteur.input["data"] ?? .null).decode(ValeurJSON.self)
            let userId = try XCTUnwrap(vecteur.input["userId"]?.string)
            let refuseParLeWeb = vecteur.expected["erreur"] != nil
            do {
                let profil = try ProfilComplet.depuis(donnees, userId: userId)
                XCTAssertFalse(refuseParLeWeb, "\(vecteur.name) : refusé par le web, accepté par le décodeur")
                XCTAssertEqual(profil.id, userId)
            } catch ValidationProfil.Erreur.profilInvalide {
                XCTAssertTrue(refuseParLeWeb, "\(vecteur.name) : accepté par le web, refusé par le décodeur")
            }
        }
    }

    func testReponseErreurOuAutreUtilisateurNeDonneJamaisUnProfilVide() {
        for donnees: ValeurJSON in [.objet(["error": .chaine("Profil introuvable")]), .null, .tableau([]), ligne(["error": .chaine("x")])] {
            XCTAssertThrowsError(try ProfilComplet.depuis(donnees, userId: "u-1"))
        }
        XCTAssertThrowsError(try ProfilComplet.depuis(ligne(), userId: "u-2"), "ligne d'un autre utilisateur")
    }

    func testValeursDAffichageEtDerivationDesContrats() throws {
        let profil = try ProfilComplet.depuis(ligne([
            "telephone": .chaine("0600000000"), "date_naissance": .chaine("1990-05-14"), "numero_rpps": .chaine("10101010101"),
            "rpps_verifie": .booleen(false), "rayon_deplacement_km": .nombre(40), "ville_recherche": .chaine("Lyon"),
            "taux_horaire_minimum": .nombre(32.5), "types_contrat_acceptes": .chaine("CDD,LIBERAL"), "bio": .chaine("Bonjour"),
            "annees_experience": .nombre(7), "avatar_url": .chaine("https://exemple.invalid/a.jpg"),
            "adresse_lat": .nombre(45.75), "adresse_lng": .nombre(4.85), "specialites": .tableau([.chaine("Urgences")]),
        ]), userId: "u-1")
        XCTAssertEqual(profil, ProfilComplet(
            id: "u-1", prenom: "Léa", nom: "Martin", email: "lea@example.invalid", telephone: "0600000000",
            dateNaissance: "1990-05-14", profession: "IDE", numeroRpps: "10101010101", rppsVerifie: false,
            rayonDeplacementKm: 40, villeRecherche: "Lyon", tauxHoraireMinimum: 32.5, typesContratAcceptes: ["CDD", "LIBERAL"],
            bio: "Bonjour", anneesExperience: 7, avatarUrl: "https://exemple.invalid/a.jpg", adresseLat: 45.75, adresseLng: 4.85))
        // `data.prenom || ''` : prénom et nom NULL deviennent des chaînes vides, jamais un refus.
        let vide = try ProfilComplet.depuis(ligne(["prenom": .null, "nom": .null]), userId: "u-1")
        XCTAssertEqual(vide.prenom, "")
        XCTAssertEqual(vide.nom, "")
    }

    func testContratsDerivesCommeGetTypesContratSoignant() throws {
        // Tableau JSON historique, liste à virgules, puis repli sur type_exercice et type_contrat.
        let cas: [([String: ValeurJSON], [String])] = [
            (["types_contrat_acceptes": .chaine("[\"CDD\",\"LIBERAL\"]")], ["CDD", "LIBERAL"]),
            (["types_contrat_acceptes": .chaine("SALARIE")], ["SALARIE"]),
            (["type_exercice": .chaine("MIXTE")], ["CDD", "LIBERAL"]),
            (["type_exercice": .chaine("LIBERAL")], ["LIBERAL"]),
            (["type_exercice": .chaine("SALARIE"), "type_contrat": .chaine("CDD")], ["CDD"]),
            ([:], ContratCompatibilite.tousTypesContrat),
        ]
        for (champs, attendu) in cas {
            XCTAssertEqual(try ProfilComplet.depuis(ligne(champs), userId: "u-1").typesContratAcceptes, attendu, "\(champs)")
        }
    }

    func testAucuneProprieteSensibleNiTypeDExercice() {
        let profil = ProfilComplet(id: "u-1", prenom: "Léa", nom: "Martin")
        let proprietes = Set(Mirror(reflecting: profil).children.compactMap(\.label))
        let sensibles: Set<String> = ["numeroSecu", "numeroAdeli", "siretLiberal", "codeApe", "assujettiTva", "numeroTva",
                                      "stripeAccountId", "ibanLast4"]
        XCTAssertEqual(proprietes.intersection(sensibles), [])
        XCTAssertFalse(proprietes.contains("typeExercice"), "type d'exercice : renvoi web (HARD STOP n°4)")
        XCTAssertFalse(proprietes.contains("attestationCumulActivite"), "attestation L1222-5 : renvoi web")
        XCTAssertEqual(ProfilComplet.clesLues.intersection(ProfilComplet.clesSensibles), [])
        XCTAssertEqual(ProfilComplet.clesSensibles, ["numero_secu", "numero_adeli", "siret_liberal", "code_ape",
                                                     "assujetti_tva", "numero_tva", "stripe_account_id", "iban_last4"])
    }

    func testUneCleSensibleRenvoyeeParLeServeurNEstJamaisRestituee() throws {
        let profil = try ProfilComplet.depuis(ligne(["numero_secu": .chaine("1900000000000"), "iban_last4": .chaine("0189"),
                                                     "stripe_account_id": .chaine("acct_demo")]), userId: "u-1")
        let rendu = String(describing: profil)
        for valeur in ["1900000000000", "0189", "acct_demo"] {
            XCTAssertFalse(rendu.contains(valeur), "valeur sensible « \(valeur) » présente dans le profil décodé")
        }
    }

    func testDescriptionMasqueeSansIdentiteNiCoordonneesNiPosition() {
        // §2.6 du blueprint : la position GPS (`adresseLat`/`adresseLng`) n'est jamais journalisée ; la description
        // par réflexion la restituerait à la moindre interpolation (journal, fil d'Ariane Sentry, message d'erreur).
        let profil = ProfilComplet(id: "u-1-identifiant", prenom: "Léa", nom: "Martin", email: "lea@example.invalid",
                                   telephone: "0611223344", dateNaissance: "1990-05-14", numeroRpps: "10101010101",
                                   villeRecherche: "Grenoble", bio: "Infirmière", adresseLat: 45.7578, adresseLng: 4.832)
        let rendus = [String(describing: profil), String(reflecting: profil), "\(profil)", "\([profil])",
                      String(describing: ProfilEditionModel.Etat.pret(profil)), String(reflecting: Optional(profil))]
        for rendu in rendus {
            for valeur in ["u-1-identifiant", "Léa", "Martin", "lea@example", "0611223344", "1990-05-14", "10101010101",
                           "Grenoble", "Infirmière", "45.7578", "4.832"] {
                XCTAssertFalse(rendu.contains(valeur), "« \(valeur) » restitué par « \(rendu) »")
            }
        }
        XCTAssertEqual(String(describing: profil), "ProfilComplet(valeurs masquées, position masquée, RPPS non vérifié)")
        XCTAssertEqual(String(describing: ProfilComplet(id: "u", prenom: "", nom: "", rppsVerifie: true)),
                       "ProfilComplet(valeurs masquées, sans position, RPPS vérifié)")
        // Les gardes de liste blanche lisent toujours les vrais noms de propriétés (`Mirror` non redéfini).
        XCTAssertTrue(Set(Mirror(reflecting: profil).children.compactMap(\.label)).isSuperset(of: ["adresseLat", "telephone"]))
    }

    func testIdentiteVerrouilleeEtChampRppsSelonLaProfession() {
        XCTAssertTrue(ProfilComplet(id: "u", prenom: "", nom: "", rppsVerifie: true).identiteVerrouillee)
        XCTAssertFalse(ProfilComplet(id: "u", prenom: "", nom: "", rppsVerifie: false).identiteVerrouillee)
        XCTAssertFalse(ProfilComplet(id: "u", prenom: "", nom: "").identiteVerrouillee)
        // `sansRPPS = PROFESSIONS_SANS_RPPS.includes(profession) && !rppsOptionnel` (SectionProfilPrincipal l.641).
        for (profession, propose, optionnel) in [("IDE", true, false), ("MEDECIN", true, false), ("AS", true, true),
                                                 ("AES", false, false), ("AUXILIAIRE_PUERICULTURE", false, false)] {
            let profil = ProfilComplet(id: "u", prenom: "", nom: "", profession: profession)
            XCTAssertEqual(profil.rppsPropose, propose, profession)
            XCTAssertEqual(profil.rppsOptionnel, optionnel, profession)
        }
        XCTAssertFalse(ProfilComplet(id: "u", prenom: "", nom: "").rppsPropose, "profession absente : aucun champ")
    }
}
