import XCTest
@testable import JoleneCore

/// Gardes de sources de la vue Swipe (lot 4, T3b ; `LOT4_PLAN.md` §3 T3b, HARD STOP et correction 17). Elles ne lisent
/// que des fichiers sous `ios-native/` :
/// - **aucun appel natif ne modifie `soignants.disponible_urgence` hors `fn_toggle_pool_urgence`** (le quiz du web
///   l'écrit par un `UPDATE` direct, sans contrôle documentaire ni consentement : D26) ;
/// - la feuille « première candidature » n'écrit aucun texte : tout vient de `TextesWeb.PremiereCandidature` ;
/// - l'app n'atteint `SwipeModel.candidater` que par `ParcoursCandidatureSwipe` (feuille obligatoire avant le premier
///   envoi, revue B8 de #1165, m3) ;
/// - les identifiants du blueprint existent dans les sources, et chaque identifiant du swipe lu par `DemoSwipeTests`
///   est posé par l'app (les XCUITest ne se compilent ni ne s'exécutent hors de la CI) ;
/// - les textes d'engagement attendus par `DemoSwipeTests` sont ceux de `TextesWeb`, au caractère près.
final class SwipeSourcesAppTests: XCTestCase {
    /// Racine `ios-native/` (le fichier est sous `ios-native/Packages/JoleneCore/Tests/JoleneCoreTests/`).
    private static var racine: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    private static func lire(_ relatif: String) throws -> String {
        try String(contentsOf: racine.appendingPathComponent(relatif), encoding: .utf8)
    }

