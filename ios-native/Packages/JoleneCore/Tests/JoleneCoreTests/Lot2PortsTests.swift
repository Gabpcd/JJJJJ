import XCTest
@testable import JoleneCore

/// Fondation du lot 2 (blueprint `docs/mobile-swift/LOT2_PLAN.md` §2.2-§2.3, tranche T1) : bloc
/// « Lot 2 » de cinq champs additifs de `Gateways`, chacun « non câblé » par défaut ; un stub refuse
/// explicitement (`.contract`) en citant la tranche ET le lot qui le livrent ; `unwiredPorts` nomme
/// aussi les ports du lot 2. Les inits du lot 0 et du lot 1 restent mot pour mot : aucun troisième
/// init, chaque monde assigne ses ports du lot 2 dans `câblerLot2(_:)`.
final class Lot2PortsTests: XCTestCase {
    /// Champs ajoutés au lot 2, dans l'ordre de déclaration de `Gateways` (§2.2).
    static let portsLot2 = ["pointage", "contestation", "notation", "documents", "contrats"]

    private let contexte = DemoWorld.context

    // MARK: - Bloc lot 2 de `Gateways`

    func testInitDuLot0LaisseLesPortsDuLot2NonCablesApresCeuxDuLot1() {
        let g = Gateways(auth: NeutralAuth(), role: NeutralRole(), missions: NeutralMissions())
        // Fusion des lots 2 et 3 : le bloc du lot 3 (`Lot3PortsTests`) suit celui du lot 2.
        XCTAssertEqual(g.unwiredPorts, Lot1PortsTests.portsLot1 + Self.portsLot2 + Lot3PortsTests.portsLot3,
                       "lot 1 puis lot 2 (puis lot 3), ordre de déclaration")
        XCTAssertTrue(g.pointage is UnwiredPointagePort)
        XCTAssertTrue(g.contestation is UnwiredContestationPort)
        XCTAssertTrue(g.notation is UnwiredNotationPort)
        XCTAssertTrue(g.documents is UnwiredDocumentsPort)
        XCTAssertTrue(g.contrats is UnwiredContratsPort)
    }

