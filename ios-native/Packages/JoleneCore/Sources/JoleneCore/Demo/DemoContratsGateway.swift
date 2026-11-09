import Foundation

/// Scénario des contrats démo (`-JOLENE_DEMO_SCENARIO`, argument DEBUG lu par `AppContainer`, T9b).
public enum ScenarioDemoContrats: Equatable, Sendable {
    case nominal
    /// Tout code saisi est refusé `OTP_EXPIRE` (`LOT2_PLAN.md` §2.8).
    case otpExpire
    /// Le soignant démo est un compte TEST (`soignants.est_compte_test`), sans admission de recette (aucune en démo,
    /// comme en production) : la signature est un renvoi web (décision 18, T9b).
    case compteTest

    public static let argument = "-JOLENE_DEMO_SCENARIO"

    public init(argument: String?) {
        switch argument {
        case "otp-expire": self = .otpExpire
        case "compte-test": self = .compteTest
        default: self = .nominal
        }
    }

    /// Valeur qui suit `-JOLENE_DEMO_SCENARIO` ; celle d'un autre domaine (`scan-incertain`, `upload-incertain`) ou
    /// absente : `.nominal`.
    public init(arguments: [String]) {
        self.init(argument: ArgumentsDemo.valeur(Self.argument, dans: arguments))
    }
}

/// Contrats du monde démo (`LOT2_PLAN.md` §2.8) : fixtures de `scripts/mobile/export-demo-fixtures.mjs`
/// (`demo-contrats.json`, originaux `demo-contrat-00N.html` rendus par le moteur serveur), horloge fixée, aucun
/// réseau. Même contrôle de l'original que le monde Supabase (`VerificationOriginal`) ; OTP du pilote
/// (`contracts/demoFixture.ts` l.4) : `000000` accepté, tout autre code refusé `OTP_INCORRECT` (cinq essais), refus
/// et ordre des contrôles de `fn_envoyer_otp_signature` / `fn_signer_contrat_otp`, messages du web
/// (`TextesWeb.SignatureOtp.message`). Chaque instance repart des fixtures ; tout autre compte est refusé
/// (`.demoOnly`) : la démo n'est jamais un repli pour un compte réel.
public struct DemoContratsGateway: ContratsPort {
    /// Numéro masqué au format du serveur (`regexp_replace(v_telephone, '\d(?=\d{2})', '*', 'g')`, l.33289),
    /// d'un numéro fictif.
    public static let telephoneMasque = "+**********00"
    static let codeAccepte = "000000"
    static let maxSms = 3
    static let maxTentatives = 5

    private let etat: EtatDemoContrats
    private let clock: any ClockPort

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), scenario: ScenarioDemoContrats = .nominal,
                fixtures: @escaping @Sendable () throws -> DemoFixtures.ContratsFile = { try DemoFixtures.loadContrats() }) {
        self.clock = clock
        self.etat = EtatDemoContrats(scenario: scenario, charger: fixtures)
    }

    public func contrats(context: MissionReadContext) async throws -> [ContratResume] {
        try verifier(context)
        return try await etat.liste()
    }

    public func contrat(id: String, context: MissionReadContext) async throws -> ContratDetail {
        try verifier(context)
        return try await etat.detail(id: id)
    }

    public func original(contrat: ContratDetail, context: MissionReadContext) async throws -> OriginalContrat {
        try verifier(context)
        if ContratRules.cddSansOriginal(contrat) { throw ContratOriginalIndisponible(motif: .cddAPreparer) }
        if let motif = VerificationOriginal.motifAvantStorage(contrat) { throw ContratOriginalIndisponible(motif: motif) }
        let (octets, signatures) = try await etat.objetStorage(contratId: contrat.id, chemin: contrat.storagePath ?? "")
        return try VerificationOriginal.verifier(contrat, octetsStorage: octets, signatures: signatures)
    }

    public func admissionRecette(contratId: String, context: MissionReadContext) async throws -> AdmissionSignatureRecette? {
        try verifier(context)
        return nil
    }

    public func envoyerOtp(contratId: String, empreinte: String, context: MissionReadContext) async throws -> IssueEnvoiOtp {
        try verifier(context)
        return try await etat.envoyer(contratId: contratId, empreinte: empreinte)
    }

    public func signer(contratId: String, code: String, empreinte: String, context: MissionReadContext) async throws -> IssueSignature {
        try verifier(context)
        return try await etat.signer(contratId: contratId, code: code, empreinte: empreinte, maintenant: clock.now())
    }

    public func certificat(contratId: String, context: MissionReadContext) async throws -> [SignatureCertificat] {
        try verifier(context)
        return try await etat.certificat(contratId: contratId)
    }

    public func fichierOriginal(contrat: OriginalContrat, context: MissionReadContext) async throws -> URL {
        try verifier(context)
        return try FichierContratTemporaire.ecrire(contrat)
    }

    private func verifier(_ context: MissionReadContext) throws {
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}

