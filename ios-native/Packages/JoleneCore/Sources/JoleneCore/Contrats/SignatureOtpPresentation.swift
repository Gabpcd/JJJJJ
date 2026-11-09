import Foundation

/// Zone « Votre signature » d'un contrat (lot 2, T9b ; `ContratMission.tsx` l.708-817) telle que l'écran la rend :
/// signature OTP native (décision 18), ou renvoi web vers `/contrat/:id` pour un compte TEST sans admission de
/// recette. Construite par `ContratModel.zoneSignature(maintenant:)` ; aucune règle ni aucun texte n'est écrit à
/// l'écran.
public enum ZoneSignature: Equatable, Sendable {
    case otp(SignatureOtpPresentation)
    /// Message du lot 0 (`MobileAccess.unsupportedRole`, repris tel quel comme pour les onglets DPAE de T7) et route
    /// web du contrat, présentée seulement quand un présentateur `.safari` est injecté (lot 1 T10).
    case renvoiWeb(message: String, route: JoleneRoute?)

    /// « Cet espace n'est pas encore disponible dans l'application. Rendez-vous sur jolene.app. » (lot 0) : aucun texte
    /// nouveau ; le web proposerait la signature manuscrite (`ContratMission.tsx` l.722-726), non portée (décision 18).
    public static var messageRenvoiWeb: String { MobileAccess.unsupportedRole(nil).message ?? "" }
}

/// Rendu de la session OTP (`SessionSignatureOtp`, T8) comme `SignerContratOtp.tsx` l.209-354 l'affiche :
/// confirmation d'une signature relue (l.209-221), indisponibilité sur une erreur bloquante du serveur qui ferme la
/// signature (l.223-235), sinon le formulaire (titre et explication l.239-248, alerte bloquante l.250-255, retour
/// l.257-264, suspension l.265, consentement l.267-278, envoi l.280-290, code envoyé l.292-351). Les conditions
/// d'activation sont celles des attributs `disabled` du web, lues dans la session (seule source) ; les textes viennent
/// de `TextesWeb.SignatureOtp` (HARD STOP n°4, verbatim) et de `LibellesWeb.SignatureOtp`. Le code saisi n'y figure
/// jamais : le champ le lit dans la session.
public struct SignatureOtpPresentation: Equatable, Sendable {
    /// Erreurs bloquantes qui remplacent le formulaire par « Signature non disponible pour le moment » et le message du
    /// serveur (l.223-225) ; toute autre erreur bloquante reste une alerte du formulaire (l.250-255).
    public static let codesIndisponibles: Set<String> = ["CONTRAT_INACTIF", "CONTRAT_DEJA_COMPLET", "DEJA_SIGNE"]

    public struct Bouton: Equatable, Sendable {
        public var libelle: String
        public var actif: Bool
        /// Infobulle du bouton (`title`, l.336), aussi lue par VoiceOver.
        public var infobulle: String?

        public init(libelle: String, actif: Bool, infobulle: String? = nil) {
            self.libelle = libelle; self.actif = actif; self.infobulle = infobulle
        }
    }

    /// Étape « code envoyé » (l.292-351).
    public struct CodeEnvoye: Equatable, Sendable {
        /// « Code envoyé au <numéro masqué> » (l.296).
        public var destinataire: String
        /// « (<n> envoi(s) restant(s)) » quand le serveur donne `sms_restants` (l.297-300).
        public var smsRestants: String?
        /// « mm:ss », « Expiré » à zéro (l.303-306).
        public var minuteur: String
        public var expire: Bool
        /// Champ du code (l.317).
        public var champActif: Bool
        /// Tentatives restantes après un code faux (l.322-328).
        public var tentatives: String?
        /// « Renvoyer le code » / « Recevoir un nouveau code » (l.332-340).
        public var renvoi: Bouton
        /// « Signer » (l.341-349).
        public var signer: Bouton
    }

