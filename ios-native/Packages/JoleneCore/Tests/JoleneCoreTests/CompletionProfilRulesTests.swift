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

    /// Revue B8 de T8, m8 : la borne du sélecteur se calcule dans le calendrier du sélecteur (UTC, `DateNaissance.fuseau`),
    /// jamais dans le fuseau de l'appareil. Cas d'un 28 février 2026 à 23:30 UTC (1er mars 00:30 à Paris) : en UTC, 18
    /// ans plus tôt est le 28 février 2008, comme le contrôle `UNDERAGE` de `register-soignant` (l.243-254, champs UTC du
    /// runtime) ; calculée à Paris, la borne laisserait choisir le 29 février 2008, refusé ensuite par le serveur.
    func testBorneDuSelecteurDansLeCalendrierUTCDuSelecteur() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let presqueMinuit = Date(timeIntervalSince1970: 1_772_321_400) // 2026-02-28T23:30:00Z
        XCTAssertEqual(utc.dateComponents([.year, .month, .day, .hour], from: presqueMinuit),
                       DateComponents(year: 2026, month: 2, day: 28, hour: 23))
        let borne = R.dateMaximale(maintenant: presqueMinuit)
        XCTAssertEqual(utc.dateComponents([.year, .month, .day], from: borne), DateComponents(year: 2008, month: 2, day: 28),
                       "borne par défaut : calendrier UTC, quel que soit le fuseau de l'appareil")
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        XCTAssertEqual(utc.dateComponents([.year, .month, .day], from: R.dateMaximale(maintenant: presqueMinuit, calendrier: paris)),
                       DateComponents(year: 2008, month: 2, day: 29), "témoin : le fuseau de Paris décalerait la borne d'un jour")
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

    /// Revue B8 de T8, m4 et B1 : la réponse « salarié(e) » est enregistrée dans le brouillon comme le web
    /// (`donneesFormulaire` l.152-167 garde `estSalarieEtablissement`), la déclaration étudiant ne l'est jamais par le
    /// natif (lue seulement : le serveur la conserve, `donnees || p_donnees`, D11).
    func testBrouillonGardeLaReponseSalarieJamaisLaDeclarationEtudiant() {
        XCTAssertTrue(R.clesBrouillon.contains("estSalarieEtablissement"))
        for lueSeulement in ["estEtudiant", "scolariteFormation", "scolariteAnnee"] {
            XCTAssertFalse(R.clesBrouillon.contains(lueSeulement), "\(lueSeulement) : jamais écrit par le natif")
        }
        let donnees = R.donneesBrouillon(FormulaireInscription(profession: "AS", typesContrat: ["CDD"],
                                                               estSalarieEtablissement: true, estEtudiant: true))
        XCTAssertEqual(donnees["estSalarieEtablissement"], .booleen(true))
        XCTAssertNil(donnees["estEtudiant"], "déclaration étudiant jamais réécrite (D11)")
        XCTAssertTrue(Set(donnees.keys).isSubset(of: R.clesBrouillon))
        XCTAssertEqual(R.donneesBrouillon(FormulaireInscription(estSalarieEtablissement: false))["estSalarieEtablissement"],
                       .booleen(false))
        XCTAssertNil(R.donneesBrouillon(FormulaireInscription())["estSalarieEtablissement"], "aucune réponse : non transmise")
    }

    /// Revue B8 de T8, B1 : un brouillon est « étudiant » quand `estEtudiant` vaut `true` (web : `est_etudiant:
    /// form.estEtudiant ?? false`, `inscriptionProgressive.ts` l.189, booléen restauré seulement) ; la finalisation
    /// native lui est refusée (D11, verrou), quelle que soit la scolarité saisie.
    func testParcoursEtudiantSurUnBooleenVraiSeulement() {
        XCTAssertTrue(R.parcoursEtudiant(FormulaireInscription(profession: "AS", estEtudiant: true)))
        XCTAssertFalse(R.parcoursEtudiant(FormulaireInscription(profession: "AS", estEtudiant: false)))
        XCTAssertFalse(R.parcoursEtudiant(FormulaireInscription(profession: "AS")))
    }

    /// Revue B8 de T8, M1 (PRINCIPES §5 : une mutation sans issue certaine exige une relecture) : les réponses de
    /// `register-soignant` qui n'excluent pas un profil créé sont des issues inconnues — tout statut ≥ 500 (passerelle,
    /// délai de l'edge, `INTERNAL_ERROR` du `catch` final l.405-407), une réponse 2xx illisible, et les codes 409 qui
    /// disent le compte finalisé, en cours de finalisation ou déjà présent dans `soignants` (l.205-212, l.329-332).
    /// Les refus certains (validation, RPPS d'un autre compte, débit) et le 503 `ACCOUNT_FINALIZATION_PENDING` (traité à
    /// part : déconnexion locale) n'en sont pas.
    func testIssuesInconnuesDeRegisterSoignant() {
        let inconnues: [(Int, String?)] = [
            (502, nil), (504, nil), (500, nil), (500, "INTERNAL_ERROR"), (503, "ACCOUNT_RESERVATION_UNAVAILABLE"),
            (546, "WORKER_LIMIT"), (200, nil), (204, nil),
            (409, "ACCOUNT_ALREADY_REGISTERED"), (409, "ACCOUNT_REGISTRATION_IN_PROGRESS"), (409, "USER_ALREADY_REGISTERED"),
        ]
        for (statut, code) in inconnues {
            XCTAssertTrue(R.issueIndeterminee(statut: statut, code: code), "\(statut) \(code ?? "sans code")")
        }
        let certaines: [(Int, String?)] = [
            (400, "UNDERAGE"), (400, "RPPS_FORMAT_INVALID"), (400, "RPPS_TRAITS_MISMATCH"), (400, "MISSING_REQUIRED_FIELDS"),
            (409, "RPPS_ALREADY_REGISTERED"), (409, "ACCOUNT_TYPE_MISMATCH"), (429, "RATE_LIMITED"), (400, nil), (403, nil),
            (503, "ACCOUNT_FINALIZATION_PENDING"),
        ]
        for (statut, code) in certaines {
            XCTAssertFalse(R.issueIndeterminee(statut: statut, code: code), "\(statut) \(code ?? "sans code")")
        }
        XCTAssertEqual(R.codesProfilPossible,
                       ["ACCOUNT_ALREADY_REGISTERED", "ACCOUNT_REGISTRATION_IN_PROGRESS", "USER_ALREADY_REGISTERED"])
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
        // Revue B8 de T8, m4 et B1 : ni la réponse « salarié(e) » (affichage et brouillon seulement, correction 21) ni la
        // déclaration étudiant (finalisée sur le web seulement, D11) ne partent vers `register-soignant`.
        let complet = R.corpsFinalisation(FormulaireInscription(prenom: "L", nom: "M", telephone: "0612345678",
                                                                dateNaissance: "1990-05-14", profession: "AS", typesContrat: ["CDD"],
                                                                rpps: "", estSalarieEtablissement: true, estEtudiant: true))
        for absente in ["estSalarieEtablissement", "estEtudiant", "est_etudiant", "etudiant_details"] {
            XCTAssertNil(complet[absente], absente)
        }
        XCTAssertTrue(Set(complet.keys).isSubset(of: R.clesFinalisation))
    }

    func testCodeDeFinalisationEnAttenteEtDelai() {
        XCTAssertEqual(R.codeFinalisationEnAttente, "ACCOUNT_FINALIZATION_PENDING")
        XCTAssertEqual(CompletionProfilModel.delaiFinalisation(15), 30)
    }
}
