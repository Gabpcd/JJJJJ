import Foundation

// Libellés non juridiques des écrans du lot 2 (tranche TL, docs/mobile-swift/LOT2_PLAN.md §3 « TL »),
// HORS HARD STOP n°4 : boutons de navigation, états d'envoi, erreurs génériques ou réseau, compteurs,
// minuteurs, en-têtes. Les textes juridiques et de consentement des mêmes composants sont dans
// `Legal/TextesWeb.swift` (HARD STOP, validation de Gabrielle).
//
// Même machinerie que TextesWeb : chaque constante est le texte EXACT que le web affiche à la ligne
// annoncée (`// source: fichier:ligne`, sans nature : tout ici est libellé), prouvé par la garde
// tests/node/textes-juridiques-ios.node.mjs. Un texte qui porte une marque juridique (code, RGPD,
// attestation, consentement, signature électronique, preuve…) est refusé ici et va dans TextesWeb.
// Chaque fonction d'assemblage est ancrée sur son code web (scripts/mobile/textes-web-ios-rendus.json)
// et ses rendus sont assertés par LibellesWebTests. Retoucher un libellé ici suit le web, sans PR
// HARD STOP.

/// Libellés non juridiques des écrans du lot 2. Les écrans les lisent ici, jamais dans un littéral local.
public enum LibellesWeb {
    /// Relance de l'établissement depuis le détail des présences (`DetailPresencesMission.tsx`
    /// l.115-124, l.699-701). Titre et explication : `TextesWeb.Presences`.
    public enum Presences {
        // source: src/pages/DetailPresencesMission.tsx:700
        public static let relancer = "Relancer l'établissement"

        // source: src/pages/DetailPresencesMission.tsx:700
        public static let relanceEnvoi = "Envoi…"

        // source: src/pages/DetailPresencesMission.tsx:122
        public static let relanceSucces = "Établissement relancé."

        // source: src/pages/DetailPresencesMission.tsx:123
        public static let relanceImpossible = "Relance impossible."

        /// Retour de `fn_relancer_validation_presence` (l.121-123) : en succès `message ?? repli`,
        /// sinon `message ?? error ?? repli` (`??` : seul un message absent est remplacé). Une erreur
        /// PostgREST (l.120) affiche son message serveur tel quel, hors de cette fonction.
        public static func messageRelance(succes: Bool, message: String?, erreur: String?) -> String {
            succes ? (message ?? relanceSucces) : (message ?? erreur ?? relanceImpossible)
        }
    }

    /// Panneau de contestation (`PanneauContestation.tsx`) : en-tête (l.262) et formulaire
    /// d'ouverture (l.361-392). Libellés de statut : `TextesWeb.Contestation`. Aucun texte de délai
    /// (Q9, en attente de Gabrielle).
    public enum Contestation {
        // source: src/components/PanneauContestation.tsx:262
        public static let titre = "Contestation"

        // source: src/components/PanneauContestation.tsx:366
        public static let contester = "Contester cette présence"

        // source: src/components/PanneauContestation.tsx:376
        public static let placeholderSoignant = "Les heures validées ne correspondent pas à ma présence réelle…"

        // source: src/components/PanneauContestation.tsx:387
        public static let envoi = "Envoi…"

        // source: src/components/PanneauContestation.tsx:387
        public static let envoyer = "Envoyer la contestation"

        // source: src/components/PanneauContestation.tsx:390
        public static let annuler = "Annuler"
    }

    /// Attestation de santé (`DocumentsSoignant.tsx`) : badge, état d'envoi, erreur. Textes de
    /// l'attestation et bouton qui l'accomplit : `TextesWeb.AttestationSante`.
    public enum AttestationSante {
        // source: src/pages/DocumentsSoignant.tsx:78
        public static let signee = "Signée"

        // source: src/pages/DocumentsSoignant.tsx:127
        public static let signatureEnCours = "Signature en cours…"

        // source: src/pages/DocumentsSoignant.tsx:52
        public static let erreurSignature = "Erreur lors de la signature. Veuillez réessayer."
    }

    /// Signature OTP SMS (`SignerContratOtp.tsx`) : erreurs génériques, envoi du code, minuteur,
    /// SMS restants, renvoi. Textes juridiques, consentement, bouton « Signer », confirmation et
    /// tentatives : `TextesWeb.SignatureOtp`.
    public enum SignatureOtp {
        // source: src/components/SignerContratOtp.tsx:48
        public static let messageParDefaut = "Une erreur est survenue. Réessayez."