    /// Sources Swift sous `relatif` (chemins relatifs à `ios-native/`), triées, hors dossiers de build. Un dossier absent
    /// est une erreur : une garde qui ne lit rien serait vide de sens.
    private static func sourcesSwift(_ relatif: String) throws -> [(chemin: String, code: String)] {
        let dossier = racine.appendingPathComponent(relatif, isDirectory: true)
        var estDossier: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dossier.path, isDirectory: &estDossier), estDossier.boolValue,
              let parcours = FileManager.default.enumerator(at: dossier, includingPropertiesForKeys: nil) else {
            throw JoleneError(.contract, "\(relatif) introuvable sous \(racine.path)")
        }
        var fichiers: [(String, String)] = []
        for case let url as URL in parcours where url.pathExtension == "swift" && !url.path.contains("/.build/") {
            let chemin = url.path.replacingOccurrences(of: racine.path + "/", with: "")
            fichiers.append((chemin, codeSeul(try String(contentsOf: url, encoding: .utf8))))
        }
        return fichiers.sorted { $0.0 < $1.0 }
    }

    /// Code sans ses commentaires (ligne, documentation, bloc), chaînes gardées : seuls les appels comptent.
    static func codeSeul(_ source: String) -> String {
        var sansBlocs = ""
        var reste = Substring(source)
        while let debut = reste.range(of: "/*") {
            sansBlocs += reste[..<debut.lowerBound]
            guard let fin = reste[debut.upperBound...].range(of: "*/") else { reste = ""; break }
            reste = reste[fin.upperBound...]
        }
        sansBlocs += reste
        return sansBlocs.split(separator: "\n", omittingEmptySubsequences: false).map { ligne -> String in
            let caracteres = Array(ligne)
            var dansChaine = false
            var index = 0
            while index < caracteres.count {
                let caractere = caracteres[index]
                if caractere == "\\" && dansChaine { index += 2; continue }
                if caractere == "\"" { dansChaine.toggle() }
                if !dansChaine, caractere == "/", index + 1 < caracteres.count, caracteres[index + 1] == "/" {
                    return String(caracteres[..<index])
                }
                index += 1
            }
            return String(ligne)
        }.joined(separator: "\n")
    }

    /// Littéraux de chaîne d'un code sans commentaires (contenu brut entre guillemets, échappements non décodés).
    static func litteraux(_ code: String) -> [String] {
        var sortie: [String] = []
        var courant: String?
        var echappe = false
        for caractere in code {
            if var texte = courant {
                if echappe { texte.append(caractere); echappe = false; courant = texte; continue }
                if caractere == "\\" { texte.append(caractere); echappe = true; courant = texte; continue }
                if caractere == "\"" { sortie.append(texte); courant = nil; continue }
                texte.append(caractere)
                courant = texte
            } else if caractere == "\"" {
                courant = ""
            }
        }
        return sortie
    }

    private static let sourcesLivrees = ["Jolene", "Packages/JoleneCore/Sources", "Packages/JoleneSupabase/Sources", "Packages/JoleneDesign/Sources"]

    private static func toutesLesSourcesLivrees() throws -> [(chemin: String, code: String)] {
        try sourcesLivrees.flatMap { try sourcesSwift($0) }
    }

    // MARK: - Témoins des lecteurs

    func testLecteursDeSourcesTemoins() {
        XCTAssertEqual(Self.codeSeul("let a = 1 // disponible_urgence\n/// doc\n/* bloc\n suite */ b()").trimmingCharacters(in: .whitespacesAndNewlines),
                       "let a = 1 \n\n b()")
        XCTAssertEqual(Self.codeSeul(#"let u = "https://x//y" // c"#), #"let u = "https://x//y" "#)
        XCTAssertEqual(Self.litteraux(#"f("a", "b \"c\" d") + g("")"#), ["a", #"b \"c\" d"#, ""])
    }

    // MARK: - Pool urgence : une seule voie d'écriture

    /// Correction 17 et D26 : la disponibilité urgente ne s'écrit que par `fn_toggle_pool_urgence` (contrôle documentaire,
    /// consentement). Aucun code livré ne l'écrit autrement : ni paramètre de `fn_modifier_mon_profil`, ni écriture
    /// PostgREST de `soignants`, ni autre RPC.
    func testAucunAppelNatifNeModifieDisponibleUrgenceHorsToggle() throws {
        let sources = try Self.toutesLesSourcesLivrees()
        XCTAssertGreaterThan(sources.count, 300, "les sources livrées sont lues (app et trois paquets)")
        XCTAssertGreaterThan(sources.filter { $0.chemin.hasPrefix("Jolene/") }.count, 50)

        // 1. Le nom de la colonne n'apparaît que là où il est lu ou interdit, jamais dans une gateway ni dans l'app.
        let lecture = "Packages/JoleneCore/Sources/JoleneCore/Profil/ValidationProfil.swift"
        let interdits = "Packages/JoleneCore/Sources/JoleneCore/Profil/ModificationProfil.swift"
        let colonne = sources.filter { $0.code.contains("disponible_urgence") }.map(\.chemin)
        let poolUrgence = colonne.filter { $0.contains("/PoolUrgence/") || $0.contains("DemoPoolUrgenceGateway") || $0.hasSuffix("Models/PoolUrgence.swift") }
        XCTAssertEqual(Set(colonne).subtracting(poolUrgence), [lecture, interdits],
                       "`disponible_urgence` : colonne lue (validation du profil) ou paramètre interdit, et rien d'autre hors du pool urgence (T11)")

        // 2. `fn_modifier_mon_profil` ne la reçoit jamais.
        XCTAssertTrue(ModificationProfil.parametresInterdits.contains("p_disponible_urgence"))
        XCTAssertFalse(ModificationProfil.parametresAutorises.contains("p_disponible_urgence"))
        let complet = ModificationProfil(prenom: "A", nom: "B", telephone: "0611111111", dateNaissance: "1990-01-01", numeroRpps: "1",
                                         rayonDeplacementKm: 10, villeRecherche: "X", tauxHoraireMinimum: 1, typesContratAcceptes: ["CDD"],
                                         bio: "b", anneesExperience: 1, avatarUrl: "u", adresseLat: 1, adresseLng: 2)
        XCTAssertFalse(complet.parametres.keys.contains { $0.contains("urgence") })
        let parametre = sources.filter { $0.code.contains("\"p_disponible_urgence\"") }.map(\.chemin)
        XCTAssertEqual(parametre, [interdits], "le paramètre n'est nommé que dans la liste des interdits")

        // 3. Aucune écriture PostgREST de `soignants` ne porte cette colonne (une écriture directe existe : préférences SMS).
        for source in sources where source.chemin.hasPrefix("Packages/JoleneSupabase/") || source.chemin.hasPrefix("Jolene/") {
            let ecrit = source.code.contains(".update(") || source.code.contains(".upsert(") || source.code.contains(".insert(")
            if ecrit && source.code.contains("from(\"soignants\")") {
                for colonneDuPool in ["disponible_urgence", "urgence_rayon_km", "ville_urgence"] {
                    XCTAssertFalse(source.code.contains(colonneDuPool), "\(source.chemin) : écriture de `soignants` qui touche à \(colonneDuPool)")
                }
            }
        }

        // 4. La seule RPC qui l'écrit n'est appelée que par la gateway du pool urgence (T11 ; aucune avant sa livraison).
        let toggle = sources.filter { $0.code.contains("\"fn_toggle_pool_urgence\"") }.map(\.chemin)
        XCTAssertTrue(toggle.allSatisfy { $0.contains("/PoolUrgence/") }, "`fn_toggle_pool_urgence` hors de la gateway du pool urgence : \(toggle)")

        // 5. Le swipe (quiz compris) ne nomme ni la colonne ni la RPC, et le port du swipe n'a aucune voie pour l'écrire.
        let swipe = sources.filter { $0.chemin.contains("/Swipe/") || $0.chemin.contains("Screens/Explorer/") || $0.chemin.hasSuffix("DemoSwipeGateway.swift") }
        XCTAssertGreaterThanOrEqual(swipe.count, 12)
        for source in swipe {
            XCTAssertFalse(source.code.contains("disponible_urgence"), source.chemin)
            XCTAssertFalse(source.code.contains("fn_toggle_pool_urgence"), source.chemin)
        }
        let quiz = try XCTUnwrap(sources.first { $0.chemin == "Jolene/Screens/Explorer/QuizPreferencesSheet.swift" })
        XCTAssertFalse(quiz.code.contains("gateways"), "le quiz ne parle à aucun port : il rend ses réponses à l'écran")
        XCTAssertTrue(quiz.code.contains("swipe-quiz-pool-urgence"), "renvoi vers l'écran Pool urgence à la place de la question du web")
    }

    /// Le quiz validé dans le monde démo laisse la disponibilité urgente du profil inchangée.
    @MainActor
    func testQuizValideNeChangeRienAuProfilDemo() async throws {
        let gateways = DemoWorld.gateways()
        let controller = SessionController(gateways: gateways)
        let etat = await controller.signIn(email: "demonstration@example.invalid", password: "demonstration")
        let snapshot = try XCTUnwrap(etat.snapshot)
        let avant = try await gateways.profil.profil(context: snapshot.context)
        let model = SwipeModel(controller: controller, snapshot: snapshot)
        for horaire in PreferencesMatching.Horaire.allCases {
            let applique = await model.appliquerQuiz(ReponsesQuizSwipe(horaire: horaire, rythme: .weekend, rayonKm: 50, tauxMin: 35).preferences)
            XCTAssertTrue(applique)
        }
        let apres = try await gateways.profil.profil(context: snapshot.context)
        XCTAssertEqual(apres, avant, "le quiz n'écrit que les préférences de matching, jamais la ligne du profil")
    }

    // MARK: - Feuille « première candidature »

    func testFeuillePremiereCandidatureNEcritAucunTexte() throws {
        let source = try Self.lire("Jolene/Screens/Explorer/PremiereCandidatureSheet.swift")
        let code = Self.codeSeul(source)
        for constante in ["titre", "description", "acceptationDirecte", "acceptationSiCas", "acceptationConfirmee",
                          "acceptationCompteSurToi", "acceptation", "engagements", "pasMaintenant", "confirmer"] {
            XCTAssertTrue(code.contains("Textes.\(constante)"), "TextesWeb.PremiereCandidature.\(constante) non affiché")
        }
        XCTAssertTrue(code.contains("private typealias Textes = TextesWeb.PremiereCandidature"))
        // Tout littéral du fichier est un identifiant, un symbole SF ou l'espace qui sépare les morceaux du paragraphe.
        let admis: Set<String> = [" ", "circle.fill"]
        for litteral in Self.litteraux(code) where !admis.contains(litteral) {
            // Partie fixe d'un identifiant (avant une interpolation) : `swipe-premiere-…`, sans espace ni texte.
            let fixe = litteral.components(separatedBy: "\\(").first ?? litteral
            XCTAssertTrue(fixe.hasPrefix("swipe-premiere-"), "texte en dur dans la feuille « première candidature » : « \(litteral) »")
            XCTAssertFalse(fixe.contains(" "), litteral)
        }
        XCTAssertTrue(source.contains("VueSwipeMissions.tsx"), "source web citée en commentaire")
    }

    func testTextesAttendusParLesTestsUISontCeuxDeTextesWeb() throws {
        let tests = try Self.lire("JoleneUITests/DemoSwipeTests.swift")
        let attendus = Set(Self.litteraux(Self.codeSeul(tests)))
        let feuille = TextesWeb.PremiereCandidature.self
        for texte in [feuille.titre, feuille.description, feuille.acceptation, feuille.retraitLibre, feuille.annulationTardive,
                      feuille.pasMaintenant, feuille.confirmer, TextesWeb.Candidature.engagementCandidature] {
            XCTAssertTrue(attendus.contains(texte), "DemoSwipeTests n'asserte pas mot pour mot « \(texte) »")
        }
    }

    // MARK: - Parcours du ❤️

    func testLAppNAtteintCandidaterQueParLeParcours() throws {
        let app = try Self.sourcesSwift("Jolene")
        let appels = app.filter { $0.code.contains(".candidater(") }.map(\.chemin)
        XCTAssertEqual(appels, [], "`SwipeModel.candidater` appelé hors de `ParcoursCandidatureSwipe` : la feuille « première candidature » serait contournable")
        let vue = try XCTUnwrap(app.first { $0.chemin == "Jolene/Screens/Explorer/SwipeModeView.swift" })
        for appel in ["parcours.demander(", "parcours.confirmerRecapitulatif()", "parcours.confirmerPremiereCandidature()",
                      "parcours.choisirContrat(", "parcours.abandonner()", "PremiereCandidatureSheet("] {
            XCTAssertTrue(vue.code.contains(appel), "\(appel) absent de la vue Swipe")
        }
        let coeur = try Self.sourcesSwift("Packages/JoleneCore/Sources")
        let dansLeCoeur = coeur.filter { $0.code.contains(".candidater(") }.map(\.chemin)
        XCTAssertEqual(dansLeCoeur, ["Packages/JoleneCore/Sources/JoleneCore/Swipe/ParcoursCandidatureSwipe.swift"])
    }

    // MARK: - Identifiants

    /// Identifiants du blueprint (T3b) et leur provenance : littéral de l'app, ou composant de JoleneDesign.
    func testIdentifiantsDuBlueprintPoses() throws {
        let explorer = try Self.sourcesSwift("Jolene/Screens/Explorer").map(\.code).joined(separator: "\n")
        for identifiant in ["\"explorer-vue\"", "\"swipe-restantes\"", "\"swipe-detail\"", "\"swipe-score-\\(carte.id)\"",
                            "\"swipe-pourquoi-\\(carte.id)\"", "\"swipe-toast-annuler\"", "\"swipe-premiere-candidature\"",
                            "\"swipe-premiere-confirmer\"", "\"swipe-fin-paquet\"", "\"swipe-quiz\"", "\"swipe-quiz-valider\"",
                            "\"swipe-erreur\""] {
            XCTAssertTrue(explorer.contains(identifiant), "identifiant \(identifiant) absent de Screens/Explorer")
        }
        // `explorer-vue-swipe` / `explorer-vue-liste` : identifiant du contrôle + valeur de la vue.
        XCTAssertEqual(VueExplorer.allCases.map { "explorer-vue-\($0.rawValue)" }, ["explorer-vue-swipe", "explorer-vue-liste"])
        // `swipe-deck`, `swipe-card-<id>`, `swipe-passer`, `swipe-sauvegarder`, `swipe-candidater` : `SwipeCardStack` et
        // `SwipeActionBar` (JoleneDesign), valeurs par défaut gardées par la vue.
        let paquet = try Self.lire("Packages/JoleneDesign/Sources/JoleneDesign/Components/SwipeCardStack.swift")
        for litteral in ["public static let deck = \"swipe-deck\"", "public static let cardPrefix = \"swipe-card\"",
                         "public static let actionsPrefix = \"swipe\"", "case passer, sauvegarder, candidater"] {
            XCTAssertTrue(paquet.contains(litteral), litteral)
        }
        XCTAssertTrue(explorer.contains("SwipeCardStack(cartes, identifier: \"\", cardAccessibility: .contain"),
                      "enfants identifiés de la carte conservés ; conteneur du paquet posé par la vue")
        // Run 45446351274 : le conteneur `swipe-deck` absorbait la carte du dessus quand elle était son unique enfant
        // (identifiant `swipe-card-<id>` perdu sur la dernière carte) ; il entoure désormais le compteur ET les cartes.
        XCTAssertTrue(explorer.contains(".accessibilityIdentifier(SwipeDeckIdentifiers.deck)"), "conteneur swipe-deck de la vue")
        XCTAssertTrue(explorer.contains("SwipeActionBar(isDisabled:"), "boutons équivalents des gestes (D22)")
    }

    /// Chaque identifiant du swipe lu par `DemoSwipeTests` est posé par l'app ou par JoleneDesign.
    func testIdentifiantsLusParLesTestsUIExistentDansLApp() throws {
        let tests = Self.codeSeul(try Self.lire("JoleneUITests/DemoSwipeTests.swift"))
        let app = try (Self.sourcesSwift("Jolene") + Self.sourcesSwift("Packages/JoleneDesign/Sources")).flatMap { Self.litteraux($0.code) }
        /// Partie fixe d'un identifiant : jusqu'à la première interpolation.
        func fixe(_ litteral: String) -> String { litteral.components(separatedBy: "\\(").first ?? litteral }
        var connus = Set(app.map(fixe))
        /// Préfixes des identifiants interpolés par l'app (`swipe-card-\(id)` → `swipe-card-`).
        var interpoles = Set(app.filter { $0.contains("\\(") }.map(fixe).filter { $0.hasSuffix("-") })
        interpoles.insert("swipe-card-")
        // Identifiants composés par les composants de JoleneDesign.
        connus.formUnion(["explorer-vue-swipe", "explorer-vue-liste", "swipe-deck", "swipe-card-", "swipe-passer", "swipe-sauvegarder",
                          "swipe-candidater", "swipe-favoris-title"])
        for suffixe in ["", "-title", "-message", "-confirm", "-cancel"] { connus.insert("candidature-recap" + suffixe) }
        connus.insert("candidature-recap-planning-creneau-1")
        let lus = Set(Self.litteraux(tests).map(fixe).filter { $0.hasPrefix("swipe-") || $0.hasPrefix("explorer-vue") || $0.hasPrefix("choix-contrat") || $0.hasPrefix("candidature-recap") })
        XCTAssertGreaterThan(lus.count, 30, "identifiants lus par DemoSwipeTests")
        for identifiant in lus.sorted() {
            // Préfixes interrogés par `elements(withPrefix:)` : au moins un identifiant de l'app commence ainsi.
            let pose = connus.contains(identifiant) || (identifiant.hasSuffix("-") && connus.contains { $0.hasPrefix(identifiant) })
                || interpoles.contains { identifiant.hasPrefix($0) } || identifiant == "swipe-quiz-urgence"
            XCTAssertTrue(pose, "DemoSwipeTests lit « \(identifiant) », que l'app ne pose pas")
        }
        XCTAssertFalse(connus.contains { $0.hasPrefix("swipe-quiz-urgence") }, "aucune question « urgence » dans le quiz natif")
    }
}
