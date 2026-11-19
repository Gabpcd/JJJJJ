import XCTest
@testable import JoleneCore

/// « Mes recherches sauvegardées » et alerte rapide (L4-T4) sur le monde démo (`DemoFiltresGateway`, fixture
/// `demo-filtres.json`) et sur des ports témoins : chaque succès est confirmé par la liste relue (PRINCIPES §3), refus
/// serveur verbatim, relecture après une erreur de transport, alerte rapide sans doublon.
@MainActor
final class FiltresModelTests: XCTestCase {
    /// Port témoin : lecture réelle du monde démo, mutation remplacée.
    private struct PortTemoin: FiltresSauvegardesPort {
        var demo = DemoFiltresGateway()
        let mutation: @Sendable () throws -> IssueFiltre
        func lister(context: MissionReadContext) async throws -> [FiltreSauvegarde] { try await demo.lister(context: context) }
        func creer(nom: String, filtres: FiltresAlerte, alerte: Bool, frequence: FrequenceAlerte,
                   context: MissionReadContext) async throws -> IssueFiltre { try mutation() }
        func modifier(id: String, nom: String?, alerte: Bool, frequence: FrequenceAlerte?,
                      context: MissionReadContext) async throws -> IssueFiltre { try mutation() }
        func supprimer(id: String, context: MissionReadContext) async throws -> IssueFiltre { try mutation() }
    }

    private func session(_ port: any FiltresSauvegardesPort) async throws -> (SessionController, SessionSnapshot) {
        var gateways = DemoWorld.gateways()
        gateways.filtres = port
        let controller = SessionController(gateways: gateways)
        let state = await controller.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        return (controller, try XCTUnwrap(state.snapshot, "session démo prête attendue, obtenu \(state)"))
    }

    private func modele(_ port: any FiltresSauvegardesPort = DemoFiltresGateway()) async throws -> FiltresModel {
        let (controller, snapshot) = try await session(port)
        let model = FiltresModel(controller: controller, snapshot: snapshot)
        await model.charger()
        return model
    }

    // MARK: - Écran

    func testChargerPuisBasculerModifierSupprimerConfirmesParRelecture() async throws {
        let model = try await modele()
        XCTAssertEqual(model.liste.recherches.map(\.id), ["demo-recherche-001", "demo-recherche-002"], "fixture, ordre serveur")
        let weekEnds = try XCTUnwrap(model.liste.recherches.last)
        XCTAssertFalse(weekEnds.alerteActive)

        await model.basculerAlerte(weekEnds)
        XCTAssertEqual(model.confirmation, FiltresTextes.alerteActivee)
        XCTAssertNil(model.erreur)
        XCTAssertEqual(model.liste.recherches.first?.id, "demo-recherche-002", "mis_a_jour_le décroissant : la ligne remonte")
        XCTAssertEqual(model.liste.recherches.first?.alerteActive, true)
        XCTAssertEqual(model.liste.recherches.first?.frequence, .quotidienne, "fréquence inchangée par la cloche")

        let ligne = try XCTUnwrap(model.liste.recherches.first)
        let vide = await model.enregistrer(ligne, nom: "   ", alerte: true, frequence: .hebdomadaire)
        XCTAssertFalse(vide)
        XCTAssertEqual(model.erreur, FiltresTextes.nomRequis, "nom vide : aucun appel")
        let doublon = await model.enregistrer(ligne, nom: "Nuits autour de Paris", alerte: true, frequence: .hebdomadaire)
        XCTAssertFalse(doublon)
        XCTAssertEqual(model.erreur, DemoFiltresGateway.nomEnDouble, "refus serveur verbatim")
        let renommee = await model.enregistrer(ligne, nom: "  Week-ends  ", alerte: false, frequence: .hebdomadaire)
        XCTAssertTrue(renommee)
        XCTAssertEqual(model.confirmation, FiltresTextes.miseAJour)
        XCTAssertEqual(model.liste.recherches.first, FiltreSauvegarde(id: "demo-recherche-002", nom: "Week-ends",
                                                                       filtres: ligne.filtres, alerteActive: false,
                                                                       frequence: .hebdomadaire, dernierCheckLe: ligne.dernierCheckLe))

        for recherche in model.liste.recherches {
            let supprimee = await model.supprimer(recherche)
            XCTAssertTrue(supprimee)
        }
        XCTAssertEqual(model.liste, .prete([]))
        XCTAssertEqual(model.confirmation, FiltresTextes.supprimee)
        let absente = await model.supprimer(ligne)
        XCTAssertFalse(absente)
        XCTAssertEqual(model.erreur, DemoFiltresGateway.introuvable)
    }

