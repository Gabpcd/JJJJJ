import XCTest
@testable import JoleneCore

/// Copies officielles des bulletins (L4-T10) sur le monde démo (`DemoBulletinsGateway`, fixtures `demo-copies-bulletins.json`
/// et `demo-copie.pdf`) et sur des ports témoins : PDF présenté seulement après contrôle de type, taille et SHA-256 ;
/// copie retirée jamais demandée ; 410 `COPIE_RETIREE` → liste relue ; signalement confirmé par relecture (`DESTINATAIRE`
/// → `RETIREE`) ; textes du web.
@MainActor
final class BulletinsModelTests: XCTestCase {
    private enum Ids {
        static let valide = "c0b1e000-0000-4000-8000-000000000001"
        static let remplacee = "c0b1e000-0000-4000-8000-000000000002"
        static let falsifiee = "c0b1e000-0000-4000-8000-000000000003"
        static let retiree = "c0b1e000-0000-4000-8000-000000000004"
    }

    /// Port témoin : liste et signalement du monde démo, téléchargement remplacé ; compte les téléchargements.
    private final class PortTemoin: BulletinsPort, @unchecked Sendable {
        let demo = DemoBulletinsGateway()
        var telechargement: @Sendable () throws -> PDFVerifie = { throw RefusCopieBulletin.indisponible }
        var signalement: (@Sendable ([CopieBulletin]) -> [CopieBulletin])?
        private(set) var appels = 0
        func copies(context: MissionReadContext) async throws -> [CopieBulletin] { try await demo.copies(context: context) }
        func telecharger(copie: CopieBulletin, context: MissionReadContext) async throws -> PDFVerifie {
            appels += 1
            return try telechargement()
        }
        func signaler(copieId: String, motif: MotifSignalementCopie, context: MissionReadContext) async throws -> [CopieBulletin] {
            if let signalement { return signalement(try await demo.copies(context: context)) }
            return try await demo.signaler(copieId: copieId, motif: motif, context: context)
        }
    }

    private func modele(_ port: any BulletinsPort = DemoBulletinsGateway(), copieCible: String? = nil) async throws -> BulletinsModel {
        var gateways = DemoWorld.gateways()
        gateways.bulletins = port
        let controller = SessionController(gateways: gateways)
        let state = await controller.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        let snapshot = try XCTUnwrap(state.snapshot, "session démo prête attendue, obtenu \(state)")
        let model = BulletinsModel(controller: controller, snapshot: snapshot, copieCible: copieCible)
        await model.charger()
        return model
    }

    private func copie(_ model: BulletinsModel, _ id: String) throws -> CopieBulletin {
        try XCTUnwrap(model.liste.copies.first { $0.id == id }, "copie \(id) attendue")
    }

    // MARK: - Liste

    func testListeDemoOrdreDuWebEtFiltreEmployeur() async throws {
        let model = try await modele()
        XCTAssertEqual(model.copiesAffichees.map(\.id), [Ids.valide, Ids.remplacee, Ids.falsifiee, Ids.retiree],
                       "periode_debut décroissant, puis version décroissante")
        XCTAssertEqual(model.employeurs.map(\.nom), ["Établissement fictif des Lilas", "Cabinet fictif du Parc"])
        model.employeur = model.employeurs.last?.id
        XCTAssertEqual(model.copiesAffichees.map(\.id), [Ids.falsifiee, Ids.retiree])
        XCTAssertFalse(model.copieCibleIndisponible)
    }

    func testCopieCibleAbsenteSignalee() async throws {
        let model = try await modele(copieCible: "c0b1e000-0000-4000-8000-0000000000ff")
        XCTAssertTrue(model.copieCibleIndisponible)
        XCTAssertEqual(LibellesWeb.CopiesBulletins.copieDemandeeIndisponible,
                       "La copie demandée n’est pas disponible pour ce compte. Les documents accessibles sont affichés ci-dessous.")
    }

    // MARK: - Ouverture

    func testOuvertureDeLaBonneCopieApresVerification() async throws {
        let model = try await modele()
        await model.ouvrir(try copie(model, Ids.valide))
        let ouvert = try XCTUnwrap(model.pdfOuvert, "PDF vérifié présenté")
        XCTAssertEqual(ouvert.copie.id, Ids.valide)
        XCTAssertEqual(ouvert.pdf.sha256, try copie(model, Ids.valide).sha256)
        XCTAssertEqual(ouvert.pdf.donnees.count, try copie(model, Ids.valide).tailleOctets)
        XCTAssertTrue(ouvert.pdf.donnees.starts(with: Data("%PDF-".utf8)))
        XCTAssertNil(model.erreur)
        model.fermerPDF()
        XCTAssertNil(model.pdfOuvert)
    }

