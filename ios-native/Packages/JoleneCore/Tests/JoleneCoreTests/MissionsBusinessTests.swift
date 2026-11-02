import XCTest
@testable import JoleneCore

/// Port des cas de `mobile-native/src/data/gateway.node.test.ts` couvrant les règles pures.
final class MissionsBusinessTests: XCTestCase {
    typealias S = MissionsTestSupport

    func testHierarchieProfessionnelleDirectionnelleEtFiltreExpliciteExact() {
        let rows = ["IDE", "IADE", "IBODE", "MEDECIN"].map { S.mission(S.record(id: $0, professionRequise: $0)) }
        let iade = S.withProfile(S.context) { $0.profession = "IADE" }
        XCTAssertEqual(S.ids(MissionBusiness.filter(rows, context: S.context)), ["IDE"])
        XCTAssertEqual(S.ids(MissionBusiness.filter(rows, context: iade)), ["IDE", "IADE"])
        XCTAssertEqual(S.ids(MissionBusiness.filter(rows, context: iade, filters: MissionFilters(profession: "IADE"))), ["IADE"])
    }

    func testCompatibiliteLiberalePreserveOptionSalarieeEtTagLegacy() {
        let rows = [S.mission(S.record(id: "salary")),
                    S.mission(S.record(id: "liberal", typeContratRecherche: "LIBERAL")),
                    S.mission(S.record(id: "legacy", description: "[CONTRAT:LIBERAL] Description", typeContratRecherche: nil))]
        let salaryOnly = S.withProfile(S.context) { $0.typesContratAcceptes = "[\"CDD\"]"; $0.typeExercice = "SALARIE" }
        let liberalOnly = S.withProfile(S.context) { $0.typesContratAcceptes = "[\"LIBERAL\"]"; $0.typeExercice = "LIBERAL" }
        XCTAssertEqual(S.ids(MissionBusiness.filter(rows, context: salaryOnly)), ["salary"])
        XCTAssertEqual(MissionBusiness.filter(rows, context: liberalOnly).count, 3)
        XCTAssertEqual(S.ids(MissionBusiness.filter(rows, context: liberalOnly, filters: MissionFilters(typeContrat: .liberal))), ["liberal", "legacy"])
        XCTAssertEqual(S.ids(MissionBusiness.filter(rows, context: S.context, filters: MissionFilters(typeContrat: .cdd))), ["salary"])
    }

    func testFixturesMasqueesSaufComptePlaywrightEtCoordonneesInconnuesVisibles() {
        let ordinary = S.mission()
        let hidden = S.mission(S.record(id: "fixture", intitule: "[pw-test:xyz] fixture"))
        var distant = ordinary; distant.record.id = "distant"; distant.distanceKm = 100
        var unknown = ordinary; unknown.record.id = "unknown"; unknown.distanceKm = nil
        XCTAssertEqual(S.ids(MissionBusiness.filter([ordinary, hidden, distant, unknown], context: S.context, filters: MissionFilters(rayonKm: 20))),
                       ["mission-1", "unknown"])
        var playwright = S.context; playwright.email = "playwright-test@example.invalid"
        XCTAssertEqual(MissionBusiness.filter([hidden], context: playwright).count, 1)
        XCTAssertEqual(MissionBusiness.filter([ordinary], context: S.context, filters: MissionFilters(ville: "750")).count, 1)
        XCTAssertEqual(MissionBusiness.filter([ordinary], context: S.context, filters: MissionFilters(ville: "Lyon")).count, 0)
        XCTAssertEqual(MissionBusiness.filter([ordinary], context: S.context, filters: MissionFilters(ville: "  PAR ")).count, 1)
    }

    func testFiltresHorairesConsiderentCreneauxTardifsEtMinuitParis() {
        let later = S.slot(id: "slot-2", debut: "2026-10-30T23:30:00Z", fin: "2026-10-31T05:00:00Z")
        let multi = S.mission(S.record(finLe: later.fin!, nbCreneaux: 2), slots: [S.slot(), later])
        XCTAssertTrue(multi.planningExact)
        XCTAssertEqual(MissionBusiness.filter([multi], context: S.context, filters: MissionFilters(horaire: .weekend)).count, 1)
        XCTAssertEqual(MissionBusiness.filter([multi], context: S.context, filters: MissionFilters(horaire: .nuit)).count, 1)
        XCTAssertEqual(MissionBusiness.filter([multi], context: S.context, filters: MissionFilters(horaire: .jour)).count, 1)
        let incomplete = S.mission(S.record(finLe: later.fin!, nbCreneaux: 2), slots: [S.slot()])
        XCTAssertFalse(incomplete.planningExact)
        XCTAssertEqual(MissionBusiness.filter([incomplete], context: S.context, filters: MissionFilters(horaire: .jour)).count, 0)
        XCTAssertEqual(MissionBusiness.filter([incomplete], context: S.context, filters: MissionFilters(horaire: .tous)).count, 1)
        XCTAssertTrue(MissionPresentation.periode(multi).contains("2 créneaux"))
        XCTAssertTrue(MissionPresentation.periode(incomplete).contains("planning à confirmer"))
    }

