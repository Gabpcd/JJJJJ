import XCTest
@testable import JoleneCore

/// Décision d'affichage du code de pointage rotatif côté établissement (lot 5, T3) : port de
/// `src/components/pointage/AffichageCodeRotatifEtab.tsx` l.49-78 et l.166-328. Rejoue les
/// scénarios d'affichage de `AffichageCodeRotatifEtab.test.tsx` (l.98-393) ; le scénario
/// « heure rétroactive inexistante » (l.313) relève de la clôture de segment (T8). S'y ajoute la
/// garde native du blueprint §2.7 : sans la permission `pointage`, aucun code n'est rendu.
final class CodeRotatifRulesTests: XCTestCase {
    private typealias Regles = CodeRotatifRules

    private func instant(_ iso: String) throws -> Date { try DateHeureParis.instantJolene(iso) }

    private func prev(_ id: String, _ debut: String, _ fin: String) -> MissionSlot {
        MissionSlot(id: id, missionId: "mission-1", debut: debut, fin: fin, estPause: false, typeCreneau: "PREVISIONNEL")
    }

    /// Mission des tests vitest (l.80-86) : période longue, `nb_creneaux` variable.
    private func planning(_ creneaux: [MissionSlot], nb: Int = 1, contratSigne: Bool = true) -> Regles.Planning {
        Regles.Planning.depuis(
            mission: MissionAvecPlanningAttendu(id: "mission-1", debutLe: "2026-07-06T08:00:00+02:00",
                                                finLe: "2026-08-31T16:00:00+02:00", nbCreneaux: nb),
            creneaux: creneaux, contratSigne: contratSigne
        )
    }

    private func etat(statut: String = "EN_COURS", prochain: String = "OUVERTURE", segmentOuvert: Bool = false,
                      segments: [Regles.Segment] = [], code: String? = "123456") -> Regles.Etat {
        Regles.Etat(statut: statut, prochainTypeScan: prochain, segmentOuvert: segmentOuvert, segments: segments, codePointageActif: code)
    }

    private func affichage(_ etat: Regles.Etat?, _ planning: Regles.Planning, pointage: Bool = true, maintenant: String) throws -> Regles.Affichage {
        Regles.affichage(etat: etat, planning: planning, autoriseAuPointage: pointage, maintenant: try instant(maintenant))
    }

    private let journee = MissionSlot(id: "creneau-1", missionId: "mission-1", debut: "2026-07-31T08:00:00+02:00",
                                      fin: "2026-07-31T16:00:00+02:00", estPause: false, typeCreneau: "PREVISIONNEL")

    // MARK: - Scénarios de AffichageCodeRotatifEtab.test.tsx

    /// l.98 : trop tôt → code masqué, prochain créneau expliqué.
    func testTropTotMasqueLeCodeEtAnnonceLeProchainCreneau() throws {
        let aout = prev("creneau-1", "2026-08-31T08:00:00+02:00", "2026-08-31T16:00:00+02:00")
        let resultat = try affichage(etat(), planning([aout]), maintenant: "2026-07-31T10:00:00+02:00")
        XCTAssertEqual(resultat.bloc, .masque(titre: "Code masqué hors créneau",
                                              detail: "Le code sera affiché 15 minutes avant le créneau 1/1, le lundi 31 août 2026 à 08:00."))
        XCTAssertNil(resultat.creneauActif)
        XCTAssertNil(resultat.codeAffiche)
    }

    /// l.118 : pendant le créneau → code, QR et progression.
    func testPendantLeCreneauAfficheLeCodeEtLaProgression() throws {
        let resultat = try affichage(etat(), planning([journee]), maintenant: "2026-07-31T10:00:00+02:00")
        XCTAssertEqual(resultat.bloc, .code(Regles.CodeVisible(valeur: "123456", chiffres: "123 456",
                                                               prochainPointage: "Arrivée", segmentEnCours: false)))
        XCTAssertEqual(resultat.codeAffiche, "123456", "le QR encode la valeur brute du code")
        XCTAssertEqual(resultat.creneauActif?.libelle, "Créneau 1/1 · vendredi 31 juillet 2026 à 08:00 → 16:00")
        XCTAssertEqual(resultat.creneauActif?.rang, 1)
        XCTAssertEqual(resultat.creneauActif?.total, 1)
    }