    func testCopieFalsifieeJamaisPresentee() async throws {
        let model = try await modele()
        await model.ouvrir(try copie(model, Ids.falsifiee))
        XCTAssertNil(model.pdfOuvert, "empreinte fausse : rien n'est affiché")
        XCTAssertTrue(model.erreurIntegrite)
        XCTAssertEqual(model.erreur, "L’intégrité du PDF ne peut pas être confirmée. Réessayez.")
    }

    func testCopieRetireeJamaisDemandee() async throws {
        let port = PortTemoin()
        let model = try await modele(port)
        await model.ouvrir(try copie(model, Ids.retiree))
        XCTAssertEqual(port.appels, 0, "copie RETIREE : aucun téléchargement")
        XCTAssertEqual(model.erreur, "Cette copie a été retirée. Son PDF n’est plus accessible.")
        XCTAssertNil(model.pdfOuvert)
    }

    func test410CopieRetireeRelitLaListe() async throws {
        let port = PortTemoin()
        port.telechargement = { throw RefusCopieBulletin.retiree }
        let model = try await modele(port)
        let cible = try copie(model, Ids.remplacee)
        // Le serveur a retiré la copie entre-temps : la relecture la montre retirée.
        _ = try await port.demo.signaler(copieId: cible.id, motif: .destinataire, context: DemoWorld.context)
        await model.ouvrir(cible)
        XCTAssertEqual(port.appels, 1)
        XCTAssertEqual(model.erreur, "Cette copie a été retirée. Son PDF n’est plus accessible.")
        XCTAssertFalse(model.erreurIntegrite)
        XCTAssertEqual(try copie(model, Ids.remplacee).statut, .retiree, "liste relue")
        XCTAssertFalse(model.telechargeable(try copie(model, Ids.remplacee)))
    }

    func testRefusDeLEdgeTexteDuWeb() async throws {
        let port = PortTemoin()
        let model = try await modele(port)
        await model.ouvrir(try copie(model, Ids.valide))
        XCTAssertEqual(model.erreur,
                       "Le PDF ne peut pas être ouvert. Votre accès ou la disponibilité du document a pu changer. Réessayez.")
        XCTAssertNil(model.pdfOuvert)
    }

    // MARK: - Signalement

    func testSignalementContenuConfirmeParRelecture() async throws {
        let model = try await modele()
        let ok = await model.signaler(try copie(model, Ids.valide), motif: .contenu)
        XCTAssertTrue(ok)
        XCTAssertEqual(model.message, "Le signalement est enregistré. L’établissement peut le consulter.")
        XCTAssertTrue(try copie(model, Ids.valide).signalee)
        XCTAssertEqual(try copie(model, Ids.valide).statut, .publiee, "CONTENU ne retire pas la copie")
    }

    func testSignalementDestinataireRetireLaCopie() async throws {
        let model = try await modele()
        let ok = await model.signaler(try copie(model, Ids.falsifiee), motif: .destinataire)
        XCTAssertTrue(ok)
        XCTAssertEqual(model.message, "La copie a été retirée. Son PDF n’est plus accessible dans Jolene.")
        XCTAssertEqual(try copie(model, Ids.falsifiee).statut, .retiree, "relecture RETIREE")
        XCTAssertFalse(model.telechargeable(try copie(model, Ids.falsifiee)), "plus de bouton d'ouverture")
    }

    func testSignalementNonConfirmeParLaRelecture() async throws {
        let port = PortTemoin()
        port.signalement = { $0 } // le serveur répond, la relecture ne montre rien
        let model = try await modele(port)
        let ok = await model.signaler(try copie(model, Ids.valide), motif: .destinataire)
        XCTAssertFalse(ok)
        XCTAssertNil(model.message)
        XCTAssertEqual(model.erreur, "Le signalement n’a pas été confirmé. Réessayez.")
    }

    func testCopieRetireeNonSignalable() async throws {
        let model = try await modele()
        let ok = await model.signaler(try copie(model, Ids.retiree), motif: .autre)
        XCTAssertFalse(ok, "pas de signalement sur une copie retirée (bouton absent, web l.77)")
    }

    // MARK: - Contrôles et présentation

