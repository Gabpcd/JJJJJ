import Foundation

/// Clé de la session de signature (`SignerContratOtp.tsx` l.62-63 : `${contratId}:${hashDocument}:${documentPret}`) :
/// le consentement et le code ne valent que pour la révision affichée.
public struct CleSessionOtp: Equatable, Sendable {
    public var contratId: String
    public var empreinte: String?
    public var documentPret: Bool

    public init(contratId: String, empreinte: String?, documentPret: Bool) {
        self.contratId = contratId; self.empreinte = empreinte; self.documentPret = documentPret
    }
}

/// Requête autorisée par la session, à transmettre au port puis à rendre avec sa réponse : une réponse dont la
/// demande n'est plus la demande en cours (autre clé, autre essai) est ignorée.
public struct DemandeOtp: Equatable, Sendable {
    public enum Nature: Equatable, Sendable {
        case envoi
        /// Code de six chiffres, jamais journalisé.
        case signature(code: String)
    }

    public var nature: Nature
    public var contratId: String
    public var empreinte: String
    let jeton: Int
}

/// Refus qui bloque tout nouvel envoi et toute signature (`erreurBloquante`, l.83, l.115-124).
public struct ErreurBloquanteOtp: Equatable, Sendable {
    public var code: String?
    public var message: String

    public init(code: String?, message: String) {
        self.code = code; self.message = message
    }
}

/// Retour affiché sous le titre (`retour`, l.73) : annonce ou erreur non bloquante.
public enum RetourOtp: Equatable, Sendable {
    case succes(String)
    case erreur(String)
}

/// Session de signature OTP, port de `SessionSignatureOtp` (`SignerContratOtp.tsx` l.66-207) en machine d'états pure
/// (`idle → otp_envoye → signe`). Le minuteur est dérivé de l'échéance du code (10 min), jamais décompté ni stocké
/// ailleurs. Une seule opération à la fois (`operationEnCours`, l.68) ; un changement de clé remet tout à zéro, y
/// compris le consentement, et rend caduque toute réponse en vol (l.62-63 : nouvelle instance du composant).
/// Messages : `TextesWeb.SignatureOtp` et `LibellesWeb.SignatureOtp` (TL), jamais un texte nouveau.
public struct SessionSignatureOtp: Equatable, Sendable {
    public enum Etape: String, Equatable, Sendable {
        case idle
        case otpEnvoye = "otp_envoye"
        case signe
    }

    /// `OTP_DUREE_SEC` (l.28).
    public static let dureeOtpSecondes = 10 * 60

    public private(set) var cle: CleSessionOtp
    public private(set) var etape: Etape = .idle
    public private(set) var accepte = false
    /// Code saisi : chiffres seulement, six au plus (l.315). Jamais journalisé.
    public private(set) var code = ""
    public private(set) var telephoneMasque: String?
    public private(set) var smsRestants: Int?
    public private(set) var tentativesRestantes: Int?
    public private(set) var echeanceOtp: Date?
    public private(set) var retour: RetourOtp?
    public private(set) var erreurBloquante: ErreurBloquanteOtp?
    public private(set) var operationEnCours = false
    public private(set) var contratComplet: Bool?
    /// Numéro de l'opération en cours ; incrémenté à chaque demande et à chaque changement de clé.
    private var jeton = 0

    public init(cle: CleSessionOtp) {
        self.cle = cle
    }

    // MARK: - Saisie

    /// Nouvelle clé : session vierge (consentement décoché, code effacé, réponse en vol ignorée). Même clé : rien.
    public mutating func changerCle(_ nouvelle: CleSessionOtp) {
        guard nouvelle != cle else { return }
        let suivant = jeton + 1
        self = SessionSignatureOtp(cle: nouvelle)
        jeton = suivant
    }

    public mutating func accepter(_ valeur: Bool) {
        accepte = valeur
    }

    /// `value.replace(/\D/g, '').slice(0, 6)` (l.315), chiffres ASCII seulement.
    public mutating func saisir(_ texte: String) {
        let chiffres = texte.unicodeScalars.filter { ("0"..."9").contains($0) }.prefix(6)
        code = String(chiffres.map { Character($0) })
    }

    // MARK: - Minuteur (dérivé)

    /// Secondes restantes `max(0, ceil((échéance − maintenant) / 1 s))` (l.81, l.103-104) ; 0 sans code envoyé.
    public func secondesRestantes(maintenant: Date) -> Int {
        guard let echeanceOtp else { return 0 }
        let restant = echeanceOtp.timeIntervalSince(maintenant)
        return restant > 0 ? Int(restant.rounded(.up)) : 0
    }

    /// `otpExpire` (l.109) : code envoyé dont le minuteur est à zéro.
    public func otpExpire(maintenant: Date) -> Bool {
        etape == .otpEnvoye && secondesRestantes(maintenant: maintenant) == 0
    }

    // MARK: - Envoi du code

    /// Bouton « Recevoir le code » / « Renvoyer le code » actif (l.284, l.335).
    public func peutEnvoyer(nouvelEnvoiAutorise: Bool = true) -> Bool {
        nouvelEnvoiAutorise && cle.documentPret && !(cle.empreinte ?? "").isEmpty && accepte && !operationEnCours
            && erreurBloquante == nil && etape != .signe && !(etape == .otpEnvoye && smsRestants == 0)
    }

    /// Garde de `envoyerOtp` (l.128) : `nil` si l'envoi n'est pas permis (aucune requête). Sinon l'opération démarre.
    public mutating func demanderEnvoi(nouvelEnvoiAutorise: Bool = true) -> DemandeOtp? {
        guard peutEnvoyer(nouvelEnvoiAutorise: nouvelEnvoiAutorise), let empreinte = cle.empreinte else { return nil }
        jeton += 1
        operationEnCours = true
        retour = nil
        tentativesRestantes = nil
        erreurBloquante = nil
        return DemandeOtp(nature: .envoi, contratId: cle.contratId, empreinte: empreinte, jeton: jeton)
    }

