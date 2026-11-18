import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurIban = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                appMetadataRole: "SOIGNANT")

/// IBAN du soignant (lot 3, T14b, B9 ; D20, TJ6 ; liste de tests du blueprint §3 T14b) :
/// - contrôle local identique au web (`validateIbanChecksum`, `SectionPaiements.tsx` l.212-225, l.248-249, l.337) ;
/// - `success:false` sans `error` → message du code (TJ6), jamais « IBAN enregistré » ; `error` serveur verbatim ;
/// - succès seulement après relecture probante (`IbanRelecture`, `iban_verifie == true`) ;
/// - IBAN jamais conservé : champ vidé dès l'envoi, quelle que soit l'issue ;
/// - textes verbatim du web à leur ligne, textes nouveaux listés dans le mémo avec la ligne de délégation.
@MainActor
final class IbanTests: XCTestCase {
    private typealias T = IbanTextes
    private static let section = "src/components/profil-soignant/SectionPaiements.tsx"
    private static let exemple = "FR7630006000011234567890189"

    // MARK: - Règles (port du web)

    func testControleMod97IdentiqueAuWeb() {
        XCTAssertTrue(IbanRules.estValide(Self.exemple))
        XCTAssertTrue(IbanRules.estValide("fr76 3000 6000 0112 3456 7890 189"), "minuscules et espaces (toUpperCase, \\s)")
        XCTAssertTrue(IbanRules.estValide("FR76\u{00A0}3000\u{202F}6000\t0112 3456 7890 189\n"), "blancs JavaScript")
        XCTAssertTrue(IbanRules.estValide("GB82WEST12345698765432"))
        XCTAssertTrue(IbanRules.estValide("DE89370400440532013000"))
        XCTAssertFalse(IbanRules.estValide("FR7630006000011234567890188"), "clé fausse")
        XCTAssertFalse(IbanRules.estValide("FR76-3000-6000-0112-3456-7890-189"), "le web ne retire que les blancs")
        XCTAssertFalse(IbanRules.estValide("FR76300060000"), "13 caractères : sous le minimum du web (14)")
        XCTAssertFalse(IbanRules.estValide("7630006000011234567890189FR"))
        XCTAssertFalse(IbanRules.estValide(String(repeating: "1", count: 40)))
        XCTAssertFalse(IbanRules.estValide("FR76３０００6000011234567890189"), "chiffres pleine chasse : hors [0-9]")
        XCTAssertEqual(IbanRules.nettoyer(" fr76 3000\u{00A0}6000 "), "FR7630006000")
        XCTAssertEqual(IbanRules.titulaireNettoye("\u{00A0} Camille Démo \n"), "Camille Démo")
        XCTAssertEqual(IbanRules.quatreDerniers("FR76 3000 6000 0112 3456 7890 189"), "0189")
        XCTAssertEqual(IbanRules.masque(last4: "0189"), "•••• •••• •••• •••• •••• 0189")
    }

    func testAffichageDeriveDeLaSaisie() {
        XCTAssertFalse(IbanRules.afficheInvalide("FR76"), "`iban.length > 4` (l.337)")
        XCTAssertTrue(IbanRules.afficheInvalide("FR763"))
        XCTAssertFalse(IbanRules.afficheInvalide(Self.exemple))
        XCTAssertFalse(IbanRules.peutEnregistrer(iban: Self.exemple, titulaire: "  "), "titulaire blanc (l.366)")
        XCTAssertFalse(IbanRules.peutEnregistrer(iban: "FR7630006000011234567890188", titulaire: "Camille Démo"))
        XCTAssertTrue(IbanRules.peutEnregistrer(iban: Self.exemple, titulaire: "Camille Démo"))
    }

    // MARK: - Refus (TJ6)

