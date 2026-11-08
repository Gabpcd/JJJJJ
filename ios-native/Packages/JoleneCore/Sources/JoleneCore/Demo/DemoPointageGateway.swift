import Foundation

/// Pointage du monde démo (blueprint lot 2 §2.8, tranche T3), sur `demo-presences.json` : aucun réseau, horloge fixée,
/// profil fictif seulement (`.demoOnly` pour tout autre utilisateur).
///
/// Comme le serveur (`fn_scanner_code_pointage`) : le code affiché désigne la mission ; une OUVERTURE ouvre un segment
/// EFFECTIF, une FERMETURE ferme le segment ouvert ; `nb_scans` et `prochain_type_scan` en découlent ; une ligne de
/// preuve (`PreuveScan`) est ajoutée ; puis le code tourne. Le nouveau code reste interne (jamais rendu, jamais saisissable :
/// il n'a pas six chiffres). Codes de démonstration : `100001` → refus `P0002` du code inconnu, `100002` → anti-rejeu
/// `23514` (87 secondes) ; scénario `scan-incertain` (`-JOLENE_DEMO_SCENARIO`, lu par `AppContainer` en T4b) : le premier
/// scan est appliqué puis sa réponse est perdue (`.incertain`), la réconciliation le retrouve par relecture.
public actor DemoPointageGateway: PointagePort {
    /// Valeurs de `-JOLENE_DEMO_SCENARIO` qui concernent le pointage.
    public enum Scenario: String, CaseIterable, Sendable {
        case normal
        case scanIncertain = "scan-incertain"
    }

    public static let codeInconnuDemo = "100001"
    public static let codeAntiRejeuDemo = "100002"
    /// Message serveur de l'anti-rejeu (`public.sql` l.55662), délai figé à 87 s pour la démo (blueprint §2.8).
    public static let messageAntiRejeuDemo = "Scan déjà pris en compte. Prochain scan possible dans 87 secondes."
    /// Messages serveur verbatim de `fn_relancer_validation_presence` (`public.sql` l.53052, l.53071 ; tutoyés côté
    /// serveur, repris tels quels : décision 9 du lot 1).
    public static let messageRelanceEnvoyee = "Établissement relancé. Il a été notifié de valider tes présences."
    public static let messageDejaRelance = "Tu as déjà relancé cet établissement aujourd'hui. Il a été notifié."
    /// Message serveur de `fn_etat_pointage_mission` pour une mission inconnue (`public.sql` l.35162).
    public static let messageMissionIntrouvable = "Mission introuvable"

    /// Fichier `demo-presences.json` (`scripts/mobile/export-demo-fixtures.mjs`, `buildDemoPresences`).
    public struct Fixture: Decodable, Sendable {
        public var fixedNow: String
        public var consentementGps: Bool?
        public var missions: [MissionPresenceLue]
        public var presencesValidees: [PresenceLue]
        public var historique: [PresenceLue]
        public var missionsHistorique: [MissionPresenceLue]
        public var creneaux: [MissionSlot]
        public var contrats: [ContratPointage]
        public var codesAffiches: [String: String]

        enum CodingKeys: String, CodingKey {
            case missions, historique, creneaux, contrats
            case fixedNow = "fixed_now"
            case consentementGps = "consentement_gps"
            case presencesValidees = "presences_validees"
            case missionsHistorique = "missions_historique"
            case codesAffiches = "codes_affiches"
        }

        public static func charger() throws -> Fixture { try DemoFixtures.load("demo-presences") }
    }

    private struct Monde {
        var fixture: Fixture
        var etablissements: [String: EtablissementSummary]
        var statuts: [String: String]
        var creneaux: [MissionSlot]
        var preuves: [String: [PreuveScan]]
        var codes: [String: String]
        var consentement: Bool?
    }

    private let clock: any ClockPort
    private var scenario: Scenario
    private var monde: Monde?
    private var rotations = 0
    private var relances: Set<String> = []
    /// Métadonnées reçues par les scans appliqués (preuve de T4b : aucune coordonnée quand le GPS est refusé).
    public private(set) var metadonneesRecues: [MetadonneesScan] = []

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), scenario: Scenario = .normal) {
        self.clock = clock
        self.scenario = scenario
    }

    // MARK: - PointagePort

    public func presences(context: MissionReadContext) async throws -> InstantanePresences {
        try verifier(context)
        let m = try charger()
        let missions = m.fixture.missions.map { mission -> MissionPresenceLue in
            var lue = mission
            lue.statut = m.statuts[mission.id] ?? mission.statut
            return lue
        }
        return InstantanePresences(missions: missions, presencesValidees: m.fixture.presencesValidees,
                                   historique: m.fixture.historique, missionsHistorique: m.fixture.missionsHistorique,
                                   creneaux: m.creneaux, contrats: m.fixture.contrats, etablissements: m.etablissements,
                                   chargeLe: clock.now())
    }

    public func etat(missionId: String, context: MissionReadContext) async throws -> EtatPointage {
        try verifier(context)
        let m = try charger()
        guard let etat = Self.etat(missionId, m) else { throw JoleneError(.unknown, Self.messageMissionIntrouvable) }
        return etat
    }

    public func consentementGps(context: MissionReadContext) async throws -> Bool? {
        try verifier(context)
        return try charger().consentement
    }

    public func enregistrerConsentementGps(_ accepte: Bool, context: MissionReadContext) async throws -> Bool {
        try verifier(context)
        _ = try charger()
        monde?.consentement = accepte
        // Relecture : la valeur rendue est celle du monde, jamais l'hypothèse de l'appelant.
        guard let relu = monde?.consentement else { throw JoleneError(.unknown, DemoWorld.messageDemoSeulement) }
        return relu
    }

    public func scanner(code: String, metadonnees: MetadonneesScan, recu: RecuScan,
                        context: MissionReadContext) async throws -> IssueScan {
        try verifier(context)
        guard recu.phase == .started, recu.userId == context.userId else {
            throw JoleneError(.contract, DemoWorld.messageDemoSeulement)
        }
        var m = try charger()
        if code == Self.codeAntiRejeuDemo { return .refuse(sqlstate: "23514", message: Self.messageAntiRejeuDemo) }
        guard code != Self.codeInconnuDemo,
              let missionId = m.codes.first(where: { $0.value == code })?.key,
              let etat = Self.etat(missionId, m), let type = etat.prochainTypeScan else {
            return .refuse(sqlstate: "P0002", message: PointageRules.messageServeurCodeInvalide)
        }
        let maintenant = DateHeureParis.isoUTC(clock.now())
        let numero = (etat.nbScans ?? 0) + 1
        switch type {
        case .ouverture:
            m.creneaux.append(MissionSlot(id: "\(missionId)-effectif-\(numero)", missionId: missionId, debut: maintenant,
                                          fin: nil, estPause: false, typeCreneau: "EFFECTIF"))
            m.statuts[missionId] = "EN_COURS"
        case .fermeture:
            guard let index = m.creneaux.lastIndex(where: { Self.estSegmentOuvert($0, missionId) }) else {
                return .refuse(sqlstate: "P0002", message: "Aucun créneau effectif ouvert à fermer.")
            }
            m.creneaux[index].fin = maintenant
        }
        m.preuves[missionId, default: []].append(PreuveScan(id: "demo-scan-\(missionId)-\(numero)", missionId: missionId,
                                                            numeroScan: numero, typeScan: type, scanneLe: maintenant,
                                                            idTerminal: metadonnees.idTerminal,
                                                            precisionGpsM: metadonnees.precisionGpsM))
        rotations += 1
        m.codes[missionId] = "rotation-\(rotations)"
        monde = m
        metadonneesRecues.append(metadonnees)
        if scenario == .scanIncertain {
            scenario = .normal
            return .incertain
        }
        // Relecture, comme la gateway Supabase : la preuve doit appartenir à la mission du reçu.
        guard case let .recu(preuve) = try recu.reconcilier(scans: m.preuves[recu.missionId] ?? [], relueLe: clock.now()),
              preuve.numeroScan == numero else { return .incertain }
        return .enregistre(typeScan: type, numeroScan: numero)
    }

    public func reconcilier(recu: RecuScan, context: MissionReadContext) async throws -> IssueScan {
        try verifier(context)
        let m = try charger()
        return IssueScan(reconciliation: try recu.reconcilier(scans: m.preuves[recu.missionId] ?? [], relueLe: clock.now()))
    }

    public func preuvesScan(missionId: String, context: MissionReadContext) async throws -> [PreuveScan] {
        try verifier(context)
        return try charger().preuves[missionId] ?? []
    }

    public func detail(missionId: String, context: MissionReadContext) async throws -> DetailPresences {
        try verifier(context)
        let m = try charger()
        let creneaux = m.creneaux.filter { $0.missionId == missionId }
        guard !creneaux.isEmpty || m.statuts[missionId] != nil else { return DetailPresences(missionId: missionId) }
        let pointe = creneaux.contains { $0.typeCreneau == "EFFECTIF" && !$0.estPause }
        return DetailPresences(missionId: missionId, creneaux: creneaux, resume: ResumePresencesServeur(pointageEffectue: pointe))
    }

    public func relancerValidation(missionId: String, context: MissionReadContext) async throws -> IssueRelance {
        try verifier(context)
        guard relances.insert(missionId).inserted else { return .refusee(message: Self.messageDejaRelance) }
        return .envoyee(message: Self.messageRelanceEnvoyee)
    }

    // MARK: - Monde

    private func verifier(_ context: MissionReadContext) throws {
        guard context.userId == DemoWorld.context.userId else { throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement) }
    }

    private func charger() throws -> Monde {
        if let monde { return monde }
        let fixture = try Fixture.charger()
        let etablissements = Dictionary(try DemoFixtures.loadEtablissements().etablissements.map { ($0.id, $0) },
                                        uniquingKeysWith: { premier, _ in premier })
        var statuts: [String: String] = [:]
        for mission in fixture.missions + fixture.missionsHistorique { statuts[mission.id] = mission.statut }
        var preuves: [String: [PreuveScan]] = [:]
        // Preuves des segments déjà pointés (une OUVERTURE, puis une FERMETURE si le segment est fermé).
        for mission in fixture.missions {
            let segments = fixture.creneaux.filter { $0.missionId == mission.id && $0.typeCreneau == "EFFECTIF" && !$0.estPause }
            var numero = 0
            for segment in segments {
                for (type, instant) in [(TypeScan.ouverture, Optional(segment.debut)), (.fermeture, segment.fin)] {
                    guard let instant else { continue }
                    numero += 1
                    preuves[mission.id, default: []].append(PreuveScan(id: "demo-scan-\(mission.id)-\(numero)", missionId: mission.id,
                                                                       numeroScan: numero, typeScan: type, scanneLe: instant,
                                                                       idTerminal: DemoTerminalIdentity.identifiantDemo,
                                                                       precisionGpsM: DemoLocationPort.precisionDemoM))
                }
            }
        }
        let nouveau = Monde(fixture: fixture, etablissements: etablissements, statuts: statuts, creneaux: fixture.creneaux,
                            preuves: preuves, codes: fixture.codesAffiches, consentement: fixture.consentementGps)
        monde = nouveau
        return nouveau
    }

    private static func estSegmentOuvert(_ creneau: MissionSlot, _ missionId: String) -> Bool {
        creneau.missionId == missionId && creneau.typeCreneau == "EFFECTIF" && !creneau.estPause && (creneau.fin ?? "").isEmpty
    }

    /// État dérivé du monde, forme de `fn_etat_pointage_mission` (`public.sql` l.35180-35190) : segments EFFECTIF
    /// par début, un scan par ouverture et par fermeture. Le code n'y figure jamais (nul pour le soignant).
    private static func etat(_ missionId: String, _ m: Monde) -> EtatPointage? {
        guard let mission = m.fixture.missions.first(where: { $0.id == missionId }) else { return nil }
        let effectifs = m.creneaux.filter { $0.missionId == missionId && $0.typeCreneau == "EFFECTIF" && !$0.estPause }
        let segments = DisponibilitePointage.triStable(effectifs, croissant: true) { DisponibilitePointage.temps($0.debut) }
            .map { SegmentPointage(id: $0.id ?? "", debut: $0.debut, fin: ($0.fin ?? "").isEmpty ? nil : $0.fin) }
        let ouvert = segments.contains { $0.fin == nil }
        let nbScans = segments.reduce(0) { $0 + ($1.fin == nil ? 1 : 2) }
        return EtatPointage(statut: m.statuts[missionId] ?? mission.statut, intitule: mission.intitule,
                            prochainTypeScan: ouvert ? .fermeture : .ouverture, nbScans: nbScans, segmentOuvert: ouvert,
                            segments: segments)
    }
}