    func testFiltresUrgenceTauxEtEtablissement() {
        let rows = [S.mission(S.record(id: "calme", tauxHoraireBase: 20)),
                    S.mission(S.record(id: "urgente", tauxHoraireBase: 30, estUrgente: true)),
                    S.mission(S.record(id: "ailleurs", tauxHoraireBase: 40, etablissementId: "etab-2"))]
        XCTAssertEqual(S.ids(MissionBusiness.filter(rows, context: S.context, filters: MissionFilters(urgentesOnly: true))), ["urgente"])
        XCTAssertEqual(S.ids(MissionBusiness.filter(rows, context: S.context, filters: MissionFilters(tauxMin: 30))), ["urgente", "ailleurs"])
        XCTAssertEqual(S.ids(MissionBusiness.filter(rows, context: S.context, filters: MissionFilters(etablissementId: "etab-2"))), ["ailleurs"])
        XCTAssertEqual(S.ids(MissionBusiness.filter(rows, context: S.context, filters: MissionFilters(etablissementId: ""))).count, 3)
        // Le taux minimum du profil s'applique quand le filtre ne le précise pas.
        let exigeant = S.withProfile(S.context) { $0.tauxHoraireMinimum = 35 }
        XCTAssertEqual(S.ids(MissionBusiness.filter(rows, context: exigeant)), ["ailleurs"])
    }

    func testTriParDistanceCroissanteStableAvecInconnuesEnFin() {
        var loin = S.mission(S.record(id: "loin")); loin.distanceKm = 12
        var pres = S.mission(S.record(id: "pres")); pres.distanceKm = 3
        var inconnue = S.mission(S.record(id: "inconnue")); inconnue.distanceKm = nil
        var egal = S.mission(S.record(id: "egal")); egal.distanceKm = 3
        XCTAssertEqual(S.ids(MissionBusiness.filter([loin, inconnue, pres, egal], context: S.context)), ["pres", "egal", "loin", "inconnue"])
    }

    func testValidateContextRefuseProfilDesynchronise() throws {
        XCTAssertNoThrow(try MissionBusiness.validateContext(S.context))
        var autre = S.context; autre.userId = "other-user"
        XCTAssertThrowsError(try MissionBusiness.validateContext(autre)) { error in
            XCTAssertEqual((error as? JoleneError)?.kind, .contract)
            XCTAssertEqual((error as? JoleneError)?.message, MissionBusiness.messageContexteInvalide)
        }
        let sansProfession = S.withProfile(S.context) { $0.profession = "" }
        XCTAssertThrowsError(try MissionBusiness.validateContext(sansProfession))
        var vide = S.context; vide.userId = ""; vide.profile.id = ""
        XCTAssertThrowsError(try MissionBusiness.validateContext(vide))
    }

    func testDefaultFiltersRepliRayonEtTaux() {
        let defauts = MissionBusiness.defaultFilters(profile: S.context.profile)
        XCTAssertEqual(defauts.rayonKm, 50)
        XCTAssertEqual(defauts.tauxMin, 0)
        XCTAssertEqual(defauts.ville, "")
        XCTAssertEqual(defauts.profession, "")
        XCTAssertEqual(defauts.urgentesOnly, false)
        XCTAssertEqual(defauts.typeContrat, .tous)
        XCTAssertEqual(defauts.horaire, .tous)
        let profilNu = S.withProfile(S.context) { $0.rayonDeplacementKm = nil; $0.tauxHoraireMinimum = nil }
        XCTAssertEqual(MissionBusiness.defaultFilters(profile: profilNu.profile).rayonKm, 50)
        let profilZero = S.withProfile(S.context) { $0.rayonDeplacementKm = 0; $0.tauxHoraireMinimum = 12 }
        XCTAssertEqual(MissionBusiness.defaultFilters(profile: profilZero.profile).rayonKm, 50)
        XCTAssertEqual(MissionBusiness.defaultFilters(profile: profilZero.profile).tauxMin, 12)
        let profilRayon = S.withProfile(S.context) { $0.rayonDeplacementKm = 15 }
        XCTAssertEqual(MissionBusiness.defaultFilters(profile: profilRayon.profile).rayonKm, 15)
    }

