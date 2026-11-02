import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/planning-derive.json` (port structurel de `src/lib/planning-derive.ts`,
/// lot 5 T3) et vérifie la re-dérivation conservatrice de `FormulaireRecurrence.tsx` l.164-218.
/// Les règles 48 h, repos 11 h et journée de plus de 12 h ne sont pas portées (blueprint lot 5
/// §2.9, D9) : le serveur les applique et le natif affiche son refus verbatim.
final class RulesPlanningDeriveTests: XCTestCase {
    // MARK: - Décodage des vecteurs

    private func creneau(_ valeur: JSONValue?) throws -> PlanningDerive.Creneau {
        let c = try XCTUnwrap(valeur, "créneau absent du vecteur")
        return PlanningDerive.Creneau(
            clientId: try XCTUnwrap(c["clientId"]?.string),
            id: c["id"]?.string,
            heureDebut: try XCTUnwrap(c["heureDebut"]?.string),
            heureFin: try XCTUnwrap(c["heureFin"]?.string),
            finJourSuivant: try XCTUnwrap(c["finJourSuivant"]?.bool),
            debutInitial: c["debutInitial"]?.string,
            finInitial: c["finInitial"]?.string
        )
    }

    private func jours(_ valeur: JSONValue?) throws -> [PlanningDerive.Jour] {
        try XCTUnwrap(valeur?.array, "jours absents du vecteur").map { jour in
            PlanningDerive.Jour(
                date: try XCTUnwrap(jour["date"]?.string),
                actif: try XCTUnwrap(jour["actif"]?.bool),
                creneaux: try XCTUnwrap(jour["creneaux"]?.array).map { try creneau($0) }
            )
        }
    }

    // MARK: - Encodage des résultats (forme `JSON.stringify` du web)

    private func golden(_ materialise: PlanningDerive.CreneauMaterialise) -> JSONValue {
        var objet: [String: JSONValue] = [
            "clientId": .string(materialise.clientId),
            "date": .string(materialise.date),
            "dateFin": .string(materialise.dateFin),
            "debut": .string(materialise.debut),
            "fin": .string(materialise.fin),
            "dureeHeures": .number(materialise.dureeHeures),
        ]
        // `id: undefined` disparaît de `JSON.stringify`.
        if let id = materialise.id { objet["id"] = .string(id) }
        return .object(objet)
    }

    private func golden(_ erreur: PlanningDerive.Erreur) -> JSONValue {
        var objet: [String: JSONValue] = [
            "type": .string(erreur.type.rawValue),
            "gravite": .string(PlanningDerive.Erreur.gravite),
            "message": .string(erreur.message),
        ]
        if let dates = erreur.datesAffectees { objet["datesAffectees"] = .array(dates.map(JSONValue.string)) }
        if let creneaux = erreur.creneauxAffectes { objet["creneauxAffectes"] = .array(creneaux.map(JSONValue.string)) }
        return .object(objet)
    }

    func testVecteursGoldenPlanningDerive() throws {
        var parFonction: [String: Int] = [:]
        let rejoues = try Golden.rejouer("planning-derive") { vecteur in
            let entree = vecteur.input
            parFonction[vecteur.fonction, default: 0] += 1
            switch vecteur.fonction {
            case "ajouterJoursDate":
                let date = try XCTUnwrap(entree["date"]?.string)
                let nombre = try XCTUnwrap(entree["nombre"]?.int)
                return Golden.capture { .string(try PlanningDerive.ajouterJoursDate(date, nombre)) }
            case "datesDansPlage":
                let debut = try XCTUnwrap(entree["dateDebut"]?.string)
                let fin = try XCTUnwrap(entree["dateFin"]?.string)
                return Golden.capture { .array(try PlanningDerive.datesDansPlage(debut, fin).map(JSONValue.string)) }
            case "jourSemaineISO":
                let date = try XCTUnwrap(entree["date"]?.string)
                return PlanningDerive.jourSemaineISO(date).map { .number(Double($0)) } ?? .null
            case "dateFinCreneau":
                let date = try XCTUnwrap(entree["date"]?.string)
                let finJourSuivant = try XCTUnwrap(entree["finJourSuivant"]?.bool)
                return Golden.capture { .string(try PlanningDerive.dateFinCreneau(date, finJourSuivant: finJourSuivant)) }
            case "materialiserCreneau":
                let date = try XCTUnwrap(entree["date"]?.string)
                let creneau = try creneau(entree["creneau"])
                return Golden.capture {
                    let resultat = try PlanningDerive.materialiserCreneau(date: date, creneau: creneau)
                    return .object([
                        "valeur": resultat.valeur.map(golden) ?? .null,
                        "erreur": .chaine(resultat.erreur),
                    ])
                }
            case "materialiserPlanning":
                let jours = try jours(entree["jours"])
                return Golden.capture { .array(try PlanningDerive.materialiserPlanning(jours).map(golden)) }
            case "validerPlanningDates":
                let jours = try jours(entree["jours"])
                return Golden.capture {
                    .object(["erreursStructurelles": .array(try PlanningDerive.erreursStructurelles(jours).map(golden))])
                }
            default:
                return nil
            }
        }
        XCTAssertGreaterThanOrEqual(rejoues, 600)
        for fonction in ["ajouterJoursDate", "datesDansPlage", "jourSemaineISO", "dateFinCreneau",
                         "materialiserCreneau", "materialiserPlanning", "validerPlanningDates"] {
            XCTAssertGreaterThan(parFonction[fonction, default: 0], 0, "aucun vecteur pour \(fonction)")
        }
    }

    /// Le golden ne contient aucune règle juridique : ni le plafond de 48 h, ni le repos de 11 h,
    /// ni la recommandation de 12 h (blueprint lot 5 §2.9, D9).
    func testGoldenSansRegleDuTravail() throws {
        for vecteur in try Golden.charger("planning-derive") {
            let rendu = vecteur.expected.description
            for interdit in ["PLAFOND_48H", "REPOS_11H", "DUREE_LONGUE", "48 h", "11 h", "12 h", "légal"] {
                XCTAssertFalse(rendu.contains(interdit), "« \(vecteur.name) » expose « \(interdit) »")
            }
        }
    }

    // MARK: - Re-dérivation (FormulaireRecurrence.tsx l.164-178)

    private func generateur(_ prefixe: String = "n") -> () -> String {
        var compteur = 0
        return {
            compteur += 1
            return "\(prefixe)-\(compteur)"
        }
    }

    func testCreneauDefautSeptHeuresDixNeufHeures() {
        XCTAssertEqual(PlanningDerive.creneauDefaut(clientId: "x"),
                       PlanningDerive.Creneau(clientId: "x", heureDebut: "07:00", heureFin: "19:00", finJourSuivant: false))
    }

    func testRederiverCreeDesJoursInactifsAvecUnCreneauParDefaut() throws {
        let jours = try PlanningDerive.rederiver(dateDebut: "2026-08-03", dateFin: "2026-08-05", precedents: [],
                                                 nouvelIdClient: generateur())
        XCTAssertEqual(jours.map(\.date), ["2026-08-03", "2026-08-04", "2026-08-05"])
        XCTAssertTrue(jours.allSatisfy { !$0.actif }, "un jour nouveau n'est jamais travaillé par défaut")
        XCTAssertEqual(jours.map { $0.creneaux.map(\.clientId) }, [["n-1"], ["n-2"], ["n-3"]])
        XCTAssertTrue(jours.allSatisfy { $0.creneaux.first?.heureDebut == "07:00" && $0.creneaux.first?.heureFin == "19:00" })
    }

    func testRederiverConserveUnJourResteDansLaPeriodeEtSupprimeUnJourSorti() throws {
        let modifie = PlanningDerive.Jour(date: "2026-08-04", actif: true, creneaux: [
            PlanningDerive.Creneau(clientId: "matin", heureDebut: "06:00", heureFin: "11:00", finJourSuivant: false),
            PlanningDerive.Creneau(clientId: "soir", heureDebut: "15:00", heureFin: "21:00", finJourSuivant: false),
        ])
        let sorti = PlanningDerive.Jour(date: "2026-08-03", actif: true, creneaux: [PlanningDerive.creneauDefaut(clientId: "sorti")])
        let jours = try PlanningDerive.rederiver(dateDebut: "2026-08-04", dateFin: "2026-08-06", precedents: [sorti, modifie],
                                                 nouvelIdClient: generateur())
        XCTAssertEqual(jours.map(\.date), ["2026-08-04", "2026-08-05", "2026-08-06"])
        XCTAssertEqual(jours[0], modifie, "le jour resté dans la période garde son état et ses créneaux (exceptions comprises)")
        XCTAssertFalse(jours[1].actif)
        XCTAssertFalse(jours[2].actif)
        XCTAssertFalse(jours.contains { $0.date == "2026-08-03" }, "le jour sorti de la période disparaît")
    }

    func testRederiverPeriodeVideOuTropLongueVideLesJours() throws {
        let precedent = [PlanningDerive.Jour(date: "2026-08-04", actif: true, creneaux: [])]
        XCTAssertEqual(try PlanningDerive.rederiver(dateDebut: "2026-08-05", dateFin: "2026-08-04", precedents: precedent,
                                                    nouvelIdClient: generateur()), [])
        XCTAssertEqual(try PlanningDerive.rederiver(dateDebut: "", dateFin: "", precedents: precedent,
                                                    nouvelIdClient: generateur()), [])
        XCTAssertEqual(try PlanningDerive.rederiver(dateDebut: "2026-01-01", dateFin: "2027-01-02", precedents: precedent,
                                                    nouvelIdClient: generateur()), [], "367 dates : plus de 366")
        XCTAssertEqual(try PlanningDerive.rederiver(dateDebut: "2026-01-01", dateFin: "2027-01-01", precedents: [],
                                                    nouvelIdClient: generateur()).count, 366)
    }

    func testRederiverUnDoublonDeDateGardeLeDernier() throws {
        // `new Map(precedents.map(...))` : la dernière entrée d'une même date l'emporte.
        let premier = PlanningDerive.Jour(date: "2026-08-04", actif: false, creneaux: [])
        let second = PlanningDerive.Jour(date: "2026-08-04", actif: true, creneaux: [PlanningDerive.creneauDefaut(clientId: "s")])
        let jours = try PlanningDerive.rederiver(dateDebut: "2026-08-04", dateFin: "2026-08-04", precedents: [premier, second],
                                                 nouvelIdClient: generateur())
        XCTAssertEqual(jours, [second])
    }

    // MARK: - Actions de saisie (FormulaireRecurrence.tsx l.233-280, l.395-402)

    private func troisJoursInactifs() throws -> [PlanningDerive.Jour] {
        try PlanningDerive.rederiver(dateDebut: "2026-08-03", dateFin: "2026-08-05", precedents: [], nouvelIdClient: generateur("d"))
    }

    func testPlusieursCreneauxSurUneDateSansModifierLesAutres() throws {
        // Rejoue « permet plusieurs créneaux sur une date sans modifier les autres dates » (vitest l.81-103).
        let ids = generateur("a")
        var jours = PlanningDerive.toutesLesDates(try troisJoursInactifs(), nouvelIdClient: ids)
        jours = PlanningDerive.ajouterCreneau(jours, date: "2026-08-04", nouvelIdClient: ids)
        XCTAssertEqual(jours[1].creneaux.count, 2)
        jours = PlanningDerive.basculer(jours, date: "2026-08-03", nouvelIdClient: ids)
        XCTAssertFalse(jours[0].actif)
        XCTAssertEqual(jours[1].creneaux.count, 2)
        XCTAssertTrue(jours[2].actif)
    }

    func testUneExceptionSurUnMercrediNeDesactivePasLeMercrediSuivant() throws {
        // Rejoue la vitest l.126-140 : une occurrence datée est modifiable individuellement.
        let ids = generateur("m")
        var jours = try PlanningDerive.rederiver(dateDebut: "2026-08-05", dateFin: "2026-08-12", precedents: [], nouvelIdClient: ids)
        jours = PlanningDerive.toutesLesDates(jours, nouvelIdClient: ids)
        jours = PlanningDerive.basculer(jours, date: "2026-08-05", nouvelIdClient: ids)
        XCTAssertEqual(jours.first { $0.date == "2026-08-05" }?.actif, false)
        XCTAssertEqual(jours.first { $0.date == "2026-08-12" }?.actif, true)
        // L'exception survit à une re-dérivation tant que la date reste dans la période.
        let rederive = try PlanningDerive.rederiver(dateDebut: "2026-08-04", dateFin: "2026-08-12", precedents: jours, nouvelIdClient: ids)
        XCTAssertEqual(rederive.first { $0.date == "2026-08-05" }?.actif, false)
        XCTAssertEqual(rederive.first { $0.date == "2026-08-12" }?.actif, true)
        XCTAssertEqual(rederive.first { $0.date == "2026-08-04" }?.actif, false)
    }

    func testBasculerUnJourSansCreneauLuiDonneLeCreneauParDefaut() {
        let jours = [PlanningDerive.Jour(date: "2026-08-03", actif: false, creneaux: [])]
        let actives = PlanningDerive.basculer(jours, date: "2026-08-03", nouvelIdClient: generateur("b"))
        XCTAssertEqual(actives, [PlanningDerive.Jour(date: "2026-08-03", actif: true, creneaux: [PlanningDerive.creneauDefaut(clientId: "b-1")])])
        let desactive = PlanningDerive.basculer(actives, date: "2026-08-03", nouvelIdClient: generateur("x"))
        XCTAssertEqual(desactive, [PlanningDerive.Jour(date: "2026-08-03", actif: false, creneaux: [PlanningDerive.creneauDefaut(clientId: "b-1")])],
                       "désactiver garde les créneaux saisis")
    }

    func testModifierEtRetirerUnCreneauCibleSonClientId() {
        let a = PlanningDerive.Creneau(clientId: "a", heureDebut: "07:00", heureFin: "12:00", finJourSuivant: false)
        let b = PlanningDerive.Creneau(clientId: "b", heureDebut: "13:00", heureFin: "18:00", finJourSuivant: false)
        let jours = [PlanningDerive.Jour(date: "2026-08-03", actif: true, creneaux: [a, b]),
                     PlanningDerive.Jour(date: "2026-08-04", actif: true, creneaux: [a])]
        var nouveauB = b
        nouveauB.heureFin = "19:00"
        let modifies = PlanningDerive.modifierCreneau(jours, date: "2026-08-03", creneau: nouveauB)
        XCTAssertEqual(modifies[0].creneaux, [a, nouveauB])
        XCTAssertEqual(modifies[1], jours[1], "les autres dates ne bougent pas")
        let retires = PlanningDerive.retirerCreneau(jours, date: "2026-08-03", clientId: "a")
        XCTAssertEqual(retires[0].creneaux, [b])
        XCTAssertEqual(retires[1].creneaux, [a])
    }

    func testSelectionsLundiVendrediAucuneEtUneSemaineSurDeux() throws {
        let ids = generateur("s")
        let jours = try PlanningDerive.rederiver(dateDebut: "2026-08-03", dateFin: "2026-08-16", precedents: [], nouvelIdClient: ids)
        let ouvres = PlanningDerive.lundiAuVendredi(jours, nouvelIdClient: ids)
        XCTAssertEqual(ouvres.filter(\.actif).map(\.date),
                       ["2026-08-03", "2026-08-04", "2026-08-05", "2026-08-06", "2026-08-07",
                        "2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13", "2026-08-14"])
        XCTAssertTrue(PlanningDerive.aucuneDate(ouvres, nouvelIdClient: ids).allSatisfy { !$0.actif })
        let alternees = try PlanningDerive.uneSemaineSurDeux(jours, nouvelIdClient: ids)
        XCTAssertEqual(alternees.filter(\.actif).map(\.date),
                       ["2026-08-03", "2026-08-04", "2026-08-05", "2026-08-06", "2026-08-07", "2026-08-08", "2026-08-09"])
    }

    func testAppliquerLePremierCreneauATousLesJoursTravailles() {
        let modele = PlanningDerive.Creneau(clientId: "m", id: "persiste", heureDebut: "20:00", heureFin: "08:00", finJourSuivant: true)
        let jours = [PlanningDerive.Jour(date: "2026-08-03", actif: false, creneaux: [PlanningDerive.creneauDefaut(clientId: "r")]),
                     PlanningDerive.Jour(date: "2026-08-04", actif: true, creneaux: [modele]),
                     PlanningDerive.Jour(date: "2026-08-05", actif: true, creneaux: [PlanningDerive.creneauDefaut(clientId: "x"),
                                                                                    PlanningDerive.creneauDefaut(clientId: "y")])]
        let appliques = PlanningDerive.appliquerPremierCreneauATous(jours, nouvelIdClient: generateur("c"))
        XCTAssertEqual(appliques[0], jours[0], "un jour de repos ne change pas")
        let attendu = { (id: String) in
            PlanningDerive.Creneau(clientId: id, id: nil, heureDebut: "20:00", heureFin: "08:00", finJourSuivant: true)
        }
        XCTAssertEqual(appliques[1].creneaux, [attendu("c-1")])
        XCTAssertEqual(appliques[2].creneaux, [attendu("c-2")], "un seul créneau, copie du modèle sans identifiant persisté")
        XCTAssertEqual(PlanningDerive.appliquerPremierCreneauATous([jours[0]], nouvelIdClient: generateur()), [jours[0]],
                       "sans jour travaillé, rien n'est appliqué")
    }

    // MARK: - Validation de la période (FormulaireRecurrence.tsx l.180-218)

    func testValiderPeriodeInvalide() throws {
        let attendu = [PlanningDerive.Erreur(type: .plageInvalide, message: PlanningDerive.messagePeriodeInvalide)]
        XCTAssertEqual(try PlanningDerive.validerPeriode(dateDebut: "", dateFin: "2026-08-03", jours: []), attendu)
        XCTAssertEqual(try PlanningDerive.validerPeriode(dateDebut: "2026-08-03", dateFin: "", jours: []), attendu)
        XCTAssertEqual(try PlanningDerive.validerPeriode(dateDebut: "2026-08-04", dateFin: "2026-08-03", jours: []), attendu)
    }

    func testValiderPeriodeDePlusDe366Dates() throws {
        XCTAssertEqual(try PlanningDerive.validerPeriode(dateDebut: "2026-01-01", dateFin: "2027-01-02", jours: []),
                       [PlanningDerive.Erreur(type: .plageInvalide, message: PlanningDerive.messagePeriodeTropLongue)])
        XCTAssertNotEqual(try PlanningDerive.validerPeriode(dateDebut: "2026-01-01", dateFin: "2027-01-01", jours: []).first?.message,
                          PlanningDerive.messagePeriodeTropLongue, "366 dates sont acceptées")
    }

    func testValiderPeriodeSansDateTravaillee() throws {
        let jours = try PlanningDerive.rederiver(dateDebut: "2026-08-03", dateFin: "2026-08-05", precedents: [], nouvelIdClient: generateur())
        XCTAssertEqual(try PlanningDerive.validerPeriode(dateDebut: "2026-08-03", dateFin: "2026-08-05", jours: jours),
                       [PlanningDerive.Erreur(type: .creneauManquant, message: PlanningDerive.messageAucuneDateTravaillee)])
    }

    func testValiderPeriodeDelegueAuxErreursStructurelles() throws {
        var jours = try PlanningDerive.rederiver(dateDebut: "2026-08-03", dateFin: "2026-08-03", precedents: [], nouvelIdClient: generateur())
        jours = PlanningDerive.toutesLesDates(jours, nouvelIdClient: generateur())
        XCTAssertEqual(try PlanningDerive.validerPeriode(dateDebut: "2026-08-03", dateFin: "2026-08-03", jours: jours), [])
        jours[0].creneaux.append(PlanningDerive.Creneau(clientId: "chevauche", heureDebut: "18:00", heureFin: "20:00", finJourSuivant: false))
        XCTAssertEqual(try PlanningDerive.validerPeriode(dateDebut: "2026-08-03", dateFin: "2026-08-03", jours: jours).map(\.type),
                       [.chevauchement])
    }

    /// Une semaine de 50 h, un repos de 9 h ou une journée de 13 h restent valides en natif :
    /// le serveur décide et le natif affiche son refus verbatim (D9).
    func testAucuneRegleDuTravailCoteClient() throws {
        let semaine50h = ["2026-07-20", "2026-07-21", "2026-07-22", "2026-07-23", "2026-07-24"].map {
            PlanningDerive.Jour(date: $0, actif: true, creneaux: [
                PlanningDerive.Creneau(clientId: $0, heureDebut: "07:00", heureFin: "17:00", finJourSuivant: false),
            ])
        }
        XCTAssertEqual(try PlanningDerive.erreursStructurelles(semaine50h), [])
        let reposCourt = [
            PlanningDerive.Jour(date: "2026-08-02", actif: true, creneaux: [
                PlanningDerive.Creneau(clientId: "nuit", heureDebut: "20:00", heureFin: "08:00", finJourSuivant: true),
            ]),
            PlanningDerive.Jour(date: "2026-08-03", actif: true, creneaux: [
                PlanningDerive.Creneau(clientId: "lundi", heureDebut: "09:00", heureFin: "17:00", finJourSuivant: false),
            ]),
        ]
        XCTAssertEqual(try PlanningDerive.erreursStructurelles(reposCourt), [])
    }

    // MARK: - Garde de dérive des messages repris du web

    func testMessagesVerbatimDuWeb() throws {
        try SourceWebLot5.verifier("src/components/FormulaireRecurrence.tsx", contient: [
            PlanningDerive.messagePeriodeInvalide,
            PlanningDerive.messagePeriodeTropLongue,
            PlanningDerive.messageAucuneDateTravaillee,
        ])
        try SourceWebLot5.verifier("src/lib/planning-derive.ts", contient: [
            PlanningDerive.messageHeuresInvalides,
            PlanningDerive.messageHeureAmbigue,
            PlanningDerive.messageFinAvantDebut,
            PlanningDerive.messageDureeHorsBornes,
            " est travaillé mais ne contient aucun créneau.",
            "Chevauchement entre les créneaux des ",
        ])
    }
}
