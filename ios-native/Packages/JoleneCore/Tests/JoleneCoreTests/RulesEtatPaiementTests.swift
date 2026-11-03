import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/paiement-soignant-ui.json` : port de `src/lib/paiementSoignantUi.ts`
/// (`repartirPaiementConfirme`, `indexerDernierPaiementParMission`, `classerPaiementSalaire`).
final class RulesEtatPaiementTests: XCTestCase {
    private func valeur(_ json: JSONValue?) throws -> ValeurJSON? {
        try json.map { try $0.decode(ValeurJSON.self) }
    }

    private func golden(_ etat: EtatPaiementSalaire) -> JSONValue {
        .object([
            "etat": .string(etat.etat.rawValue),
            "libelle": .string(etat.libelle),
            "montantDeclare": etat.montantDeclare.map(JSONValue.number) ?? .null,
            "montantReferenceEmployeur": etat.montantReferenceEmployeur.map(JSONValue.number) ?? .null,
        ])
    }

    func testVecteursGoldenEtatPaiement() throws {
        let rejoues = try Golden.rejouer("paiement-soignant-ui") { vecteur in
            let entree = vecteur.input
            switch vecteur.fonction {
            case "repartirPaiementConfirme":
                let repartition = EtatPaiement.repartirPaiementConfirme(montantDu: try valeur(entree["montantDu"]),
                                                                        montantRegle: try valeur(entree["montantRegle"]))
                return .object([
                    "montantPaye": .number(repartition.montantPaye),
                    "montantRestant": .number(repartition.montantRestant),
                    "estPartiel": .bool(repartition.estPartiel),
                ])
            case "indexerDernierPaiementParMission":
                let paiements = try XCTUnwrap(entree["paiements"]).decode([PaiementSoignantPourUi].self)
                let index = EtatPaiement.indexerDernierPaiementParMission(paiements)
                return .object(index.mapValues { .string($0.id) })
            case "classerPaiementSalaire":
                // `null` et clé absente : `!paiement` côté web.
                let paiement: PaiementSalairePourUi? = try entree["paiement"].flatMap { brut in
                    if brut.estNull { return nil }
                    return try brut.decode(PaiementSalairePourUi.self)
                }
                return golden(EtatPaiement.classerPaiementSalaire(paiement))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 600)
    }

    func testValeursNonRepresentablesEnJSON() {
        // Cas vitest `NaN` et `Infinity` (it.each l.67) : hors JSON, rejoués ici.
        let repartition = EtatPaiement.repartirPaiementConfirme(montantDu: .nombre(.infinity), montantRegle: .nombre(.nan))
        XCTAssertEqual(repartition, RepartitionPaiementConfirme(montantPaye: 0, montantRestant: 0, estPartiel: false))
        for montant in [Double.nan, .infinity, -.infinity] {
            let etat = EtatPaiement.classerPaiementSalaire(PaiementSalairePourUi(statut: "CONFIRME", montantNet: .nombre(montant),
                                                                                 confirmeParSoignant: true, conteste: false))
            XCTAssertEqual(etat.etat, .aVerifier)
            XCTAssertNil(etat.montantDeclare)
        }
    }

    func testLibellesVerbatimDuWeb() {
        // paiementSoignantUi.ts l.103-114.
        XCTAssertEqual(EtatPaiement.classerPaiementSalaire(nil).libelle, "Aucun versement déclaré")
        XCTAssertEqual(EtatPaiement.classerPaiementSalaire(PaiementSalairePourUi(statut: "CONTESTE")).libelle, "Paiement contesté")
        XCTAssertEqual(EtatPaiement.classerPaiementSalaire(PaiementSalairePourUi(statut: "RESOLU")).libelle, "Litige résolu · réception à vérifier")
        XCTAssertEqual(EtatPaiement.classerPaiementSalaire(PaiementSalairePourUi(statut: "CONFIRME", montantNet: .nombre(1),
                                                                                 confirmeParSoignant: true)).libelle, "Réception confirmée")
        XCTAssertEqual(EtatPaiement.classerPaiementSalaire(PaiementSalairePourUi(statut: "DECLARE")).libelle, "Réception à confirmer")
        XCTAssertEqual(EtatPaiement.classerPaiementSalaire(PaiementSalairePourUi(statut: "EN_ATTENTE")).libelle, "Réception à vérifier")
    }

    func testArrondiAuCentimeCommeToFixed() {
        // `toFixed(2)` arrondit la valeur décimale exacte ; les égalités parfaites montent en valeur absolue.
        XCTAssertEqual(PrimitivesJS.arrondiCentimes(0.125), 0.13)
        XCTAssertEqual(PrimitivesJS.arrondiCentimes(-0.125), -0.13)
        XCTAssertEqual(PrimitivesJS.arrondiCentimes(0.375), 0.38)
        XCTAssertEqual(PrimitivesJS.arrondiCentimes(1.005), 1.0, "1,005 vaut 1,00499… en binaire")
        XCTAssertEqual(PrimitivesJS.arrondiCentimes(346.85 - 300), 46.85)
        XCTAssertEqual(PrimitivesJS.arrondiCentimes(2e21), 2e21)
    }
}
