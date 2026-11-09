import XCTest
@testable import JoleneCore

/// Règles pures de la complétion soignant (lot 3, T8), portées de `src/pages/InscriptionSoignant.tsx` (mode parcours) et
/// de `finaliserProfil` (`src/lib/inscriptionProgressive.ts`) : garde du formulaire, RPPS par profession (listes du web
/// et de `register-soignant`, vecteur golden `professions-rpps.json`), modes après le référentiel (aucune règle en dur),
/// clés du brouillon et du corps de `register-soignant` (liste blanche).
final class CompletionProfilRulesTests: XCTestCase {
    private typealias R = CompletionRules
    private typealias T = CompletionTextes

    /// 9 novembre 2026, 12:00 UTC.
    private let maintenant = Date(timeIntervalSince1970: 1_794_225_600)

    func testTelephoneSelonLeMotifDuWeb() {
        // `/^[+]?[0-9\s]{8,15}$/` sur la saisie sans blancs de bord (l.228).
        for valide in ["+33612345678", "06 12 34 56 78", " 0612345678 ", "12345678"] {
            XCTAssertTrue(R.telephoneValide(valide), valide)
        }
        for invalide in ["", "0612", "06-12-34-56-78", "+33 6 12 34 56 78", "06123456789012345", "++33612345678", "06a2345678"] {
            XCTAssertFalse(R.telephoneValide(invalide), invalide)
        }
    }

    func testRppsAfficheOptionnelOuObligatoireSelonLesListesDuWeb() {
        // Correction 20 : obligatoire pour `PROFESSIONS_RPPS_REQUIS`, optionnel pour les autres professions à RPPS et
        // pour AS, masqué pour `PROFESSIONS_SANS_RPPS` hors AS.
        for (valeur, _) in MissionPresentation.professions {
            XCTAssertEqual(R.afficheRpps(profession: valeur), !ProfessionsRpps.estSansRpps(valeur) || valeur == "AS", valeur)
            XCTAssertEqual(R.rppsObligatoire(profession: valeur), ProfessionsRpps.exigeRpps(valeur), valeur)
        }
        XCTAssertTrue(R.afficheRpps(profession: "AS"))
        XCTAssertFalse(R.rppsObligatoire(profession: "AS"))
        XCTAssertEqual(R.aideRpps(profession: "AS"), T.aideRppsAideSoignant)
        XCTAssertFalse(R.afficheRpps(profession: "AES"), "AES : CNI et diplôme, ni RPPS ni RCP (CLAUDE.md)")
        XCTAssertFalse(R.afficheRpps(profession: "AUXILIAIRE_PUERICULTURE"))
        XCTAssertEqual(R.aideRpps(profession: "IDE"), T.aideRppsOptionnel)
        for requis in ["MEDECIN", "DENTISTE", "SAGE_FEMME", "PHARMACIEN"] {
            XCTAssertTrue(R.rppsObligatoire(profession: requis), requis)
            XCTAssertNil(R.aideRpps(profession: requis), "aucune aide « optionnel » pour \(requis)")
        }
        XCTAssertFalse(R.afficheRpps(profession: ""), "profession absente : aucun champ")
    }

    func testSaisieDuRppsChiffresSeulementOnzeAuPlus() {
        XCTAssertEqual(R.filtrerRpps("10 00-1234 5678 999"), "10001234567")
        XCTAssertEqual(R.filtrerRpps("abc"), "")
        XCTAssertEqual(R.filtrerRpps("١٢٣"), "", "chiffres non ASCII refusés (`\\D` du web)")
    }

