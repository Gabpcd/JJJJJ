import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/date-heure-paris.json` (port de `src/lib/date-heure-paris.ts`).
final class RulesDateHeureParisTests: XCTestCase {
    func testVecteursGoldenDateHeureParis() throws {
        let rejoues = try Golden.rejouer("date-heure-paris") { vecteur in
            let entree = vecteur.input
            switch vecteur.fonction {
            case "instantJolene":
                return Golden.capture { .instant(try Golden.instant(entree["valeur"])) }
            case "instantDepuisSaisieParis":
                return Golden.capture { .instant(try DateHeureParis.instantDepuisSaisie(entree["valeur"]?.string ?? "")) }
            case "instantDateHeureParis":
                return Golden.capture {
                    let parties = try XCTUnwrap(entree["parties"]).decode(PartiesDateHeureParis.self)
                    return .instant(try DateHeureParis.instant(parties))
                }
            case "partiesDateHeureParis":
                return Golden.capture { try .depuis(DateHeureParis.parties(try Golden.instant(entree["valeur"]))) }
            case "formatParis":
                return Golden.capture {
                    .string(DateHeureParis.format(try Golden.instant(entree["valeur"]), entree["masque"]?.string ?? ""))
                }
            case "valeurSaisieDateHeureParis":
                return Golden.capture { .string(DateHeureParis.valeurSaisie(try Golden.instant(entree["valeur"]))) }
            case "debutJourParis":
                return Golden.capture { .instant(DateHeureParis.debutJour(try Golden.instant(entree["valeur"]))) }
            case "ajouterJoursCivilsParis":
                return Golden.capture {
                    .instant(DateHeureParis.ajouterJoursCivils(try Golden.instant(entree["valeur"]), entree["jours"]?.int ?? 0))
                }
            case "debutMoisParis":
                return Golden.capture { .instant(DateHeureParis.debutMois(try Golden.instant(entree["valeur"]))) }
            case "ajouterMoisCivilsParis":
                return Golden.capture {
                    .instant(DateHeureParis.ajouterMoisCivils(try Golden.instant(entree["valeur"]), entree["mois"]?.int ?? 0))
                }
            case "finMoisParis":
                return Golden.capture { .instant(DateHeureParis.finMois(try Golden.instant(entree["valeur"]))) }
            case "debutSemaineParis":
                return Golden.capture { .instant(DateHeureParis.debutSemaine(try Golden.instant(entree["valeur"]))) }
            case "semaineSuivanteParis":
                return Golden.capture { .instant(DateHeureParis.semaineSuivante(try Golden.instant(entree["valeur"]))) }
            case "cleJourParis":
                return Golden.capture { .string(DateHeureParis.cleJour(try Golden.instant(entree["valeur"]))) }
            case "cleMoisParis":
                return Golden.capture { .string(DateHeureParis.cleMois(try Golden.instant(entree["valeur"]))) }
            case "cleSemaineParis":
                return Golden.capture { .string(DateHeureParis.cleSemaine(try Golden.instant(entree["valeur"]))) }
            case "memeJourParis":
                return Golden.capture { .bool(DateHeureParis.memeJour(try Golden.instant(entree["a"]), try Golden.instant(entree["b"]))) }
            case "memeMoisParis":
                return Golden.capture { .bool(DateHeureParis.memeMois(try Golden.instant(entree["a"]), try Golden.instant(entree["b"]))) }
            case "heureDecimaleParis":
                return Golden.capture { .number(DateHeureParis.heureDecimale(try Golden.instant(entree["valeur"]))) }
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    /// Les jours civils de 23 h et 25 h aux changements d'heure (test vitest d'origine).
    func testJoursCivilsDe23hEt25hAuxChangementsDHeure() throws {
        let debutCourt = DateHeureParis.debutJour(try DateHeureParis.instantJolene("2026-03-29T12:00:00.000Z"))
        let finCourt = DateHeureParis.ajouterJoursCivils(debutCourt, 1)
        XCTAssertEqual(finCourt.timeIntervalSince(debutCourt) / 3600, 23)

        let debutLong = DateHeureParis.debutJour(try DateHeureParis.instantJolene("2026-10-25T12:00:00.000Z"))
        let finLong = DateHeureParis.ajouterJoursCivils(debutLong, 1)
        XCTAssertEqual(finLong.timeIntervalSince(debutLong) / 3600, 25)
    }

    func testMessagesDErreurReprennentLeWordingWeb() {
        XCTAssertThrowsError(try DateHeureParis.instantDepuisSaisie("2026-03-29T02:30")) { erreur in
            XCTAssertEqual((erreur as? DateHeureParisError)?.code, "INEXISTANTE")
            XCTAssertEqual(erreur.localizedDescription, "Date/heure inexistante dans le fuseau Europe/Paris: 2026-03-29T02:30:00")
        }
        XCTAssertThrowsError(try DateHeureParis.instantDepuisSaisie("2026-10-25T02:30")) { erreur in
            XCTAssertEqual((erreur as? DateHeureParisError)?.code, "AMBIGUE")
            XCTAssertTrue(erreur.localizedDescription.contains("ambiguë"))
        }
    }
}
