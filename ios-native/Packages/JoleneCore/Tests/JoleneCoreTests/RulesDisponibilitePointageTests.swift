import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/disponibilite-pointage.json`
/// (port de `src/lib/disponibilite-pointage.ts`).
final class RulesDisponibilitePointageTests: XCTestCase {
    private struct MissionStatut: Decodable, AvecStatutMission {
        let id: String
        let statut: String
    }

    private func creneaux(_ valeur: JSONValue?) throws -> [MissionSlot] {
        try (valeur ?? .array([])).decode([MissionSlot].self)
    }

    private func periode(_ valeur: JSONValue?) throws -> PeriodeMissionPointage {
        PeriodeMissionPointage(
            id: valeur?["id"]?.string,
            debutLe: try XCTUnwrap(valeur?["debut_le"]?.string),
            finLe: try XCTUnwrap(valeur?["fin_le"]?.string)
        )
    }

    private func golden(_ etat: EtatDisponibilitePointage) -> JSONValue {
        .object([
            "peutPointer": .bool(etat.peutPointer),
            "action": .chaine(etat.action?.rawValue),
            "motif": .chaine(etat.motif?.rawValue),
            "creneauCourant": etat.creneauCourant?.golden ?? .null,
            "prochainCreneau": etat.prochainCreneau?.golden ?? .null,
        ])
    }

    private func golden(_ etat: EtatTerminaisonMission) -> JSONValue {
        .object([
            "peutTerminer": .bool(etat.peutTerminer),
            "motif": .chaine(etat.motif?.rawValue),
            "finReference": .instant(etat.finReference),
        ])
    }

    private func golden(_ etat: EtatClotureAdminMission) -> JSONValue {
        .object([
            "peutTerminer": .bool(etat.peutTerminer),
            "motif": .chaine(etat.motif?.rawValue),
            "finReference": .instant(etat.finReference),
            "clotureAnticipee": .bool(etat.clotureAnticipee),
        ])
    }

    private func terminaison(_ entree: JSONValue?) throws -> EtatTerminaisonMission {
        DisponibilitePointage.evaluerTerminaisonMission(
            creneaux: try creneaux(entree?["creneaux"]),
            finMission: entree?["finMission"]?.string ?? "",
            presences: try (entree?["presences"] ?? .array([])).decode([PresencePointage].self),
            maintenant: try Golden.instant(entree?["maintenant"])
        )
    }

    func testVecteursGoldenDisponibilitePointage() throws {
        let rejoues = try Golden.rejouer("disponibilite-pointage") { vecteur in
            let entree = vecteur.input
            switch vecteur.fonction {
            case "choisirContratPointage":
                let contrats = try (entree["contrats"] ?? .array([])).decode([ContratPointage].self)
                return .chaine(DisponibilitePointage.choisirContratPointage(contrats)?.id)
            case "filtrerMissionsEnCours":
                let missions = try (entree["missions"] ?? .array([])).decode([MissionStatut].self)
                return .array(DisponibilitePointage.filtrerMissionsEnCours(missions).map { .string($0.id) })
            case "creneauxPrevisionnels":
                return .array(DisponibilitePointage.creneauxPrevisionnels(try creneaux(entree["creneaux"])).map(\.golden))
            case "ajouterRepliMissionPonctuelle":
                return .array(DisponibilitePointage.ajouterRepliMissionPonctuelle(try creneaux(entree["creneaux"]), mission: try periode(entree["mission"])).map(\.golden))
            case "creneauChevauchePeriode":
                let creneau = try XCTUnwrap(entree["creneau"]).decode(MissionSlot.self)
                return .bool(DisponibilitePointage.creneauChevauchePeriode(
                    creneau, debutPeriode: try Golden.instant(entree["debutPeriode"]), finPeriode: try Golden.instant(entree["finPeriode"])
                ))
            case "prochainCreneauPointage":
                return DisponibilitePointage.prochainCreneauPointage(try creneaux(entree["creneaux"]), maintenant: try Golden.instant(entree["maintenant"]))?.golden ?? .null
            case "evaluerDisponibilitePointage":
                return golden(DisponibilitePointage.evaluerDisponibilitePointage(
                    creneaux: try creneaux(entree["creneaux"]),
                    contratStatut: entree["contratStatut"]?.string,
                    maintenant: try Golden.instant(entree["maintenant"])
                ))
            case "evaluerTerminaisonMission":
                return golden(try terminaison(entree))
            case "evaluerClotureAdminMission":
                return golden(DisponibilitePointage.evaluerClotureAdminMission(
                    terminaison: try terminaison(entree["terminaison"]),
                    estAdmin: entree["estAdmin"]?.bool ?? false,
                    litigeActif: entree["litigeActif"]?.bool ?? false
                ))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    func testFenetreDOuvertureEstDe15Minutes() {
        XCTAssertEqual(DisponibilitePointage.fenetreOuvertureMinutes, 15)
    }

    func testMissionRecordEstUtilisableDirectement() {
        let record = MissionRecord(
            id: "m1", intitule: "IDE", description: nil, service: nil, professionRequise: "IDE",
            specialiteMedicaleRequise: nil, accepteNonSpecialises: nil,
            debutLe: "2026-07-31T08:00:00+02:00", finLe: "2026-07-31T16:00:00+02:00",
            dureeHeures: 8, nbCreneaux: 1, tauxHoraireBase: nil, tauxRistPlafonne: nil, ristPlafondApplique: nil,
            totalBrut: nil, netAPayer: nil, estUrgente: false, niveauUrgence: nil, statut: "EN_COURS",
            etablissementId: "e1", typeContratRecherche: nil, boosteeLe: nil, modeRemuneration: nil, retrocessionPct: nil
        )
        XCTAssertEqual(DisponibilitePointage.filtrerMissionsEnCours([record]).count, 1)
        let repli = DisponibilitePointage.ajouterRepliMissionPonctuelle([], mission: PeriodeMissionPointage(record))
        XCTAssertEqual(repli.map(\.id), ["mission-ponctuelle-m1"])
    }
}