    func testLeSecondInitDuLot1NeTouchePasAuBlocLot2() {
        let g = Lot1Fakes.gateways(clock: FixedClock(Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(g.unwiredPorts, Self.portsLot2 + Lot3PortsTests.portsLot3,
                       "le second init câble tout le lot 1, le lot 2 (puis le lot 3) s'assigne après")
    }

    func testAssignerUnPortDuLot2LeRetireDeLaListe() {
        var g = Lot1Fakes.gateways(clock: SystemClock())
        g.pointage = FauxPointage()
        g.contrats = FauxContrats()
        XCTAssertEqual(g.unwiredPorts, Self.portsLot2.filter { $0 != "pointage" && $0 != "contrats" } + Lot3PortsTests.portsLot3)
        XCTAssertTrue(g.pointage is FauxPointage)
        XCTAssertTrue(g.contrats is FauxContrats)
    }

    // MARK: - Stubs « non câblés »

    func testChaquePortNonCableDuLot2RefuseEnCitantSaTrancheEtSonLot() async throws {
        let g = Gateways(auth: NeutralAuth(), role: NeutralRole(), missions: NeutralMissions())
        let c = contexte
        let recuScan = try RecuScan.preparer(userId: c.userId, epoch: 1, missionId: "m-1", terminalId: "TERM_IOS_DEMODEMODEMODEMODEMO",
                                             typeAttendu: .ouverture, nbScansAvant: 0, preuvesAvant: [], gps: .nonDemande,
                                             attemptId: "6f1c2c1e-4c1a-4f55-9a0e-2b7b1d9e8a01")
        let metadonnees = MetadonneesScan(idTerminal: "TERM_IOS_DEMODEMODEMODEMODEMO", observation: nil)
        let fichier = FichierChoisi(nom: "diplome.pdf", mime: .pdf, tailleOctets: 1_024)
        let recuDocument = try RecuDocument.preparer(userId: c.userId, epoch: 1, typeDocument: "DIPLOME", fichier: fichier,
                                                     horodatageMs: 1_793_577_600_000)
        let document = DocumentSoignant(id: "d-1", typeDocument: "DIPLOME")
        let contrat = ContratDetail(id: "k-1", missionId: "m-1", statut: "EN_ATTENTE_SIGNATURES")
        let original = OriginalContrat(contratId: "k-1", html: "<p>Contrat</p>", empreinte: String(repeating: "a", count: 64))

        await refuse("T3") { _ = try await g.pointage.presences(context: c) }
        await refuse("T3") { _ = try await g.pointage.etat(missionId: "m-1", context: c) }
        await refuse("T3") { _ = try await g.pointage.consentementGps(context: c) }
        await refuse("T3") { _ = try await g.pointage.enregistrerConsentementGps(true, context: c) }
        await refuse("T3") { _ = try await g.pointage.scanner(code: "123456", metadonnees: metadonnees, recu: recuScan, context: c) }
        await refuse("T3") { _ = try await g.pointage.reconcilier(recu: recuScan, context: c) }
        await refuse("T3") { _ = try await g.pointage.detail(missionId: "m-1", context: c) }
        await refuse("T3") { _ = try await g.pointage.relancerValidation(missionId: "m-1", context: c) }
        await refuse("T5a") { _ = try await g.pointage.ficheDetail(missionId: "m-1", context: c) }
        // Ajout de T3 (amendement du §2.3) : base `preuvesAvant` du reçu ; le défaut ne rend jamais une base vide.
        await refuse("T3") { _ = try await g.pointage.preuvesScan(missionId: "m-1", context: c) }
        await refuse("T3") { _ = try await PortTemoinLot2().preuvesScan(missionId: "m-1", context: c) }
        // Seconde revue fraîche de T3 (mi-1) : moitiés du scan ; défauts sûrs (requête par `scanner`, relecture refusée).
        await refuse("T3") { _ = try await g.pointage.envoyerScan(code: "123456", metadonnees: metadonnees, recu: recuScan, context: c) }
        await refuse("T3") { _ = try await g.pointage.relireScanAccepte(nil, recu: recuScan, context: c) }
        await refuse("T3") { _ = try await PortTemoinLot2().relireScanAccepte(nil, recu: recuScan, context: c) }
        await refuse("T5b") { _ = try await g.contestation.litige(presenceId: "p-1", context: c) }
        await refuse("T5b") { _ = try await g.contestation.fenetreOuverte(missionId: "m-1", context: c) }
        await refuse("T5b") {
            _ = try await g.contestation.contester(missionId: "m-1", presenceId: "p-1", motif: "Heures erronées", context: c)
        }
        await refuse("T5a") { _ = try await g.notation.noter(missionId: "m-1", note: 5, criteres: nil, context: c) }
        await refuse("T5a") { _ = try await g.notation.finPrevue(missionId: "m-1", context: c) }
        await refuse("T6") { _ = try await g.documents.dossier(context: c) }
        await refuse("T6") { _ = try await g.documents.preparerEnvoi(type: "DIPLOME", fichier: fichier, libelle: nil, context: c) }
        await refuse("T6") { _ = try await g.documents.envoyer(recu: recuDocument, octets: Data([0x25]), context: c) }
        await refuse("T6") { _ = try await g.documents.reconcilier(recu: recuDocument, context: c) }
        await refuse("T6") { _ = try await g.documents.reverifier(documentId: "d-1", context: c) }
        await refuse("T6") { try await g.documents.demanderRevue(documentId: "d-1", context: c) }
        await refuse("T6") { _ = try await g.documents.consulter(document: document, context: c) }
        await refuse("T6") { _ = try await g.documents.signerAttestationSante(context: c) }
        await refuse("T6") { _ = try await g.documents.coherence(context: c) }
        await refuse("T8") { _ = try await g.contrats.contrats(context: c) }
        await refuse("T8") { _ = try await g.contrats.contrat(id: "k-1", context: c) }
        await refuse("T8") { _ = try await g.contrats.original(contrat: contrat, context: c) }
        await refuse("T8") { _ = try await g.contrats.admissionRecette(contratId: "k-1", context: c) }
        await refuse("T8") { _ = try await g.contrats.envoyerOtp(contratId: "k-1", empreinte: original.empreinte, context: c) }
        await refuse("T8") {
            _ = try await g.contrats.signer(contratId: "k-1", code: "000000", empreinte: original.empreinte, context: c)
        }
        await refuse("T8") { _ = try await g.contrats.certificat(contratId: "k-1", context: c) }
        await refuse("T8") { _ = try await g.contrats.fichierOriginal(contrat: original, context: c) }
    }

    func testMessageGeneriqueParLotEtCompatibiliteDuLot1() {
        // Même surcharge que le lot 3 (`Lot1Ports.swift`) : le lot 2 ne la duplique pas.
        XCTAssertEqual(UnwiredPorts.erreur(port: "pointage", tranche: "T3", lot: 2),
                       JoleneError(.contract, "Port « pointage » non câblé : livré par la tranche T3 du lot 2 (docs/mobile-swift/LOT2_PLAN.md §3)."))
        XCTAssertEqual(UnwiredPorts.erreur(port: "favoris", tranche: "T4b", lot: 1), UnwiredPorts.erreur(port: "favoris", tranche: "T4b"),
                       "pour le lot 1, même texte que la surcharge historique")
    }

    // MARK: - Audit (T4b)

    func testActionDAuditDuLot2ApresCelleDuLot1() {
        // Consentement GPS du premier pointage (décision 4) : action du CHECK `journaux_audit_action_check` (l.70290) ;
        // jamais `GPS_CONSENTEMENT_*` (retrait depuis le Profil), absentes du CHECK (correction 15).
        // Fusion des lots 2 et 3 : les trois actions du lot 3 (`Lot3PortsTests.testActionsAuditDuLot3`) suivent celle du lot 2.
        XCTAssertEqual(Array(AuditAction.allCases.map(\.rawValue).prefix(2)), ["MISSION_ASSIGNATION", "RGPD_CONSENTEMENT_DONNE"])
        XCTAssertEqual(AuditAction.allCases.map(\.rawValue), ["MISSION_ASSIGNATION", "RGPD_CONSENTEMENT_DONNE",
                                                             "DONNEES_PERSO_CONSULTATION", "DONNEES_PERSO_MODIFICATION",
                                                             "RGPD_EXPORT_DONNEES"])
        XCTAssertFalse(AuditAction.allCases.contains { $0.rawValue.hasPrefix("GPS_CONSENTEMENT") })
    }

    // MARK: - Drapeaux d'écran (D-FLAGS)

    func testClesDesEcransDuLot2ApresCellesDuLot1() async {
        // `DECISIONS_LOT2.md` « D-FLAGS » ; clés posées par la migration `20261102204450_drapeaux_ios_natif_lots_2_4_5.sql`.
        XCTAssertEqual(EcranNatif.allCases.map(\.cle), ["ios_natif_accueil_actif", "ios_natif_explorer_actif",
                                                        "ios_natif_missions_actif", "ios_natif_revenus_actif",
                                                        "ios_natif_profil_actif",
                                                        "ios_natif_presences_actif", "ios_natif_documents_actif",
                                                        "ios_natif_contrats_actif"])
        let flags = FakeFlags(valeurs: [EcranNatif.contrats.cle: false])
        let contrats = await flags.ecranActif(.contrats)
        let presences = await flags.ecranActif(.presences)
        let documents = await flags.ecranActif(.documents)
        XCTAssertFalse(contrats, "coupe-circuit de la signature")
        XCTAssertTrue(presences, "clé absente : défaut fail-open, comme au lot 1")
        XCTAssertTrue(documents)
        let demo = DemoWorld.gateways(drapeaux: [EcranNatif.presences.cle: false]).flags
        let presencesDemo = await demo.ecranActif(.presences)
        let documentsDemo = await demo.ecranActif(.documents)
        XCTAssertFalse(presencesDemo, "surcharge de lancement honorée en démo")
        XCTAssertTrue(documentsDemo)
    }

    // MARK: - Aide

    private func refuse(_ tranche: String, file: StaticString = #filePath, line: UInt = #line,
                        _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("un port non câblé ne doit jamais répondre", file: file, line: line)
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract, file: file, line: line)
            XCTAssertTrue(error.message.contains("non câblé"), error.message, file: file, line: line)
            XCTAssertTrue(error.message.contains("tranche \(tranche) du lot 2 "), "\(error.message) doit citer \(tranche) du lot 2",
                          file: file, line: line)
            XCTAssertTrue(error.message.contains("LOT2_PLAN.md"), error.message, file: file, line: line)
        } catch {
            XCTFail("type d'erreur inattendu : \(error)", file: file, line: line)
        }
    }
}

