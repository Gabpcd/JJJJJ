import Foundation

/// Contrats de l'établissement démo (lot 5, T10 ; `LOT5_PLAN.md` §2.10, §3 T10) : fixture `demo-etab-contrats.json`
/// (`scripts/mobile/demo-etab-contrats.mjs` : contrats **dérivés** des missions M4 et M5 de l'établissement démo,
/// originaux rendus par le moteur serveur comme ceux du lot 2), horloge fixée, aucun réseau. Servis par le port des
/// contrats du monde démo (`DemoContratsGateway`, extension ci-dessous) sous un `EtablissementReadContext`.
///
/// Mêmes règles que le monde Supabase : contexte cohérent, compte fictif seulement (`.demoOnly`), permission
/// `contrats` servie (§2.7, sinon `RefusAccesEtablissement`), contrat de l'établissement confirmé seulement ; triple
/// contrôle de l'original (`VerificationOriginal`) à la lecture, **avant tout envoi de code et avant la signature** ;
/// OTP démo du lot 2 (`000000` accepté, tout autre code refusé `OTP_INCORRECT`, cinq essais, trois envois) ; refus dans
/// l'ordre de `fn_envoyer_otp_signature` et `fn_signer_contrat_otp`, messages du web (`TextesWeb.SignatureOtp.message`).
/// La signature démo pose `signature_etablissement` et `signature_etablissement_le` (horloge démo), relus avant tout
/// succès. Le numéro masqué est fictif, au format du serveur ; aucun numéro complet n'existe en démo.
///
/// Scénarios (`-JOLENE_DEMO_SCENARIO`) : `cdd-a-preparer` sert le contrat à signer sans original (CDD à préparer par
/// l'employeur : renvoi web) ; `compte-test` marque l'établissement démo comme compte TEST (signature renvoyée au web,
/// aucune admission de recette en démo) ; `otp-expire` refuse tout code `OTP_EXPIRE`.
public struct DemoEtabContratsGateway: Sendable {
    /// Contrat que l'établissement démo signe (mission M5 « Contrat à signer »).
    public static let contratASigner = "demo-etab-contrat-m05"
    /// Contrat signé par les deux parties (mission M4).
    public static let contratSigne = "demo-etab-contrat-m04"

    private let etat: EtatDemoEtabContrats
    private let clock: any ClockPort

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), scenario: ScenarioDemoContrats = .nominal,
                fixtures: @escaping @Sendable () throws -> DemoFixtures.ContratsFile = { try DemoFixtures.loadEtabContrats() }) {
        self.clock = clock
        self.etat = EtatDemoEtabContrats(scenario: scenario, charger: fixtures)
    }

    func contrats(context: EtablissementReadContext) async throws -> [ContratResume] {
        try verifier(context)
        return try await etat.liste(etablissementId: context.etablissementId)
    }

    func contrat(id: String, context: EtablissementReadContext) async throws -> ContratDetail {
        try verifier(context)
        return try await etat.detail(id: id, etablissementId: context.etablissementId)
    }

    func original(contrat: ContratDetail, context: EtablissementReadContext) async throws -> OriginalContrat {
        try verifier(context)
        return try await etat.original(contratId: contrat.id, etablissementId: context.etablissementId)
    }

    func admissionRecette(contratId: String, context: EtablissementReadContext) async throws -> AdmissionSignatureRecette? {
        try verifier(context)
        return nil
    }

    func envoyerOtp(contratId: String, empreinte: String, context: EtablissementReadContext) async throws -> IssueEnvoiOtp {
        try verifier(context)
        return try await etat.envoyer(contratId: contratId, empreinte: empreinte, etablissementId: context.etablissementId)
    }

    func signer(contratId: String, code: String, empreinte: String, context: EtablissementReadContext) async throws -> IssueSignature {
        try verifier(context)
        return try await etat.signer(contratId: contratId, code: code, empreinte: empreinte, userId: context.userId,
                                     etablissementId: context.etablissementId, maintenant: clock.now())
    }

    func certificat(contratId: String, context: EtablissementReadContext) async throws -> [SignatureCertificat] {
        try verifier(context)
        return try await etat.certificat(contratId: contratId, etablissementId: context.etablissementId)
    }

    func fichierOriginal(contrat: OriginalContrat, context: EtablissementReadContext) async throws -> URL {
        try verifier(context)
        return try FichierContratTemporaire.ecrire(contrat)
    }

    /// Contexte cohérent et compte fictif (`DemoEtablissementWorld`), puis permission `contrats` servie.
    private func verifier(_ context: EtablissementReadContext) throws {
        try DemoEtablissementWorld.verifier(context)
        try ContratsEtablissement.verifier(context)
    }
}

/// Méthodes établissement du port des contrats dans le monde démo (lot 5, T10) : `Gateways.contrats` reste un seul
/// port ; la moitié établissement est servie par `DemoEtabContratsGateway`.
extension DemoContratsGateway {
    public func contratsEtablissement(context: EtablissementReadContext) async throws -> [ContratResume] {
        try await etablissement.contrats(context: context)
    }

