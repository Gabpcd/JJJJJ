import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « copies des bulletins » (`Gateways.bulletins`), câblée par L4-T10.
    static func bulletins() -> BulletinsPort { DemoBulletinsGateway() }
}

extension DemoFixtures {
    /// `demo-copies-bulletins.json` (L4-T10, `scripts/mobile/demo-fixtures/bulletins.mjs`) : copies du compte démo au
    /// format exact de `fn_lister_copies_bulletins`, plus la description du PDF servi (`demo-copie.pdf`).
    public struct CopiesBulletinsFile: Decodable, Sendable {
        public struct PDF: Decodable, Sendable {
            public var fichier: String
            public var sha256: String
            public var tailleOctets: Int
            enum CodingKeys: String, CodingKey { case fichier, sha256, tailleOctets = "taille_octets" }
        }

        public var fixedNow: String
        public var pdf: PDF
        public var copies: ValeurJSON
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", pdf, copies }
    }

    public static func loadCopiesBulletins() throws -> CopiesBulletinsFile { try load("demo-copies-bulletins") }

    /// Octets du PDF de démonstration (`demo-copie.pdf`, généré par l'exporteur, jamais réécrit).
    public static func pdfDemo(fichier: String) throws -> Data {
        let nom = (fichier as NSString).deletingPathExtension
        guard (fichier as NSString).pathExtension == "pdf",
              let url = Bundle.module.url(forResource: nom, withExtension: "pdf", subdirectory: sousDossier)
                ?? Bundle.module.url(forResource: nom, withExtension: "pdf") else {
            throw JoleneError(.contract, "Fixture démo introuvable : \(fichier).")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw JoleneError(.contract, "Fixture démo illisible : \(fichier).")
        }
    }
}

/// Copies du compte démo : initialisées depuis la fixture au premier accès, en mémoire ensuite (signalements compris),
/// perdues au relancement, jamais envoyées.
actor DemoBulletinsStore {
    private var copies: [CopieBulletin]?

    var estInitialise: Bool { copies != nil }

    func initialiser(_ lignes: [CopieBulletin]) {
        guard copies == nil else { return }
        copies = lignes
    }

    func liste() -> [CopieBulletin] { copies ?? [] }

    func copie(_ id: String) -> CopieBulletin? { copies?.first { $0.id == id } }

    /// `fn_signaler_copie_bulletin` : signalement (une fois, `ON CONFLICT DO NOTHING`) ; `DESTINATAIRE` retire la copie.
    func signaler(_ id: String, motif: MotifSignalementCopie) {
        copies = copies?.map { copie in
            guard copie.id == id else { return copie }
            var signalee = copie
            signalee.signalee = true
            if motif == .destinataire { signalee.statut = .retiree }
            return signalee
        }
    }
}

/// Copies officielles du monde démo (L4-T10) : aucun réseau. Le PDF servi est toujours `demo-copie.pdf`, avec le type
/// `application/pdf` de l'edge ; il passe par la même vérification que les octets de l'edge (`BulletinsTelechargement`),
/// si bien que la copie au SHA-256 faux de la fixture est refusée comme elle le serait en production. Mêmes refus que le
/// serveur (copie inconnue : accès refusé ; `RETIREE` : 410 `COPIE_RETIREE`), relecture après chaque signalement ;
/// refuse tout contexte qui n'est pas celui du profil fictif.
public struct DemoBulletinsGateway: BulletinsPort {
    private let store = DemoBulletinsStore()
    private let initiales: [CopieBulletin]?

    /// `initiales` : copies de départ (tests) ; `nil` = fixture `demo-copies-bulletins.json`.
    public init(initiales: [CopieBulletin]? = nil) {
        self.initiales = initiales
    }

    public func copies(context: MissionReadContext) async throws -> [CopieBulletin] {
        try check(context)
        try await initialiser()
        return await store.liste()
    }

    public func telecharger(copie: CopieBulletin, context: MissionReadContext) async throws -> PDFVerifie {
        try check(context)
        try await initialiser()
        guard let actuelle = await store.copie(copie.id) else { throw RefusCopieBulletin.indisponible }
        guard CopieBulletinValidation.telechargeable(actuelle.statut) else { throw RefusCopieBulletin.retiree }
        let fichier = try DemoFixtures.loadCopiesBulletins().pdf.fichier
        let octets = try DemoFixtures.pdfDemo(fichier: fichier)
        // Vérifiée contre la ligne affichée, comme les octets de l'edge.
        return try BulletinsTelechargement.verifier(donnees: octets, typeContenu: BulletinsTelechargement.typePDF, copie: copie)
    }

    public func signaler(copieId: String, motif: MotifSignalementCopie,
                         context: MissionReadContext) async throws -> [CopieBulletin] {
        try check(context)
        try await initialiser()
        guard await store.copie(copieId) != nil else {
            throw JoleneError(.unknown, LibellesWeb.CopiesBulletins.signalementNonConfirme)
        }
        await store.signaler(copieId, motif: motif)
        return await store.liste()
    }

    // MARK: - Interne

    private func check(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }

    private func initialiser() async throws {
        guard await !store.estInitialise else { return }
        if let initiales {
            await store.initialiser(initiales)
            return
        }
        do {
            await store.initialiser(try CopieBulletinValidation.valider(try DemoFixtures.loadCopiesBulletins().copies))
        } catch is CopieBulletinValidation.ListeNonVerifiable {
            throw JoleneError(.contract, "Fixture démo illisible : demo-copies-bulletins.json.")
        }
    }
}
