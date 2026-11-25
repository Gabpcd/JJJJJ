import XCTest
@testable import JoleneCore

/// Disponibilités (L4-T5) hors modèle d'écran : textes repris mot pour mot du web (`src/pages/MesDisponibilites.tsx`)
/// et du serveur (`fn_definir_disponibilite`), jours civils, lecture des lignes `disponibilites_soignant`, grille
/// présentée, monde démo et fixture `demo-disponibilites.json`.
///
/// Les sources sont relues par leur contenu, pas par leur numéro de ligne : une ligne décalée ne rougit rien, un texte
/// modifié rougit.
final class DisponibilitesLectureTests: XCTestCase {
    private typealias T = DisponibilitesTextes

    private static let lundi = JourParis(iso: "2026-11-02")
    private static let mardi = JourParis(iso: "2026-11-03")
    private static let mardiJour = DispoCle(jour: mardi, creneau: .journee)
    private static let mardiNuit = DispoCle(jour: mardi, creneau: .nuit)
    private static let jeudiNuit = DispoCle(jour: JourParis(iso: "2026-11-05"), creneau: .nuit)
    private static let samediSuivant = DispoCle(jour: JourParis(iso: "2026-11-14"), creneau: .journee)
    private static let fixture: Set<DispoCle> = [mardiJour, jeudiNuit, samediSuivant]

    private static func sourceDepot(_ chemin: String) throws -> String {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent(chemin)
        guard FileManager.default.fileExists(atPath: fichier.path) else {
            throw XCTSkip("\(chemin) introuvable : \(fichier.path)")
        }
        return try String(contentsOf: fichier, encoding: .utf8)
    }

    // MARK: - Textes

    func testTextesReprisDuWebMotPourMot() throws {
        let web = try Self.sourceDepot("src/pages/MesDisponibilites.tsx")
        XCTAssertEqual(T.titre, "Mes disponibilités")
        XCTAssertTrue(web.contains("usePageTitle('\(T.titre)')"))

        // Paragraphes écrits sur plusieurs lignes JSX : chaque ligne figure telle quelle, jointes par une espace au rendu.
        let introduction = ["Indiquez vos jours et nuits disponibles : vous êtes alertée dès que des missions",
                            "correspondent à votre planning, et les établissements voient qu'ils peuvent compter",
                            "sur vous ce jour-là (prénom et score uniquement, jamais vos coordonnées)."]
        for ligne in introduction { XCTAssertTrue(web.contains(ligne), ligne) }
        XCTAssertEqual(T.introduction, introduction.joined(separator: " "))

        let aide = ["Touchez <strong>Jour</strong> ou <strong>Nuit</strong> sur les dates où vous êtes",
                    "disponible. Vous pouvez tout modifier à tout moment."]
        for ligne in aide { XCTAssertTrue(web.contains(ligne), ligne) }
        XCTAssertEqual(T.aide.map { $0.gras ? "<strong>\($0.texte)</strong>" : $0.texte }.joined(), aide.joined(separator: " "))
        XCTAssertEqual(T.aide.filter { $0.gras }.map(\.texte), ["Jour", "Nuit"])
        XCTAssertEqual(T.aideTexte, "Touchez Jour ou Nuit sur les dates où vous êtes disponible. Vous pouvez tout modifier à tout moment.")
        XCTAssertTrue(web.contains("{nbDispos === 0 && ("), "l'aide n'est affichée que sans créneau déclaré")

        XCTAssertTrue(web.contains(">\(T.echecTitre)</h1>"))
        XCTAssertTrue(web.contains(">\(T.echecMessage)</p>"))
        XCTAssertTrue(web.contains(">\(T.reessayer)</button>"))
        XCTAssertEqual(T.echecMessage, "Vos disponibilités n’ont pas pu être chargées. Réessayez avant de les modifier.")
        XCTAssertTrue(web.contains("          \(T.mention)\n"))
        XCTAssertEqual(T.mention, "Déclarer une disponibilité n'engage à rien : c'est un signal de matching, pas un engagement.")
    }

