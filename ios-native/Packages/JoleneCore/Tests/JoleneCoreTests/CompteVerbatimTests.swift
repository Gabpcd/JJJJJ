import XCTest
@testable import JoleneCore

/// Textes du hub « Mon compte » livrés par le lot 3, T11 (HARD STOP n°4) : mot de passe, export RGPD, thème,
/// « Aide & légal ». Chaque texte affiché repris du web figure tel quel à sa ligne source ; le titre RGPD de l'export
/// est verbatim, sa description web inexacte (« l'intégralité ») n'est pas portée (critère de TJ8) ; textes RGPD et
/// textes sans équivalent web (non juridiques) tranchés par délégation (L3-TJ, décision TJ2 de `DECISIONS_LOT3.md`).
final class CompteVerbatimTests: XCTestCase {
    private typealias M = MotDePasse.Textes
    private typealias E = ExportRGPD.Textes

    /// Lignes d'un fichier du dépôt (racine = six niveaux au-dessus de ce fichier).
    static func lignes(_ chemin: String) throws -> [String] {
        try source(chemin).components(separatedBy: "\n")
    }

    static func source(_ chemin: String) throws -> String {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent(chemin)
        guard FileManager.default.fileExists(atPath: fichier.path) else {
            throw XCTSkip("\(chemin) introuvable : \(fichier.path)")
        }
        return try String(contentsOf: fichier, encoding: .utf8)
    }

    private static let mdp = "src/components/soignant/ChangementMotDePasse.tsx"
    private static let hub = "src/pages/MonCompteSoignant.tsx"
    private static let confidentialite = "src/components/profil-soignant/SectionConfidentialite.tsx"
    private static let erreurs = "src/lib/erreurs.ts"
    private static let schema = "supabase/schema/public.sql"

    /// (texte natif, fichier web, ligne) : le texte figure tel quel à sa ligne (échappements `\'` du JS ramenés à `'`).
    private static var attendus: [(String, String, Int)] {
        let liens: [(String, String, Int)] = zip(HubCompte.aideEtLegal, [130, 132, 133, 134]).map { lien, ligne in
            ("label: '\(lien.libelle)', route: '\(lien.chemin)'", hub, ligne)
        }
        let textes: [(String, String, Int)] = [
            (M.ancienIncorrect, mdp, 58), (M.succes, mdp, 96), (M.ancien, mdp, 115), (M.nouveau, mdp, 137),
            (M.confirmation, mdp, 160), (M.nonCorrespondance, mdp, 171), (M.correspondance, mdp, 176),
            (M.soumettre, mdp, 187), (M.titre, hub, 206), (M.sectionHub, hub, 178),
            (MotDePasse.auditTypeRessource, mdp, 86), (AuditAction.donneesPersoModification.rawValue, mdp, 85),
            ("champ: 'mot_de_passe'", mdp, 88), ("new Date().toISOString()", mdp, 88),
            (M.erreurGenerique, erreurs, 532),
            (E.titre, confidentialite, 111), (E.exporterJSON, confidentialite, 123),
            (E.enCours, confidentialite, 123), (E.exporterCSV, confidentialite, 131), (E.enCours, confidentialite, 131),
            ("Données exportées en ${fmt.toUpperCase()}.", confidentialite, 73),
            (ExportRGPD.auditTypeRessource, confidentialite, 45), (AuditAction.rgpdExportDonnees.rawValue, confidentialite, 44),
            ("p_details: { format: fmt }", confidentialite, 46),
            (FormatExportRGPD.csv.mime, confidentialite, 65), (FormatExportRGPD.json.mime, confidentialite, 69),
            ("`mes-donnees-jolene-${new Date().toISOString().slice(0, 10)}.csv`", confidentialite, 66),
            ("`mes-donnees-jolene-${new Date().toISOString().slice(0, 10)}.json`", confidentialite, 70),
            (E.echec, erreurs, 532),
            (HubCompte.titreReglages, hub, 113), (HubCompte.titreAideEtLegal, hub, 126),
        ]
        return textes + liens
    }

    func testChaqueTexteRepriseDuWebEstVerbatimASaLigne() throws {
        var lignes: [String: [String]] = [:]
        for (texte, fichier, ligne) in Self.attendus {
            if lignes[fichier] == nil { lignes[fichier] = try Self.lignes(fichier) }
            let source = try XCTUnwrap(lignes[fichier])
            XCTAssertGreaterThanOrEqual(source.count, ligne, fichier)
            let brute = source[ligne - 1].replacingOccurrences(of: "\\'", with: "'")
            XCTAssertTrue(brute.contains(texte), "« \(texte) » absent de \(fichier) l.\(ligne)")
        }
    }