    /// Réponse du serveur à l'envoi (l.139-153) ; `false` si elle concerne une demande caduque (ignorée).
    @discardableResult
    public mutating func terminerEnvoi(_ issue: IssueEnvoiOtp, demande: DemandeOtp, maintenant: Date) -> Bool {
        guard enCours(demande) else { return false }
        operationEnCours = false
        switch issue {
        case .envoye(let envoi):
            telephoneMasque = envoi.telephoneMasque
            smsRestants = envoi.smsRestants
            echeanceOtp = maintenant.addingTimeInterval(TimeInterval(Self.dureeOtpSecondes))
            code = ""
            etape = .otpEnvoye
            // « Code envoyé au <telephone_masked>. Valide <expire_dans_minutes> min. » (l.151) ; sans valeur serveur,
            // « numéro masqué » (l.296) et la durée du minuteur (l.145).
            let numero = envoi.telephoneMasque.flatMap { $0.isEmpty ? nil : $0 } ?? LibellesWeb.SignatureOtp.numeroMasque
            retour = .succes(LibellesWeb.SignatureOtp.codeEnvoye(telephoneMasque: numero,
                                                                  minutes: envoi.expireDansMinutes ?? Self.dureeOtpSecondes / 60))
        case .refuse(let code, let message, let bloquant):
            appliquerRefus(code: code, message: message, bloquant: bloquant)
        }
        return true
    }

    /// Erreur de transport à l'envoi (l.154-156) : message de l'erreur, sinon « Erreur réseau. Réessayez. ».
    public mutating func echouerEnvoi(message: String?, demande: DemandeOtp) {
        guard enCours(demande) else { return }
        operationEnCours = false
        retour = .erreur(message.flatMap { $0.isEmpty ? nil : $0 } ?? LibellesWeb.SignatureOtp.erreurReseauEnvoi)
    }

    // MARK: - Signature

    /// Bouton « Signer » actif (l.344).
    public func peutSigner(maintenant: Date) -> Bool {
        etape == .otpEnvoye && cle.documentPret && !(cle.empreinte ?? "").isEmpty && accepte && code.count == 6
            && !operationEnCours && !otpExpire(maintenant: maintenant) && erreurBloquante == nil
    }

    /// Garde de `signer` (l.164-173) : `nil` sans requête ; code incomplet ou consentement retiré → erreur affichée.
    public mutating func demanderSignature(maintenant: Date) -> DemandeOtp? {
        guard etape == .otpEnvoye, cle.documentPret, let empreinte = cle.empreinte, !empreinte.isEmpty, !operationEnCours,
              erreurBloquante == nil, !otpExpire(maintenant: maintenant) else { return nil }
        guard code.count == 6 else {
            retour = .erreur(LibellesWeb.SignatureOtp.codeSixChiffresRequis)
            return nil
        }
        guard accepte else {
            retour = .erreur(TextesWeb.SignatureOtp.consentementRequis)
            return nil
        }
        jeton += 1
        operationEnCours = true
        retour = nil
        return DemandeOtp(nature: .signature(code: code), contratId: cle.contratId, empreinte: empreinte, jeton: jeton)
    }

    /// Réponse relue de la signature (l.186-199) ; ignorée si la demande est caduque.
    public mutating func terminerSignature(_ issue: IssueSignature, demande: DemandeOtp) {
        guard enCours(demande) else { return }
        operationEnCours = false
        switch issue {
        case .signee(let complet):
            etape = .signe
            contratComplet = complet
            retour = .succes(TextesWeb.SignatureOtp.confirmationSignature(contratComplet: complet))
        case .refuse(let code, let message, let restantes):
            appliquerRefus(code: code, message: message,
                           bloquant: code.map { TextesWeb.SignatureOtp.codesBloquants.contains($0) } ?? false)
            if let restantes { tentativesRestantes = restantes }
        }
    }

    /// Erreur de transport à la signature (l.200-202), après la relecture de la gateway.
    public mutating func echouerSignature(message: String?, demande: DemandeOtp) {
        guard enCours(demande) else { return }
        operationEnCours = false
        retour = .erreur(message.flatMap { $0.isEmpty ? nil : $0 } ?? LibellesWeb.SignatureOtp.erreurReseauSignature)
    }

    // MARK: - Recette STAGING

    /// Code encore valable relu par l'admission de recette (`otpCourantExpireA`, l.74, l.85-98) : à l'étape d'envoi,
    /// reprend le code jusqu'à son échéance ; sans code valable, retour à l'envoi (consentement et code effacés).
    public mutating func reprendre(otpExpireLe: Date?, maintenant: Date) {
        guard let otpExpireLe, otpExpireLe > maintenant else {
            echeanceOtp = nil
            code = ""
            accepte = false
            if etape != .signe { etape = .idle }
            return
        }
        echeanceOtp = otpExpireLe
        if etape == .idle { etape = .otpEnvoye }
    }

    // MARK: - Interne

    private func enCours(_ demande: DemandeOtp) -> Bool {
        operationEnCours && demande.jeton == jeton && demande.contratId == cle.contratId && demande.empreinte == cle.empreinte
    }

    /// `gererErreur` (l.112-125) : bloquant → alerte ; sinon retour d'erreur.
    private mutating func appliquerRefus(code: String?, message: String, bloquant: Bool) {
        if bloquant {
            erreurBloquante = ErreurBloquanteOtp(code: code, message: message)
        } else {
            retour = .erreur(message)
        }
    }
}