    func testMajoriteCommeLeFormulaireWeb() {
        // `Date.now() - new Date(dateNaissance) >= 18 × 365,25 jours` (minuit UTC de la date saisie).
        XCTAssertTrue(R.majeur(dateNaissance: "2000-01-01", maintenant: maintenant))
        XCTAssertTrue(R.majeur(dateNaissance: "2008-11-08", maintenant: maintenant), "6 575,5 jours")
        XCTAssertFalse(R.majeur(dateNaissance: "2008-11-11", maintenant: maintenant), "6 572,5 jours")
        XCTAssertFalse(R.majeur(dateNaissance: "2010-06-15", maintenant: maintenant))
        for illisible in [nil, "", "2000-13-01", "2000-02-30", "01/01/2000", "2000-1-1"] {
            XCTAssertFalse(R.majeur(dateNaissance: illisible, maintenant: maintenant), illisible ?? "nil")
        }
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "UTC")!
        let borne = R.dateMaximale(maintenant: maintenant, calendrier: calendrier)
        XCTAssertEqual(calendrier.dateComponents([.year, .month, .day], from: borne),
                       DateComponents(year: 2008, month: 11, day: 9), "`max` du sélecteur : aujourd'hui moins 18 ans (l.554)")
    }

    func testInformationsAVerifierDansLOrdreDuWeb() {
        let manques = R.manques(prenom: "", nom: "", telephone: "06", dateNaissance: nil, profession: "MEDECIN",
                                typesContrat: [], rpps: "123", maintenant: maintenant)
        XCTAssertEqual(manques, [T.manquePrenom, T.manqueNom, T.manqueTelephone, T.manqueDateNaissance, T.manqueModeExercice,
                                 T.manqueRpps])
        XCTAssertEqual(R.messageManques(manques),
                       "Vérifiez les informations suivantes : prénom, nom, téléphone valide, date de naissance (18 ans minimum), mode d’exercice, numéro RPPS à 11 chiffres.")
        XCTAssertEqual(R.manques(prenom: "Léa", nom: "Martin", telephone: "0612345678", dateNaissance: "1990-05-14",
                                 profession: "IDE", typesContrat: ["CDD"], rpps: "", maintenant: maintenant), [],
                       "RPPS optionnel pour IDE : formulaire envoyable sans numéro")
        XCTAssertEqual(R.manques(prenom: "Léa", nom: "Martin", telephone: "0612345678", dateNaissance: "2010-05-14",
                                 profession: "IDE", typesContrat: ["CDD"], rpps: "", maintenant: maintenant),
                       [T.manqueDateNaissance], "mineur : bloqué avant l'envoi comme le web")
        XCTAssertEqual(R.manques(prenom: "Léa", nom: "Martin", telephone: "0612345678", dateNaissance: "1990-05-14",
                                 profession: "", typesContrat: ["CDD"], rpps: "", maintenant: maintenant), [T.manqueProfession])
    }

    func testTypeUniqueEtPhraseAssembleeCommeLeJSX() {
        XCTAssertEqual(R.typeUnique(["SALARIE"]), "SALARIE")
        XCTAssertNil(R.typeUnique(["SALARIE", "LIBERAL", "MIXTE"]))
        XCTAssertNil(R.typeUnique([]))
        XCTAssertNil(R.typeUnique(nil), "référentiel inconnu : aucune phrase")
        XCTAssertEqual(R.phraseTypeUnique(profession: "AS", type: "SALARIE"),
                       "En tant que Aide-Soignant(e) (AS), votre type d'exercice est automatiquement défini comme salarié.")
        XCTAssertEqual(R.phraseTypeUnique(profession: "IDE", type: "LIBERAL"),
                       "En tant que Infirmier(ère) Diplômé(e) d'État (IDE), votre type d'exercice est automatiquement défini comme libéral.")
        XCTAssertTrue(R.phraseTypeUnique(profession: "IDE", type: "MIXTE").hasSuffix("comme mixte."))
        XCTAssertTrue(R.phraseTypeUnique(profession: "IDE", type: "AUTRE").hasSuffix("comme mixte."), "ternaire du web : « mixte » sinon")
    }

    /// Décision déléguée du 8 novembre 2026 (`DECISIONS_LOT3.md`, T8) : parité avec le web actuel (l.191-199,
    /// `ChoixModesExercice.tsx` l.43) — retrait du libéral quand le référentiel ne le propose pas, conservation tant que le
    /// référentiel est inconnu, jamais d'ajout sans confirmation.
    func testModesApresLeReferentiel() {
        XCTAssertEqual(R.contratsApresReferentiel(["CDD", "LIBERAL"], typesAutorises: ["SALARIE"]), ["CDD"])
        XCTAssertEqual(R.contratsApresReferentiel(["LIBERAL"], typesAutorises: ["SALARIE"]), [], "le web retire sans remplacer")
        XCTAssertEqual(R.contratsApresReferentiel(["CDD", "LIBERAL"], typesAutorises: ["SALARIE", "LIBERAL", "MIXTE"]), ["CDD", "LIBERAL"])
        XCTAssertEqual(R.contratsApresReferentiel(["LIBERAL"], typesAutorises: ["MIXTE"]), ["LIBERAL"])
        XCTAssertEqual(R.contratsApresReferentiel(["CDD", "LIBERAL"], typesAutorises: nil), ["CDD", "LIBERAL"],
                       "référentiel inconnu : choix conservés")
        // Libéral jamais ajoutable sans référentiel : l'option n'est pas proposée tant qu'elle n'est pas cochée.
        let inconnu = ChoixModesExercice.presenter(valeur: ["CDD"], typesAutorises: nil, chargement: false, indisponible: true)
        XCTAssertEqual(inconnu.options.map(\.mode), [.salarie])
    }

    func testBrouillonReduitALaListeBlanche() throws {
        let formulaire = FormulaireInscription(prenom: "Léa", nom: "", telephone: "0612345678", dateNaissance: "1990-05-14",
                                               profession: "IDE", typesContrat: ["CDD", "LIBERAL"], rpps: "", rayon: 25)
        let donnees = R.donneesBrouillon(formulaire)
        XCTAssertEqual(Set(donnees.keys), ["prenom", "nom", "telephone", "dateNaissance", "typesContrat", "rpps", "rayon"])
        XCTAssertTrue(Set(donnees.keys).isSubset(of: R.clesBrouillon))
        XCTAssertNil(donnees["profession"], "profession figée du parcours : jamais réécrite")
        XCTAssertEqual(donnees["nom"], .chaine(""), "un effacement saisi est transmis (`donnees || p_donnees`)")
        XCTAssertEqual(donnees["typesContrat"], .tableau([.chaine("CDD"), .chaine("LIBERAL")]))
        XCTAssertEqual(donnees["rayon"], .nombre(25))
        // Liste blanche serveur (`fn_enregistrer_parcours_inscription`, public.sql l.32485-32491) : aucune clé interdite.
        let serveur: Set<String> = ["profession", "prenom", "nom", "telephone", "dateNaissance", "typesContrat", "rpps", "rayon",
                                    "estSalarieEtablissement", "estEtudiant", "scolariteFormation", "scolariteAnnee"]
        XCTAssertTrue(R.clesBrouillon.isSubset(of: serveur))
        for interdite in ["email", "motDePasse", "confirmMdp", "lat", "lng", "turnstileToken", "etudiant_details"] {
            XCTAssertFalse(R.clesBrouillon.contains(interdite), interdite)
        }
        let minimal = R.donneesBrouillon(FormulaireInscription(profession: "IDE"))
        XCTAssertEqual(Set(minimal.keys), ["typesContrat"], "champ nil : non transmis")
    }

    func testCorpsDeRegisterSoignantCommeFinaliserProfil() {
        let corps = R.corpsFinalisation(FormulaireInscription(prenom: "Léa", nom: "Martin", telephone: "", dateNaissance: "1990-05-14",
                                                              profession: "IDE", typesContrat: ["CDD"], rpps: "", rayon: nil))
        XCTAssertEqual(Set(corps.keys), ["prenom", "nom", "telephone", "dateNaissance", "profession", "typesContrat", "rpps"])
        XCTAssertTrue(Set(corps.keys).isSubset(of: R.clesFinalisation))
        XCTAssertEqual(corps["telephone"], .null, "`form.telephone || null`")
        XCTAssertEqual(corps["rpps"], .null, "`form.rpps || null`")
        XCTAssertEqual(corps["profession"], .chaine("IDE"))
        XCTAssertNil(corps["rayon"], "aucun rayon par défaut côté app : le serveur applique 30 km (l.295)")
        for absente in ["lat", "lng", "est_etudiant", "etudiant_details", "email", "navigateur", "attribution", "estSalarieEtablissement"] {
            XCTAssertNil(corps[absente], absente)
        }
        let avecRayon = R.corpsFinalisation(FormulaireInscription(prenom: "L", nom: "M", telephone: "0612345678", dateNaissance: "1990-05-14",
                                                                  profession: "MEDECIN", typesContrat: ["CDD"], rpps: "10001234567", rayon: 40))
        XCTAssertEqual(avecRayon["rayon"], .nombre(40), "rayon du brouillon retransmis")
        XCTAssertEqual(avecRayon["rpps"], .chaine("10001234567"))
        XCTAssertEqual(avecRayon["telephone"], .chaine("0612345678"))
    }

    func testCodeDeFinalisationEnAttenteEtDelai() {
        XCTAssertEqual(R.codeFinalisationEnAttente, "ACCOUNT_FINALIZATION_PENDING")
        XCTAssertEqual(CompletionProfilModel.delaiFinalisation(15), 30)
    }
}