    func testRelectureQuiNeConfirmePasJamaisUnSucces() async throws {
        let model = try await modele(PortTemoin { .relue([]) })
        let ligne = try XCTUnwrap(model.liste.recherches.first)
        await model.basculerAlerte(ligne)
        XCTAssertEqual(model.erreur, FiltresTextes.nonConfirmee)
        XCTAssertNil(model.confirmation)
        XCTAssertEqual(model.liste, .prete([]), "la liste affichée est celle relue")
    }

    func testErreurDeTransportPuisRelectureEtSessionExpiree() async throws {
        let reseau = try await modele(PortTemoin { throw JoleneError(.network, "Connexion impossible.") })
        let ligne = try XCTUnwrap(reseau.liste.recherches.first)
        let coupee = await reseau.supprimer(ligne)
        XCTAssertFalse(coupee)
        XCTAssertEqual(reseau.erreur, "Connexion impossible.")
        XCTAssertEqual(reseau.liste.recherches.count, 2, "relecture après l'échec : le serveur a pu agir")
        XCTAssertFalse(reseau.sessionExpiree)

        let session = try await modele(PortTemoin { throw JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous.") })
        let expiree = try await session.supprimer(XCTUnwrap(session.liste.recherches.first))
        XCTAssertFalse(expiree)
        XCTAssertTrue(session.sessionExpiree)
        XCTAssertEqual(session.erreur, "Votre session a expiré. Reconnectez-vous.")

        let annulation = try await modele(PortTemoin { throw CancellationError() })
        let annulee = try await annulation.supprimer(XCTUnwrap(annulation.liste.recherches.first))
        XCTAssertFalse(annulee)
        XCTAssertNil(annulation.erreur, "une annulation n'est jamais une erreur")
    }

    // MARK: - Alerte rapide

    func testAlerteRapideCreePuisReutiliseSansDoublon() async throws {
        let port = DemoFiltresGateway()
        let (controller, snapshot) = try await session(port)
        let alerte = AlerteRapideModel(controller: controller, snapshot: snapshot)
        let filtres = ExplorerFiltres.initiaux(profile: snapshot.context.profile)

        let premiereAlerte = await alerte.activer(filtres: filtres, profile: snapshot.context.profile)
        XCTAssertTrue(premiereAlerte)
        XCTAssertEqual(alerte.issue, .confirmee(FiltresTextes.alerteCreee))
        var liste = try await port.lister(context: snapshot.context)
        XCTAssertEqual(liste.count, 3)
        let creee = try XCTUnwrap(liste.first)
        XCTAssertEqual(creee.nom, "Alerte missions \(MissionPresentation.professionLabel("IDE"))")
        XCTAssertTrue(creee.alerteActive)
        XCTAssertEqual(creee.frequence, .immediate)
        XCTAssertEqual(AlerteRecherche.cle(creee.filtres),
                       AlerteRecherche.cle(FiltresSauvegardesEncodage.valeur(FiltresSauvegardesEncodage.criteres(filtres))))

        let reutilisee = await alerte.activer(filtres: filtres, profile: snapshot.context.profile)
        XCTAssertTrue(reutilisee)
        XCTAssertEqual(alerte.issue, .confirmee("Une alerte existe déjà pour cette recherche (toutes les heures)."))
        liste = try await port.lister(context: snapshot.context)
        XCTAssertEqual(liste.count, 3, "même recherche : réutilisée, jamais doublée")
    }

    /// Recherche identique sans alerte (« Week-ends en CDD » de la fixture, quotidienne) : activée à sa fréquence
    /// enregistrée, sans création (revue B8 de #1167, M1).
    func testAlerteRapideReactiveLaRechercheIdentique() async throws {
        let port = DemoFiltresGateway()
        let (controller, snapshot) = try await session(port)
        let alerte = AlerteRapideModel(controller: controller, snapshot: snapshot)
        var filtres = ExplorerFiltres.initiaux(profile: snapshot.context.profile)
        filtres.rayonKm = 50; filtres.tauxMin = 30; filtres.typeContrat = .cdd; filtres.horaire = .weekend
        filtres.ville = ""; filtres.profession = ""; filtres.urgentesOnly = false

        let reactivee = await alerte.activer(filtres: filtres, profile: snapshot.context.profile)
        XCTAssertTrue(reactivee)
        XCTAssertEqual(alerte.issue, .confirmee("Alerte activée pour cette recherche (chaque jour)."))
        let liste = try await port.lister(context: snapshot.context)
        XCTAssertEqual(liste.count, 2)
        XCTAssertEqual(liste.first?.id, "demo-recherche-002")
        XCTAssertEqual(liste.first?.alerteActive, true)
        XCTAssertEqual(liste.first?.frequence, .quotidienne, "fréquence choisie par le soignant conservée")
    }

    /// Recherche identique dont l'alerte est déjà active en quotidienne ou hebdomadaire : aucune écriture, fréquence relue
    /// inchangée, message exact (revue B8 de #1167, M1).
    func testAlerteRapideNeReecritJamaisUneAlerteActive() async throws {
        let profil = DemoWorld.context.profile
        let filtres = ExplorerFiltres.initiaux(profile: profil)
        let valeur = FiltresSauvegardesEncodage.valeur(FiltresSauvegardesEncodage.criteres(filtres))
        for (frequence, attendu) in [(FrequenceAlerte.quotidienne, "Une alerte existe déjà pour cette recherche (chaque jour)."),
                                     (.hebdomadaire, "Une alerte existe déjà pour cette recherche (chaque semaine).")] {
            let demo = DemoFiltresGateway(initiales: [
                FiltreSauvegarde(id: "identique", nom: "Ma recherche", filtres: valeur, alerteActive: true, frequence: frequence),
            ])
            let port = PortTemoin(demo: demo) { XCTFail("aucune écriture pour une alerte déjà active"); return .relue([]) }
            let (controller, snapshot) = try await session(port)
            let alerte = AlerteRapideModel(controller: controller, snapshot: snapshot)
            let confirmee = await alerte.activer(filtres: filtres, profile: profil)
            XCTAssertTrue(confirmee)
            XCTAssertEqual(alerte.issue, .confirmee(attendu))
            let relue = try await demo.lister(context: snapshot.context)
            XCTAssertEqual(relue.map(\.frequence), [frequence], "fréquence relue inchangée")
        }
    }

    /// Cloche : `p_alerte_active` seul ; un renommage fait ailleurs entre-temps n'est jamais écrasé (revue B8 de #1167, m2).
    func testClocheNeRenvoiePasLeNomNiLaFrequenceLus() async throws {
        let port = DemoFiltresGateway()
        let model = try await modele(port)
        let affichee = try XCTUnwrap(model.liste.recherches.last)
        _ = try await port.modifier(id: affichee.id, nom: "Renommée ailleurs", alerte: false, frequence: .hebdomadaire,
                                    context: DemoWorld.context)
        await model.basculerAlerte(affichee)
        let relue = try XCTUnwrap(model.liste.recherches.first { $0.id == affichee.id })
        XCTAssertEqual(relue.nom, "Renommée ailleurs")
        XCTAssertEqual(relue.frequence, .hebdomadaire)
        XCTAssertTrue(relue.alerteActive)
        XCTAssertEqual(model.confirmation, FiltresTextes.alerteActivee)
    }

    func testAlerteRapideRefusVerbatimEtLectureImpossible() async throws {
        let pleine = DemoFiltresGateway(initiales: (1...20).map {
            FiltreSauvegarde(id: "r\($0)", nom: "Recherche \($0)", filtres: .objet([:]), alerteActive: false, frequence: .quotidienne)
        })
        let (controller, snapshot) = try await session(pleine)
        let alerte = AlerteRapideModel(controller: controller, snapshot: snapshot)
        let profil = snapshot.context.profile
        let limite = await alerte.activer(filtres: ExplorerFiltres.initiaux(profile: profil), profile: profil)
        XCTAssertFalse(limite)
        XCTAssertEqual(alerte.issue, .echec(DemoFiltresGateway.limiteAtteinte))

        struct Illisible: FiltresSauvegardesPort {
            func lister(context: MissionReadContext) async throws -> [FiltreSauvegarde] { throw JoleneError(.network, "Connexion impossible.") }
            func creer(nom: String, filtres: FiltresAlerte, alerte: Bool, frequence: FrequenceAlerte,
                       context: MissionReadContext) async throws -> IssueFiltre { XCTFail("aucune écriture sans lecture"); return .relue([]) }
            func modifier(id: String, nom: String?, alerte: Bool, frequence: FrequenceAlerte?,
                          context: MissionReadContext) async throws -> IssueFiltre { XCTFail("aucune écriture sans lecture"); return .relue([]) }
            func supprimer(id: String, context: MissionReadContext) async throws -> IssueFiltre { .relue([]) }
        }
        let (c2, s2) = try await session(Illisible())
        let echec = AlerteRapideModel(controller: c2, snapshot: s2)
        let sansLecture = await echec.activer(filtres: ExplorerFiltres.initiaux(profile: profil), profile: profil)
        XCTAssertFalse(sansLecture)
        XCTAssertEqual(echec.issue, .echec(FiltresTextes.alerteVerificationImpossible))
    }

    // MARK: - Boîte « Aller à la recherche »

    func testBoiteRemetLaRechercheASonSeulAuteur() {
        let boite = BoiteRechercheExplorer()
        let recherche = FiltreSauvegarde(id: "vide", nom: "Nuits", filtres: .objet(["horaire": .chaine("NUIT")]), alerteActive: true,
                                         frequence: .immediate)
        boite.deposer(recherche, userId: "u-1")
        let premiere = boite.demande?.id
        boite.deposer(recherche, userId: "u-1")
        XCTAssertNotEqual(boite.demande?.id, premiere, "deux dépôts successifs sont distincts")
        XCTAssertNil(boite.retirer(userId: "u-2"), "jamais remise à une autre identité")
        XCTAssertNil(boite.demande, "et effacée")
        boite.deposer(recherche, userId: "u-1")
        let demande = boite.retirer(userId: "u-1")
        XCTAssertEqual(demande?.nomSource, "Nuits")
        XCTAssertEqual(demande?.filtres, recherche.filtres)
        XCTAssertNil(boite.retirer(userId: "u-1"), "remise une seule fois")
    }

    // MARK: - Monde démo

    func testMondeDemoCableEtRefusDesRPC() async throws {
        XCTAssertTrue(DemoWorld.gateways().filtres is DemoFiltresGateway, "T4 câble les recherches sauvegardées")
        let port = DemoFiltresGateway()
        let context = DemoWorld.context
        let fixture = try await port.lister(context: context)
        XCTAssertEqual(fixture.map(\.nom), ["Nuits autour de Paris", "Week-ends en CDD"])
        XCTAssertEqual(fixture.first?.nbResultatsDernierCheck, 3)
        let criteres = FiltresAlerte(profession: "", rayonKm: 10, tauxMin: 0, typeContrat: "TOUS", urgentesOnly: false, horaire: "TOUS",
                                     villeRecherche: "")
        let longNom = String(repeating: "é", count: 101)
        guard case .refusee(let nomInvalide) = try await port.creer(nom: longNom, filtres: criteres, alerte: false, frequence: .quotidienne,
                                                                   context: context) else { return XCTFail("refus attendu") }
        XCTAssertEqual(nomInvalide, DemoFiltresGateway.nomInvalide)
        var mauvais = criteres
        mauvais.typeContrat = "INTERIM"
        guard case .refusee(let invalides) = try await port.creer(nom: "x", filtres: mauvais, alerte: false, frequence: .quotidienne,
                                                                 context: context) else { return XCTFail("refus attendu") }
        XCTAssertEqual(invalides, DemoFiltresGateway.criteresInvalides)
        guard case .refusee(let introuvable) = try await port.modifier(id: "inconnu", nom: "x", alerte: true, frequence: .immediate,
                                                                      context: context) else { return XCTFail("refus attendu") }
        XCTAssertEqual(introuvable, DemoFiltresGateway.introuvable)
        let autre = MissionReadContext(userId: "autre", email: nil, profile: SoignantProfile(id: "autre", profession: "IDE"))
        do {
            _ = try await port.lister(context: autre)
            XCTFail("contexte hors démo refusé")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
    }
}