// MARK: - Doubles minimaux (assignation seulement)

private struct FauxPointage: PointagePort {
    func presences(context: MissionReadContext) async throws -> InstantanePresences { InstantanePresences() }
    func etat(missionId: String, context: MissionReadContext) async throws -> EtatPointage { EtatPointage() }
    func consentementGps(context: MissionReadContext) async throws -> Bool? { nil }
    func enregistrerConsentementGps(_ accepte: Bool, context: MissionReadContext) async throws -> Bool { accepte }
    func scanner(code: String, metadonnees: MetadonneesScan, recu: RecuScan, context: MissionReadContext) async throws -> IssueScan {
        .incertain
    }
    func reconcilier(recu: RecuScan, context: MissionReadContext) async throws -> IssueScan { .incertain }
    func detail(missionId: String, context: MissionReadContext) async throws -> DetailPresences { DetailPresences(missionId: missionId) }
    func relancerValidation(missionId: String, context: MissionReadContext) async throws -> IssueRelance { .refusee(message: "x") }
}

private struct FauxContrats: ContratsPort {
    func contrats(context: MissionReadContext) async throws -> [ContratResume] { [] }
    func contrat(id: String, context: MissionReadContext) async throws -> ContratDetail {
        ContratDetail(id: id, missionId: "m", statut: "EN_ATTENTE_SIGNATURES")
    }
    func original(contrat: ContratDetail, context: MissionReadContext) async throws -> OriginalContrat {
        OriginalContrat(contratId: contrat.id, html: "", empreinte: "")
    }
    func admissionRecette(contratId: String, context: MissionReadContext) async throws -> AdmissionSignatureRecette? { nil }
    func envoyerOtp(contratId: String, empreinte: String, context: MissionReadContext) async throws -> IssueEnvoiOtp {
        .refuse(code: nil, message: "x", bloquant: true)
    }
    func signer(contratId: String, code: String, empreinte: String, context: MissionReadContext) async throws -> IssueSignature {
        .refuse(code: nil, message: "x", tentativesRestantes: nil)
    }
    func certificat(contratId: String, context: MissionReadContext) async throws -> [SignatureCertificat] { [] }
    func fichierOriginal(contrat: OriginalContrat, context: MissionReadContext) async throws -> URL {
        URL(fileURLWithPath: "/dev/null")
    }
}