        /// Repli de l'envoi du code quand ni le code ni le serveur ne donnent de message.
        // source: src/components/SignerContratOtp.tsx:140
        public static let repliEnvoi = "Erreur envoi OTP"

        /// Repli de la signature quand ni le code ni le serveur ne donnent de message.
        // source: src/components/SignerContratOtp.tsx:188
        public static let repliSignature = "Erreur de signature"

        // source: src/components/SignerContratOtp.tsx:167
        public static let codeSixChiffresRequis = "Code à 6 chiffres requis."

        // source: src/components/SignerContratOtp.tsx:230
        public static let signatureNonDisponible = "Signature non disponible pour le moment"

        /// Envoi du code accepté (l.149-152) : voir `codeEnvoye(telephoneMasque:minutes:)`.
        // source: src/components/SignerContratOtp.tsx:151
        public static let codeEnvoyePrefixe = "Code envoyé au"

        // source: src/components/SignerContratOtp.tsx:151
        public static let codeEnvoyeValide = ". Valide"

        // source: src/components/SignerContratOtp.tsx:151
        public static let codeEnvoyeMinutes = "min."

        /// Erreur réseau sans message lisible, à l'envoi du code (l.156) et à la signature (l.202).
        // source: src/components/SignerContratOtp.tsx:156
        public static let erreurReseauEnvoi = "Erreur réseau. Réessayez."

        // source: src/components/SignerContratOtp.tsx:202
        public static let erreurReseauSignature = "Erreur réseau. Réessayez."

        // source: src/components/SignerContratOtp.tsx:265
        public static let verificationSignatureEnCours = "Vérification de la signature en cours…"

        /// Rappel au-dessus du champ (l.296-300) : voir `codeEnvoyeAu(telephoneMasque:)` et `smsRestants(n:)`.
        // source: src/components/SignerContratOtp.tsx:296
        public static let codeEnvoyeAuLibelle = "Code envoyé au"

        // source: src/components/SignerContratOtp.tsx:296
        public static let numeroMasque = "numéro masqué"

        // source: src/components/SignerContratOtp.tsx:299
        public static let smsParentheseOuvrante = "("

        // source: src/components/SignerContratOtp.tsx:299
        public static let smsDernierEnvoi = "dernier envoi possible"

        // source: src/components/SignerContratOtp.tsx:299
        public static let smsEnvoiMot = "envoi"

        // source: src/components/SignerContratOtp.tsx:299
        public static let smsPlurielEnvoi = "s"

        // source: src/components/SignerContratOtp.tsx:299
        public static let smsRestantMot = "restant"

        // source: src/components/SignerContratOtp.tsx:299
        public static let smsPlurielRestant = "s"

        // source: src/components/SignerContratOtp.tsx:299
        public static let smsParentheseFermante = ")"

        // source: src/components/SignerContratOtp.tsx:110
        public static let minuteurSeparateur = ":"

        // source: src/components/SignerContratOtp.tsx:305
        public static let minuteurExpire = "Expiré"

        /// Libellé d'accessibilité du champ du code (`aria-label`).
        // source: src/components/SignerContratOtp.tsx:319
        public static let champCodeAccessibilite = "Code SMS à 6 chiffres"

        /// Infobulles du bouton de renvoi désactivé (l.336) : voir `infobulleRenvoi(nouvelEnvoiAutorise:smsRestants:)`.
        // source: src/components/SignerContratOtp.tsx:336
        public static let renvoiNonAutoriseRecette = "Aucun nouvel envoi autorisé pour cette recette"

        // source: src/components/SignerContratOtp.tsx:336
        public static let plafondSmsAtteint = "3 SMS max par 24h atteints"

        // source: src/components/SignerContratOtp.tsx:339
        public static let recevoirNouveauCode = "Recevoir un nouveau code"

        // source: src/components/SignerContratOtp.tsx:339
        public static let renvoyerCode = "Renvoyer le code"

        /// « Code envoyé au <numéro>. Valide <n> min. » (l.151), tel que le gabarit du web l'assemble.
        public static func codeEnvoye(telephoneMasque: String, minutes: Int) -> String {
            codeEnvoyePrefixe + " " + telephoneMasque + codeEnvoyeValide + " " + String(minutes) + " " + codeEnvoyeMinutes
        }

        /// « Code envoyé au <numéro> » (l.296), « numéro masqué » si le serveur n'en donne pas.
        public static func codeEnvoyeAu(telephoneMasque: String?) -> String {
            let numero = telephoneMasque.flatMap { $0.isEmpty ? nil : $0 } ?? numeroMasque
            return codeEnvoyeAuLibelle + " " + numero
        }