    /// l.138 : un EFFECTIF ouvert est associé au shift qui contient son début.
    func testEffectifAssocieAuShiftQuiContientSonDebut() throws {
        let matin = prev("creneau-matin", "2026-07-31T08:00:00", "2026-07-31T12:00:00")
        let apresMidi = prev("creneau-apres-midi", "2026-07-31T14:00:00", "2026-07-31T18:00:00")
        let ouvert = etat(prochain: "FERMETURE", segmentOuvert: true,
                          segments: [Regles.Segment(id: "segment-apres-midi", debut: "2026-07-31T14:05:00", fin: nil)], code: "654321")
        let resultat = try affichage(ouvert, planning([matin, apresMidi], nb: 2), maintenant: "2026-07-31T15:00:00+02:00")
        XCTAssertEqual(resultat.bloc, .code(Regles.CodeVisible(valeur: "654321", chiffres: "654 321",
                                                               prochainPointage: "Départ ou pause", segmentEnCours: true)))
        XCTAssertEqual(resultat.creneauActif?.libelle, "Créneau 2/2 · vendredi 31 juillet 2026 à 14:00 → 18:00")
    }

    /// l.177 : nouvelle ouverture après un segment fermé du même créneau, le même jour.
    func testRepriseApresUnSegmentFermeLeMemeJour() throws {
        let longue = prev("creneau-journee", "2026-07-31T08:00:00+02:00", "2026-07-31T18:00:00+02:00")
        let ferme = etat(segments: [Regles.Segment(id: "segment-matin", debut: "2026-07-31T08:00:00+02:00", fin: "2026-07-31T12:00:00+02:00")])
        let resultat = try affichage(ferme, planning([longue]), maintenant: "2026-07-31T14:00:00+02:00")
        XCTAssertEqual(resultat.codeVisible?.prochainPointage, "Reprise (fin de pause)")
    }

    /// l.203 : second PREVISIONNEL distinct du même jour → arrivée.
    func testSecondPrevisionnelDuMemeJourEstUneArrivee() throws {
        let matin = prev("creneau-matin", "2026-07-31T08:00:00+02:00", "2026-07-31T12:00:00+02:00")
        let apresMidi = prev("creneau-apres-midi", "2026-07-31T14:00:00+02:00", "2026-07-31T18:00:00+02:00")
        let ferme = etat(segments: [Regles.Segment(id: "segment-matin", debut: "2026-07-31T08:00:00+02:00", fin: "2026-07-31T12:00:00+02:00")])
        let resultat = try affichage(ferme, planning([matin, apresMidi], nb: 2), maintenant: "2026-07-31T14:00:00+02:00")
        XCTAssertEqual(resultat.codeVisible?.prochainPointage, "Arrivée")
        XCTAssertEqual(resultat.creneauActif?.rang, 2)
    }

    /// l.241 : première ouverture du jour malgré un segment la veille → arrivée.
    func testPremiereOuvertureDuJourMalgreUnSegmentLaVeille() throws {
        let veille = etat(segments: [Regles.Segment(id: "segment-veille", debut: "2026-07-30T08:00:00+02:00", fin: "2026-07-30T16:00:00+02:00")])
        let resultat = try affichage(veille, planning([journee]), maintenant: "2026-07-31T10:00:00+02:00")
        XCTAssertEqual(resultat.codeVisible?.prochainPointage, "Arrivée")
    }