    public func contrat(id: String, etab: EtablissementReadContext) async throws -> ContratDetail {
        try await etablissement.contrat(id: id, context: etab)
    }

    public func original(contrat: ContratDetail, etab: EtablissementReadContext) async throws -> OriginalContrat {
        try await etablissement.original(contrat: contrat, context: etab)
    }

    public func admissionRecette(contratId: String, etab: EtablissementReadContext) async throws -> AdmissionSignatureRecette? {
        try await etablissement.admissionRecette(contratId: contratId, context: etab)
    }

    public func envoyerOtp(contratId: String, empreinte: String, etab: EtablissementReadContext) async throws -> IssueEnvoiOtp {
        try await etablissement.envoyerOtp(contratId: contratId, empreinte: empreinte, context: etab)
    }

    public func signer(contratId: String, code: String, empreinte: String,
                       etab: EtablissementReadContext) async throws -> IssueSignature {
        try await etablissement.signer(contratId: contratId, code: code, empreinte: empreinte, context: etab)
    }

    public func certificat(contratId: String, etab: EtablissementReadContext) async throws -> [SignatureCertificat] {
        try await etablissement.certificat(contratId: contratId, context: etab)
    }

    public func fichierOriginal(contrat: OriginalContrat, etab: EtablissementReadContext) async throws -> URL {
        try await etablissement.fichierOriginal(contrat: contrat, context: etab)
    }
}

