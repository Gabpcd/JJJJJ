import Foundation

extension DemoFixtures {
    /// `demo-paiements-declares.json` (lot 3, T13) : lignes `paiements_soignant` du profil fictif (colonnes de
    /// `BandeauPaiementDeclare.tsx` l.97, plus `statut`, `confirme_par_soignant` et `conteste`, état initial du serveur
    /// simulé), missions (l.122), présences (l.132) et créneaux (l.137). Les déclarations sont celles de
    /// `demo-missions-terminees.json` (mêmes identifiants), si bien qu'une confirmation démo change aussi l'état de la
    /// mission dans l'onglet.
    public struct PaiementsDeclaresFile: Decodable, Sendable {
        public var fixedNow: String
        public var paiements: [LignePaiementDeclare]
        public var missions: [MissionPaiementDeclare]
        public var presences: [PresencePaiementDeclare]
        public var creneaux: [CreneauPaiementDeclare]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", paiements, missions, presences, creneaux }
    }

    public static func loadPaiementsDeclares() throws -> PaiementsDeclaresFile { try load("demo-paiements-declares") }
}

/// `PaiementsDeclaresPort` du monde démo (lot 3, T13), sans réseau : serveur simulé en mémoire (un acteur par
/// lancement), mêmes décodeurs, même assemblage et même règle de relecture que le monde Supabase
/// (`PaiementsDeclaresAssemblage`, `PaiementsDeclaresRelecture`). Les refus reprennent mot pour mot ceux des RPC
/// (`supabase/schema/public.sql`, `fn_confirmer_paiement_soignant` l.24548, `fn_contester_paiement_soignant` l.25741
/// d'après B3), dans leur ordre. Refuse tout contexte qui n'est pas celui du profil fictif (`.demoOnly`).
///
/// Variante de recette DEBUG `JOLENE_DEMO_PAIEMENTS=refus` (`DemoPaiementsTests`) : la première confirmation trouve le
/// paiement déjà confirmé ailleurs (le serveur répond « Paiement déjà confirmé » et la ligne est `CONFIRME`) ; toute
/// contestation trouve un litige déjà ouvert sur la mission (`LITIGE_DEJA_OUVERT`, aucune écriture).
public actor DemoPaiementsGateway: PaiementsDeclaresPort {
    public enum Scenario: String, Sendable {
        case normal
        case refus
    }

    public static let variableEnvironnement = "JOLENE_DEMO_PAIEMENTS"

    // Refus du serveur, verbatim (dump `supabase/schema/public.sql`).
    static let introuvable = "Paiement introuvable"                                   // source: public.sql:24565, :25771
    static let dejaConfirme = "Paiement déjà confirmé"                                // source: public.sql:24571, :25781
    static let dejaConteste = "Paiement déjà contesté"                                // source: public.sql:25778
    static let motifRequis = "Motif requis"                                           // source: public.sql:25758
    static let motifTropLong = "Motif trop long (500 caractères maximum)"             // source: public.sql:25761
    static let litigeDejaOuvert = "Un litige de ce type est déjà ouvert pour cette mission." // source: public.sql:25821
    static func statutConfirmation(_ statut: String) -> String {
        "Ce paiement ne peut plus être confirmé (statut: \(statut))"                  // source: public.sql:24576
    }
    static func statutContestation(_ statut: String) -> String {
        "Ce paiement ne peut plus être contesté (statut: \(statut))"                  // source: public.sql:25785
    }

    private let scenario: Scenario
    private var lignes: [LignePaiementDeclare]?
    private var litiges = 0
    private var confirmationsRefusees = 0

    public init(scenario: Scenario = .normal) {
        self.scenario = scenario
    }

    public func aConfirmer(context: MissionReadContext) async throws -> [PaiementDeclare] {
        try DemoRevenusGateway.verifier(context)
        let fichier = try DemoFixtures.loadPaiementsDeclares()
        let declares = try etat().filter { $0.statut == PaiementsDeclaresAssemblage.statutDeclare }
        guard !declares.isEmpty else { return [] }
        let missionIds = Set(declares.map(\.missionId))
        let noms = Dictionary(try DemoFixtures.loadEtablissements().etablissements.map { ($0.id, $0.nom) },
                              uniquingKeysWith: { premier, _ in premier })
        // `.order('pointage_arrivee_le', { ascending: true })` (NULLS LAST d'un ASC) ; `.order('debut', …)`.
        let presences = fichier.presences.filter { missionIds.contains($0.missionId) }.enumerated().sorted { a, b in
            switch (a.element.pointageArriveeLe, b.element.pointageArriveeLe) {
            case let (x?, y?) where x != y: return Self.instant(x) < Self.instant(y)
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.offset < b.offset
            }
        }.map(\.element)
        let creneaux = fichier.creneaux.filter { missionIds.contains($0.missionId) }.enumerated().sorted { a, b in
            let (x, y) = (Self.instant(a.element.debut), Self.instant(b.element.debut))
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
        return PaiementsDeclaresAssemblage.assembler(declares, etablissements: noms,
                                                     missions: fichier.missions.filter { missionIds.contains($0.id) },
                                                     presences: presences, creneaux: creneaux)
    }

    public func confirmer(id: String, context: MissionReadContext) async throws -> IssuePaiement {
        try DemoRevenusGateway.verifier(context)
        var lignes = try etat()
        guard let index = lignes.firstIndex(where: { $0.id == id }) else { return .refuse(message: Self.introuvable) }
        if scenario == .refus, confirmationsRefusees == 0 {
            // Confirmé ailleurs (web) avant ce tap : le serveur l'a déjà en `CONFIRME`.
            confirmationsRefusees += 1
            lignes[index].statut = PaiementsDeclaresAssemblage.statutConfirme
            lignes[index].confirmeParSoignant = true
            self.lignes = lignes
        }
        let ligne = lignes[index]
        if ligne.confirmeParSoignant == true { return .refuse(message: Self.dejaConfirme) }
        let statut = ligne.statut ?? ""
        guard ["DECLARE", "EN_ATTENTE"].contains(statut) else { return .refuse(message: Self.statutConfirmation(statut)) }
        lignes[index].statut = PaiementsDeclaresAssemblage.statutConfirme
        lignes[index].confirmeParSoignant = true
        self.lignes = lignes
        // `{success:true, …}` puis relecture de la ligne, comme le monde Supabase.
        return try PaiementsDeclaresRelecture.confirmation(relue: relire(id))
    }

    public func contester(id: String, motif: String, context: MissionReadContext) async throws -> IssuePaiement {
        try DemoRevenusGateway.verifier(context)
        // `btrim(COALESCE(p_motif, ''))` : espaces seulement (caractère par défaut de `btrim`).
        let nettoye = Self.btrim(motif)
        if nettoye.isEmpty { return .refuse(message: Self.motifRequis) }
        if nettoye.unicodeScalars.count > 500 { return .refuse(message: Self.motifTropLong) }
        var lignes = try etat()
        guard let index = lignes.firstIndex(where: { $0.id == id }) else { return .refuse(message: Self.introuvable) }
        let ligne = lignes[index]
        if ligne.statut == PaiementsDeclaresAssemblage.statutConteste || ligne.conteste == true {
            return .refuse(message: Self.dejaConteste)
        }
        if ligne.confirmeParSoignant == true { return .refuse(message: Self.dejaConfirme) }
        let statut = ligne.statut ?? ""
        guard ["DECLARE", "EN_ATTENTE"].contains(statut) else { return .refuse(message: Self.statutContestation(statut)) }
        // Litige `AUTRE` sans facture déjà ouvert sur la mission : sous-bloc annulé, aucune écriture.
        if scenario == .refus { return .refuse(message: Self.litigeDejaOuvert) }
        lignes[index].statut = PaiementsDeclaresAssemblage.statutConteste
        lignes[index].conteste = true
        self.lignes = lignes
        litiges += 1
        return try PaiementsDeclaresRelecture.contestation(relue: relire(id), litigeId: "demo-litige-\(litiges)")
    }

    /// Déclarations de l'onglet (`demo-missions-terminees.json`) mises à l'état du serveur simulé : une confirmation ou
    /// une contestation démo change l'état affiché de la mission (`DemoRevenusGateway`).
    public func surcharger(_ paiements: [PaiementSoignantLu]) -> [PaiementSoignantLu] {
        guard let lignes else { return paiements }
        let parId = Dictionary(lignes.map { ($0.id, $0) }, uniquingKeysWith: { premiere, _ in premiere })
        return paiements.map { lu in
            guard let ligne = parId[lu.id] else { return lu }
            var relu = lu
            relu.statut = ligne.statut
            relu.confirmeParSoignant = ligne.confirmeParSoignant
            relu.conteste = ligne.conteste
            return relu
        }
    }

    // MARK: - Interne

    private func etat() throws -> [LignePaiementDeclare] {
        if let lignes { return lignes }
        let initiales = try DemoFixtures.loadPaiementsDeclares().paiements
        lignes = initiales
        return initiales
    }

    private func relire(_ id: String) -> PaiementDeclare? {
        (lignes ?? []).first { $0.id == id }.map { PaiementsDeclaresAssemblage.paiement($0) }
    }

    private static func instant(_ valeur: String) -> Date {
        (try? DateHeureParis.instantJolene(valeur)) ?? .distantPast
    }

    private static func btrim(_ texte: String) -> String {
        var scalaires = Substring(texte)
        while scalaires.first == " " { scalaires.removeFirst() }
        while scalaires.last == " " { scalaires.removeLast() }
        return String(scalaires)
    }
}