    /// l.267 : un segment ouvert garde le code de sortie visible, même sur un planning incomplet.
    func testSegmentOuvertGardeLeCodeDeSortie() throws {
        let hier = prev("creneau-1", "2026-07-30T08:00:00+02:00", "2026-07-30T16:00:00+02:00")
        let ouvert = etat(prochain: "FERMETURE", segmentOuvert: true,
                          segments: [Regles.Segment(id: "segment-1", debut: "2026-07-31T08:00:00+02:00", fin: nil)], code: "654321")
        let resultat = try affichage(ouvert, planning([hier], nb: 2), maintenant: "2026-07-31T10:00:00+02:00")
        XCTAssertEqual(resultat.bloc, .code(Regles.CodeVisible(valeur: "654321", chiffres: "654 321",
                                                               prochainPointage: "Départ ou pause", segmentEnCours: true)))
        XCTAssertNil(resultat.creneauActif, "planning incomplet : aucun créneau planifié exploitable")
    }

    /// l.295 : nombre de créneaux reçu incomplet → arrivée masquée.
    func testPlanningIncompletMasqueUneArrivee() throws {
        let resultat = try affichage(etat(), planning([journee], nb: 2), maintenant: "2026-07-31T10:00:00+02:00")
        XCTAssertEqual(resultat.bloc, .planningInutilisable(message:
            "Le planning détaillé est incomplet ou ne correspond pas au nombre de créneaux prévu. Confirmez-le avant de présenter un code d’arrivée."))
        XCTAssertNil(resultat.codeAffiche)
    }

    /// l.347 : contrat non signé → code d'arrivée masqué.
    func testContratNonSigneMasqueLeCodeDArrivee() throws {
        let resultat = try affichage(etat(), planning([journee], contratSigne: false), maintenant: "2026-07-31T10:00:00+02:00")
        XCTAssertEqual(resultat.bloc, .masque(titre: "Code masqué — contrat non signé",
                                              detail: "Le code d’arrivée sera disponible lorsque le contrat aura été signé par les deux parties."))
        XCTAssertEqual(resultat.creneauActif?.rang, 1, "le créneau courant reste annoncé")
    }

    /// l.365 : signature illisible (null, "true", objet) → planning inutilisable, aucun QR.
    func testSignatureIllisibleRendLePlanningIndisponible() throws {
        let resultat = try affichage(etat(), .indisponible, maintenant: "2026-07-31T10:00:00+02:00")
        XCTAssertEqual(resultat.bloc, .planningInutilisable(message:
            "Le planning détaillé est momentanément indisponible. Réessayez avant de présenter un code au soignant."))
        XCTAssertNil(resultat.codeAffiche)
    }

    /// l.374 : la lecture de signature échoue mais un segment est ouvert → la sortie reste possible.
    func testSignatureEnEchecAvecSegmentOuvertGardeLeCode() throws {
        let ouvert = etat(prochain: "FERMETURE", segmentOuvert: true,
                          segments: [Regles.Segment(id: "segment-1", debut: "2026-07-31T08:00:00+02:00", fin: nil)], code: "654321")
        let resultat = try affichage(ouvert, .indisponible, maintenant: "2026-07-31T10:00:00+02:00")
        XCTAssertEqual(resultat.codeAffiche, "654321")
    }

    /// l.386 : état serveur indisponible → erreur actionnable.
    func testEtatServeurIndisponible() throws {
        XCTAssertEqual(try affichage(nil, planning([journee]), maintenant: "2026-07-31T10:00:00+02:00").bloc,
                       .indisponible(message: "Impossible de charger l’état du pointage."))
        var refus = etat()
        refus.erreur = "Accès interdit"
        XCTAssertEqual(try affichage(refus, planning([journee]), maintenant: "2026-07-31T10:00:00+02:00").bloc,
                       .indisponible(message: "Accès interdit"), "le refus serveur est affiché verbatim")
        XCTAssertEqual(Regles.titreIndisponible, "Code de pointage indisponible")
    }

    // MARK: - Branches restantes