        /// SMS encore possibles (l.297-300), affichés quand le serveur donne `sms_restants` :
        /// « (dernier envoi possible) » à 0 — formulation du web, alors qu'à 0 le bouton de renvoi
        /// est désactivé (l.335-336) —, sinon « (<n> envoi(s) restant(s)) », pluriel au-delà de 1.
        public static func smsRestants(n: Int) -> String {
            let detail = n == 0 ? smsDernierEnvoi
                : String(n) + " " + smsEnvoiMot + (n > 1 ? smsPlurielEnvoi : "") + " "
                    + smsRestantMot + (n > 1 ? smsPlurielRestant : "")
            return smsParentheseOuvrante + detail + smsParentheseFermante
        }

        /// Minuteur de validité du code (l.109-110, l.305) : « mm:ss », « Expiré » à zéro.
        public static func minuteur(secondesRestantes: Int) -> String {
            guard secondesRestantes > 0 else { return minuteurExpire }
            return LibellesWeb.deuxChiffres(secondesRestantes / 60) + minuteurSeparateur
                + LibellesWeb.deuxChiffres(secondesRestantes % 60)
        }

        /// Bouton de renvoi (l.339) : « Recevoir un nouveau code » une fois le code expiré.
        public static func renvoi(otpExpire: Bool) -> String {
            otpExpire ? recevoirNouveauCode : renvoyerCode
        }

        /// Infobulle du bouton de renvoi (l.336) : recette STAGING sans nouvel envoi autorisé, puis
        /// plafond de SMS atteint (`sms_restants` à 0) ; aucune sinon.
        public static func infobulleRenvoi(nouvelEnvoiAutorise: Bool, smsRestants: Int?) -> String? {
            if !nouvelEnvoiAutorise { return renvoiNonAutoriseRecette }
            return smsRestants == 0 ? plafondSmsAtteint : nil
        }
    }

    /// Durée restante du compte à rebours de signature (`Countdown72hSignature.tsx` l.49-51, l.72).
    /// Textes du compte à rebours : `TextesWeb.CompteARebours`.
    public enum CompteARebours {
        // source: src/components/Countdown72hSignature.tsx:72
        public static let uniteHeures = "h"

        // source: src/components/Countdown72hSignature.tsx:72
        public static let uniteMinutes = "m"

        // source: src/components/Countdown72hSignature.tsx:72
        public static let uniteSecondes = "s"

        /// Durée restante « <h>h <mm>m <ss>s » (l.49-51, l.72), minutes et secondes sur deux chiffres.
        public static func duree(restantSecondes: Int) -> String {
            let heures = restantSecondes / 3600
            let minutes = (restantSecondes % 3600) / 60
            let secondes = restantSecondes % 60
            return String(heures) + uniteHeures + " " + LibellesWeb.deuxChiffres(minutes) + uniteMinutes + " "
                + LibellesWeb.deuxChiffres(secondes) + uniteSecondes
        }
    }

    /// En-tête de la page `/contrat/:id/certificat` (`CertificatSignaturePage.tsx` l.186). Titre,
    /// certificat et empreinte : `TextesWeb.Certificat`.
    public enum Certificat {
        // source: src/pages/CertificatSignaturePage.tsx:186
        public static let contratPrefixe = "Contrat"

        /// « Contrat <numéro> » (`contrat.numero_contrat || contrat.id`, l.186).
        public static func contrat(numero: String?, id: String) -> String {
            contratPrefixe + " " + (numero.flatMap { $0.isEmpty ? nil : $0 } ?? id)
        }
    }

    /// `String(valeur).padStart(2, '0')` du web (minuteurs ; valeur positive ou nulle).
    static func deuxChiffres(_ valeur: Int) -> String {
        valeur < 10 ? String(0) + String(valeur) : String(valeur)
    }

