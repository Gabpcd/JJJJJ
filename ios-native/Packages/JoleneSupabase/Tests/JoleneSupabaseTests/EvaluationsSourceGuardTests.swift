import Foundation
import XCTest

/// Test-garde natif du filtre de visibilité centralisé (L4-T9 ; `CLAUDE.md`, « Publication différée = filtre de
/// visibilité centralisé » ; fiche « Jamais … côté natif » de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`).
///
/// Une notation non publiée ne doit jamais transparaître, ni en liste, ni en statistique, ni dans un score. Côté app,
/// la règle tient en une phrase : **aucun fichier Swift livré ne lit la table des notations, ni la table ou la vue des
/// évaluations** ; les notes reçues ne viennent que des deux RPC qui répliquent le filtre du serveur
/// (`fn_mes_notations_recues_avec_stats`, `fn_lister_notations_recues`). Ce test énumère les fichiers Swift livrés
/// (les trois paquets et la cible app) et échoue si l'un d'eux :
/// - porte, dans son code (commentaires retirés), le nom de la table des notations ou celui de la vue des
///   évaluations publiées, où que ce soit — littéral, embed PostgREST `select("…(…)")`, canal Realtime ;
/// - porte un littéral exactement égal au nom de la table des évaluations (même motif que le garde-fou 18 de
///   `tests/non-regression/guards.sh`) ;
/// et, pour les fichiers de la tranche, si une gateway ouvre une lecture PostgREST autre que la ligne `soignants` du
/// compte, appelle une RPC hors de la liste, envoie le chemin d'un justificatif (D10), ou si un écran ou un modèle
/// recalcule une moyenne.
///
/// Les noms interdits sont assemblés à l'exécution : ce fichier ne les écrit pas entre guillemets.
final class EvaluationsSourceGuardTests: XCTestCase {
    private static let tableNotations = ["notations", "missions"].joined(separator: "_")
    private static let tableEvaluations = ["evalua", "tions"].joined()
    private static let vuePubliees = [tableEvaluations, "publiees"].joined(separator: "_")
    private static let parametreJustificatif = ["p", "justificatif", "storage", "path"].joined(separator: "_")

