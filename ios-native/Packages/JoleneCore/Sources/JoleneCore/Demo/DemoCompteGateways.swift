import Foundation

extension DemoFixtures {
    /// `demo-export-rgpd.json` (exporté par `scripts/mobile/export-demo-fixtures.mjs`) : réponse de
    /// `fn_rgpd_exporter_rate_limited` du profil fictif, clés dans l'ordre d'un jsonb (longueur, puis octets),
    /// lue OCTET POUR OCTET (aucun réencodage : l'ordre des clés va jusqu'au fichier exporté).
    public static func donneesExportRGPD() throws -> Data {
        guard let url = url("demo-export-rgpd") else {
            throw JoleneError(.contract, "Fixture démo introuvable : demo-export-rgpd.json.")
        }
        return try Data(contentsOf: url)
    }
}

/// Mot de passe du compte démo, en mémoire pour la durée du jeu de ports (perdu au relancement).
actor DemoMotDePasseStore {
    private var actuel = DemoMotDePasseGateway.ancienDemo

    func changer(ancien: String, nouveau: String) -> ResultatMotDePasse {
        guard ancien == actuel else { return .ancienIncorrect }
        actuel = nouveau
        // Relecture après mutation : aucun succès fabriqué.
        return actuel == nouveau ? .modifie : .refuse(message: MotDePasse.Textes.erreurGenerique)
    }
}

/// `MotDePassePort` du monde démo (lot 3, T11 ; blueprint §2.7) : l'ancien mot de passe démo est
/// `demo-motdepasse` (distinct du mot de passe de connexion démo, que `DemoAuthGateway` n'examine pas) ; un
/// changement réussi le remplace en mémoire. Aucun réseau. Refuse tout autre contexte que le profil fictif.
public struct DemoMotDePasseGateway: MotDePassePort {
    public static let ancienDemo = "demo-motdepasse"
    private let store = DemoMotDePasseStore()

    public init() {}

    public func changer(ancien: String, nouveau: String, context: MissionReadContext) async throws -> ResultatMotDePasse {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
        return await store.changer(ancien: ancien, nouveau: nouveau)
    }
}

/// `ExportRGPDPort` du monde démo (lot 3, T11) : rend la fixture `demo-export-rgpd.json` telle quelle, lue
/// comme la réponse du serveur (`ExportRGPD.analyserReponse`). `refus` (DEBUG, variante de recette
/// `JOLENE_FORCE_EXPORT_ECHEC=1`) : refus `{error}` scripté, message serveur verbatim. Aucun réseau. Refuse tout
/// autre contexte que le profil fictif.
public struct DemoExportRGPDGateway: ExportRGPDPort {
    private let fixture: @Sendable () throws -> Data
    private let refus: String?

    public init(refus: String? = nil, fixture: @escaping @Sendable () throws -> Data = { try DemoFixtures.donneesExportRGPD() }) {
        self.refus = refus
        self.fixture = fixture
    }

    public func exporter(context: MissionReadContext) async throws -> ExportDonneesRGPD {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
        if let refus { throw JoleneError(.unknown, refus) }
        switch ExportRGPD.analyserReponse(try fixture()) {
        case .donnees(let donnees):
            return donnees
        case .refus(let message):
            throw JoleneError(.unknown, message ?? ExportRGPD.Textes.echec)
        case .illisible:
            throw JoleneError(.contract, "Fixture démo illisible : demo-export-rgpd.json.")
        }
    }
}
