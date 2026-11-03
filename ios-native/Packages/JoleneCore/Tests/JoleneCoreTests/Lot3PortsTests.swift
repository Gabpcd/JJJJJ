import XCTest
@testable import JoleneCore

/// Fondation du lot 3 (blueprint `docs/mobile-swift/LOT3_PLAN.md` §2.2-§2.3, tranche T1) : bloc
/// « Lot 3 » de champs additifs de `Gateways`, chacun « non câblé » par défaut ; un stub refuse
/// explicitement (`.contract`) en citant la tranche ET le lot qui le livrent ; `unwiredPorts`
/// nomme aussi les ports du lot 3. Les inits du lot 0 et du lot 1 restent mot pour mot : aucun
/// troisième init, chaque monde assigne ses ports du lot 3 dans `câblerLot3(_:)`.
final class Lot3PortsTests: XCTestCase {
    /// Champs ajoutés au lot 3, dans l'ordre de déclaration de `Gateways` (§2.2).
    static let portsLot3 = ["push", "notifications", "preferences", "inscription", "profil", "avatar", "geocodage",
                            "motDePasse", "exportRGPD", "revenus", "paiements", "iban", "stripeConnect"]

    private let contexte = DemoWorld.context

    // MARK: - Bloc lot 3 de `Gateways`

    func testInitDuLot0LaisseLesPortsDuLot3NonCablesApresCeuxDuLot1() {
        let g = Gateways(auth: NeutralAuth(), role: NeutralRole(), missions: NeutralMissions())
        XCTAssertEqual(g.unwiredPorts, Lot1PortsTests.portsLot1 + Self.portsLot3, "lot 1 puis lot 3, ordre de déclaration")
        XCTAssertTrue(g.push is UnwiredPushRegistrationPort)
        XCTAssertTrue(g.notifications is UnwiredNotificationsCenterPort)
        XCTAssertTrue(g.preferences is UnwiredNotificationPreferencesPort)
        XCTAssertTrue(g.inscription is UnwiredInscriptionPort)
        XCTAssertTrue(g.profil is UnwiredProfilPort)
        XCTAssertTrue(g.avatar is UnwiredAvatarStoragePort)
        XCTAssertTrue(g.geocodage is UnwiredGeocodagePort)
        XCTAssertTrue(g.motDePasse is UnwiredMotDePassePort)
        XCTAssertTrue(g.exportRGPD is UnwiredExportRGPDPort)
        XCTAssertTrue(g.revenus is UnwiredRevenusPort)
        XCTAssertTrue(g.paiements is UnwiredPaiementsDeclaresPort)
        XCTAssertTrue(g.iban is UnwiredIbanPort)
        XCTAssertTrue(g.stripeConnect is UnwiredStripeConnectPort)
    }

