import XCTest
@testable import JoleneCore

/// Publication dans le monde démo (lot 5, T9) : charge de seize paramètres journalisée, mission insérée dans l'état de
/// la session puis relue (« publiée » seulement ensuite), visible « Ouverte » par les gateways démo des missions et des
/// candidatures, blocage de l'établissement (`-JOLENE_DEMO_BLOCAGE 1`), refus au texte du serveur, compte fictif
/// seulement. Aucun réseau.
final class DemoEtabPublicationGatewayTests: XCTestCase {
    private func contexte(_ permissions: Set<PermissionEtab> = [.lecture, .missions, .candidatures],
                          userId: String = DemoEtablissementWorld.userId) -> EtablissementReadContext {
        EtablissementReadContext(userId: userId, etablissementId: "demo-etab-1", roleEtab: .proprietaire,
                                 permissions: PermissionsEtab(accordees: permissions), epoch: 1)
    }

    private func brouillon(intitule: String = "  Renfort de nuit ", profession: String = "IDE", urgente: Bool = true,
                           creneaux: [CreneauConfirme] = [
                               CreneauConfirme(debut: "2026-11-03T06:00:00Z", fin: "2026-11-03T18:00:00Z"),
                               CreneauConfirme(debut: "2026-11-02T06:00:00Z", fin: "2026-11-02T18:00:00Z"),
                           ]) -> PublicationMission {
        PublicationMission(intitule: intitule, description: "Renfort [SERIE_ID:x]", professionRequise: profession,
                           service: "Urgences", tauxHoraireBase: 30, estUrgente: urgente, creneaux: creneaux, niveauUrgence: 2,
                           modeAttribution: .candidature)
    }

    func testPublieeApresRelectureEtVisibleDansLesMissions() async throws {
        let etat = DemoEtabEtatPublication()
        let publication = DemoEtabPublicationGateway(etat: etat)
        let missions = DemoEtabMissionsGateway(publications: etat)
        let avant = try await missions.missions(context: contexte(), statut: "OUVERTE", page: 0)
        XCTAssertEqual(avant.missions.count, 5)

        let issue = try await publication.publier(brouillon(), context: contexte())
        XCTAssertEqual(issue, .publiee(missionId: "demo-etab-publiee-1"))

        let journal = await etat.journal()
        XCTAssertEqual(journal.count, 1)
        XCTAssertEqual(Set(journal[0].valeurs.keys), Set(PublicationPayload.cles), "charge démo journalisée : seize paramètres")
        XCTAssertEqual(journal[0].valeurs["p_niveau_urgence"], .nombre(2))
        XCTAssertEqual(journal[0].valeurs["p_est_urgente"], .booleen(true))

        let apres = try await missions.missions(context: contexte(), statut: "OUVERTE", page: 0)
        XCTAssertEqual(apres.missions.count, 6, "la mission publiée apparaît parmi les ouvertes")
        XCTAssertEqual(apres.compteurs?.nombre(.ouvertes), 6)
        let creee = try XCTUnwrap(apres.missions.first { $0.id == "demo-etab-publiee-1" })
        XCTAssertEqual(creee.intitule, "Renfort de nuit", "comme le serveur : espaces de bord retirés")
        XCTAssertEqual(creee.statut, "OUVERTE")
        XCTAssertEqual(creee.typeContratRecherche, "SALARIE")
        XCTAssertEqual(creee.estUrgente, true)
        XCTAssertEqual(creee.niveauUrgence, 2)
        XCTAssertEqual(creee.modeAttribution, "CANDIDATURE")
        XCTAssertEqual(creee.nbCreneaux, 2)
        XCTAssertEqual(creee.debutLe, "2026-11-02T06:00:00Z")
        XCTAssertEqual(creee.finLe, "2026-11-03T18:00:00Z")
        XCTAssertEqual(creee.description, "Renfort", "balise de série jamais conservée")
        XCTAssertEqual(apres.creneaux["demo-etab-publiee-1"]?.count, 2)

        let detailLu = try await missions.mission(id: "demo-etab-publiee-1", context: contexte())
        let detail = try XCTUnwrap(detailLu)
        XCTAssertTrue(PublicationRelecture.confirme(detail, envoi: brouillon().creneaux))
        XCTAssertEqual(detail.candidaturesEnAttente, 0, "mission sur candidature, aucune candidature encore")

        // La lecture habilitée des candidatures voit la même mission, sans candidature.
        let candidatures = DemoEtabCandidaturesGateway(etat: DemoEtabEtatCandidatures(), publications: etat)
        let lecture = try await candidatures.lecture(missionId: "demo-etab-publiee-1", context: contexte())
        XCTAssertEqual(lecture.candidatures, [])
        XCTAssertEqual(lecture.creneaux.count, 2)

        // Seconde publication : identifiant suivant, journal dans l'ordre.
        let seconde = try await publication.publier(brouillon(urgente: false), context: contexte())
        XCTAssertEqual(seconde, .publiee(missionId: "demo-etab-publiee-2"))
        let journalFinal = await etat.journal()
        XCTAssertEqual(journalFinal.map { $0.valeurs["p_niveau_urgence"] }, [.nombre(2), .nombre(0)])
    }