    func testSuccesDeLExportAssembleCommeLeGabaritWeb() {
        // `Données exportées en ${fmt.toUpperCase()}.` (l.73).
        XCTAssertEqual(E.succes(.json), "Données exportées en JSON.")
        XCTAssertEqual(E.succes(.csv), "Données exportées en CSV.")
        XCTAssertEqual(FormatExportRGPD.json.libelle, "JSON")
        XCTAssertEqual(FormatExportRGPD.csv.libelle, "CSV")
    }

    /// Texte web de la description de l'export (`SectionConfidentialite.tsx` l.114), inexact au regard du serveur et du
    /// RGPD (TJ2). Il n'est cité ici que comme témoin : jamais dans les sources de l'app.
    private static let descriptionWebInexacte = "Télécharge l'intégralité de tes données personnelles dans le format de ton choix."

    /// Sources de l'app et de ses paquets (hors tests).
    private static let dossiersSources = ["ios-native/Jolene", "ios-native/Packages/JoleneCore/Sources",
                                          "ios-native/Packages/JoleneDesign/Sources", "ios-native/Packages/JoleneSupabase/Sources"]

    func testTitreRGPDVerbatimEtDescriptionInexacteNonPortee() throws {
        // HARD STOP n°4, décision TJ2 de L3-TJ (revue fraîche B8, majeur 2) : un seul critère pour un texte juridique du
        // web inexact, celui de TJ8 — il n'est pas porté (ne pas porter n'est pas reformuler) ; le titre et les boutons
        // restent verbatim. Quand la PR web corrige l.114, le témoin rougit : le nouveau texte est instruit puis porté
        // verbatim (tutoiement compris), et cette garde le suit.
        XCTAssertEqual(E.titre, "Mes données (RGPD)")
        let web = try Self.lignes(Self.confidentialite)
        XCTAssertTrue(web[114 - 1].contains(Self.descriptionWebInexacte),
                      "témoin web : l.114 a changé (PR web de TJ2 ?) — instruire le nouveau texte, puis le porter verbatim")
        let (puce, sousSection) = try DecisionsLot3Document.puceDeleguee("- **Textes RGPD de l'export** (T11)")
        XCTAssertTrue(sousSection.contains("### TJ2 — "), "décision TJ2 (textes de T11)")
        XCTAssertTrue(puce.contains("« \(E.titre) »"), "décision TJ2 : « \(E.titre) » validé verbatim")
        XCTAssertTrue(puce.contains("« \(Self.descriptionWebInexacte) »") && puce.contains("**non portée**")
                      && puce.contains("critère de TJ8"), "décision TJ2 : description citée, non portée, critère de TJ8")
        // Aucune source de l'app ni de ses paquets ne porte la description (ni constante, ni identifiant d'affichage).
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        var porteurs: [String] = []
        for dossier in Self.dossiersSources {
            let base = racine.appendingPathComponent(dossier)
            guard let parcours = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let fichier as URL in parcours where fichier.pathExtension == "swift" {
                let texte = try String(contentsOf: fichier, encoding: .utf8)
                if texte.contains("l'intégralité de tes données") || texte.contains("\"compte-export-info\"") {
                    porteurs.append(fichier.lastPathComponent)
                }
            }
        }
        XCTAssertEqual(porteurs, [], "description inexacte de l'export portée par : \(porteurs)")
    }

    /// Corps de `fn_rgpd_exporter_rate_limited` dans le dump, localisé par son en-tête (revue B8, m5) : un
    /// `schema-snapshot` qui décale le dump ne fait pas rougir ce test. Les numéros de ligne cités dans les
    /// sources (`public.sql:55385`, `:55379` au 08/11/2026) ne sont qu'indicatifs.
    static func corpsExportLimite() throws -> [String] {
        let schema = try lignes(Self.schema)
        let entete = #"CREATE OR REPLACE FUNCTION "public"."fn_rgpd_exporter_rate_limited"() RETURNS "jsonb""#
        let debut = try XCTUnwrap(schema.firstIndex { $0.contains(entete) }, "en-tête de fn_rgpd_exporter_rate_limited introuvable")
        let fin = try XCTUnwrap(schema[debut...].firstIndex { $0.hasPrefix("$$;") }, "fin du corps introuvable")
        return Array(schema[debut...fin])
    }

