import XCTest
@testable import JoleneCore

/// Ports de l'espace établissement (lot 5 T1, §2.3) : un seul champ additif dans `Gateways`, huit ports
/// non câblés par défaut qui refusent explicitement en citant leur tranche (« un gap connu reste
/// verrouillé »), jamais un état vide plausible.
final class Lot5PortsTests: XCTestCase {
    private let context = EtablissementReadContext(userId: "u-1", etablissementId: "e-1", roleEtab: .proprietaire,
                                                   permissions: PermissionsEtab(accordees: Set(PermissionEtab.allCases)), epoch: 1)

    private func refus(_ tranche: String, file: StaticString = #filePath, line: UInt = #line,
                       _ appel: () async throws -> Void) async {
        do {
            try await appel()
            XCTFail("un port non câblé ne rend jamais de valeur", file: file, line: line)
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract, file: file, line: line)
            XCTAssertTrue(error.message.contains("tranche \(tranche) du lot 5"), error.message, file: file, line: line)
            XCTAssertTrue(error.message.contains("LOT5_PLAN.md"), file: file, line: line)
        } catch {
            XCTFail("type d'erreur inattendu : \(error)", file: file, line: line)
        }
    }

    func testGatewaysExposeUnSeulChampEtablissementNonCableParDefaut() {
        let gateways = Gateways(auth: DemoAuthGateway(), role: DemoRoleGateway(), missions: DemoMissionsGateway())
        XCTAssertEqual(gateways.etablissement.unwiredPorts, EtablissementGateways.nonCable.unwiredPorts)
        XCTAssertEqual(EtablissementGateways.nonCable.unwiredPorts,
                       ["etablissement.session", "etablissement.dashboard", "etablissement.missions",
                        "etablissement.candidatures", "etablissement.pointage", "etablissement.presences",
                        "etablissement.publication", "etablissement.audit"])
        XCTAssertFalse(gateways.unwiredPorts.contains { $0.hasPrefix("etablissement") },
                       "les ports du lot 1 restent comptés à part (DemoWorldTests.portsEnAttenteLot1)")
    }

    func testJeuCompletNommeChaquePort() {
        let complet = EtablissementGateways(
            session: UnwiredEtabSessionPort(), dashboard: UnwiredEtabDashboardPort(), missions: UnwiredEtabMissionsPort(),
            candidatures: UnwiredEtabCandidaturesPort(), pointage: UnwiredEtabPointagePort(),
            presences: UnwiredEtabPresencesPort(), publication: UnwiredEtabPublicationPort(), audit: UnwiredEtabAuditPort())
        XCTAssertEqual(complet.unwiredPorts.count, 8)
        var partiel = complet
        partiel.audit = DemoEtabAuditGateway()
        XCTAssertEqual(partiel.unwiredPorts.last, "etablissement.publication", "un port câblé sort de la liste")
        XCTAssertEqual(partiel.unwiredPorts.count, 7)
    }

    func testChaquePortNonCableRefuseEnCitantSaTranche() async {
        let ports = EtablissementGateways.nonCable
        await refus("T1") { _ = try await ports.session.permissions(etablissementId: nil) }
        await refus("T1") { _ = try await ports.session.profil() }
        await refus("T4") { _ = try await ports.dashboard.tableauDeBord(context: self.context) }
        await refus("T5") { _ = try await ports.missions.missions(context: self.context, statut: nil, page: 0) }
        await refus("T5") { _ = try await ports.missions.mission(id: "m-1", context: self.context) }
        await refus("T5") { _ = try await ports.missions.soignant(id: "s-1", context: self.context) }
        await refus("T6") { _ = try await ports.candidatures.lecture(missionId: "m-1", context: self.context) }
        await refus("T6") {
            _ = try await ports.candidatures.accepter(candidatureId: "c-1", creneauxConfirmes: [], context: self.context)
        }
        await refus("T6") { _ = try await ports.candidatures.refuser(candidatureId: "c-1", context: self.context) }
        await refus("T7") { _ = try await ports.pointage.etat(missionId: "m-1", context: self.context) }
        await refus("T7") { _ = try await ports.pointage.contratSigne(missionId: "m-1", context: self.context) }
        await refus("T7") { _ = try await ports.pointage.planning(missionId: "m-1", context: self.context) }
        await refus("T8") { _ = try await ports.presences.presences(context: self.context) }
        await refus("T8") { _ = try await ports.presences.valider(presenceId: "p-1", context: self.context) }
        await refus("T8") { _ = try await ports.presences.validerLot(ids: ["p-1"], context: self.context) }
        await refus("T8") { _ = try await ports.presences.contester(presenceId: "p-1", motif: "Absent", context: self.context) }
        await refus("T8") { _ = try await ports.presences.noter(missionId: "m-1", note: 5, context: self.context) }
        await refus("T8") {
            _ = try await ports.presences.cloturerSegment(missionId: "m-1", heureFin: Date(timeIntervalSince1970: 0), context: self.context)
        }
        await refus("T9") {
            let brouillon = PublicationMission(intitule: "Mission", description: nil, professionRequise: "IDE", service: nil,
                                               tauxHoraireBase: 30, estUrgente: false, creneaux: [])
            _ = try await ports.publication.publier(brouillon, context: self.context)
        }
        await refus("T1") { _ = try await ports.audit.consultation(page: .tableauDeBord, context: self.context) }
    }

    func testContratsDesIssuesEtDesConstantes() {
        XCTAssertEqual(DecisionCandidature.allCases.map(\.rawValue), ["ACCEPTEE", "REFUSEE"])
        XCTAssertEqual(TraitementCandidatureOutcome.codeCadreEtudiantAConfirmer, "CADRE_ETUDIANT_A_CONFIRMER")
        XCTAssertTrue(TraitementCandidatureOutcome.codeCadreEtudiantAConfirmer.hasPrefix(TraitementCandidatureOutcome.prefixeCadreEtudiant))
        XCTAssertEqual(PageAuditEtab.tableauDeBord.rawValue, "dashboard_etablissement", "valeur du web (DashboardEtablissement.tsx l.424)")
        XCTAssertEqual(EtabMissionsPage.taille, MissionsPage.taille)
        // Pointage : le type d'état est celui des règles pures de T3, jamais un second décodeur.
        let etat: EtatPointageEtab = CodeRotatifRules.Etat(statut: "ASSIGNEE", prochainTypeScan: nil, segmentOuvert: false,
                                                           segments: [], codePointageActif: nil)
        XCTAssertEqual(etat.statut, "ASSIGNEE")
    }

    func testModelesDeLectureSansMontant() {
        // §2.8 : aucun champ monétaire dans les modèles de lecture établissement.
        let modeles: [Any] = [
            EtabMissionResume(id: "m-1", intitule: "Mission"),
            EtabMissionDetail(mission: EtabMissionResume(id: "m-1", intitule: "Mission"), creneaux: [], soignantAssigneId: nil),
            EtabDashboardSnapshot(), SoignantPourEtab(id: "s-1", prenom: nil, nom: nil, profession: nil),
            PresenceEtab(id: "p-1", missionId: "m-1", valideParEtablissement: false, valideLe: nil, motifLitige: nil),
            LectureCandidaturesHabilitee(missionId: "m-1", statutMission: nil, nbCreneaux: nil, creneaux: [], candidatures: []),
            CandidatureHabilitee(id: "c-1", soignantId: nil, statut: nil, creeLe: nil),
        ]
        for modele in modeles {
            let proprietes = Mirror(reflecting: modele).children.compactMap(\.label).map { $0.lowercased() }
            for interdit in ["taux", "brut", "net", "montant", "commission", "note", "facture"] {
                XCTAssertFalse(proprietes.contains { $0.contains(interdit) }, "\(type(of: modele)).\(interdit)")
            }
        }
    }
}