    /// Code → message épinglé (TJ6, règle 4) : `error` verbatim s'il existe, sinon texte existant ou nouveau.
    func testChaqueCodeAffichePasseParSaRegleJamaisIbanEnregistre() {
        let sansError: [(CodeRefusIban, RefusIbanAffiche)] = [
            (.ibanInvalide, RefusIbanAffiche(message: "IBAN invalide")),
            (.ribCourantRequis, RefusIbanAffiche(titre: "RIB vérifié requis",
                                                 message: "Téléversez puis faites vérifier le RIB correspondant.",
                                                 action: .televerserRib)),
            (.ribNonConcordant, RefusIbanAffiche(titre: "RIB vérifié requis",
                                                 message: "Téléversez puis faites vérifier le RIB correspondant.",
                                                 action: .televerserRib)),
            (.identiteVerifieeRequise, RefusIbanAffiche(
                message: "Faites d'abord vérifier votre identité, cohérente avec votre profil, depuis Mes documents.",
                action: .mesDocuments)),
            (.identiteCouranteRequise, RefusIbanAffiche(
                message: "Une pièce d'identité vérifiée à vos nom et prénom est requise : téléversez-la depuis Mes documents.",
                action: .mesDocuments)),
            (.profilIntrouvable, RefusIbanAffiche(message: "Une erreur est survenue. Veuillez réessayer.")),
        ]
        for (code, attendu) in sansError {
            let affiche = IbanPresentation.refus(code: code.rawValue, message: nil)
            XCTAssertEqual(affiche, attendu, code.rawValue)
            XCTAssertFalse(affiche.message.contains(T.ibanEnregistre), code.rawValue)
        }
        XCTAssertEqual(IbanPresentation.refus(code: "INCONNU", message: nil).message, T.erreurGenerique)
        XCTAssertEqual(IbanPresentation.refus(code: nil, message: "  ").message, T.erreurGenerique)
        // Règle 1 : `error` serveur verbatim (les deux codes qui en portent un).
        let titulaire = "Le titulaire doit correspondre exactement à votre identité vérifiée."
        XCTAssertEqual(IbanPresentation.refus(code: "TITULAIRE_NON_CONCORDANT", message: titulaire),
                       RefusIbanAffiche(message: titulaire))
        XCTAssertEqual(IbanPresentation.refus(code: "RIB_VERIFIE_REQUIS", message: T.ribCorrespondant),
                       RefusIbanAffiche(titre: T.ribVerifieRequis, message: T.ribCorrespondant, action: .televerserRib))
        XCTAssertEqual(CodeRefusIban.allCases.count, 9)
    }

    func testSuccesSeulementSurRelectureProbante() throws {
        let verifiee = ConsultationIban(ibanRenseigne: true, ibanVerifie: true, verificationRequise: false, ibanLast4: "0189")
        XCTAssertEqual(try IbanRelecture.enregistrement(relue: verifiee, ibanEnvoye: Self.exemple), .enregistre(verifiee))
        let nonVerifiee = ConsultationIban(ibanRenseigne: true, ibanVerifie: false, verificationRequise: true, ibanLast4: "0189")
        let autre = ConsultationIban(ibanRenseigne: true, ibanVerifie: true, verificationRequise: false, ibanLast4: "1234")
        for relue in [nonVerifiee, autre] {
            XCTAssertThrowsError(try IbanRelecture.enregistrement(relue: relue, ibanEnvoye: Self.exemple)) { erreur in
                XCTAssertEqual(erreur as? JoleneError, JoleneError(.unknown, T.erreurGenerique))
            }
        }
    }

    // MARK: - Démo

    func testDemoAppliqueLesRefusDuServeurPuisRelit() async throws {
        let demo = DemoIbanGateway()
        let c = DemoWorld.context
        let vide = try await demo.consulter(context: c)
        XCTAssertFalse(vide.ibanRenseigne)
        let refusTitulaire = try await demo.enregistrer(iban: Self.exemple, titulaire: "Autre Personne", context: c)
        XCTAssertEqual(refusTitulaire, .refuse(code: "TITULAIRE_NON_CONCORDANT",
                                               message: "Le titulaire doit correspondre exactement à votre identité vérifiée."))
        let autreIban = try await demo.enregistrer(iban: "GB82WEST12345698765432", titulaire: "camille demo", context: c)
        XCTAssertEqual(autreIban, .refuse(code: "RIB_NON_CONCORDANT", message: nil), "RIB démo : un seul IBAN")
        let succes = try await demo.enregistrer(iban: Self.exemple, titulaire: "Démo Camille", context: c)
        guard case let .enregistre(relue) = succes else { return XCTFail("succès attendu, obtenu \(succes)") }
        XCTAssertEqual(relue.ibanLast4, "0189")
        XCTAssertEqual(relue.ibanTitulaire, "Camille Démo")
        let ribRequis = try await DemoIbanGateway(scenario: .ribRequis)
            .enregistrer(iban: Self.exemple, titulaire: "Camille Démo", context: c)
        XCTAssertEqual(ribRequis, .refuse(code: "RIB_VERIFIE_REQUIS", message: T.ribCorrespondant))
    }

    // MARK: - Modèle

