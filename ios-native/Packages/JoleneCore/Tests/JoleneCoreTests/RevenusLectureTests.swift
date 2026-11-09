import XCTest
@testable import JoleneCore

/// Lecture des revenus (lot 3, T12, B9) : formes de réponse de `fn_mes_revenus_connect` et `fn_mes_paiements_escrow`
/// (définitions live relues en lecture seule le 09/11/2026, identiques au dump `public.sql` l.42233 et l.42396), lignes
/// PostgREST des colonnes de `MesGains.tsx` l.95 (missions) et l.102 (paiements), assemblage d'une page (dernière
/// déclaration par mission, nom d'établissement de `fn_etablissements_safe`). Aucun montant n'est recalculé.
final class RevenusLectureTests: XCTestCase {
    private func json(_ texte: String) throws -> ValeurJSON {
        try JSONDecoder().decode(ValeurJSON.self, from: Data(texte.utf8))
    }

    private func decoder<T: Decodable>(_ type: T.Type, _ texte: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(texte.utf8))
    }

    // MARK: - Totaux (`fn_mes_revenus_connect`)

    func testTotauxTroisNombresFinisEtDrapeauConnect() throws {
        let totaux = TotauxRevenus.lire(try json(#"{"mois_en_cours":195,"total":1425.6,"en_attente":0,"stripe_connect_actif":true}"#))
        XCTAssertEqual(totaux, TotauxRevenus(moisEnCours: 195, total: 1425.6, enAttente: 0, stripeConnectActif: true))
        let sansDrapeau = TotauxRevenus.lire(try json(#"{"mois_en_cours":1,"total":2,"en_attente":3,"stripe_connect_actif":null}"#))
        XCTAssertEqual(sansDrapeau, TotauxRevenus(moisEnCours: 1, total: 2, enAttente: 3, stripeConnectActif: nil))
    }

    /// Web `PageStripeConnect.tsx` l.74-76 : `typeof data[key] !== 'number' || !Number.isFinite(data[key])` → indisponible.
    func testTotauxIncompletsTextuelsOuNonObjetRefuses() throws {
        let refuses = [
            #"{"mois_en_cours":1,"total":2}"#,
            #"{"mois_en_cours":"1","total":2,"en_attente":3}"#,
            #"{"mois_en_cours":null,"total":2,"en_attente":3}"#,
            #"{"mois_en_cours":true,"total":2,"en_attente":3}"#,
            #"{"error":"Non authentifié"}"#,
            "null", "[]", "12",
        ]
        for corps in refuses {
            XCTAssertNil(TotauxRevenus.lire(try json(corps)), corps)
        }
    }

    // MARK: - Exercice et compte Connect (visibilité des totaux)

    /// Revue B8 de T12, M1 : les cartes du web ne sont **rendues** que pour `isLiberal` (`PageStripeConnect.tsx` l.178,
    /// `typeExercice === 'LIBERAL' || typeExercice === 'MIXTE'`, appliqué l.300 ; `statut_liberal` n'y entre pas) hors
    /// compte de test (`!estCompteTest`, l.302 et l.367). La condition de l.106 (`… || sg.statut_liberal === 'ACTIF'`)
    /// n'est que celle du CHARGEMENT : un salarié `statut_liberal = ACTIF` ne voit jamais les totaux (ses réceptions de
    /// salaire `paiements_soignant` CONFIRME y seraient comptées comme « Total réglé »). C'est la visibilité d'une
    /// section, jamais le régime d'une ligne financière (règle Lot 14 : `missions.type_contrat_applique`).
    func testExerciceAfficheLesTotauxCommeLesCartesDeLaPageStripeConnect() throws {
        let cas: [(String?, Bool?, Bool)] = [
            ("LIBERAL", nil, true), ("MIXTE", nil, true), ("LIBERAL", false, true), ("MIXTE", false, true),
            ("SALARIE", nil, false), ("SALARIE", false, false), (nil, nil, false), ("liberal", false, false),
            ("LIBERAL", true, false), ("MIXTE", true, false), ("SALARIE", true, false),
        ]
        for (type, test, attendu) in cas {
            XCTAssertEqual(ExerciceRevenus(typeExercice: type, estCompteTest: test).afficheTotaux, attendu,
                           "\(String(describing: type)) compte test \(String(describing: test))")
        }
        let lu = try decoder(ExerciceRevenus.self, #"{"type_exercice":"MIXTE","est_compte_test":false}"#)
        XCTAssertEqual(lu, ExerciceRevenus(typeExercice: "MIXTE", estCompteTest: false))
        // Le cas de la revue : salarié avec `statut_liberal = ACTIF` (clé ignorée), jamais de totaux.
        let salarieActif = try decoder(ExerciceRevenus.self, #"{"type_exercice":"SALARIE","statut_liberal":"ACTIF","est_compte_test":false}"#)
        XCTAssertFalse(salarieActif.afficheTotaux, "SALARIE + statut_liberal ACTIF : chargé par le web (l.106), jamais affiché (l.178, l.300)")
        let test = try decoder(ExerciceRevenus.self, #"{"type_exercice":"LIBERAL","est_compte_test":true}"#)
        XCTAssertFalse(test.afficheTotaux, "compte de test : carte « Stripe désactivé », jamais les totaux (l.302, l.367)")
    }

    /// `statut === 'COMPLET'` (l.367) : seul un compte Connect complet voit les cartes. Le natif ne lit pas l'edge
    /// `stripe-connect-status` (T14a) : il prend `stripe_connect_actif` de la même réponse
    /// (`fn_soignant_stripe_connect_actif` : `stripe_connect_onboarding` COMPLET + `onboarding_complete`, `charges_enabled`,
    /// `payouts_enabled`, la ligne que l'edge relit et réécrit). `false` → section absente même sans les trois nombres ;
    /// drapeau absent ou non booléen → statut inconnu, section absente (le web masque les cartes sur `erreurStatut`) ;
    /// `true` sans les trois nombres finis → « indisponible » (l.387-391, `erreurRevenus` dans la branche COMPLET).
    func testTotauxVisiblesSeulementPourUnCompteConnectComplet() throws {
        let complet = try TotauxRevenus.visibles(try json(#"{"mois_en_cours":195,"total":1425.6,"en_attente":0,"stripe_connect_actif":true}"#))
        XCTAssertEqual(complet, TotauxRevenus(moisEnCours: 195, total: 1425.6, enAttente: 0, stripeConnectActif: true))
        for corps in [
            #"{"mois_en_cours":195,"total":1425.6,"en_attente":0,"stripe_connect_actif":false}"#,
            #"{"mois_en_cours":"x","stripe_connect_actif":false}"#,
            #"{"mois_en_cours":195,"total":1425.6,"en_attente":0}"#,
            #"{"mois_en_cours":195,"total":1425.6,"en_attente":0,"stripe_connect_actif":null}"#,
            #"{"mois_en_cours":195,"total":1425.6,"en_attente":0,"stripe_connect_actif":"true"}"#,
        ] {
            XCTAssertNil(try TotauxRevenus.visibles(try json(corps)), "compte Connect non complet ou inconnu : aucune carte (\(corps))")
        }
        for corps in [#"{"mois_en_cours":1,"total":"2","en_attente":3,"stripe_connect_actif":true}"#,
                      #"{"error":"Non authentifié"}"#, "null", "[]"] {
            XCTAssertThrowsError(try TotauxRevenus.visibles(try json(corps)), corps) { erreur in
                XCTAssertEqual((erreur as? JoleneError)?.kind, .unknown, corps)
                XCTAssertEqual((erreur as? JoleneError)?.message, RevenusTextes.totauxIndisponibles, corps)
            }
        }
    }

    /// Test-garde des sources web citées (M1) : si la condition d'affichage change sur le web, ce test rougit.
    func testConditionsDuWebCiteesASaLigne() throws {
        let stripe = try CompteVerbatimTests.lignes("src/pages/PageStripeConnect.tsx")
        XCTAssertTrue(stripe[94].contains(".select('prenom, nom, type_exercice, statut_liberal, est_compte_test')"), "l.95")
        XCTAssertTrue(stripe[105].contains("if (sg.type_exercice === 'LIBERAL' || sg.type_exercice === 'MIXTE' || sg.statut_liberal === 'ACTIF') {"),
                      "l.106 : condition de chargement seulement")
        XCTAssertTrue(stripe[177].contains("const isLiberal = typeExercice === 'LIBERAL' || typeExercice === 'MIXTE';"), "l.178")
        XCTAssertTrue(stripe[299].contains("{isLiberal && ("), "l.300")
        XCTAssertTrue(stripe[366].contains("{!estCompteTest && !erreurStatut && statut === 'COMPLET' && ("), "l.367")
        XCTAssertTrue(stripe[391].contains("{revenus && ("), "l.392")
        XCTAssertTrue(stripe[92].contains("Ne jamais déduire le mode d'exercice d'une lecture en panne."), "l.93")
    }

    // MARK: - Paiements rapides (`fn_mes_paiements_escrow`)

    func testEscrowLuDansLOrdreServeur() throws {
        let corps = try json("""
        [{"mission_id":"m-2","mission_intitule":"Nuit","etablissement_nom":"Clinique","honoraires_cents":15000,"etat":"RETARDE",
          "date_affichee":"2026-11-04T08:00:00+00:00","mission_date":"2026-10-28T07:00:00+00:00","a_litige":false},
         {"mission_id":"m-1","mission_intitule":null,"etablissement_nom":null,"honoraires_cents":24000,"etat":"RESERVE",
          "date_affichee":null,"mission_date":"2026-11-09T07:00:00+00:00","a_litige":true}]
        """)
        let lignes = try PaiementRapide.lireListe(corps)
        XCTAssertEqual(lignes, [
            PaiementRapide(missionId: "m-2", missionIntitule: "Nuit", etablissementNom: "Clinique", honorairesCents: 15000,
                           etat: "RETARDE", dateAffichee: "2026-11-04T08:00:00+00:00", missionDate: "2026-10-28T07:00:00+00:00",
                           aLitige: false),
            PaiementRapide(missionId: "m-1", honorairesCents: 24000, etat: "RESERVE", missionDate: "2026-11-09T07:00:00+00:00",
                           aLitige: true),
        ])
        XCTAssertEqual(try PaiementRapide.lireListe(try json("[]")), [])
    }

    /// `eur((cents ?? 0) / 100)` du web : un montant absent vaut 0 ; une ligne sans mission n'a pas d'identifiant et
    /// n'est pas affichée ; l'état est conservé tel quel (le filtre des sept états est une règle de présentation).
    func testEscrowMontantAbsentEtLigneSansMission() throws {
        let corps = try json("""
        [{"mission_id":"m-1","honoraires_cents":null,"etat":"ANNULE"},{"honoraires_cents":100,"etat":"VERSE"},
         {"mission_id":"","honoraires_cents":100,"etat":"VERSE"},{"mission_id":"m-3","honoraires_cents":100,"etat":"INCONNU"}]
        """)
        let lignes = try PaiementRapide.lireListe(corps)
        XCTAssertEqual(lignes.map(\.missionId), ["m-1", "m-3"])
        XCTAssertEqual(lignes.first?.honorairesCents, 0)
        XCTAssertEqual(lignes.last?.etat, "INCONNU")
    }

    /// La RPC rend toujours un tableau (`COALESCE(jsonb_agg(…), '[]')`) : un autre corps est un décalage de contrat,
    /// jamais une liste vide plausible.
    func testEscrowCorpsNonTableauEstUnRefusDeContrat() throws {
        for corps in [#"{"error":"x"}"#, "null", "12", #""liste""#] {
            XCTAssertThrowsError(try PaiementRapide.lireListe(try json(corps)), corps) { erreur in
                XCTAssertEqual((erreur as? JoleneError)?.kind, .contract, corps)
            }
        }
    }

    // MARK: - Missions terminées (`MesGains.tsx` l.95)

    func testMissionDecodeLesColonnesDeMesGains() throws {
        let mission = try decoder(MissionTerminee.self, """
        {"id":"m-1","intitule":"Nuit","debut_le":"2026-11-01T07:00:00+00:00","fin_le":"2026-11-01T15:00:00+00:00",
         "duree_heures":8,"nb_creneaux":1,"taux_horaire_base":"26.50","net_a_payer":224.6,"net_estime":162.4,"total_brut":208,
         "statut":"TERMINEE","etablissement_id":"e-1","service":"Médecine","type_contrat_applique":"SALARIE",
         "type_contrat_recherche":"SALARIE","presences":[{"valide_par_etablissement":true,"valide_auto_72h_le":null,"valide_le":null}]}
        """)
        XCTAssertEqual(mission, MissionTerminee(id: "m-1", intitule: "Nuit", debutLe: "2026-11-01T07:00:00+00:00",
                                                finLe: "2026-11-01T15:00:00+00:00", etablissementId: "e-1",
                                                typeContratApplique: "SALARIE", typeContratRecherche: "SALARIE",
                                                netAPayer: 224.6, netEstime: 162.4, totalBrut: 208, dureeHeures: 8,
                                                tauxHoraireBase: 26.5, service: "Médecine", statut: "TERMINEE"))
        XCTAssertThrowsError(try decoder(MissionTerminee.self, #"{"intitule":"sans id"}"#))
    }

    /// Décision 5 du lot 3 (correction 19) : les colonnes Rist ne sont pas lues ; même présentes dans la ligne (fixture
    /// démo complète), la correction de l'ancien plafond reste inactive et le montant stocké est affiché, comme le web.
    func testColonnesRistIgnoreesLaCorrectionResteInactive() throws {
        let mission = try decoder(MissionTerminee.self, """
        {"id":"m-rist","type_contrat_applique":"LIBERAL","type_contrat_recherche":"LIBERAL","taux_horaire_base":40,
         "net_a_payer":280,"total_brut":280,"rist_plafond_applique":true,"taux_rist_plafonne":35,
         "soignant_assigne_id":"demo-soignant","profession_requise":"IDE"}
        """)
        XCTAssertNil(mission.finance.ristPlafondApplique)
        XCTAssertNil(mission.finance.tauxRistPlafonne)
        XCTAssertNil(mission.finance.soignantAssigneId)
        XCTAssertEqual(MontantMission.montantAffiche(mission.finance)?.montant, 280, "jamais 320 (correction inactive)")
    }

    /// `regimeMission` du web (l.56-59) : `type_contrat_applique ?? type_contrat_recherche`, seulement SALARIE ou LIBERAL.
    /// Jamais `soignants.type_exercice` (règle Lot 14, `test:guards` 7).
    func testRegimeDeLaMissionVientDuContratDeLaMission() {
        let cas: [(String?, String?, String?)] = [
            ("SALARIE", "LIBERAL", "SALARIE"), (nil, "LIBERAL", "LIBERAL"), ("LIBERAL", nil, "LIBERAL"),
            (nil, "TOUS", nil), (nil, nil, nil), ("", "LIBERAL", nil),
        ]
        for (applique, recherche, attendu) in cas {
            let mission = MissionTerminee(id: "m", typeContratApplique: applique, typeContratRecherche: recherche)
            XCTAssertEqual(mission.regime, attendu, "\(String(describing: applique)) / \(String(describing: recherche))")
        }
    }

    // MARK: - Paiements déclarés (`MesGains.tsx` l.102)

    func testPaiementDecodeLesColonnesDuWeb() throws {
        let paiement = try decoder(PaiementSoignantLu.self, """
        {"id":"p-1","mission_id":"m-1","facture_honoraire_id":null,"statut":"DECLARE","montant_net":"162.40",
         "confirme_par_soignant":false,"conteste":false,"montant_du_reference":null,"source_montant_du":null,
         "methode":"VIREMENT","reference_virement":null,"date_paiement":"2026-11-02","modifie_le":null,"cree_le":"2026-11-02T08:00:00+00:00"}
        """)
        XCTAssertEqual(paiement.id, "p-1")
        XCTAssertEqual(paiement.missionId, "m-1")
        XCTAssertEqual(paiement.salaire, PaiementSalairePourUi(statut: "DECLARE", montantNet: .chaine("162.40"), confirmeParSoignant: false,
                                                               conteste: false, montantDuReference: nil, sourceMontantDu: nil))
        XCTAssertEqual(EtatPaiement.classerPaiementSalaire(paiement.salaire).libelle, "Réception à confirmer")
    }

    // MARK: - Assemblage d'une page

    func testPageIndexeLaDerniereDeclarationEtLeNomDEtablissement() throws {
        let missions = [
            MissionTerminee(id: "m-1", etablissementId: "e-1", typeContratApplique: "SALARIE"),
            MissionTerminee(id: "m-2", etablissementId: "e-2", typeContratApplique: "SALARIE"),
            MissionTerminee(id: "m-3", etablissementId: nil, typeContratApplique: "LIBERAL"),
        ]
        let paiements = [
            PaiementSoignantLu(id: "p-b", missionId: "m-1", statut: "CONTESTE", conteste: true, modifieLe: "2026-10-01T08:00:00+00:00"),
            PaiementSoignantLu(id: "p-a", missionId: "m-1", statut: "CONFIRME", montantNet: .nombre(170.5), confirmeParSoignant: true,
                               modifieLe: "2026-10-03T08:00:00+00:00"),
            PaiementSoignantLu(id: "p-c", missionId: "autre", statut: "DECLARE"),
        ]
        let page = RevenusAssemblage.page(missions, paiements: paiements, etablissements: ["e-1": "Clinique", "e-9": "Autre"], page: 0)
        XCTAssertEqual(page.page, 0)
        XCTAssertFalse(page.aSuivre)
        XCTAssertEqual(page.missions.map(\.id), ["m-1", "m-2", "m-3"], "ordre serveur conservé")
        XCTAssertEqual(page.missions[0].etablissementNom, "Clinique")
        XCTAssertNil(page.missions[1].etablissementNom, "nom absent : jamais deviné")
        XCTAssertEqual(page.missions[0].dernierPaiement?.id, "p-a", "la plus récente l'emporte (modifie_le), jamais l'ordre reçu")
        XCTAssertNil(page.missions[1].dernierPaiement)
        XCTAssertEqual(EtatPaiement.classerPaiementSalaire(page.missions[0].dernierPaiement?.salaire).libelle, "Réception confirmée")
    }

    func testPageASuivreSeulementQuandElleEstPleine() {
        XCTAssertEqual(RevenusAssemblage.taillePage, 50, "PAGE_SIZE de MesGains.tsx l.72")
        let pleine = (0..<50).map { MissionTerminee(id: "m-\($0)") }
        XCTAssertTrue(RevenusAssemblage.page(pleine, paiements: [], etablissements: [:], page: 2).aSuivre)
        XCTAssertFalse(RevenusAssemblage.page(Array(pleine.dropLast()), paiements: [], etablissements: [:], page: 2).aSuivre)
    }
}