    func testRefusEtBornesDeLaRPCReprisDuDump() throws {
        let schema = try Self.sourceDepot("supabase/schema/public.sql")
        let debut = try XCTUnwrap(schema.range(of: #"CREATE OR REPLACE FUNCTION "public"."fn_definir_disponibilite""#))
        let fin = try XCTUnwrap(schema.range(of: "\n$$;", range: debut.upperBound..<schema.endIndex))
        let corps = String(schema[debut.lowerBound..<fin.lowerBound])

        XCTAssertEqual(T.horsFenetre, "La disponibilité doit être entre aujourd'hui et J+90")
        XCTAssertTrue(corps.contains("'\(T.horsFenetre.replacingOccurrences(of: "'", with: "''"))'"), "message serveur verbatim")
        XCTAssertTrue(corps.contains("p_jour < CURRENT_DATE OR p_jour > CURRENT_DATE + \(DemoDisponibilitesGateway.joursMax)"),
                      "bornes du monde démo = bornes de la RPC")
        XCTAssertEqual(CreneauDispo.allCases.map(\.rawValue), ["JOURNEE", "NUIT"], "créneaux du web (l.24), sous-ensemble de la RPC")
        for creneau in CreneauDispo.allCases { XCTAssertTrue(corps.contains("'\(creneau.rawValue)'"), creneau.rawValue) }
        XCTAssertTrue(corps.contains("jsonb_build_object('success', TRUE)"))
    }

    func testLibelleDuJourCapitaliseCommeLeWeb() {
        // Classe CSS `capitalize` du web (l.164) sur le libellé date-fns `EEEE d MMM`.
        XCTAssertEqual(DisponibilitesPresentation.libelle("lundi 2 nov."), "Lundi 2 Nov.")
        XCTAssertEqual(DisponibilitesPresentation.libelle("samedi 13 févr."), "Samedi 13 Févr.")
        XCTAssertEqual(DisponibilitesPresentation.libelle("jeudi 1 août"), "Jeudi 1 Août")
        XCTAssertEqual(DisponibilitesPresentation.libelle("mardi 1 déc."), "Mardi 1 Déc.")
    }

    // MARK: - Jours civils

    func testJourCivilValiditeDecalageEtSemaine() {
        XCTAssertTrue(Self.mardi.estValide)
        XCTAssertTrue(JourParis(iso: "2028-02-29").estValide)
        for invalide in ["", "2026-11-3", "2026-13-01", "2026-02-30", "2027-02-29", "2026-11-03T00:00:00Z", " 2026-11-03",
                         "2026/11/03", "٢٠٢٦-١١-٠٣", "2026-11-0x", "+026-11-03", "2026-00-10", "2026-11-00"] {
            XCTAssertFalse(JourParis(iso: invalide).estValide, "« \(invalide) »")
        }

        XCTAssertEqual(Self.mardi.decale(de: 0), Self.mardi)
        XCTAssertEqual(Self.lundi.decale(de: 90)?.iso, "2027-01-31")
        XCTAssertEqual(JourParis(iso: "2026-12-31").decale(de: 1)?.iso, "2027-01-01")
        XCTAssertEqual(JourParis(iso: "2028-03-01").decale(de: -1)?.iso, "2028-02-29")
        XCTAssertNil(JourParis(iso: "2026-02-30").decale(de: 1))

        // Semaine civile, du lundi au dimanche : des jours, aucune heure (les changements d'heure n'y changent rien).
        XCTAssertEqual(Self.mardi.semaine, Self.lundi...JourParis(iso: "2026-11-08"))
        XCTAssertEqual(Self.lundi.semaine, Self.lundi...JourParis(iso: "2026-11-08"))
        XCTAssertEqual(JourParis(iso: "2026-11-08").semaine, Self.lundi...JourParis(iso: "2026-11-08"))
        XCTAssertEqual(JourParis(iso: "2026-10-25").semaine, JourParis(iso: "2026-10-19")...JourParis(iso: "2026-10-25"),
                       "dimanche du retour à l'heure d'hiver")
        XCTAssertEqual(JourParis(iso: "2027-03-28").semaine, JourParis(iso: "2027-03-22")...JourParis(iso: "2027-03-28"),
                       "dimanche du passage à l'heure d'été")
        XCTAssertEqual(JourParis(iso: "2027-01-01").semaine, JourParis(iso: "2026-12-28")...JourParis(iso: "2027-01-03"))
        XCTAssertNil(JourParis(iso: "2026-02-30").semaine)
    }

    // MARK: - Lecture des lignes

    func testLectureDesLignesDeLaTable() throws {
        XCTAssertEqual(DisponibilitesLecture.colonnes, "jour,creneau", "colonnes du web (l.52)")
        let json = """
        [{"jour":"2026-11-03","creneau":"JOURNEE"},{"jour":"2026-11-03","creneau":"NUIT","cree_le":"2026-11-01T10:00:00+00:00"},
         {"jour":"2026-11-04","creneau":"MATIN"},{"jour":"2026-11-05","creneau":"APRES_MIDI"}]
        """
        let lignes = try JSONDecoder().decode([LigneDisponibilite].self, from: Data(json.utf8))
        XCTAssertEqual(DisponibilitesLecture.cles(lignes), [Self.mardiJour, Self.mardiNuit],
                       "MATIN et APRES_MIDI (admis par la RPC, jamais écrits par le web ni par l'app) ne sont pas des cases de la grille")
        XCTAssertEqual(DisponibilitesLecture.cles([]), [])
        XCTAssertNil(DisponibilitesLecture.cles([LigneDisponibilite(jour: "2026-11-03", creneau: "NUIT"),
                                                 LigneDisponibilite(jour: "03/11/2026", creneau: "NUIT")]),
                     "un jour illisible : réponse refusée, jamais une grille plausible")
        XCTAssertThrowsError(try JSONDecoder().decode([LigneDisponibilite].self, from: Data(#"[{"creneau":"NUIT"}]"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode([LigneDisponibilite].self, from: Data(#"{"jour":"2026-11-03","creneau":"NUIT"}"#.utf8)))
    }

    // MARK: - Grille présentée

    func testGrillePresenteeDepuisLaGrilleLesCasesDeclareesEtLesAppelsEnCours() throws {
        // Mercredi 4 novembre 2026, 10 h à Paris.
        let grille = SemainesDisponibilites.grille(maintenant: try DateHeureParis.instantJolene("2026-11-04T09:00:00Z"))
        let jeudiJour = DispoCle(jour: JourParis(iso: "2026-11-05"), creneau: .journee)
        let semaines = DisponibilitesPresentation.semaines(grille: grille, declarees: [Self.jeudiNuit, Self.samediSuivant],
                                                           enCours: [jeudiJour])
        XCTAssertEqual(semaines.map(\.id), ["dispos-semaine-1", "dispos-semaine-2", "dispos-semaine-3", "dispos-semaine-4"])
        XCTAssertEqual(semaines.map(\.entete), grille.semaines.map(\.entete))
        XCTAssertEqual(semaines.map(\.jours.count), [7, 7, 7, 7])
        let jours = semaines.flatMap(\.jours)
        XCTAssertEqual(jours.map(\.id), grille.semaines.flatMap(\.jours).map(\.jour.iso), "identifiant de ligne : jour `yyyy-MM-dd`")
        XCTAssertEqual(jours.filter(\.passe).map(\.id), ["2026-11-02", "2026-11-03"])
        XCTAssertEqual(jours.filter(\.estAujourdhui).map(\.libelle), ["Mercredi 4 Nov."])
        let jeudi = try XCTUnwrap(jours.first { $0.id == "2026-11-05" })
        XCTAssertEqual(jeudi.journee, CaseDisponibilite(declaree: false, enCours: true))
        XCTAssertEqual(jeudi.nuit, CaseDisponibilite(declaree: true, enCours: false))
        XCTAssertEqual(jeudi.etat(.journee), jeudi.journee)
        XCTAssertEqual(jeudi.etat(.nuit), jeudi.nuit)
        let samedi = try XCTUnwrap(jours.first { $0.id == "2026-11-14" })
        XCTAssertEqual(samedi.journee, CaseDisponibilite(declaree: true, enCours: false))
        XCTAssertEqual(jours.filter { $0.journee.declaree || $0.nuit.declaree }.count, 2)
    }

    // MARK: - Monde démo

    func testFixtureDemoTroisCreneauxDansLaGrilleDeLHorlogeDemo() throws {
        let fichier = try DemoFixtures.loadDisponibilites()
        XCTAssertEqual(fichier.fixedNow, "2026-11-02T00:00:00.000Z")
        let cles = try XCTUnwrap(DisponibilitesLecture.cles(fichier.disponibilites))
        XCTAssertEqual(cles, Self.fixture, "trois créneaux posés (LOT4_PLAN.md §2.7)")
        XCTAssertEqual(fichier.disponibilites.count, 3, "aucune ligne hors grille dans la fixture")
        let grille = SemainesDisponibilites.grille(maintenant: DemoWorld.fixedNow)
        let basculables = Set(grille.semaines.flatMap(\.jours).filter { !$0.passe }.map(\.jour))
        XCTAssertTrue(cles.allSatisfy { basculables.contains($0.jour) }, "créneaux visibles dans la grille de l'horloge démo")
        XCTAssertFalse(cles.contains(Self.mardiNuit), "case basculée par l'XCUITest : libre au lancement")
    }

    func testMondeDemoCableLectureBasculeEtRefusDeLaRPC() async throws {
        XCTAssertTrue(DemoWorld.gateways().disponibilites is DemoDisponibilitesGateway, "T5 câble les disponibilités")
        let port = DemoDisponibilitesGateway()
        let context = DemoWorld.context
        let lues = try await port.lister(depuis: Self.lundi, context: context)
        XCTAssertEqual(lues, Self.fixture)
        let depuisJeudi = try await port.lister(depuis: JourParis(iso: "2026-11-05"), context: context)
        XCTAssertEqual(depuisJeudi, [Self.jeudiNuit, Self.samediSuivant], "lecture bornée comme `.gte('jour', …)`")

        // Bascule : semaine civile du jour relue, idempotente comme la RPC (`ON CONFLICT DO NOTHING`, `DELETE`).
        let posee = try await port.definir(jour: Self.mardi, creneau: .nuit, disponible: true, context: context)
        XCTAssertEqual(posee, .relue([Self.mardiJour, Self.mardiNuit, Self.jeudiNuit]), "la semaine du jour, pas les autres")
        let reposee = try await port.definir(jour: Self.mardi, creneau: .nuit, disponible: true, context: context)
        XCTAssertEqual(reposee, posee)
        let retiree = try await port.definir(jour: Self.mardi, creneau: .nuit, disponible: false, context: context)
        XCTAssertEqual(retiree, .relue([Self.mardiJour, Self.jeudiNuit]))
        let absente = try await port.definir(jour: Self.mardi, creneau: .nuit, disponible: false, context: context)
        XCTAssertEqual(absente, retiree)

        // Bornes de la RPC : de `CURRENT_DATE` à `CURRENT_DATE + 90`, refus verbatim.
        let hier = try await port.definir(jour: JourParis(iso: "2026-11-01"), creneau: .journee, disponible: true, context: context)
        XCTAssertEqual(hier, .refusee(message: "La disponibilité doit être entre aujourd'hui et J+90"))
        let limite = try await port.definir(jour: JourParis(iso: "2027-01-31"), creneau: .journee, disponible: true, context: context)
        XCTAssertEqual(limite, .relue([DispoCle(jour: JourParis(iso: "2027-01-31"), creneau: .journee)]), "J+90 accepté")
        let audela = try await port.definir(jour: JourParis(iso: "2027-02-01"), creneau: .journee, disponible: true, context: context)
        XCTAssertEqual(audela, .refusee(message: DisponibilitesTextes.horsFenetre), "J+91 refusé")
        let apresRefus = try await port.lister(depuis: Self.lundi, context: context)
        XCTAssertEqual(apresRefus.count, 4, "un refus n'écrit rien")

        // Jour illisible : jamais envoyé, jamais une issue plausible.
        for appel in [0, 1] {
            do {
                if appel == 0 {
                    _ = try await port.lister(depuis: JourParis(iso: "aujourd'hui"), context: context)
                } else {
                    _ = try await port.definir(jour: JourParis(iso: "2026-02-30"), creneau: .nuit, disponible: true, context: context)
                }
                XCTFail("jour illisible refusé")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .contract)
            }
        }

        let autre = MissionReadContext(userId: "autre", email: nil, profile: SoignantProfile(id: "autre", profession: "IDE"))
        do {
            _ = try await port.lister(depuis: Self.lundi, context: autre)
            XCTFail("contexte hors démo refusé")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
        do {
            _ = try await port.definir(jour: Self.mardi, creneau: .nuit, disponible: true, context: autre)
            XCTFail("contexte hors démo refusé")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }

        // Aucun état démo persisté : une autre instance repart de la fixture.
        let relance = try await DemoDisponibilitesGateway().lister(depuis: Self.lundi, context: context)
        XCTAssertEqual(relance, Self.fixture)
    }
}