    private struct PretAuth: AuthPort {
        var utilisateur = utilisateurIban
        func restoreSession() async throws -> AuthenticatedUser? { utilisateur }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw nonScripte }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    /// Port scripté : files de réponses, journal des appels (sans l'IBAN : seul le fait de l'appel est noté). Verrou
    /// pris dans des fonctions synchrones seulement (`withLock`), jamais à travers un `await` (concurrence stricte).
    /// `lectureRetenue` : la lecture de rang donné (0 = première) attend l'ouverture de sa barrière, une fois sa
    /// réponse déjà tirée de la file (réponse « partie avant l'écriture »).
    private final class ScriptedIban: IbanPort, @unchecked Sendable {
        private let lock = NSLock()
        private var lectures: [Result<ConsultationIban, Error>]
        private var envois: [Result<ResultatIban, Error>]
        private var journal: [String] = []
        private var rangLecture = 0
        private let lectureRetenue: (rang: Int, barriere: Gate)?

        init(lectures: [Result<ConsultationIban, Error>], envois: [Result<ResultatIban, Error>] = [],
             lectureRetenue: (rang: Int, barriere: Gate)? = nil) {
            self.lectures = lectures; self.envois = envois; self.lectureRetenue = lectureRetenue
        }

        var appels: [String] { lock.withLock { journal } }

        private func noter(_ appel: String) { lock.withLock { journal.append(appel) } }

        private func suivante<V>(_ file: inout [Result<V, Error>]) -> Result<V, Error> {
            lock.withLock { file.isEmpty ? .failure(nonScripte) : file.removeFirst() }
        }

        /// Rang de la lecture et réponse tirée, sous le verrou.
        private func tirerLecture() -> (Int, Result<ConsultationIban, Error>) {
            lock.withLock {
                defer { rangLecture += 1 }
                return (rangLecture, lectures.isEmpty ? .failure(nonScripte) : lectures.removeFirst())
            }
        }

        func consulter(context: MissionReadContext) async throws -> ConsultationIban {
            noter("consulter")
            let (rang, reponse) = tirerLecture()
            if let lectureRetenue, lectureRetenue.rang == rang { await lectureRetenue.barriere.wait() }
            return try reponse.get()
        }

        func enregistrer(iban: String, titulaire: String, context: MissionReadContext) async throws -> ResultatIban {
            noter("enregistrer \(iban.count) « \(titulaire) »")
            return try suivante(&envois).get()
        }
    }

    private static let aucun = ConsultationIban(ibanRenseigne: false, ibanVerifie: false, verificationRequise: false)
    private static let verifie = ConsultationIban(ibanRenseigne: true, ibanVerifie: true, verificationRequise: false,
                                                  ibanLast4: "0189", ibanTitulaire: "Camille Démo")

    /// `utilisateur` : `DemoWorld.user` pour un port démo (qui refuse tout autre contexte, `.demoOnly`).
    private func modele(_ port: IbanPort, utilisateur: AuthenticatedUser = utilisateurIban) async throws -> IbanModel {
        var gateways = Gateways(auth: PretAuth(utilisateur: utilisateur), role: NeutralRole(), missions: PretMissions(),
                                clock: FixedClock(DemoWorld.fixedNow))
        gateways.iban = port
        let store = SessionStore(controller: SessionController(gateways: gateways,
                                                               resolutionTimeout: SessionController.defaultResolutionTimeout))
        await store.start()
        let snapshot = try XCTUnwrap(store.state.snapshot, "session prête attendue")
        return IbanModel(session: store, snapshot: snapshot)
    }

    func testSuccesApresRelectureChampsVidesEtLibelles() async throws {
        let port = ScriptedIban(lectures: [.success(Self.aucun)], envois: [.success(.enregistre(Self.verifie))])
        let model = try await modele(port)
        await model.charger()
        XCTAssertEqual(model.libelleChamp, "IBAN")
        XCTAssertEqual(model.libelleBouton, "Enregistrer l'IBAN")
        model.iban = "fr76 3000 6000 0112 3456 7890 189"
        XCTAssertEqual(model.iban, "FR76 3000 6000 0112 3456 7890 189", "mis en majuscules (l.331)")
        model.titulaire = " Camille Démo "
        XCTAssertTrue(model.afficheValide)
        XCTAssertTrue(model.peutEnregistrer)

        await model.enregistrer()

        XCTAssertEqual(model.issue, .enregistre)
        XCTAssertEqual(model.iban, "", "IBAN jamais conservé")
        XCTAssertEqual(model.titulaire, "")
        XCTAssertEqual(model.masque, "•••• •••• •••• •••• •••• 0189")
        XCTAssertEqual(model.ligneTitulaire, "Titulaire : Camille Démo")
        XCTAssertEqual(model.libelleChamp, "Modifier l'IBAN")
        XCTAssertEqual(model.libelleBouton, "Mettre à jour")
        XCTAssertEqual(port.appels, ["consulter", "enregistrer 27 « Camille Démo »"], "IBAN nettoyé, titulaire `trim()`")
    }