    func testSansPermissionPointageAucunCodeNEstRendu() throws {
        for lecture in [planning([journee]), Regles.Planning.indisponible] {
            for etatLu in [etat(), nil] as [Regles.Etat?] {
                let resultat = try affichage(etatLu, lecture, pointage: false, maintenant: "2026-07-31T10:00:00+02:00")
                XCTAssertEqual(resultat, Regles.Affichage(bloc: .reservePointage, creneauActif: nil))
                XCTAssertNil(resultat.codeAffiche)
            }
        }
        XCTAssertEqual(Regles.messageReservePointage, "Code réservé aux membres habilités au pointage")
    }

    func testMissionHorsAssigneeEtEnCoursNAfficheRien() throws {
        for statut in ["OUVERTE", "TERMINEE", "ANNULEE", ""] {
            XCTAssertEqual(try affichage(etat(statut: statut), planning([journee]), maintenant: "2026-07-31T10:00:00+02:00").bloc, .aucun)
        }
        XCTAssertEqual(try affichage(etat(statut: "ASSIGNEE"), planning([journee]), maintenant: "2026-07-31T10:00:00+02:00").codeAffiche,
                       "123456")
    }

    func testCodeAbsentPendantLeCreneau() throws {
        let resultat = try affichage(etat(code: nil), planning([journee]), maintenant: "2026-07-31T10:00:00+02:00")
        XCTAssertEqual(resultat.bloc, .momentanementIndisponible)
        XCTAssertEqual(Regles.messageMomentanementIndisponible, "Code momentanément indisponible. Actualisez dans quelques secondes.")
        XCTAssertEqual(try affichage(etat(code: ""), planning([journee]), maintenant: "2026-07-31T10:00:00+02:00").bloc,
                       .momentanementIndisponible, "chaîne vide = code absent (`Boolean(code)`)")
    }

    func testTousLesCreneauxTermines() throws {
        let resultat = try affichage(etat(), planning([journee]), maintenant: "2026-07-31T17:00:00+02:00")
        XCTAssertEqual(resultat.bloc, .masque(titre: "Code masqué hors créneau", detail: "Tous les créneaux planifiés sont terminés."))
    }

    func testAucunCreneauDetaille() throws {
        let resultat = try affichage(etat(), .charge(creneaux: [], complet: true, contratSigne: true), maintenant: "2026-07-31T10:00:00+02:00")
        XCTAssertEqual(resultat.bloc, .masque(titre: "Code masqué hors créneau",
            detail: "Aucun créneau détaillé n’est planifié pour cette mission. Le code sera disponible après confirmation du planning."))
    }

    func testFenetreDeQuinzeMinutesAvantLeCreneau() throws {
        XCTAssertEqual(try affichage(etat(), planning([journee]), maintenant: "2026-07-31T07:45:00+02:00").codeAffiche, "123456")
        XCTAssertNil(try affichage(etat(), planning([journee]), maintenant: "2026-07-31T07:44:59+02:00").codeAffiche)
    }

    func testPlanningDepuisLaCompletude() {
        XCTAssertEqual(planning([journee]), .charge(creneaux: [journee], complet: true, contratSigne: true))
        XCTAssertEqual(planning([journee], nb: 2, contratSigne: false), .charge(creneaux: [], complet: false, contratSigne: false))
    }

    // MARK: - trouverCreneauAssocie (l.49-70)

    func testTrouverCreneauAssocieFinExclusiveEtPlusProche() {
        let matin = prev("m", "2026-07-31T08:00:00+02:00", "2026-07-31T12:00:00+02:00")
        let midi = prev("a", "2026-07-31T12:00:00+02:00", "2026-07-31T18:00:00+02:00")
        let soir = prev("s", "2026-07-31T20:00:00+02:00", "2026-07-31T23:00:00+02:00")
        let planifies = [matin, midi, soir]
        XCTAssertEqual(Regles.trouverCreneauAssocie(planifies, debutEffectif: "2026-07-31T12:00:00+02:00"), midi,
                       "à l'heure exacte où le second shift démarre, il est choisi")
        XCTAssertEqual(Regles.trouverCreneauAssocie(planifies, debutEffectif: "2026-07-31T08:00:00+02:00"), matin)
        XCTAssertEqual(Regles.trouverCreneauAssocie(planifies, debutEffectif: "2026-07-31T19:00:00+02:00"), soir,
                       "hors de tout créneau : début le plus proche")
        XCTAssertEqual(Regles.trouverCreneauAssocie(planifies, debutEffectif: "2026-07-31T07:00:00+02:00"), matin)
        XCTAssertNil(Regles.trouverCreneauAssocie(planifies, debutEffectif: "pas une date"))
        XCTAssertNil(Regles.trouverCreneauAssocie([], debutEffectif: "2026-07-31T07:00:00+02:00"))
    }