    /// `ios-native/` : Tests/JoleneSupabaseTests/<fichier> → 5 niveaux au-dessus.
    private static var natif: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url = url.deletingLastPathComponent() }
        return url
    }

    /// Fichiers Swift livrés : sources des trois paquets et cible app (jamais les cibles de test ni `.build`).
    private static func fichiersLivres() throws -> [URL] {
        let racines = ["Packages/JoleneCore/Sources", "Packages/JoleneSupabase/Sources", "Packages/JoleneDesign/Sources", "Jolene"]
        var fichiers: [URL] = []
        for racine in racines {
            let dossier = natif.appendingPathComponent(racine)
            var estDossier: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dossier.path, isDirectory: &estDossier), estDossier.boolValue else {
                // Fail-closed : un dossier renommé ne doit pas rendre la garde muette.
                XCTFail("dossier de sources introuvable : \(dossier.path)")
                continue
            }
            let parcours = FileManager.default.enumerator(at: dossier, includingPropertiesForKeys: nil)
            while let url = parcours?.nextObject() as? URL {
                if url.pathComponents.contains(".build") { continue }
                if url.pathExtension == "swift" { fichiers.append(url) }
            }
        }
        return fichiers
    }

    /// Code d'un fichier, commentaires de fin de ligne et de documentation retirés (une chaîne n'est jamais coupée :
    /// `//` n'ouvre un commentaire qu'en dehors d'un littéral).
    static func code(_ source: String) -> String {
        source.components(separatedBy: "\n").map { ligne -> String in
            var dansChaine = false
            var precedent: Character?
            var sortie = ""
            for caractere in ligne {
                if caractere == "\"", precedent != "\\" { dansChaine.toggle() }
                if !dansChaine, caractere == "/", precedent == "/" {
                    sortie.removeLast()
                    break
                }
                sortie.append(caractere)
                precedent = caractere
            }
            return sortie
        }.joined(separator: "\n")
    }

    private static func chemin(_ url: URL) -> String {
        url.path.replacingOccurrences(of: natif.path + "/", with: "")
    }

    // MARK: - Tout le Swift livré

    func testAucunFichierLivreNeLitLesNotationsNiLesEvaluations() throws {
        let fichiers = try Self.fichiersLivres()
        XCTAssertGreaterThan(fichiers.count, 300, "périmètre de la garde : \(fichiers.count) fichiers")
        XCTAssertTrue(fichiers.contains { $0.lastPathComponent == "SupabaseEvaluationsGateway.swift" })
        XCTAssertTrue(fichiers.contains { $0.lastPathComponent == "EvaluationsScreen.swift" })
        let exact = "\"\(Self.tableEvaluations)\""
        for fichier in fichiers {
            let code = Self.code(try String(contentsOf: fichier, encoding: .utf8))
            XCTAssertFalse(code.contains(Self.tableNotations),
                           "\(Self.chemin(fichier)) : la table des notations n'est jamais lue par l'app (RPC filtrées seulement)")
            XCTAssertFalse(code.contains(Self.vuePubliees),
                           "\(Self.chemin(fichier)) : la vue des évaluations publiées est réservée à service_role")
            XCTAssertFalse(code.contains(exact),
                           "\(Self.chemin(fichier)) : littéral égal au nom de la table des évaluations (garde-fou 18)")
        }
    }

    func testLaGardeDetecteUnLecteur() {
        // Témoins : la garde n'est pas un faux constant.
        let lecteur = "let lignes = try await client.from(\"\(Self.tableNotations)\").select().execute()"
        XCTAssertTrue(Self.code(lecteur).contains(Self.tableNotations))
        let embed = "client.from(\"missions\").select(\"id, \(Self.tableNotations)(note)\") // rien"
        XCTAssertTrue(Self.code(embed).contains(Self.tableNotations), "embed PostgREST détecté")
        let commentaire = "let x = 1 // jamais \(Self.tableNotations)"
        XCTAssertFalse(Self.code(commentaire).contains(Self.tableNotations), "un commentaire n'est pas une lecture")
        let documentation = "/// filtre centralisé `\(Self.vuePubliees)`"
        XCTAssertFalse(Self.code(documentation).contains(Self.vuePubliees))
        let url = "let lien = \"https://jolene.app/x\" // \(Self.tableNotations)"
        XCTAssertEqual(Self.code(url), "let lien = \"https://jolene.app/x\" ", "`//` dans une chaîne n'ouvre pas un commentaire")
        XCTAssertEqual(Self.tableEvaluations.count, 11)
    }

    // MARK: - Fichiers de la tranche

    private static let gateways = [
        "Packages/JoleneSupabase/Sources/JoleneSupabase/Evaluations/SupabaseEvaluationsGateway.swift",
        "Packages/JoleneSupabase/Sources/JoleneSupabase/Score/SupabaseScoreGateway.swift",
    ]
    private static let rpcPermises: Set<String> = [
        "fn_mes_notations_recues_avec_stats", "fn_signaler_notation", "fn_mon_breakdown_actuel", "fn_evolution_score_soignant",
        "fn_mes_evenements_score", "fn_lister_notations_recues", "fn_creer_reclamation_score",
    ]

    private static func source(_ cheminRelatif: String) throws -> String {
        let url = natif.appendingPathComponent(cheminRelatif)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("fichier de la tranche introuvable : \(cheminRelatif)")
            return ""
        }
        return code(try String(contentsOf: url, encoding: .utf8))
    }

    func testGatewaysDeLaTrancheNeLisentQueLesRPCFiltreesEtLeProfil() throws {
        var rpc: Set<String> = []
        for chemin in Self.gateways {
            let code = try Self.source(chemin)
            for litteral in Self.litteraux(code) where litteral.hasPrefix("fn_") { rpc.insert(litteral) }
            XCTAssertFalse(code.contains(".channel(") || code.contains("realtimeV2"), "\(chemin) : aucun canal Realtime")
            XCTAssertFalse(code.contains(".storage"), "\(chemin) : aucun dépôt de fichier")
            XCTAssertFalse(code.contains(Self.parametreJustificatif), "\(chemin) : chemin d'un justificatif jamais envoyé (D10)")
        }
        XCTAssertEqual(rpc, Self.rpcPermises, "RPC appelées par la tranche")
        let evaluations = try Self.source(Self.gateways[0])
        XCTAssertFalse(evaluations.contains(".from("), "évaluations : deux RPC seulement, aucune requête PostgREST")
        let score = try Self.source(Self.gateways[1])
        let lectures = score.components(separatedBy: ".from(").dropFirst().map { String($0.prefix(11)) }
        XCTAssertEqual(lectures, ["\"soignants\""], "score : seule la ligne soignants du compte est lue par PostgREST")
    }

    func testAucuneMoyenneRecalculeeDansLesEcransNiLesModeles() throws {
        let fichiers = [
            "Packages/JoleneCore/Sources/JoleneCore/Evaluations/EvaluationsModel.swift",
            "Packages/JoleneCore/Sources/JoleneCore/Evaluations/EvaluationsPresentation.swift",
            "Packages/JoleneCore/Sources/JoleneCore/Score/ScoreModel.swift",
            "Packages/JoleneCore/Sources/JoleneCore/Score/ScorePresentation.swift",
            "Packages/JoleneCore/Sources/JoleneCore/Models/Evaluations.swift",
            "Packages/JoleneCore/Sources/JoleneCore/Models/Score.swift",
            "Jolene/Screens/Secondaires/Evaluations/EvaluationsScreen.swift",
            "Jolene/Screens/Secondaires/Score/ScoreScreen.swift",
        ]
        for chemin in fichiers {
            let code = try Self.source(chemin)
            for calcul in [".reduce(", "criteres.map", "/ 4", "/ Double(", ".average", "vDSP", ".sum"] {
                XCTAssertFalse(code.contains(calcul), "\(chemin) : « \(calcul) » — aucune moyenne ni total n'est recalculé par l'app")
            }
        }
        // Le monde démo sert les statistiques de la fixture : il ne les dérive pas des notations filtrées.
        let demo = try Self.source("Packages/JoleneCore/Sources/JoleneCore/Demo/Lot4/DemoEvaluationsGateway.swift")
        XCTAssertFalse(demo.contains(".reduce(") || demo.contains("base.stats ="), "statistiques démo : celles de la fixture")
    }

    /// Littéraux de chaîne simples d'un code sans commentaires.
    private static func litteraux(_ code: String) -> [String] {
        var litteraux: [String] = []
        for ligne in code.components(separatedBy: "\n") {
            let morceaux = ligne.components(separatedBy: "\"")
            for rang in stride(from: 1, to: morceaux.count, by: 2) { litteraux.append(morceaux[rang]) }
        }
        return litteraux
    }
}
