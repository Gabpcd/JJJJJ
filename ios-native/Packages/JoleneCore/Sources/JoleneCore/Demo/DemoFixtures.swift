import Foundation

/// Lecture des fixtures JSON du monde démo (plan §4.6). Fichiers générés par
/// `scripts/mobile/export-demo-fixtures.mjs`, versionnés sous
/// `Resources/fixtures/` et embarqués dans `Bundle.module`.
public enum DemoFixtures {
    public static let sousDossier = "Resources/fixtures"

    /// Mission démo telle qu'exportée : la ligne `missions` plus ses créneaux (`creneaux`).
    public struct MissionFixture: Decodable, Equatable, Sendable {
        public var record: MissionRecord
        public var creneaux: [MissionSlot]

        enum CodingKeys: String, CodingKey { case creneaux }

        public init(record: MissionRecord, creneaux: [MissionSlot]) {
            self.record = record; self.creneaux = creneaux
        }

        public init(from decoder: Decoder) throws {
            record = try MissionRecord(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            creneaux = try container.decodeIfPresent([MissionSlot].self, forKey: .creneaux) ?? []
        }
    }

    public struct MissionsFile: Decodable, Sendable {
        public var fixedNow: String
        public var missions: [MissionFixture]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", missions }
    }

    public struct EtablissementsFile: Decodable, Sendable {
        public var fixedNow: String
        public var etablissements: [EtablissementSummary]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", etablissements }
    }

    public struct ProfileFile: Decodable, Sendable {
        public var fixedNow: String
        public var userId: String
        public var email: String?
        public var profile: SoignantProfile
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", userId = "user_id", email, profile }

        public var context: MissionReadContext {
            MissionReadContext(userId: userId, email: email, profile: profile)
        }
    }

    /// Lot 2, T8 : contrats démo (`demo-contrats.json`) ; les originaux « Storage » sont des fichiers HTML à part,
    /// octets rendus par le moteur serveur (`originalDemo(fichier:)`).
    public struct ContratsFile: Decodable, Sendable {
        public struct Original: Decodable, Equatable, Sendable {
            public var contratId: String
            public var storagePath: String
            public var fichier: String
            enum CodingKeys: String, CodingKey { case contratId = "contrat_id", storagePath = "storage_path", fichier }
        }

        public var fixedNow: String
        public var contrats: [ContratDetail]
        public var missions: [MissionContrat]
        public var originaux: [Original]
        public var signatures: [SignatureCertificat]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", contrats, missions, originaux, signatures }
    }

    public static func loadContrats() throws -> ContratsFile { try load("demo-contrats") }

    /// Octets d'un original démo (`demo-contrat-00N.html`), jamais réécrits.
    public static func originalDemo(fichier: String) throws -> Data {
        let nom = (fichier as NSString).deletingPathExtension
        guard (fichier as NSString).pathExtension == "html",
              let url = Bundle.module.url(forResource: nom, withExtension: "html", subdirectory: sousDossier)
                ?? Bundle.module.url(forResource: nom, withExtension: "html") else {
            throw JoleneError(.contract, "Fixture démo introuvable : \(fichier).")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw JoleneError(.contract, "Fixture démo illisible : \(fichier).")
        }
    }

    public static func loadMissions() throws -> MissionsFile { try load("demo-missions") }
    public static func loadEtablissements() throws -> EtablissementsFile { try load("demo-etablissements") }
    public static func loadProfile() throws -> ProfileFile { try load("demo-profile") }

    static func url(_ nom: String) -> URL? {
        Bundle.module.url(forResource: nom, withExtension: "json", subdirectory: sousDossier)
            ?? Bundle.module.url(forResource: nom, withExtension: "json")
    }

    static func load<T: Decodable>(_ nom: String) throws -> T {
        guard let url = url(nom) else {
            throw JoleneError(.contract, "Fixture démo introuvable : \(nom).json.")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as JoleneError {
            throw error
        } catch {
            throw JoleneError(.contract, "Fixture démo illisible : \(nom).json.")
        }
    }
}
