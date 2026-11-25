import XCTest
@testable import JoleneCore

/// Charge de publication d'une mission (lot 5, T9 ; `LOT5_PLAN.md` §3 T9) : exactement les seize paramètres de
/// `fn_creer_mission_multi_jours_v4`, aucune clé de plus ; valeurs fixées par le périmètre natif (D8) ; description
/// purgée des balises ; urgence ; spécialisation exacte ; créneaux en UTC sans fraction, changements d'heure compris.
/// Puis les règles structurelles locales et la relecture de la mission créée. L'égalité des seize clés avec la signature
/// SQL versionnée est prouvée par `SupabaseEtabPublicationGatewayTests` (`ios-native/rpc-contracts.json`).
final class PublicationPayloadTests: XCTestCase {
    private func brouillon(intitule: String = "IDE de nuit", description: String? = nil, profession: String = "IDE",
                           service: String? = "Urgences", taux: Double = 30, urgente: Bool = false, niveau: Int = 1,
                           mode: ModeAttributionPublication = .premierArrive,
                           creneaux: [CreneauConfirme] = [CreneauConfirme(debut: "2026-11-25T06:00:00Z", fin: "2026-11-25T18:00:00Z")])
        -> PublicationMission {
        PublicationMission(intitule: intitule, description: description, professionRequise: profession, service: service,
                           tauxHoraireBase: taux, estUrgente: urgente, creneaux: creneaux, niveauUrgence: niveau,
                           modeAttribution: mode)
    }

    // MARK: - Charge