    func testMondeDemoPartageUnSeulEtatEntrePublicationEtMissions() async throws {
        let gateways = DemoEtablissementWorld.gateways(identite: { DemoEtablissementWorld.userId })
        XCTAssertTrue(gateways.publication is DemoEtabPublicationGateway, "T9 câble la publication démo")
        let issue = try await gateways.publication.publier(brouillon(), context: contexte())
        guard case let .publiee(id) = issue else { return XCTFail("publication démo attendue, obtenu \(issue)") }
        let relue = try await gateways.missions.mission(id: id, context: contexte())
        XCTAssertEqual(relue?.mission.statut, "OUVERTE")
        let lecture = try await gateways.candidatures.lecture(missionId: id, context: contexte())
        XCTAssertEqual(lecture.missionId, id)
    }

    func testBlocageDeLEtablissement() async throws {
        let etat = DemoEtabEtatPublication()
        let gateway = DemoEtabPublicationGateway(etat: etat, blocage: true)
        let issue = try await gateway.publier(brouillon(), context: contexte())
        XCTAssertEqual(issue, .blocageEtablissement(
            code: "PUBLICATION_SUSPENDUE", message: "Publication suspendue en raison d obligations de paiement à régulariser."))
        let surcouche = await etat.surcouche()
        XCTAssertEqual(surcouche.missions, [], "aucune mission créée")
        let viaMonde = DemoEtablissementWorld.gateways(configuration: .init(blocage: true), identite: { DemoEtablissementWorld.userId })
        let bloquee = try await viaMonde.publication.publier(brouillon(), context: contexte())
        guard case .blocageEtablissement = bloquee else { return XCTFail("blocage attendu, obtenu \(bloquee)") }
    }

    func testRefusAuTexteDuServeur() async throws {
        let etat = DemoEtabEtatPublication()
        let gateway = DemoEtabPublicationGateway(etat: etat)
        // Début avant l'horloge démo (2 novembre 2026, 00:00 UTC).
        let passe = [CreneauConfirme(debut: "2026-11-01T06:00:00Z", fin: "2026-11-01T18:00:00Z")]
        let dansLePasse = try await gateway.publier(brouillon(creneaux: passe), context: contexte())
        XCTAssertEqual(dansLePasse, .refusee(code: nil, message: "La mission ne peut pas commencer dans le passé."))
        let sansCreneau = try await gateway.publier(brouillon(creneaux: []), context: contexte())
        XCTAssertEqual(sansCreneau, .refusee(code: nil, message: "Ajoutez au moins un créneau travaillé."))
        // Sans le droit d'écriture, le serveur avale le refus de droit et rend « indisponible ».
        let sansDroit = try await gateway.publier(brouillon(), context: contexte([.lecture, .pointage]))
        XCTAssertEqual(sansDroit, .refusee(code: "CREATION_MISSION_INDISPONIBLE",
                                           message: "La création de la mission est temporairement indisponible."))
        let surcouche = await etat.surcouche()
        XCTAssertEqual(surcouche.missions, [], "aucun refus ne crée de mission")
        let journal = await etat.journal()
        XCTAssertEqual(journal.count, 3, "les charges refusées sont journalisées aussi")
    }

    func testBrouillonHorsPerimetreEtCompteNonFictifRefusesAvantTout() async throws {
        let etat = DemoEtabEtatPublication()
        let gateway = DemoEtabPublicationGateway(etat: etat)
        for invalide in [brouillon(profession: "MEDECIN"), brouillon(intitule: "ab")] {
            do {
                _ = try await gateway.publier(invalide, context: contexte())
                XCTFail("brouillon hors périmètre refusé")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .contract)
            }
        }
        do {
            _ = try await gateway.publier(brouillon(), context: contexte(userId: "autre"))
            XCTFail("compte non fictif refusé")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
        let journal = await etat.journal()
        XCTAssertEqual(journal, [], "rien n'est journalisé pour un brouillon refusé avant tout traitement")
    }
}