    /// Tous les libellés, pour les tests (la garde Node vérifie que la liste est complète et exacte).
    public static let catalogue: [EntreeTexteWeb] = [
        .init(cle: "Presences.relancer", texte: Presences.relancer),
        .init(cle: "Presences.relanceEnvoi", texte: Presences.relanceEnvoi),
        .init(cle: "Presences.relanceSucces", texte: Presences.relanceSucces),
        .init(cle: "Presences.relanceImpossible", texte: Presences.relanceImpossible),
        .init(cle: "Contestation.titre", texte: Contestation.titre),
        .init(cle: "Contestation.contester", texte: Contestation.contester),
        .init(cle: "Contestation.placeholderSoignant", texte: Contestation.placeholderSoignant),
        .init(cle: "Contestation.envoi", texte: Contestation.envoi),
        .init(cle: "Contestation.envoyer", texte: Contestation.envoyer),
        .init(cle: "Contestation.annuler", texte: Contestation.annuler),
        .init(cle: "AttestationSante.signee", texte: AttestationSante.signee),
        .init(cle: "AttestationSante.signatureEnCours", texte: AttestationSante.signatureEnCours),
        .init(cle: "AttestationSante.erreurSignature", texte: AttestationSante.erreurSignature),
        .init(cle: "SignatureOtp.messageParDefaut", texte: SignatureOtp.messageParDefaut),
        .init(cle: "SignatureOtp.repliEnvoi", texte: SignatureOtp.repliEnvoi),
        .init(cle: "SignatureOtp.repliSignature", texte: SignatureOtp.repliSignature),
        .init(cle: "SignatureOtp.codeSixChiffresRequis", texte: SignatureOtp.codeSixChiffresRequis),
        .init(cle: "SignatureOtp.signatureNonDisponible", texte: SignatureOtp.signatureNonDisponible),
        .init(cle: "SignatureOtp.codeEnvoyePrefixe", texte: SignatureOtp.codeEnvoyePrefixe),
        .init(cle: "SignatureOtp.codeEnvoyeValide", texte: SignatureOtp.codeEnvoyeValide),
        .init(cle: "SignatureOtp.codeEnvoyeMinutes", texte: SignatureOtp.codeEnvoyeMinutes),
        .init(cle: "SignatureOtp.erreurReseauEnvoi", texte: SignatureOtp.erreurReseauEnvoi),
        .init(cle: "SignatureOtp.erreurReseauSignature", texte: SignatureOtp.erreurReseauSignature),
        .init(cle: "SignatureOtp.verificationSignatureEnCours", texte: SignatureOtp.verificationSignatureEnCours),
        .init(cle: "SignatureOtp.codeEnvoyeAuLibelle", texte: SignatureOtp.codeEnvoyeAuLibelle),
        .init(cle: "SignatureOtp.numeroMasque", texte: SignatureOtp.numeroMasque),
        .init(cle: "SignatureOtp.smsParentheseOuvrante", texte: SignatureOtp.smsParentheseOuvrante),
        .init(cle: "SignatureOtp.smsDernierEnvoi", texte: SignatureOtp.smsDernierEnvoi),
        .init(cle: "SignatureOtp.smsEnvoiMot", texte: SignatureOtp.smsEnvoiMot),
        .init(cle: "SignatureOtp.smsPlurielEnvoi", texte: SignatureOtp.smsPlurielEnvoi),
        .init(cle: "SignatureOtp.smsRestantMot", texte: SignatureOtp.smsRestantMot),
        .init(cle: "SignatureOtp.smsPlurielRestant", texte: SignatureOtp.smsPlurielRestant),
        .init(cle: "SignatureOtp.smsParentheseFermante", texte: SignatureOtp.smsParentheseFermante),
        .init(cle: "SignatureOtp.minuteurSeparateur", texte: SignatureOtp.minuteurSeparateur),
        .init(cle: "SignatureOtp.minuteurExpire", texte: SignatureOtp.minuteurExpire),
        .init(cle: "SignatureOtp.champCodeAccessibilite", texte: SignatureOtp.champCodeAccessibilite),
        .init(cle: "SignatureOtp.renvoiNonAutoriseRecette", texte: SignatureOtp.renvoiNonAutoriseRecette),
        .init(cle: "SignatureOtp.plafondSmsAtteint", texte: SignatureOtp.plafondSmsAtteint),
        .init(cle: "SignatureOtp.recevoirNouveauCode", texte: SignatureOtp.recevoirNouveauCode),
        .init(cle: "SignatureOtp.renvoyerCode", texte: SignatureOtp.renvoyerCode),
        .init(cle: "CompteARebours.uniteHeures", texte: CompteARebours.uniteHeures),
        .init(cle: "CompteARebours.uniteMinutes", texte: CompteARebours.uniteMinutes),
        .init(cle: "CompteARebours.uniteSecondes", texte: CompteARebours.uniteSecondes),
        .init(cle: "Certificat.contratPrefixe", texte: Certificat.contratPrefixe),
    ]
}