    // MARK: - Formats d'affichage

    func testFormatCodeEnDeuxGroupes() {
        XCTAssertEqual(Regles.formatCode("123456"), "123 456")
        XCTAssertEqual(Regles.formatCode("100002"), "100 002")
        XCTAssertEqual(Regles.formatCode("12"), "12 ", "`slice(0, 3) + ' ' + slice(3)`")
    }

    func testLignesDesSegmentsEnregistres() throws {
        let segments = [
            Regles.Segment(id: "s1", debut: "2026-07-31T08:00:00+02:00", fin: "2026-07-31T12:00:00+02:00"),
            Regles.Segment(id: "s2", debut: "2026-07-31T13:00:00+02:00", fin: nil),
            Regles.Segment(id: "s3", debut: "2026-07-31T13:00:00+02:00", fin: "2026-07-31T13:45:20+02:00"),
        ]
        let lignes = Regles.lignesSegments(segments, maintenant: try instant("2026-07-31T14:30:00+02:00"))
        XCTAssertEqual(lignes, [
            Regles.LigneSegment(id: "s1", libelle: "Segment 1 · 31/07/2026 08h00 → 31/07/2026 12h00", duree: "4h00"),
            Regles.LigneSegment(id: "s2", libelle: "Segment 2 · 31/07/2026 13h00 → en cours", duree: "1h30"),
            Regles.LigneSegment(id: "s3", libelle: "Segment 3 · 31/07/2026 13h00 → 31/07/2026 13h45", duree: "45 min"),
        ])
        XCTAssertEqual(Regles.titreSegments, "Pointages enregistrés")
        XCTAssertEqual(Regles.dureeSegment(debut: "2026-07-31T13:00:00+02:00", fin: "2026-07-31T12:00:00+02:00",
                                           maintenant: try instant("2026-07-31T14:30:00+02:00")), "0 min")
    }

    // MARK: - Garde de dérive des messages repris du web

    func testMessagesVerbatimDuWeb() throws {
        try SourceWebLot5.verifier("src/components/pointage/AffichageCodeRotatifEtab.tsx", contient: [
            Regles.titreIndisponible,
            Regles.messageEtatIndisponible,
            Regles.titreMasque,
            Regles.messagePlanningIndisponible,
            Regles.messagePlanningIncomplet,
            Regles.libelleChangeAChaqueScan,
            Regles.consignePresentation,
            Regles.libelleReprise,
            Regles.libelleArrivee,
            Regles.libelleDepartOuPause,
            Regles.libelleSegmentEnCours,
            Regles.messageMomentanementIndisponible,
            Regles.titreMasqueContrat,
            Regles.titreMasqueHorsCreneau,
            Regles.detailContratNonSigne,
            Regles.detailAucunCreneau,
            Regles.detailTousTermines,
            Regles.titreSegments,
            "`Le code sera affiché ${FENETRE_OUVERTURE_POINTAGE_MINUTES} minutes avant le créneau ${indexProchainCreneau + 1}/${planifies.length}, le ${formatParis(disponibilite.prochainCreneau.debut, 'EEEE d MMMM yyyy à HH:mm')}.`",
            "'EEEE d MMMM yyyy à HH:mm'",
            "\"dd/MM/yyyy HH'h'mm\"",
            "' → en cours'",
        ])
    }
}