/// État mutable des contrats démo (signatures, OTP) : un acteur par gateway.
actor EtatDemoContrats {
    private struct Otp {
        var envoyes = 0
        var tentatives = 0
        var demande = false
    }

    private let scenario: ScenarioDemoContrats
    private let charger: @Sendable () throws -> DemoFixtures.ContratsFile
    private var fichier: DemoFixtures.ContratsFile?
    private var otp: [String: Otp] = [:]

    init(scenario: ScenarioDemoContrats, charger: @escaping @Sendable () throws -> DemoFixtures.ContratsFile) {
        self.scenario = scenario
        self.charger = charger
    }

    private func donnees() throws -> DemoFixtures.ContratsFile {
        if let fichier { return fichier }
        let lu = try charger()
        fichier = lu
        return lu
    }

    func liste() throws -> [ContratResume] {
        let f = try donnees()
        return f.contrats.sorted { ($0.creeLe ?? "") > ($1.creeLe ?? "") }.map { c in
            let mission = f.missions.first { $0.id == c.missionId }
            return ContratResume(id: c.id, missionId: c.missionId, statut: c.statut, typeContrat: c.typeContrat, creeLe: c.creeLe,
                                 numeroContrat: c.numeroContrat, soignantId: c.soignantId, etablissementId: c.etablissementId,
                                 signatureSoignant: c.signatureSoignant, signatureEtablissement: c.signatureEtablissement,
                                 mission: MissionResumeContrat(intitule: mission?.intitule, debutLe: mission?.debutLe, finLe: mission?.finLe))
        }
    }

    func detail(id: String) throws -> ContratDetail {
        let f = try donnees()
        guard var contrat = f.contrats.first(where: { $0.id == id }) else {
            throw JoleneError(.unknown, MessagesContrats.indisponible)
        }
        let missionId = contrat.missionId
        let etablissementId = contrat.etablissementId
        contrat.mission = f.missions.first { $0.id == missionId }
        let etablissements = (try? DemoFixtures.loadEtablissements().etablissements) ?? []
        contrat.etablissementNom = etablissements.first { $0.id == etablissementId }?.nom
        contrat.estCompteTest = scenario == .compteTest
        return contrat
    }

    func objetStorage(contratId: String, chemin: String) throws -> (Data, [SignatureCertificat]) {
        let f = try donnees()
        guard let reference = f.originaux.first(where: { $0.contratId == contratId && $0.storagePath == chemin }) else {
            throw ContratOriginalIndisponible(motif: .storageMismatch)
        }
        return (try DemoFixtures.originalDemo(fichier: reference.fichier), f.signatures.filter { $0.contratId == contratId })
    }

    func certificat(contratId: String) throws -> [SignatureCertificat] {
        try donnees().signatures.filter { $0.contratId == contratId }.sorted { ($0.creeLe ?? "") < ($1.creeLe ?? "") }
    }

    /// Ordre des refus de `fn_envoyer_otp_signature` (l.33120-33220) utiles à la démo.
    func envoyer(contratId: String, empreinte: String) throws -> IssueEnvoiOtp {
        let contrat = try detail(id: contratId)
        if ["ANNULE", "EXPIRE"].contains(contrat.statut) { return refusEnvoi("CONTRAT_INACTIF") }
        if contrat.statut == "SIGNE_COMPLET" { return refusEnvoi("CONTRAT_DEJA_COMPLET") }
        if contrat.signatureSoignant == true { return refusEnvoi("DEJA_SIGNE") }
        var etatOtp = otp[contratId] ?? Otp()
        guard etatOtp.envoyes < DemoContratsGateway.maxSms else { return refusEnvoi("TROP_DE_SMS") }
        etatOtp.envoyes += 1
        etatOtp.tentatives = 0
        etatOtp.demande = true
        otp[contratId] = etatOtp
        return .envoye(OtpEnvoye(role: "soignant", telephoneMasque: DemoContratsGateway.telephoneMasque, expireDansMinutes: 10,
                                 smsEnvoyes: etatOtp.envoyes, smsRestants: max(0, DemoContratsGateway.maxSms - etatOtp.envoyes)))
    }

    /// Ordre des refus de `fn_signer_contrat_otp` (l.56505-56565) ; succès : signature soignant enregistrée et relisible.
    func signer(contratId: String, code: String, empreinte: String, maintenant: Date) throws -> IssueSignature {
        let contrat = try detail(id: contratId)
        if ["ANNULE", "EXPIRE"].contains(contrat.statut) { return refusSignature("CONTRAT_INACTIF") }
        guard var etatOtp = otp[contratId], etatOtp.demande else { return refusSignature("OTP_NON_DEMANDE") }
        if contrat.signatureSoignant == true { return refusSignature("DEJA_SIGNE") }
        if etatOtp.tentatives >= DemoContratsGateway.maxTentatives { return refusSignature("TROP_DE_TENTATIVES") }
        if scenario == .otpExpire { return refusSignature("OTP_EXPIRE") }
        guard code == DemoContratsGateway.codeAccepte else {
            etatOtp.tentatives += 1
            otp[contratId] = etatOtp
            return refusSignature("OTP_INCORRECT", tentativesRestantes: DemoContratsGateway.maxTentatives - etatOtp.tentatives)
        }
        guard empreinte == contrat.hashDocument else { return refusSignature("HASH_DOCUMENT_CHANGE") }
        try enregistrerSignature(contratId: contratId, empreinte: empreinte, maintenant: maintenant)
        let relu = try detail(id: contratId)
        return .signee(contratComplet: relu.signatureSoignant == true && relu.signatureEtablissement == true)
    }

    private func enregistrerSignature(contratId: String, empreinte: String, maintenant: Date) throws {
        var f = try donnees()
        guard let index = f.contrats.firstIndex(where: { $0.id == contratId }) else { return }
        let horodatage = DateHeureParis.isoUTC(maintenant)
        f.contrats[index].signatureSoignant = true
        f.contrats[index].signatureSoignantLe = horodatage
        f.contrats[index].statut = f.contrats[index].signatureEtablissement == true ? "SIGNE_COMPLET" : "SIGNE_SOIGNANT"
        f.signatures.append(SignatureCertificat(
            id: "demo-signature-\(contratId)-soignant", contratId: contratId, signataireUserId: DemoWorld.context.userId,
            signataireRole: "soignant", signeA: horodatage, ipSignature: nil, userAgent: nil, hashDocument: empreinte,
            otpValideA: horodatage, pscSessionActive: false, rppsVerifie: false, traitsIdentiteVerifies: false,
            statutSignature: "signe", creeLe: horodatage))
        fichier = f
    }

    private func refusEnvoi(_ code: String) -> IssueEnvoiOtp {
        .refuse(code: code, message: TextesWeb.SignatureOtp.message(code: code, erreurServeur: nil, repli: LibellesWeb.SignatureOtp.repliEnvoi),
                bloquant: TextesWeb.SignatureOtp.codesBloquants.contains(code))
    }

    private func refusSignature(_ code: String, tentativesRestantes: Int? = nil) -> IssueSignature {
        .refuse(code: code, message: TextesWeb.SignatureOtp.message(code: code, erreurServeur: nil,
                                                                   repli: LibellesWeb.SignatureOtp.repliSignature),
                tentativesRestantes: tentativesRestantes)
    }
}