    public struct Formulaire: Equatable, Sendable {
        public var titre: String
        public var explication: String
        /// Erreur bloquante (l.250-255), sans retour affiché.
        public var alerte: String?
        /// Annonce ou erreur (l.257-264), absente sous une erreur bloquante.
        public var retour: RetourOtp?
        /// « Vérification de la signature en cours… » pendant la relecture de l'admission de recette (l.265).
        public var suspension: String?
        public var consentement: String
        public var accepte: Bool
        public var consentementActif: Bool
        /// « Recevoir le code SMS pour signer », avant tout envoi (l.280-290).
        public var recevoir: Bouton?
        public var codeEnvoye: CodeEnvoye?
        /// Requête en vol : indicateur de chargement (l.287, l.347).
        public var enCours: Bool
    }

    public enum Mode: Equatable, Sendable {
        /// Signature acceptée et relue : confirmation (l.214, ou son repli) et mention (l.216).
        case signee(confirmation: String, mention: String)
        /// Titre (l.230) et message du serveur (l.231).
        case indisponible(titre: String, message: String)
        case formulaire(Formulaire)
    }

    public var mode: Mode

    /// - Parameters:
    ///   - nouvelEnvoiAutorise: compte réel, ou recette STAGING admise avec un envoi restant (`ContratMission.tsx` l.762).
    ///   - actionsSuspendues: relecture de l'admission de recette en cours (l.761).
    public init(session: SessionSignatureOtp, maintenant: Date, nouvelEnvoiAutorise: Bool, actionsSuspendues: Bool) {
        if session.etape == .signe {
            let confirmation: String
            if case .succes(let message)? = session.retour, !message.isEmpty { confirmation = message } else {
                confirmation = TextesWeb.SignatureOtp.contratSigne
            }
            mode = .signee(confirmation: confirmation, mention: TextesWeb.SignatureOtp.signeAvecSucces)
            return
        }
        if let bloquante = session.erreurBloquante, let code = bloquante.code, Self.codesIndisponibles.contains(code) {
            mode = .indisponible(titre: LibellesWeb.SignatureOtp.signatureNonDisponible, message: bloquante.message)
            return
        }
        let suspendu = actionsSuspendues
        let envoiPossible = !suspendu && session.peutEnvoyer(nouvelEnvoiAutorise: nouvelEnvoiAutorise)
        var formulaire = Formulaire(
            titre: TextesWeb.SignatureOtp.titre, explication: TextesWeb.SignatureOtp.explication,
            alerte: session.erreurBloquante?.message, retour: session.erreurBloquante == nil ? session.retour : nil,
            suspension: suspendu ? LibellesWeb.SignatureOtp.verificationSignatureEnCours : nil,
            consentement: TextesWeb.SignatureOtp.consentement, accepte: session.accepte, consentementActif: !suspendu,
            recevoir: nil, codeEnvoye: nil, enCours: session.operationEnCours)
        switch session.etape {
        case .idle:
            formulaire.recevoir = Bouton(libelle: TextesWeb.SignatureOtp.recevoirCode, actif: envoiPossible)
        case .otpEnvoye:
            let secondes = session.secondesRestantes(maintenant: maintenant)
            let expire = session.otpExpire(maintenant: maintenant)
            formulaire.codeEnvoye = CodeEnvoye(
                destinataire: LibellesWeb.SignatureOtp.codeEnvoyeAu(telephoneMasque: session.telephoneMasque),
                smsRestants: session.smsRestants.map(LibellesWeb.SignatureOtp.smsRestants(n:)),
                minuteur: LibellesWeb.SignatureOtp.minuteur(secondesRestantes: secondes),
                expire: expire,
                champActif: !suspendu && !expire,
                tentatives: session.tentativesRestantes.flatMap(TextesWeb.SignatureOtp.tentativesRestantes(n:)),
                renvoi: Bouton(libelle: LibellesWeb.SignatureOtp.renvoi(otpExpire: expire), actif: envoiPossible,
                               infobulle: LibellesWeb.SignatureOtp.infobulleRenvoi(nouvelEnvoiAutorise: nouvelEnvoiAutorise,
                                                                                  smsRestants: session.smsRestants)),
                signer: Bouton(libelle: TextesWeb.SignatureOtp.signer, actif: !suspendu && session.peutSigner(maintenant: maintenant)))
        case .signe:
            break
        }
        mode = .formulaire(formulaire)
    }
}