/// État mutable des contrats de l'établissement démo (signature, OTP) : un acteur par gateway, remis à zéro à chaque
/// lancement (aucun stockage).
actor EtatDemoEtabContrats {
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

    /// Fixture lue une fois ; `cdd-a-preparer` retire l'original du contrat à signer (CDD à préparer par l'employeur).
    private func donnees() throws -> DemoFixtures.ContratsFile {
        if let fichier { return fichier }
        var lu = try charger()
        if scenario == .cddAPreparer, let index = lu.contrats.firstIndex(where: { $0.id == DemoEtabContratsGateway.contratASigner }) {
            lu.contrats[index].contenuHtml = nil
            lu.contrats[index].hashDocument = nil
            lu.contrats[index].storagePath = nil
            lu.contrats[index].contenuHtmlRenduLe = nil
            lu.originaux.removeAll { $0.contratId == DemoEtabContratsGateway.contratASigner }
        }
        fichier = lu
        return lu
    }

    func liste(etablissementId: String) throws -> [ContratResume] {
        let f = try donnees()
        return f.contrats.filter { $0.etablissementId == etablissementId }.sorted { ($0.creeLe ?? "") > ($1.creeLe ?? "") }.map { c in
            let mission = f.missions.first { $0.id == c.missionId }
            return ContratResume(id: c.id, missionId: c.missionId, statut: c.statut, typeContrat: c.typeContrat, creeLe: c.creeLe,
                                 numeroContrat: c.numeroContrat, soignantId: c.soignantId, etablissementId: c.etablissementId,
                                 signatureSoignant: c.signatureSoignant, signatureEtablissement: c.signatureEtablissement,
                                 mission: MissionResumeContrat(intitule: mission?.intitule, debutLe: mission?.debutLe, finLe: mission?.finLe))
        }
    }

    /// Contrat de l'établissement confirmé seulement ; aucun contexte de mission ni montant (D15), compte TEST selon
    /// le scénario (`etablissements.est_compte_test`).
    func detail(id: String, etablissementId: String) throws -> ContratDetail {
        guard var contrat = try donnees().contrats.first(where: { $0.id == id && $0.etablissementId == etablissementId }) else {
            throw JoleneError(.unknown, MessagesContrats.indisponible)
        }
        contrat.estCompteTest = scenario == .compteTest
        return contrat
    }

    func certificat(contratId: String, etablissementId: String) throws -> [SignatureCertificat] {
        _ = try detail(id: contratId, etablissementId: etablissementId)
        return try donnees().signatures.filter { $0.contratId == contratId }.sorted { ($0.creeLe ?? "") < ($1.creeLe ?? "") }
    }

    /// Triple contrôle de l'original sur l'état courant du contrat (jamais sur une copie reçue de l'écran).
    func original(contratId: String, etablissementId: String) throws -> OriginalContrat {
        let contrat = try detail(id: contratId, etablissementId: etablissementId)
        if ContratRules.cddSansOriginal(contrat) { throw ContratOriginalIndisponible(motif: .cddAPreparer) }
        if let motif = VerificationOriginal.motifAvantStorage(contrat) { throw ContratOriginalIndisponible(motif: motif) }
        let f = try donnees()
        guard let reference = f.originaux.first(where: { $0.contratId == contratId && $0.storagePath == contrat.storagePath }) else {
            throw ContratOriginalIndisponible(motif: .storageMismatch)
        }
        return try VerificationOriginal.verifier(contrat, octetsStorage: try DemoFixtures.originalDemo(fichier: reference.fichier),
                                                 signatures: f.signatures.filter { $0.contratId == contratId })
    }

    /// L'original relu par le triple contrôle porte-t-il l'empreinte affichée ? Tout refus du contrôle vaut « non ».
    private func originalIdentique(contratId: String, empreinte: String, etablissementId: String) throws -> Bool {
        do {
            return try original(contratId: contratId, etablissementId: etablissementId).empreinte == empreinte
        } catch is ContratOriginalIndisponible {
            return false
        }
    }

    /// Triple contrôle, puis refus dans l'ordre de `fn_envoyer_otp_signature` (branche `etablissement`).
    func envoyer(contratId: String, empreinte: String, etablissementId: String) throws -> IssueEnvoiOtp {
        let contrat = try detail(id: contratId, etablissementId: etablissementId)
        guard try originalIdentique(contratId: contratId, empreinte: empreinte, etablissementId: etablissementId) else {
            return ContratsEtablissement.refusEnvoiOriginalChange
        }
        if ["ANNULE", "EXPIRE"].contains(contrat.statut) { return refusEnvoi("CONTRAT_INACTIF") }
        if contrat.statut == "SIGNE_COMPLET" { return refusEnvoi("CONTRAT_DEJA_COMPLET") }
        if contrat.signatureEtablissement == true { return refusEnvoi("DEJA_SIGNE") }
        var etatOtp = otp[contratId] ?? Otp()
        guard etatOtp.envoyes < DemoContratsGateway.maxSms else { return refusEnvoi("TROP_DE_SMS") }
        etatOtp.envoyes += 1
        etatOtp.tentatives = 0
        etatOtp.demande = true
        otp[contratId] = etatOtp
        return .envoye(OtpEnvoye(role: PartieContrat.etablissement.rawValue, telephoneMasque: DemoContratsGateway.telephoneMasque,
                                 expireDansMinutes: 10, smsEnvoyes: etatOtp.envoyes,
                                 smsRestants: max(0, DemoContratsGateway.maxSms - etatOtp.envoyes)))
    }

    /// Triple contrôle, puis refus dans l'ordre de `fn_signer_contrat_otp` ; succès : signature de l'établissement
    /// enregistrée, puis **relue** (`signature_etablissement_le` non nul) avant d'être annoncée.
    func signer(contratId: String, code: String, empreinte: String, userId: String, etablissementId: String,
                maintenant: Date) throws -> IssueSignature {
        let contrat = try detail(id: contratId, etablissementId: etablissementId)
        guard try originalIdentique(contratId: contratId, empreinte: empreinte, etablissementId: etablissementId) else {
            return ContratsEtablissement.refusSignatureOriginalChange
        }
        if ["ANNULE", "EXPIRE"].contains(contrat.statut) { return refusSignature("CONTRAT_INACTIF") }
        guard var etatOtp = otp[contratId], etatOtp.demande else { return refusSignature("OTP_NON_DEMANDE") }
        if contrat.signatureEtablissement == true { return refusSignature("DEJA_SIGNE") }
        if etatOtp.tentatives >= DemoContratsGateway.maxTentatives { return refusSignature("TROP_DE_TENTATIVES") }
        if scenario == .otpExpire { return refusSignature("OTP_EXPIRE") }
        guard code == DemoContratsGateway.codeAccepte else {
            etatOtp.tentatives += 1
            otp[contratId] = etatOtp
            return refusSignature("OTP_INCORRECT", tentativesRestantes: DemoContratsGateway.maxTentatives - etatOtp.tentatives)
        }
        try enregistrerSignature(contratId: contratId, empreinte: empreinte, userId: userId, maintenant: maintenant)
        let relu = try detail(id: contratId, etablissementId: etablissementId)
        guard relu.signatureEtablissement == true, !(relu.signatureEtablissementLe ?? "").isEmpty else {
            throw JoleneError(.unknown, MessagesContrats.indisponible)
        }
        return .signee(contratComplet: relu.statut == "SIGNE_COMPLET" || relu.signatureSoignant == true)
    }

    private func enregistrerSignature(contratId: String, empreinte: String, userId: String, maintenant: Date) throws {
        var f = try donnees()
        guard let index = f.contrats.firstIndex(where: { $0.id == contratId }) else { return }
        let horodatage = DateHeureParis.isoUTC(maintenant)
        f.contrats[index].signatureEtablissement = true
        f.contrats[index].signatureEtablissementLe = horodatage
        f.contrats[index].statut = f.contrats[index].signatureSoignant == true ? "SIGNE_COMPLET" : "SIGNE_ETABLISSEMENT"
        f.signatures.append(SignatureCertificat(
            id: "demo-etab-signature-\(contratId)", contratId: contratId, signataireUserId: userId,
            signataireRole: PartieContrat.etablissement.rawValue, signeA: horodatage, ipSignature: nil, userAgent: nil,
            hashDocument: empreinte, otpValideA: horodatage, pscSessionActive: false, rppsVerifie: false,
            traitsIdentiteVerifies: false, statutSignature: "signe", creeLe: horodatage))
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

public extension DemoFixtures {
    /// `demo-etab-contrats.json` (lot 5, T10) : même forme que `demo-contrats.json`, originaux `demo-etab-contrat-*.html`.
    static func loadEtabContrats() throws -> ContratsFile { try load("demo-etab-contrats") }
}