    func testRefusSansErrorMessageDuCodeChampIbanVideEtEtatRelu() async throws {
        let port = ScriptedIban(lectures: [.success(Self.aucun), .success(Self.aucun)],
                                envois: [.success(.refuse(code: "IDENTITE_COURANTE_REQUISE", message: nil))])
        let model = try await modele(port)
        await model.charger()
        model.iban = Self.exemple
        model.titulaire = "Camille Démo"
        await model.enregistrer()
        XCTAssertEqual(model.issue, .refus(IbanPresentation.refus(code: "IDENTITE_COURANTE_REQUISE", message: nil)))
        XCTAssertEqual(model.iban, "", "vidé dès l'envoi, même sur un refus")
        XCTAssertEqual(model.titulaire, "Camille Démo", "titulaire gardé sur un refus (le web ne le vide qu'au succès)")
        XCTAssertNil(model.masque, "jamais « IBAN enregistré » sur un refus")
        XCTAssertEqual(port.appels.filter { $0 == "consulter" }.count, 2, "état relu après le refus")
    }

    func testErreurDeTransportJamaisUnSuccesEtSessionExpiree() async throws {
        let port = ScriptedIban(lectures: [.success(Self.aucun), .success(Self.aucun)],
                                envois: [.failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))])
        let model = try await modele(port)
        await model.charger()
        model.iban = Self.exemple
        model.titulaire = "Camille Démo"
        await model.enregistrer()
        XCTAssertEqual(model.issue, .erreur("Votre session a expiré. Reconnectez-vous."))
        XCTAssertTrue(model.sessionExpiree)
        XCTAssertEqual(model.iban, "")
        XCTAssertEqual(port.appels.filter { $0.hasPrefix("enregistrer") }.count, 1, "jamais renvoyé")
    }

    /// État `iban_renseigne && !iban_verifie` (variante démo `non-verifie`, revue B8 de #1142, m2) : « RIB vérifié
    /// requis » et « Téléverser mon RIB », jamais l'IBAN masqué ni « IBAN enregistré » ; libellés de mise à jour.
    func testRenseigneNonVerifieAfficheRibRequisSansIbanMasque() async throws {
        let model = try await modele(DemoIbanGateway(scenario: .nonVerifie), utilisateur: DemoWorld.user)
        await model.charger()
        XCTAssertTrue(model.afficheRibRequis)
        XCTAssertFalse(model.afficheEnregistre)
        XCTAssertNil(model.masque, "IBAN non vérifié : jamais affiché comme enregistré")
        XCTAssertNil(model.ligneTitulaire)
        XCTAssertEqual(model.libelleChamp, "Modifier l'IBAN")
        XCTAssertEqual(model.libelleBouton, "Mettre à jour")
        XCTAssertEqual(model.consultation?.verificationRequise, true)
        // Le RIB démo vérifié lève l'état : relecture vérifiée, « RIB vérifié requis » disparaît.
        model.iban = Self.exemple
        model.titulaire = "Camille Démo"
        await model.enregistrer()
        XCTAssertEqual(model.issue, .enregistre)
        XCTAssertFalse(model.afficheRibRequis)
        XCTAssertEqual(model.masque, "•••• •••• •••• •••• •••• 0189")
    }

    /// Course `.task` × envoi (revue B8 de #1142, m4) : une lecture partie avant l'enregistrement et revenue après lui
    /// (réponse d'avant l'écriture) est ignorée ; l'état relu après le succès reste affiché.
    func testLectureEnVolAvantLEnvoiNEcrasePasLEtatRelu() async throws {
        let barriere = Gate()
        let port = ScriptedIban(lectures: [.success(Self.aucun), .success(Self.aucun)],
                                envois: [.success(.enregistre(Self.verifie))], lectureRetenue: (rang: 1, barriere: barriere))
        let model = try await modele(port)
        await model.charger()
        let lecture = Task { await model.charger() }
        while port.appels.filter({ $0 == "consulter" }).count < 2 { await Task.yield() }
        model.iban = Self.exemple
        model.titulaire = "Camille Démo"
        await model.enregistrer()
        XCTAssertEqual(model.consultation, Self.verifie)
        await barriere.open()
        await lecture.value
        XCTAssertEqual(model.consultation, Self.verifie, "réponse d'une lecture antérieure à l'envoi : ignorée")
        XCTAssertEqual(model.issue, .enregistre)
    }

    // MARK: - Textes

    /// Textes repris du web, verbatim à leur ligne (`\'` du JSX ramené à `'`).
    func testChaqueTexteRepriseDuWebEstVerbatimASaLigne() throws {
        let attendus: [(String, String, Int)] = [
            // Titre de la section (l.65) : `StripeConnectTextes.sectionHub` seul, épinglé par `StripeConnectTests`.
            (T.entreeHub, "src/pages/MonCompteSoignant.tsx", 73),
            (T.titre, Self.section, 277),
            (T.ibanEnregistre, Self.section, 262),
            (T.ibanEnregistre, Self.section, 291),
            ("•••• •••• •••• •••• •••• {current.iban_last4}", Self.section, 293),
            ("Titulaire : {current.iban_titulaire}", Self.section, 296),
            (T.ribVerifieRequis, Self.section, 306),
            (T.televerserRib, Self.section, 316),
            (T.libelleModifier, Self.section, 325),
            ("'\(T.libelleIban)'", Self.section, 325),
            (T.placeholderIban, Self.section, 332),
            (T.ibanInvalide, Self.section, 339),
            (T.ibanValide, Self.section, 344),
            (T.libelleTitulaire, Self.section, 350),
            (T.placeholderTitulaire, Self.section, 356),
            (T.enregistrement, Self.section, 369),
            (T.mettreAJour, Self.section, 369),
            (T.enregistrer, Self.section, 369),
            (T.erreurGenerique, "src/lib/erreurs.ts", 532),
            ("'error', '\(T.ribCorrespondant)'", "supabase/schema/public.sql", 32735),
        ]
        var lignes: [String: [String]] = [:]
        for (texte, fichier, ligne) in attendus {
            if lignes[fichier] == nil { lignes[fichier] = try CompteVerbatimTests.lignes(fichier) }
            let source = try XCTUnwrap(lignes[fichier])
            XCTAssertGreaterThanOrEqual(source.count, ligne, fichier)
            let brute = source[ligne - 1].replacingOccurrences(of: "\\'", with: "'")
            XCTAssertTrue(brute.contains(texte), "« \(texte) » absent de \(fichier) l.\(ligne)")
        }
        // Non portés (TJ6, TJ8) : l.280 (destinataires) et l.308 (« historique »), retirés du web par #1152 (HARD STOP
        // n°4) ; témoins inversés comme `tests/node/check-rpc-contracts-lot3.node.mjs` : la phrase de l.280 s'arrête au
        // parrainage, et aucune ligne ne dit plus « jamais partagé » ni « conservé dans ton historique ».
        let web = try CompteVerbatimTests.lignes(Self.section)
        XCTAssertTrue(web[279].contains("Ton IBAN est utilisé pour le versement de tes primes de parrainage."), "l.280")
        XCTAssertFalse(web.contains { $0.contains("jamais partagé") }, "l.280 : « jamais partagé » retiré (#1152)")
        XCTAssertFalse(web.contains { $0.contains("conservé dans ton historique") }, "l.308 : « historique » retiré (#1152)")
        let natifs = [T.titre, T.ibanEnregistre, T.ribVerifieRequis, T.ribCorrespondant, T.identiteVerifieeRequise,
                      T.identiteCouranteRequise, T.erreurGenerique]
        XCTAssertFalse(natifs.contains { $0.contains("partagé") || $0.contains("historique") || $0.contains("parrainage") })
    }

    /// TJ6, règle 4 : les deux textes nouveaux sont listés dans la section T14b du mémo, avec la ligne de délégation.
    func testTextesNouveauxListesDansLeMemoParDelegation() throws {
        let memo = try DecisionsLot3Document.document()
        let debut = try XCTUnwrap(memo.range(of: "\n### T14b — textes des refus IBAN"), "sous-section T14b du mémo")
        let suite = memo[debut.upperBound...]
        let sousSection = suite[..<(suite.range(of: "\n## ")?.lowerBound ?? suite.endIndex)]
        for texte in [T.identiteVerifieeRequise, T.identiteCouranteRequise] {
            XCTAssertTrue(sousSection.contains(texte), "« \(texte) » listé dans le mémo")
        }
        XCTAssertTrue(sousSection.contains(DecisionsLot3Document.ligneDelegation))
    }
}