    func testLeSecondInitDuLot1NeTouchePasAuBlocLot3() {
        let g = Lot1Fakes.gateways(clock: FixedClock(Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(g.unwiredPorts, Self.portsLot3, "le second init câble tout le lot 1, le lot 3 s'assigne après")
    }

    func testAssignerUnPortDuLot3LeRetireDeLaListe() {
        var g = Lot1Fakes.gateways(clock: SystemClock())
        g.push = FakePushRegistration()
        g.stripeConnect = FakeStripeConnect()
        XCTAssertEqual(g.unwiredPorts, Self.portsLot3.filter { $0 != "push" && $0 != "stripeConnect" })
        XCTAssertTrue(g.push is FakePushRegistration)
    }

    // MARK: - Stubs « non câblés »

    func testChaquePortNonCableDuLot3RefuseEnCitantSaTrancheEtSonLot() async {
        let g = Gateways(auth: NeutralAuth(), role: NeutralRole(), missions: NeutralMissions())
        let c = contexte
        let formulaire = FormulaireInscription(profession: "IDE")
        let intention = IntentionInscription(profession: "IDE", cgu: true)
        await refuse("T4") { try await g.push.enregistrer(token: String(repeating: "a", count: 64), context: c) }
        await refuse("T4") { _ = try await g.push.desactiver(token: String(repeating: "a", count: 64)) }
        await refuse("T5") { _ = try await g.notifications.liste(context: c) }
        await refuse("T5") { _ = try await g.notifications.marquerLue(id: "n-1", context: c) }
        await refuse("T6") { _ = try await g.preferences.lire(context: c) }
        await refuse("T6") {
            _ = try await g.preferences.enregistrer(PreferencesNotifications(canalEmail: true, canalSms: false, canalPush: true,
                                                                             canalInApp: true, parEvenement: []),
                                                    smsAlertes: nil, context: c)
        }
        await refuse("T7") { _ = try await g.inscription.creerCompte(email: "a@b.c", motDePasse: "x", intention: intention) }
        await refuse("T7") { _ = try await g.inscription.confirmer(.tokenHash(tokenHash: "x", otpType: "signup")) }
        await refuse("T7") { _ = try await g.inscription.contexte() }
        await refuse("T7") { _ = try await g.inscription.parcours(userId: c.userId) }
        await refuse("T7") { _ = try await g.inscription.demarrer(intention: intention) }
        await refuse("T8") { _ = try await g.inscription.enregistrerBrouillon(formulaire) }
        await refuse("T8") { _ = try await g.inscription.typesExercice(profession: "IDE") }
        await refuse("T8") { _ = try await g.inscription.finaliser(formulaire) }
        await refuse("T9") { _ = try await g.profil.profil(context: c) }
        await refuse("T9") { _ = try await g.profil.modifier(ModificationProfil(bio: "x"), context: c) }
        await refuse("T10") { _ = try await g.avatar.televerser(jpeg: Data([0xFF, 0xD8]), context: c) }
        await refuse("T10") { _ = try await g.geocodage.adresse(lat: 45.76, lng: 4.85) }
        await refuse("T11") { _ = try await g.motDePasse.changer(ancien: "a", nouveau: "b", context: c) }
        await refuse("T11") { _ = try await g.exportRGPD.exporter(context: c) }
        await refuse("T12") { _ = try await g.revenus.totaux(context: c) }
        await refuse("T12") { _ = try await g.revenus.paiementsRapides(context: c) }
        await refuse("T12") { _ = try await g.revenus.missionsTerminees(context: c, page: 0) }
        await refuse("T13") { _ = try await g.paiements.aConfirmer(context: c) }
        await refuse("T13") { _ = try await g.paiements.confirmer(id: "p-1", context: c) }
        await refuse("T13") { _ = try await g.paiements.contester(id: "p-1", motif: "Montant erroné", context: c) }
        await refuse("T14b") { _ = try await g.iban.consulter(context: c) }
        await refuse("T14b") { _ = try await g.iban.enregistrer(iban: "FR7630006000011234567890189", titulaire: "A B", context: c) }
        await refuse("T14a") { _ = try await g.stripeConnect.statut(force: true, context: c) }
        await refuse("T14a") { _ = try await g.stripeConnect.lienOnboarding(context: c) }
    }

    func testMessageGeneriqueParLotEtCompatibiliteDuLot1() {
        XCTAssertEqual(UnwiredPorts.erreur(port: "push", tranche: "T4", lot: 3),
                       JoleneError(.contract, "Port « push » non câblé : livré par la tranche T4 du lot 3 (docs/mobile-swift/LOT3_PLAN.md §3)."))
        XCTAssertEqual(UnwiredPorts.erreur(port: "favoris", tranche: "T4b", lot: 1), UnwiredPorts.erreur(port: "favoris", tranche: "T4b"),
                       "la surcharge générique rend mot pour mot le message du lot 1")
        XCTAssertTrue(UnwiredPorts.erreur(port: "pointage", tranche: "T3", lot: 2).message.contains("LOT2_PLAN.md"),
                      "surcharge générique, partagée avec le lot 2")
    }

    // MARK: - Audit (`AuditAction` +3 cas)

    func testActionsAuditDuLot3() {
        XCTAssertEqual(AuditAction.allCases.map(\.rawValue),
                       ["MISSION_ASSIGNATION", "DONNEES_PERSO_CONSULTATION", "DONNEES_PERSO_MODIFICATION", "RGPD_EXPORT_DONNEES"])
        XCTAssertEqual(AuditAction.donneesPersoConsultation.rawValue, "DONNEES_PERSO_CONSULTATION")
        XCTAssertEqual(AuditAction.donneesPersoModification.rawValue, "DONNEES_PERSO_MODIFICATION")
        XCTAssertEqual(AuditAction.rgpdExportDonnees.rawValue, "RGPD_EXPORT_DONNEES")
    }

    /// Une action hors `journaux_audit_action_check` serait avalée par `fn_ecrire_audit_safe` :
    /// chaque cas doit figurer dans la contrainte du dump versionné.
    func testChaqueActionAuditFigureDansLaContrainteDuDump() throws {
        let contrainte = try ligneDuDump(contenant: #"CONSTRAINT "journaux_audit_action_check""#)
        for action in AuditAction.allCases {
            XCTAssertTrue(contrainte.contains("'\(action.rawValue)'::\"text\""), "\(action.rawValue) absente du CHECK")
        }
    }

    // MARK: - Résultats et contrats du lot 3

    func testAutorisationPush() {
        XCTAssertEqual(AutorisationPush.allCases, [.nonDemandee, .accordee, .refusee, .provisoire])
        XCTAssertEqual(AutorisationPush.allCases.filter(\.permetEnregistrement), [.accordee, .provisoire],
                       "jamais d'enregistrement sans autorisation (§2.5)")
    }

    func testStatutsConnectIdentiquesALaContrainteDuDump() throws {
        let contrainte = try ligneDuDump(contenant: #"CONSTRAINT "stripe_connect_onboarding_statut_check""#)
        let attendus = ["NON_DEMANDE", "EN_COURS", "COMPLET", "SUSPENDU", "REJETE", "SUPPRIME"]
        XCTAssertEqual(StatutOnboardingConnect.allCases.map(\.rawValue), attendus)
        for statut in attendus {
            XCTAssertTrue(contrainte.contains("'\(statut)'::\"text\""), "\(statut) absent du CHECK")
        }
        XCTAssertNil(StatutOnboardingConnect(rawValue: "INCONNU"), "statut hors CHECK : erreur d'écran, jamais un défaut")
    }

    func testCanauxIdentiquesALEnumDuDump() throws {
        XCTAssertEqual(CanalNotification.allCases.map(\.rawValue), ["EMAIL", "SMS", "PUSH", "IN_APP"])
        let dump = try String(contentsOf: Self.dumpURL, encoding: .utf8)
        XCTAssertTrue(dump.contains("CREATE TYPE \"public\".\"canal_notification\" AS ENUM (\n    'EMAIL',\n    'SMS',\n    'PUSH',\n    'IN_APP'\n);"))
    }

    func testIssuesSansSuccesFabrique() {
        // L'issue d'un flux hébergé n'est jamais un succès : elle impose une relecture (§2.3).
        let retour = URL(string: "https://jolene.app/soignant/stripe-connect?success=true")!
        XCTAssertNotEqual(IssueFlux.retour(retour), IssueFlux.ferme)
        XCTAssertEqual(RetourAttendu.stripeConnect, RetourAttendu(hote: "jolene.app", chemin: "/soignant/stripe-connect"))
        XCTAssertNotEqual(IssueDesactivationPush.desactive(tokensDesactives: 0), .nonDesactive)
        XCTAssertEqual(IntentionInscription(profession: "IDE", cgu: true).typeCompte, "SOIGNANT")
        XCTAssertEqual(IntentionInscription(profession: "IDE", cgu: true).cgv, false)
    }

    /// Données sensibles (§2.6, correction 7) : `ProfilComplet` n'a aucune propriété pour les clés
    /// que `fn_mon_profil_soignant_complet` renvoie mais que le natif ne doit ni décoder ni afficher.
    func testProfilCompletSansProprieteSensible() {
        let profil = ProfilComplet(id: "demo-soignant", prenom: "Camille", nom: "Martin")
        let proprietes = Set(Mirror(reflecting: profil).children.compactMap(\.label))
        let interdites: Set<String> = ["numeroSecu", "numeroAdeli", "siretLiberal", "codeApe", "assujettiTva", "numeroTva",
                                       "stripeAccountId", "ibanLast4"]
        XCTAssertEqual(proprietes.intersection(interdites), [])
        XCTAssertTrue(proprietes.contains("prenom"))
        let modification = Set(Mirror(reflecting: ModificationProfil()).children.compactMap(\.label))
        XCTAssertEqual(modification.intersection(interdites), [])
        XCTAssertFalse(modification.contains("typeExercice"), "type d'exercice : renvoi web (HARD STOP n°4, correction 8)")
    }

    func testModificationProfilVideNeChangeRien() {
        // `fn_modifier_mon_profil` : un paramètre NULL est inchangé (COALESCE) ; le natif envoie nil, jamais "".
        XCTAssertTrue(ModificationProfil().estVide)
        XCTAssertFalse(ModificationProfil(bio: "Infirmière").estVide)
    }

    // MARK: - Aide

    static var dumpURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // …/Tests/JoleneCoreTests
            .deletingLastPathComponent() // …/JoleneCore/Tests
            .deletingLastPathComponent() // …/Packages/JoleneCore
            .deletingLastPathComponent() // …/ios-native/Packages
            .deletingLastPathComponent() // …/ios-native
            .deletingLastPathComponent() // racine du dépôt
            .appendingPathComponent("supabase/schema/public.sql")
    }

    private func ligneDuDump(contenant marqueur: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let dump = try String(contentsOf: Self.dumpURL, encoding: .utf8)
        let ligne = dump.components(separatedBy: "\n").first { $0.contains(marqueur) }
        return try XCTUnwrap(ligne, "\(marqueur) introuvable dans supabase/schema/public.sql", file: file, line: line)
    }

    private func refuse(_ tranche: String, file: StaticString = #filePath, line: UInt = #line,
                        _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("un port non câblé ne doit jamais répondre", file: file, line: line)
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract, file: file, line: line)
            XCTAssertTrue(error.message.contains("non câblé"), error.message, file: file, line: line)
            XCTAssertTrue(error.message.contains("tranche \(tranche) du lot 3 "), "\(error.message) doit citer \(tranche)",
                          file: file, line: line)
            XCTAssertTrue(error.message.contains("LOT3_PLAN.md"), error.message, file: file, line: line)
        } catch {
            XCTFail("type d'erreur inattendu : \(error)", file: file, line: line)
        }
    }
}

// MARK: - Doubles du lot 3 (complétés par chaque tranche)

struct FakePushRegistration: PushRegistrationPort {
    func enregistrer(token: String, context: MissionReadContext) async throws {}
    func desactiver(token: String) async throws -> IssueDesactivationPush { .desactive(tokensDesactives: 1) }
}

struct FakeStripeConnect: StripeConnectPort {
    func statut(force: Bool, context: MissionReadContext) async throws -> StatutConnect {
        StatutConnect(statut: .nonDemande, onboardingComplete: false, chargesEnabled: false, payoutsEnabled: false)
    }
    func lienOnboarding(context: MissionReadContext) async throws -> ResultatLienConnect { .compteTest }
}