    func testRefusDuServeurEtTraductionsDesErreursAuthVerbatim() throws {
        // Message de refus de `fn_rgpd_exporter_rate_limited` (définition live relue le 08/11/2026) : valeur JSON
        // réelle, l'apostrophe doublée par le littéral SQL est simple. Chaque texte est cherché dans le corps de la
        // fonction (et non à une ligne fixe du dump), une seule fois.
        let corps = try Self.corpsExportLimite()
        let limite = "RETURN jsonb_build_object('error', 'Trop d''exports en peu de temps. Réessayez dans quelques minutes.');"
        let nonAuthentifie = "RETURN jsonb_build_object('error', 'Non authentifié');"
        XCTAssertEqual(corps.filter { $0.contains(limite) }.count, 1, "refus de limite dans fn_rgpd_exporter_rate_limited")
        XCTAssertEqual(ExportRGPD.refusLimiteServeur, "Trop d'exports en peu de temps. Réessayez dans quelques minutes.")
        XCTAssertEqual(corps.filter { $0.contains(nonAuthentifie) }.count, 1, "refus sans session dans fn_rgpd_exporter_rate_limited")
        let indexLimite = try XCTUnwrap(corps.firstIndex { $0.contains(limite) })
        let indexSession = try XCTUnwrap(corps.firstIndex { $0.contains(nonAuthentifie) })
        XCTAssertLessThan(indexSession, indexLimite, "la session est vérifiée avant la limite")

        // Table `traductions` d'`extraireMessageErreur` (erreurs.ts l.480-493) et repli `weak_password` (l.502-503) :
        // chaque paire portée figure à sa ligne, dans l'ordre du web.
        let erreurs = try Self.lignes(Self.erreurs)
        XCTAssertEqual(MotDePasse.traductionsWeb.count, 14)
        for (index, paire) in MotDePasse.traductionsWeb.enumerated() {
            let ligne = erreurs[480 + index - 1].replacingOccurrences(of: "\\'", with: "'")
            XCTAssertTrue(ligne.contains("'\(paire.anglais)': '\(paire.francais)'"), "erreurs.ts l.\(480 + index)")
        }
        XCTAssertTrue(erreurs[502 - 1].contains("errorCode === 'weak_password' || errorCode === 'invalid_password'"))
        XCTAssertTrue(erreurs[503 - 1].contains("'\(M.motDePasseTropFaible)'"))
    }

    func testTextesSansEquivalentWebListesPourRelecture() throws {
        // Textes natifs non juridiques (D13, D16) : aucune source web. Tranchés par délégation (L3-TJ, décision TJ2 de
        // `DECISIONS_LOT3.md`, « Décisions déléguées du 8 novembre 2026 ») : chacun est listé dans la puce de T11, dans
        // une sous-section qui porte la ligne de délégation, et n'est plus « à relire par Gabrielle ».
        let nouveaux = [M.reauthentificationRequise, M.confirmationIndisponible, ChoixTheme.titreGroupe]
            + ChoixTheme.allCases.map(\.libelle)
        XCTAssertEqual(ChoixTheme.allCases.map(\.libelle), ["Système", "Clair", "Sombre"])
        XCTAssertEqual(ChoixTheme.titreGroupe, "Thème")
        let (puce, sousSection) = try DecisionsLot3Document.puceDeleguee(
            "- **T11 — textes sans équivalent web** (non juridiques), validés par délégation")
        XCTAssertTrue(sousSection.contains("### TJ2 — "), "décision TJ2 (textes de T11)")
        for texte in nouveaux {
            XCTAssertTrue(puce.contains("« \(texte) »"), "DECISIONS_LOT3.md liste « \(texte) »")
        }
        try DecisionsLot3Document.assertHardStopSansRelectureEnAttente()
        let web = try [Self.mdp, Self.hub].map(Self.source).joined()
        for texte in [M.reauthentificationRequise, M.confirmationIndisponible] {
            XCTAssertFalse(web.contains(texte), "aucune source web : « \(texte) » n'est pas présenté comme verbatim")
        }
        // Vouvoiement des textes natifs.
        for texte in nouveaux {
            for tutoiement in [" tu ", " tes ", " ton ", " ta ", "Tu ", "Tape "] {
                XCTAssertFalse(texte.contains(tutoiement), "« \(texte) » doit être vouvoyé")
            }
        }
    }