    func testVerificationTypeTailleEtEmpreinte() throws {
        let octets = Data("%PDF-1.4 test".utf8)
        let ligne = CopieBulletin(id: Ids.valide, etablissementId: Ids.valide, employeurNom: "E", periodeDebut: "2026-10-01",
                                  periodeFin: "2026-10-31", statut: .publiee, version: 1, publieLe: "2026-10-31T09:30:00.000Z",
                                  motifRemplacement: nil, tailleOctets: octets.count,
                                  sha256: BulletinsTelechargement.sha256(octets), missionIds: [Ids.valide], signalee: false)
        XCTAssertEqual(try BulletinsTelechargement.verifier(donnees: octets, typeContenu: "application/pdf", copie: ligne).sha256,
                       ligne.sha256)
        XCTAssertNoThrow(try BulletinsTelechargement.verifier(donnees: octets, typeContenu: "Application/PDF; x=y", copie: ligne))
        XCTAssertThrowsError(try BulletinsTelechargement.verifier(donnees: octets, typeContenu: "application/json", copie: ligne)) {
            XCTAssertEqual($0 as? RefusCopieBulletin, .indisponible)
        }
        XCTAssertThrowsError(try BulletinsTelechargement.verifier(donnees: octets, typeContenu: nil, copie: ligne)) {
            XCTAssertEqual($0 as? RefusCopieBulletin, .indisponible)
        }
        XCTAssertThrowsError(try BulletinsTelechargement.verifier(donnees: Data(), typeContenu: "application/pdf", copie: ligne)) {
            XCTAssertEqual($0 as? RefusCopieBulletin, .indisponible)
        }
        var fausse = ligne
        fausse.sha256 = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try BulletinsTelechargement.verifier(donnees: octets, typeContenu: "application/pdf", copie: fausse)) {
            XCTAssertEqual($0 as? RefusCopieBulletin, .integrite)
        }
        var taille = ligne
        taille.tailleOctets += 1
        XCTAssertThrowsError(try BulletinsTelechargement.verifier(donnees: octets, typeContenu: "application/pdf", copie: taille)) {
            XCTAssertEqual($0 as? RefusCopieBulletin, .integrite)
        }
        XCTAssertEqual(BulletinsTelechargement.sha256(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testFixturePDFCoherente() throws {
        let fichier = try DemoFixtures.loadCopiesBulletins()
        let octets = try DemoFixtures.pdfDemo(fichier: fichier.pdf.fichier)
        XCTAssertEqual(BulletinsTelechargement.sha256(octets), fichier.pdf.sha256)
        XCTAssertEqual(octets.count, fichier.pdf.tailleOctets)
        XCTAssertTrue(String(decoding: octets, as: UTF8.self).contains("D\\311MONSTRATION"))
    }

    func testLignesDuWeb() async throws {
        let model = try await modele()
        let valide = try copie(model, Ids.valide)
        XCTAssertEqual(BulletinsPresentation.periode(valide), "Du 01/10/2026 au 31/10/2026")
        XCTAssertEqual(BulletinsPresentation.meta(valide), "Version 2 · publiée le 31/10/2026 à 10:30 · 2 missions liées")
        XCTAssertTrue(BulletinsPresentation.meta(try copie(model, Ids.falsifiee)).hasSuffix(" · 1 mission liée"))
        XCTAssertEqual(BulletinsPresentation.motifRemplacement(valide), "Motif de remplacement : correction du contenu.")
        XCTAssertNil(BulletinsPresentation.motifRemplacement(try copie(model, Ids.remplacee)))
        XCTAssertEqual(BulletinsPresentation.statut(.remplacee), "Version remplacée")
        XCTAssertEqual(BulletinsPresentation.motifs.map(BulletinsPresentation.motif),
                       ["Ce document ne me concerne pas", "Le contenu contient une erreur", "Autre erreur"])
        XCTAssertEqual(BulletinsPresentation.accessibilite(valide), "Copie du bulletin, version 2")
    }

    func testFichierTemporaireProtegeEtEfface() throws {
        let pdf = PDFVerifie(donnees: Data("%PDF-1.4".utf8), sha256: "x")
        let url = try FichierCopieBulletinTemporaire.ecrire(pdf)
        XCTAssertEqual(url.lastPathComponent, "copie-bulletin.pdf")
        XCTAssertEqual(try Data(contentsOf: url), pdf.donnees)
        XCTAssertEqual(try url.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        FichierCopieBulletinTemporaire.effacer(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        FichierCopieBulletinTemporaire.effacer(URL(fileURLWithPath: "/tmp/ailleurs/x.pdf")) // sans effet hors du dossier
        FichierCopieBulletinTemporaire.effacerTout()
    }
}