    func testTypesContratSoignantEtPreferenceContrat() {
        XCTAssertEqual(ContratCompatibilite.typesContratSoignant(nil), ["CDD", "VACATION", "LIBERAL", "SALARIE"])
        XCTAssertEqual(ContratCompatibilite.typesContratSoignant(S.context.profile), ["CDD", "LIBERAL"])
        let virgules = S.withProfile(S.context) { $0.typesContratAcceptes = " CDD, VACATION ,," }
        XCTAssertEqual(ContratCompatibilite.typesContratSoignant(virgules.profile), ["CDD", "VACATION"])
        // Quirk web conservé : un tableau JSON vide retombe sur la découpe par virgules et renvoie ["[]"].
        let tableauVide = S.withProfile(S.context) { $0.typesContratAcceptes = "[]"; $0.typeExercice = "LIBERAL" }
        XCTAssertEqual(ContratCompatibilite.typesContratSoignant(tableauVide.profile), ["[]"])
        let tableauInvalide = S.withProfile(S.context) { $0.typesContratAcceptes = "[CDD"; $0.typeExercice = "LIBERAL" }
        XCTAssertEqual(ContratCompatibilite.typesContratSoignant(tableauInvalide.profile), ["[CDD"])
        let mixte = S.withProfile(S.context) { $0.typesContratAcceptes = nil; $0.typeExercice = "MIXTE" }
        XCTAssertEqual(ContratCompatibilite.typesContratSoignant(mixte.profile), ["CDD", "LIBERAL"])
        let salarie = S.withProfile(S.context) { $0.typesContratAcceptes = nil; $0.typeExercice = "SALARIE"; $0.typeContrat = "CDD" }
        XCTAssertEqual(ContratCompatibilite.typesContratSoignant(salarie.profile), ["CDD"])
        let incomplet = S.withProfile(S.context) { $0.typesContratAcceptes = ""; $0.typeExercice = nil; $0.typeContrat = nil }
        XCTAssertEqual(ContratCompatibilite.typesContratSoignant(incomplet.profile), ["CDD", "VACATION", "LIBERAL", "SALARIE"])

        XCTAssertEqual(ContratCompatibilite.extraireContratPreference(nil), "TOUS")
        XCTAssertEqual(ContratCompatibilite.extraireContratPreference("Texte [CONTRAT:SALARIE] suite"), "SALARIE")
        XCTAssertEqual(ContratCompatibilite.extraireContratPreference("[CONTRAT:AUTRE] [CONTRAT:LIBERAL]"), "LIBERAL")
        XCTAssertEqual(ContratCompatibilite.extraireContratPreference("[CONTRAT:TOUS]"), "TOUS")
        XCTAssertTrue(ContratCompatibilite.missionCompatible(preference: "SALARIE", typesContratSoignant: ["LIBERAL"]))
        XCTAssertFalse(ContratCompatibilite.missionCompatible(preference: "LIBERAL", typesContratSoignant: ["CDD"]))
        XCTAssertTrue(ContratCompatibilite.missionCompatible(preference: "TOUS", typesContratSoignant: []))
        XCTAssertTrue(ContratCompatibilite.missionCompatible(preference: nil, typesContratSoignant: []))
    }

    func testHierarchieProfessions() {
        XCTAssertEqual(ProfessionHierarchy.professionsCompatibles(soignant: "IADE"), ["IADE", "IDE"])
        XCTAssertEqual(ProfessionHierarchy.professionsCompatibles(soignant: "IBODE"), ["IBODE", "IDE"])
        XCTAssertEqual(ProfessionHierarchy.professionsCompatibles(soignant: "IDE"), ["IDE"])
        XCTAssertEqual(ProfessionHierarchy.missionsCompatiblesFilter(soignant: "IADE"), "profession_requise.eq.IADE,profession_requise.eq.IDE")
        XCTAssertNil(ProfessionHierarchy.missionsCompatiblesFilter(soignant: "MEDECIN"))
        XCTAssertNil(ProfessionHierarchy.missionsCompatiblesFilter(soignant: nil))
        XCTAssertTrue(ProfessionHierarchy.exigeSpecialisationExacte(professionRequise: "IBODE"))
        XCTAssertFalse(ProfessionHierarchy.exigeSpecialisationExacte(professionRequise: "IDE"))
    }