    func testSeizeClesExactesAucuneEnPlus() throws {
        let charge = PublicationPayload(brouillon())
        XCTAssertEqual(PublicationPayload.cles.count, 16)
        XCTAssertEqual(Set(PublicationPayload.cles).count, 16, "aucun doublon")
        XCTAssertEqual(Set(charge.valeurs.keys), Set(PublicationPayload.cles), "exactement les seize paramètres, aucun de plus")
        XCTAssertEqual(PublicationPayload.cles, [
            "p_intitule", "p_description", "p_profession_requise", "p_service", "p_taux_horaire_base", "p_est_urgente",
            "p_niveau_urgence", "p_mode_attribution", "p_specialite_medicale_requise", "p_accepte_non_specialises",
            "p_creneaux", "p_type_contrat_recherche", "p_mode_remuneration", "p_retrocession_pct",
            "p_nature_tva_prestation", "p_accepte_internes",
        ], "ordre de la signature SQL")
        // Le corps JSON encodé porte les mêmes clés, les valeurs nulles comprises (jamais omises).
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(charge.valeurs)) as? [String: Any]
        XCTAssertEqual(Set(try XCTUnwrap(json).keys), Set(PublicationPayload.cles))
    }

    func testValeursFixeesParLePerimetreNatif() {
        let v = PublicationPayload(brouillon(mode: .candidature)).valeurs
        XCTAssertEqual(v["p_intitule"], .chaine("IDE de nuit"))
        XCTAssertEqual(v["p_profession_requise"], .chaine("IDE"))
        XCTAssertEqual(v["p_service"], .chaine("Urgences"))
        XCTAssertEqual(v["p_taux_horaire_base"], .nombre(30))
        XCTAssertEqual(v["p_mode_attribution"], .chaine("CANDIDATURE"))
        XCTAssertEqual(v["p_type_contrat_recherche"], .chaine("SALARIE"), "seul type de contrat publié en natif (D8)")
        XCTAssertEqual(v["p_mode_remuneration"], .chaine("TAUX_HORAIRE"))
        XCTAssertEqual(v["p_retrocession_pct"], .null)
        XCTAssertEqual(v["p_nature_tva_prestation"], .null)
        XCTAssertEqual(v["p_specialite_medicale_requise"], .null)
        XCTAssertEqual(v["p_accepte_internes"], .booleen(false))
        XCTAssertEqual(v["p_description"], .null, "description absente : null, jamais une chaîne vide")
        XCTAssertEqual(PublicationPayload(brouillon(service: "  ")).valeurs["p_service"], .null)
        XCTAssertEqual(PublicationPayload(brouillon(service: nil)).valeurs["p_service"], .null)
        XCTAssertEqual(PublicationPayload(brouillon(mode: .premierArrive)).valeurs["p_mode_attribution"], .chaine("PREMIER_ARRIVE"))
        XCTAssertEqual(PublicationPayload.typeContratRecherche, CandidaturesEtabRules.contratAcceptableNativement,
                       "publication (D8) et acceptation (D25) natives : le même type de contrat")
    }

    /// Revue B8 sécurité de la vague D (m1) : retrait répété jusqu'à stabilité, sans tenir compte de la casse. Une saisie
    /// imbriquée ne laisse jamais une balise que le serveur (`[CONTRAT:…]`, `fn_creer_mission_multi_jours`) ou l'ILIKE de
    /// la série (`[SERIE_ID:…]`) interpréterait.
    func testDescriptionPurgeeJusquAStabiliteSansTenirCompteDeLaCasse() {
        XCTAssertEqual(PublicationPayload.description("A [SERIE_[SERIE_ID:]ID:x] B"), "A  B")
        XCTAssertEqual(PublicationPayload.description("[CON[CON[CONTRAT:]TRAT:]TRAT:LIBERAL] Renfort"), "Renfort",
                       "trois niveaux d'imbrication : aucune balise de contrat ne reste")
        XCTAssertEqual(PublicationPayload.description("[serie_id:x][Contrat:liberal] Renfort"), "Renfort")
        XCTAssertNil(PublicationPayload.description("[SERIE_[serie_ID:a]ID:b]"))
        for saisie in ["[SERIE_[SERIE_ID:]ID:x]", "[CON[CONTRAT:SALARIE]TRAT:LIBERAL]", "x[cOnTrAt:[CONTRAT:]LIBERAL]y"] {
            let texte = PublicationPayload.description(saisie) ?? ""
            XCTAssertNil(texte.range(of: #"\[(SERIE_ID|CONTRAT):"#, options: [.regularExpression, .caseInsensitive]), saisie)
        }
    }

    func testDescriptionPurgeeDesBalises() {
        XCTAssertEqual(PublicationPayload.description("Garde de nuit [SERIE_ID:x] aux urgences"), "Garde de nuit  aux urgences",
                       "comme le web : la balise est retirée, le reste n'est pas reformaté")
        XCTAssertEqual(PublicationPayload.description("  [SERIE_ID:abc-123][CONTRAT:LIBERAL] Renfort  "), "Renfort")
        XCTAssertEqual(PublicationPayload.description("[CONTRAT:TOUS]"), nil, "le serveur pose lui-même la balise de contrat")
        XCTAssertNil(PublicationPayload.description("   \n "))
        XCTAssertNil(PublicationPayload.description(nil))
        XCTAssertEqual(PublicationPayload.description("Crochets [conservés] hors balise"), "Crochets [conservés] hors balise")
        let v = PublicationPayload(brouillon(description: "Renfort [SERIE_ID:x]")).valeurs
        XCTAssertEqual(v["p_description"], .chaine("Renfort"))
        if case let .chaine(texte)? = v["p_description"] {
            XCTAssertFalse(texte.contains("SERIE_ID") || texte.contains("CONTRAT"))
        }
    }

    func testUrgenteEtNonUrgente() {
        let urgente = PublicationPayload(brouillon(urgente: true, niveau: 2)).valeurs
        XCTAssertEqual(urgente["p_est_urgente"], .booleen(true))
        XCTAssertEqual(urgente["p_niveau_urgence"], .nombre(2))
        let nonUrgente = PublicationPayload(brouillon(urgente: false, niveau: 3)).valeurs
        XCTAssertEqual(nonUrgente["p_est_urgente"], .booleen(false))
        XCTAssertEqual(nonUrgente["p_niveau_urgence"], .nombre(0), "niveau saisi ignoré hors urgence (web l.430)")
    }

    func testSpecialisationExacte() {
        for profession in ["IADE", "IBODE"] {
            XCTAssertEqual(PublicationPayload(brouillon(profession: profession)).valeurs["p_accepte_non_specialises"], .booleen(false), profession)
        }
        for profession in ["IDE", "AS", "SAGE_FEMME", "KINE"] {
            XCTAssertEqual(PublicationPayload(brouillon(profession: profession)).valeurs["p_accepte_non_specialises"], .booleen(true), profession)
        }
    }

    func testCreneauxISOZSansFractionEtChangementsDHeure() throws {
        var compteur = 0
        let id = { () -> String in compteur += 1; return "c\(compteur)" }
        // Passage à l'heure d'été (dimanche 28 mars 2027, 02:00 → 03:00) : 07:00 vaut 06:00Z la veille, 05:00Z le jour même.
        var jours = try PlanningDerive.rederiver(dateDebut: "2027-03-27", dateFin: "2027-03-28", precedents: [], nouvelIdClient: id)
        jours = PlanningDerive.toutesLesDates(jours, nouvelIdClient: id)
        let ete = try XCTUnwrap(PublicationPayload.creneaux(try PlanningDerive.materialiserPlanning(jours)))
        XCTAssertEqual(ete, [CreneauConfirme(debut: "2027-03-27T06:00:00Z", fin: "2027-03-27T18:00:00Z"),
                             CreneauConfirme(debut: "2027-03-28T05:00:00Z", fin: "2027-03-28T17:00:00Z")])
        // Passage à l'heure d'hiver (dimanche 25 octobre 2026) : garde de nuit du 24 au 25, neuf heures réelles.
        let nuit = PlanningDerive.Jour(date: "2026-10-24", actif: true, creneaux: [
            PlanningDerive.Creneau(clientId: "n", heureDebut: "22:00", heureFin: "06:00", finJourSuivant: true),
        ])
        let hiver = try XCTUnwrap(PublicationPayload.creneaux(try PlanningDerive.materialiserPlanning([nuit])))
        XCTAssertEqual(hiver, [CreneauConfirme(debut: "2026-10-24T20:00:00Z", fin: "2026-10-25T05:00:00Z")])
        for creneau in ete + hiver {
            for borne in [creneau.debut, creneau.fin] {
                XCTAssertTrue(borne.hasSuffix("Z") && !borne.contains(".") && borne.count == 20, borne)
            }
        }
        XCTAssertNil(PublicationPayload.creneaux([]), "aucun créneau : aucune charge")
        let illisible = PlanningDerive.CreneauMaterialise(clientId: "x", id: nil, date: "2026-11-25", dateFin: "2026-11-25",
                                                          debut: "2026-11-25T06:00:00.250Z", fin: "2026-11-25T18:00:00Z", dureeHeures: 12)
        XCTAssertNil(PublicationPayload.creneaux([illisible]), "fraction non nulle : jamais une charge approximative")
        // La charge porte les chaînes du brouillon telles quelles, dans l'ordre.
        let charge = PublicationPayload(brouillon(creneaux: ete)).valeurs["p_creneaux"]
        XCTAssertEqual(charge, .tableau(ete.map { .objet(["debut": .chaine($0.debut), "fin": .chaine($0.fin)]) }))
    }

    // MARK: - Règles structurelles

    func testProfessionsPubliablesSansCelleRenvoyeeAuWeb() {
        XCTAssertEqual(PublicationRules.professionRenvoyeeAuWeb, "MEDECIN")
        XCTAssertEqual(PublicationRules.professions.count, MissionPresentation.professions.count - 1)
        XCTAssertFalse(PublicationRules.professions.contains { $0.valeur == "MEDECIN" })
        XCTAssertEqual(PublicationRules.professions.first?.valeur, "IDE", "ordre du web conservé")
        XCTAssertTrue(PublicationRules.professionPubliable("AS"))
        XCTAssertFalse(PublicationRules.professionPubliable("MEDECIN"))
        XCTAssertFalse(PublicationRules.professionPubliable(""))
        XCTAssertFalse(PublicationRules.professionPubliable("INCONNUE"))
    }

    func testTauxSaisi() {
        XCTAssertEqual(PublicationRules.taux("30"), 30)
        XCTAssertEqual(PublicationRules.taux("25,5"), 25.5)
        XCTAssertEqual(PublicationRules.taux("25.50"), 25.5)
        XCTAssertEqual(PublicationRules.taux(" 18,75 "), 18.75)
        for refuse in ["", "0", "0,00", "-5", "abc", "25,555", "25,", ",5", "1.2.3", "25 €", "1e3", "12345678901"] {
            XCTAssertNil(PublicationRules.taux(refuse), refuse)
        }
    }

    /// Revue B8 des textes de la vague D (M4) : plancher du taux horaire du web (`min` du champ hors libéral,
    /// `FormulaireMission.tsx` l.921), repris par `LibellesWeb.Publication.tauxMinimumHorsLiberal` et épinglé à sa ligne ;
    /// aucun nombre recopié dans la logique. Parité provisoire : le serveur ne refuse qu'un taux ≤ 0 (`public.sql`).
    func testPlancherDuTauxHoraireReprisDuWebASaLigne() throws {
        let lignes = try CompteVerbatimTests.lignes("src/components/FormulaireMission.tsx")
        let ligne = lignes[921 - 1]
        XCTAssertTrue(ligne.contains("min={contratPreference === 'LIBERAL' ? '0.01' : '\(LibellesWeb.Publication.tauxMinimumHorsLiberal)'}"),
                      "plancher du web déplacé ou modifié : \(ligne)")
        XCTAssertEqual(PublicationPayload.typeContratRecherche, "SALARIE", "publication native salariée : plancher hors libéral")
        XCTAssertEqual(PublicationRules.tauxMinimum, Double(LibellesWeb.Publication.tauxMinimumHorsLiberal))
        let minimum = LibellesWeb.Publication.tauxMinimumHorsLiberal
        XCTAssertEqual(PublicationRules.champsInvalides(brouillon(taux: PublicationRules.tauxMinimum)), [], "le plancher lui-même est publiable")
        XCTAssertEqual(PublicationRules.champsInvalides(brouillon(taux: PublicationRules.tauxMinimum - 0.01)), [.taux])
        XCTAssertEqual(PublicationRules.champsInvalides(brouillon(taux: 5)), [.taux], "la gateway refuse avant tout envoi")
        var saisie = PublicationSaisie()
        saisie.intitule = "IDE"
        saisie.profession = "IDE"
        saisie.taux = "5"
        XCTAssertEqual(PublicationRules.champsInvalides(saisie), [.taux])
        XCTAssertTrue(PublicationRules.tauxSousLeMinimum(saisie.taux))
        XCTAssertFalse(PublicationRules.tauxSousLeMinimum(minimum))
        XCTAssertFalse(PublicationRules.tauxSousLeMinimum(""), "saisie vide : champ obligatoire, pas un taux sous le plancher")
        XCTAssertEqual(PublicationPresentation.tauxSousLeMinimum, "Le taux horaire doit être d'au moins 11,65 €/h.",
                       "nombre à la française, formaté depuis la constante (fr_FR)")
        XCTAssertEqual(PublicationPresentation.montantFrancais(1234.5), "1234,50")
    }

    func testChampsInvalides() {
        var saisie = PublicationSaisie()
        XCTAssertEqual(PublicationRules.champsInvalides(saisie), [.intitule, .profession, .taux])
        saisie.intitule = "  ab "
        XCTAssertTrue(PublicationRules.champsInvalides(saisie).contains(.intitule), "trois caractères hors espaces de bord")
        saisie.intitule = "IDE"
        saisie.profession = "MEDECIN"
        saisie.taux = "30"
        XCTAssertEqual(PublicationRules.champsInvalides(saisie), [.profession], "profession renvoyée au web jamais publiable")
        saisie.profession = "IDE"
        XCTAssertEqual(PublicationRules.champsInvalides(saisie), [])
        saisie.estUrgente = true
        saisie.niveauUrgence = 4
        XCTAssertEqual(PublicationRules.champsInvalides(saisie), [.niveauUrgence])
        saisie.estUrgente = false
        XCTAssertEqual(PublicationRules.champsInvalides(saisie), [], "niveau ignoré hors urgence")

        XCTAssertEqual(PublicationRules.champsInvalides(brouillon()), [])
        XCTAssertEqual(PublicationRules.champsInvalides(brouillon(profession: "MEDECIN")), [.profession])
        XCTAssertEqual(PublicationRules.champsInvalides(brouillon(taux: 0)), [.taux])
        XCTAssertEqual(PublicationRules.champsInvalides(brouillon(taux: .nan)), [.taux])
        XCTAssertEqual(PublicationRules.champsInvalides(brouillon(urgente: true, niveau: 0)), [.niveauUrgence])
        XCTAssertEqual(PublicationRules.intitule(String(repeating: "a", count: 130)).count, 120)
    }

    // MARK: - Relecture

    private func detail(statut: String? = "OUVERTE", contrat: String? = "SALARIE", nb: Int? = 2,
                        debutLe: String? = "2026-11-25T06:00:00+00:00", finLe: String? = "2026-11-26T18:00:00+00:00",
                        creneaux: [(String, String?)] = [("2026-11-26T06:00:00+00:00", "2026-11-26T18:00:00+00:00"),
                                                         ("2026-11-25T06:00:00+00:00", "2026-11-25T18:00:00+00:00")],
                        erreurPlanning: String? = nil) -> EtabMissionDetail {
        EtabMissionDetail(
            mission: EtabMissionResume(id: "m-1", intitule: "IDE de nuit", statut: statut, debutLe: debutLe, finLe: finLe,
                                       nbCreneaux: nb, typeContratRecherche: contrat, etablissementId: "e-1"),
            creneaux: creneaux.enumerated().map { rang, c in
                MissionSlot(id: "c-\(rang)", missionId: "m-1", debut: c.0, fin: c.1, estPause: false, typeCreneau: "PREVISIONNEL")
            },
            soignantAssigneId: nil, erreurPlanning: erreurPlanning)
    }

    private let envoi = [CreneauConfirme(debut: "2026-11-25T06:00:00Z", fin: "2026-11-25T18:00:00Z"),
                         CreneauConfirme(debut: "2026-11-26T06:00:00Z", fin: "2026-11-26T18:00:00Z")]

    func testRelectureConfirmeParInstantsQuelQueSoitLOrdre() {
        XCTAssertTrue(PublicationRelecture.confirme(detail(), envoi: envoi), "+00:00 relu, Z envoyé, ordre différent")
    }

    func testRelectureDivergenteJamaisConfirmee() {
        XCTAssertFalse(PublicationRelecture.confirme(detail(statut: "ANNULEE_PAR_ETABLISSEMENT"), envoi: envoi))
        XCTAssertFalse(PublicationRelecture.confirme(detail(statut: nil), envoi: envoi))
        XCTAssertFalse(PublicationRelecture.confirme(detail(contrat: "TOUS"), envoi: envoi), "type de contrat modifié côté serveur")
        XCTAssertFalse(PublicationRelecture.confirme(detail(contrat: nil), envoi: envoi))
        XCTAssertFalse(PublicationRelecture.confirme(detail(nb: 3), envoi: envoi))
        XCTAssertFalse(PublicationRelecture.confirme(detail(debutLe: "2026-11-25T07:00:00+00:00"), envoi: envoi))
        XCTAssertFalse(PublicationRelecture.confirme(detail(finLe: nil), envoi: envoi))
        XCTAssertFalse(PublicationRelecture.confirme(detail(erreurPlanning: "Planning indisponible"), envoi: envoi))
        XCTAssertFalse(PublicationRelecture.confirme(detail(creneaux: [("2026-11-25T06:00:00+00:00", "2026-11-25T18:00:00+00:00"),
                                                                       ("2026-11-26T06:00:00+00:00", "2026-11-26T17:00:00+00:00")]),
                                                     envoi: envoi), "une fin différente")
        XCTAssertFalse(PublicationRelecture.confirme(detail(creneaux: [("2026-11-25T06:00:00+00:00", "2026-11-25T18:00:00+00:00"),
                                                                       ("2026-11-26T06:00:00+00:00", nil)]), envoi: envoi))
        XCTAssertFalse(PublicationRelecture.confirme(detail(nb: 1, creneaux: [("2026-11-25T06:00:00+00:00", "2026-11-25T18:00:00+00:00")]),
                                                     envoi: envoi), "un créneau manquant")
        XCTAssertFalse(PublicationRelecture.confirme(detail(nb: 0, creneaux: []), envoi: []), "aucun envoi : jamais confirmé")
    }
}