    func testTitreReglagesAUneSeuleSource() throws {
        // Revue B8 (m7), règle « doublons » de CLAUDE.md : le titre « Réglages » du hub n'est déclaré qu'une fois
        // (`HubCompte.titreReglages`) dans les sources de l'app et de ses paquets.
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let dossiers = ["ios-native/Jolene", "ios-native/Packages/JoleneCore/Sources", "ios-native/Packages/JoleneDesign/Sources",
                        "ios-native/Packages/JoleneSupabase/Sources"]
        var declarations: [String] = []
        for dossier in dossiers {
            let base = racine.appendingPathComponent(dossier)
            guard let parcours = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let fichier as URL in parcours where fichier.pathExtension == "swift" {
                let texte = try String(contentsOf: fichier, encoding: .utf8)
                if texte.contains("\"\(HubCompte.titreReglages)\"") { declarations.append(fichier.lastPathComponent) }
            }
        }
        XCTAssertEqual(declarations, ["HubCompte.swift"], "« Réglages » déclaré une seule fois")
    }

    func testDependanceDuRenvoiMotDePasseOublieConsignee() throws {
        // Revue B8 (m6) : le refus verrouillé renvoie vers « Mot de passe oublié ? », que l'écran de connexion ne
        // porte qu'avec L1-T10 (`login-forgot`) ; la dépendance est consignée dans les manques de T11.
        XCTAssertTrue(M.reauthentificationRequise.contains("« Mot de passe oublié ? »"))
        let decisions = try Self.source("docs/mobile-swift/DECISIONS_LOT3.md")
        let section = try XCTUnwrap(decisions.range(of: "## T11 — hub Compte"), "section T11 de DECISIONS_LOT3.md")
        let suite = decisions[section.upperBound...]
        let t11 = suite.range(of: "\n## ").map { suite[..<$0.lowerBound] } ?? suite
        XCTAssertTrue(t11.contains("login-forgot") && t11.contains("L1-T10"), "dépendance du renvoi à L1-T10 consignée")
        // Revue fraîche B8 de L3-TJ (mineur 2), verrou « un gap connu reste verrouillé » : tant que la connexion native
        // n'a pas `login-forgot`, ce renvoi est sans effet ; TJ2 l'accepte jusqu'à L1-T10 avec ses motifs, et le
        // préalable est inscrit au §6.10 (TestFlight externe).
        let connexion = try Self.source("ios-native/Jolene/Screens/LoginScreen.swift")
        guard !connexion.contains("\"login-forgot\"") else { return }
        let (puce, _) = try DecisionsLot3Document.puceDeleguee(
            "- **T11 — textes sans équivalent web** (non juridiques), validés par délégation")
        XCTAssertTrue(puce.contains("renvoi sans effet") && puce.contains("L1-T10"), "TJ2 : renvoi sans effet qualifié")
        let attente = try DecisionsLot3Document.section("## En attente de Gabrielle", dans: decisions)
        let debut = try XCTUnwrap(attente.range(of: "**§6.10"), "§6.10 de « En attente de Gabrielle »")
        let apres610 = attente[debut.lowerBound...]
        let p610 = apres610.range(of: "\n- ").map { apres610[..<$0.lowerBound] } ?? apres610
        for element in ["Préalable", "« Mot de passe oublié ? »", "`login-forgot`", "L1-T10", "un gap connu reste verrouillé"] {
            XCTAssertTrue(p610.contains(element), "§6.10 : « \(element) » (préalable TestFlight externe)")
        }
    }

    func testAideEtLegalSontDesRenvoisSafariCanoniques() throws {
        // « Aide & légal » (MonCompteSoignant.tsx l.126-136) : liens vers des pages publiques, servis par Safari
        // (`DestinationLien.destination`), jamais un écran natif. « Contacter Jolene » (modale web) et « Supprimer
        // mon compte » (section native du lot 1, T8) n'en font pas partie.
        XCTAssertEqual(HubCompte.aideEtLegal.map(\.libelle), ["Centre d'aide", "Confidentialité", "Conditions générales", "Mentions légales"])
        XCTAssertEqual(HubCompte.aideEtLegal.map(\.id), ["compte-aide", "compte-confidentialite", "compte-cgu", "compte-mentions-legales"])
        for lien in HubCompte.aideEtLegal {
            let destination = try XCTUnwrap(HubCompte.destination(lien), lien.chemin)
            XCTAssertEqual(destination, .safari(try XCTUnwrap(URL(string: "https://jolene.app\(lien.chemin)"))), lien.chemin)
            XCTAssertFalse(destination.isNative)
        }
    }
}