    func testEnrichConserveCreneauxChargesEtMontantsServeur() {
        let mission = S.mission()
        XCTAssertEqual(mission.record.tauxHoraireBase, 26.75)
        XCTAssertEqual(mission.record.netAPayer, 167.11)
        XCTAssertEqual(mission.record.ristPlafondApplique, true)
        XCTAssertEqual(mission.distanceKm, 0)
        XCTAssertEqual(mission.creneauxPlanifies.map(\.id), ["slot-1"])
        XCTAssertTrue(mission.planningExact)
        XCTAssertFalse(mission.erreurPlanning)
        // Sans créneau chargé, la mission ponctuelle reçoit son repli contractuel.
        let sansCreneau = S.mission(slots: [])
        XCTAssertEqual(sansCreneau.creneauxPlanifies.count, 1)
        XCTAssertEqual(sansCreneau.creneauxPlanifies[0].id, "mission-ponctuelle-mission-1")
        XCTAssertTrue(sansCreneau.planningExact)
        // Sans établissement, la distance est inconnue.
        let orpheline = MissionBusiness.enrich(record: S.record(), context: S.context, etablissement: nil, slots: [S.slot()])
        XCTAssertNil(orpheline.distanceKm)
        XCTAssertNil(orpheline.etablissement)
    }
}


/// Jeu de données du test Node `gateway.node.test.ts`, porté tel quel.
enum MissionsTestSupport {
    static let etablissement = EtablissementSummary(id: "etab-1", nom: "Établissement de test", adresseVille: "Paris",
                                                    adresseCodePostal: "75011", adresseLat: 48.8566, adresseLng: 2.3522, type: "CLINIQUE")

    static let context = MissionReadContext(
        userId: "user-1", email: "soignant@example.invalid",
        profile: SoignantProfile(id: "user-1", profession: "IDE", adresseLat: 48.8566, adresseLng: 2.3522, rayonDeplacementKm: 50,
                                 tousDocumentsValides: false, typeContrat: "CDD", typesContratAcceptes: "[\"CDD\",\"LIBERAL\"]",
                                 typeExercice: "MIXTE", tauxHoraireMinimum: 0))

    static func record(id: String = "mission-1", intitule: String = "Mission de test unitaire", description: String? = nil,
                       professionRequise: String = "IDE", finLe: String = "2026-10-27T16:00:00Z", nbCreneaux: Int? = 1,
                       tauxHoraireBase: Double? = 26.75, estUrgente: Bool = false, etablissementId: String = "etab-1",
                       typeContratRecherche: String? = "SALARIE", modeRemuneration: String? = "HORAIRE",
                       retrocessionPct: Double? = nil) -> MissionRecord {
        MissionRecord(id: id, intitule: intitule, description: description, service: "Médecine", professionRequise: professionRequise,
                      specialiteMedicaleRequise: nil, accepteNonSpecialises: nil, debutLe: "2026-10-27T08:00:00Z", finLe: finLe,
                      dureeHeures: 8, nbCreneaux: nbCreneaux, tauxHoraireBase: tauxHoraireBase, tauxRistPlafonne: 26.75,
                      ristPlafondApplique: true, totalBrut: 214, netAPayer: 167.11, estUrgente: estUrgente, niveauUrgence: 0,
                      statut: "OUVERTE", etablissementId: etablissementId, typeContratRecherche: typeContratRecherche, boosteeLe: nil,
                      modeRemuneration: modeRemuneration, retrocessionPct: retrocessionPct)
    }

    static func slot(id: String = "slot-1", debut: String = "2026-10-27T08:00:00Z", fin: String? = "2026-10-27T16:00:00Z",
                     missionId: String? = "mission-1", estPause: Bool = false, typeCreneau: String = "PREVISIONNEL") -> MissionSlot {
        MissionSlot(id: id, missionId: missionId, debut: debut, fin: fin, estPause: estPause, typeCreneau: typeCreneau)
    }

    static func mission(_ record: MissionRecord = record(), slots: [MissionSlot] = [slot()],
                        context: MissionReadContext = context) -> Mission {
        MissionBusiness.enrich(record: record, context: context, etablissement: etablissement, slots: slots)
    }

    static func withProfile(_ context: MissionReadContext, _ change: (inout SoignantProfile) -> Void) -> MissionReadContext {
        var copie = context
        change(&copie.profile)
        return copie
    }

    static func ids(_ missions: [Mission]) -> [String] { missions.map(\.id) }
}
