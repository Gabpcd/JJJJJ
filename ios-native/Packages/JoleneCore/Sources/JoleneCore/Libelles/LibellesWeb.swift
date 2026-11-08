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

    /// Liste des contrats du soignant (`ListeContrats.tsx`, T9a) : titre, filtres, pastilles de statut, états
    /// vides (branche soignant), carte mobile (`renduCarte`), erreur de chargement (`ErreurRubriqueEtablissement`).
    public enum Contrats {
        // source: src/pages/ListeContrats.tsx:101
        public static let titre = "Mes contrats"

        /// Libellés des filtres (l.121) : voir `libelleFiltre(_:)` (« Tous » y est la valeur même du filtre).
        // source: src/pages/ListeContrats.tsx:121
        public static let filtreEnAttente = "En attente"

        // source: src/pages/ListeContrats.tsx:121
        public static let filtreSignes = "Signés"

        // source: src/pages/ListeContrats.tsx:121
        public static let filtreAnnules = "Annulés"

        /// Pastille de statut (l.161-165) : voir `badge(_:)`.
        // source: src/pages/ListeContrats.tsx:163
        public static let badgeSigne = "✅ Signé"

        // source: src/pages/ListeContrats.tsx:163
        public static let badgeAnnule = "❌ Annulé"

        // source: src/pages/ListeContrats.tsx:163
        public static let badgeEnAttente = "⏳ En attente"

        /// États vides du soignant (l.126-145) : voir `titreVide(_:)` et `descriptionVide(_:)`.
        // source: src/pages/ListeContrats.tsx:128
        public static let videTitre = "Aucun contrat"

        // source: src/pages/ListeContrats.tsx:131
        public static let videEnAttenteTitre = "Aucun contrat en attente"

        // source: src/pages/ListeContrats.tsx:134
        public static let videEnAttente = "Aucun contrat en attente de signature pour le moment."

        // source: src/pages/ListeContrats.tsx:138
        public static let videSignes = "Aucun contrat signé pour le moment."

        // source: src/pages/ListeContrats.tsx:140
        public static let videAnnules = "Aucun contrat annulé."

        // source: src/pages/ListeContrats.tsx:144
        public static let videTous = "Vos contrats apparaîtront ici après avoir accepté une mission."

        /// Carte mobile (l.205-226) : voir `numero(_:)`, `mission(intitule:)`, `typeEtDate(type:dateFormatee:)`,
        /// `action(aSigner:)`.
        // source: src/pages/ListeContrats.tsx:210
        public static let sansValeur = "—"

        // source: src/pages/ListeContrats.tsx:214
        public static let pictoMission = "📋"

        // source: src/pages/ListeContrats.tsx:215
        public static let creeLe = "· Créé le"

        /// Masque date-fns de la date de création (l.215), appliqué en heure de Paris (`ContratPresentation.date`).
        // source: src/pages/ListeContrats.tsx:215
        public static let formatDateCreation = "dd/MM/yyyy"

        /// Appel de la carte : ouvre la page du contrat, ne signe rien (l.216-224).
        // source: src/pages/ListeContrats.tsx:223
        public static let signerLeContrat = "✍️ Signer le contrat"

        // source: src/pages/ListeContrats.tsx:223
        public static let voirLeContrat = "Voir le contrat"

        /// Erreur de chargement (l.96, `ErreurRubriqueEtablissement`).
        // source: src/pages/ListeContrats.tsx:96
        public static let indisponiblesTitre = "Contrats indisponibles"

        // source: src/components/AccesEtablissement.tsx:82
        public static let chargementNAbouti = "Le chargement n'a pas abouti. Réessayez dans un instant."

        // source: src/components/AccesEtablissement.tsx:84
        public static let reessayer = "Réessayer"

        /// Libellé d'un filtre (l.121) : « Tous », « En attente », « Signés », sinon « Annulés ». Pour « Tous », le web
        /// affiche la valeur du filtre elle-même (`f === 'Tous' ? 'Tous'`, la zone de rendu le garde) : le libellé est
        /// `FiltreContrat.tous.rawValue`, déjà égal à `FILTRES_STATUT[0]` (l.20, `ContratRulesTests`).
        public static func libelleFiltre(_ filtre: FiltreContrat) -> String {
            switch filtre {
            case .tous: return filtre.rawValue
            case .enAttenteSignatures: return filtreEnAttente
            case .signeComplet: return filtreSignes
            case .annule: return filtreAnnules
            }
        }

        /// Pastille de statut (l.163) : signé, annulé, sinon en attente (`ContratRules.statutAffiche(statut:)`).
        public static func badge(_ statut: StatutContratAffiche) -> String {
            switch statut {
            case .signe: return badgeSigne
            case .annule: return badgeAnnule
            case .enAttente: return badgeEnAttente
            }
        }

        /// Titre de l'état vide (l.128-131) : « Aucun contrat en attente » pour ce filtre, sinon « Aucun contrat ».
        public static func titreVide(_ filtre: FiltreContrat) -> String {
            filtre == .enAttenteSignatures ? videEnAttenteTitre : videTitre
        }

        /// Description de l'état vide du soignant (l.130-145, branches `isEtab` exclues).
        public static func descriptionVide(_ filtre: FiltreContrat) -> String {
            switch filtre {
            case .enAttenteSignatures: return videEnAttente
            case .signeComplet: return videSignes
            case .annule: return videAnnules
            case .tous: return videTous
            }
        }

        /// Numéro de la carte (`c.numero_contrat || '—'`, l.210).
        public static func numero(_ numero: String?) -> String {
            numero.flatMap { $0.isEmpty ? nil : $0 } ?? sansValeur
        }

        /// Mission de la carte (`📋 {intitule || '—'}`, l.214).
        public static func mission(intitule: String?) -> String {
            pictoMission + " " + (intitule.flatMap { $0.isEmpty ? nil : $0 } ?? sansValeur)
        }

        /// Type et date de création (`{c.type_contrat} · Créé le {date}`, l.215) : un type NULL est rendu vide.
        public static func typeEtDate(type: String?, dateFormatee: String) -> String {
            (type ?? "") + " " + creeLe + " " + dateFormatee
        }

        /// Appel de la carte (l.223) : « ✍️ Signer le contrat » quand le soignant n'a pas signé, sinon « Voir le
        /// contrat ».
        public static func action(aSigner: Bool) -> String {
            aSigner ? signerLeContrat : voirLeContrat
        }
    }

    /// Page d'un contrat (`ContratMission.tsx`, T9a) : en-tête, boutons, section Signatures, zone « Votre
    /// signature » et préparation du document final. Bandeaux, document figé, contenu indisponible, mentions et
    /// pied de page : `TextesWeb.Contrat`.
    public enum Contrat {
        /// Partie d'une ligne de la section Signatures (l.669-705).
        public enum Partie: Sendable, CaseIterable {
            case etablissement
            case soignant
        }

        /// En-tête (l.591) : voir `titre(numero:)`.
        // source: src/pages/ContratMission.tsx:591
        public static let titrePrefixe = "Contrat"

        /// Statut de l'en-tête (l.592-597) : voir `statut(_:)`.
        // source: src/pages/ContratMission.tsx:593
        public static let statutPrefixe = "Statut :"

        // source: src/pages/ContratMission.tsx:594
        public static let statutSigne = "✅ Signé"

        // source: src/pages/ContratMission.tsx:595
        public static let statutAnnule = "❌ Annulé"

        // source: src/pages/ContratMission.tsx:596
        public static let statutEnAttente = "⏳ En attente de signatures"

        /// Contrat absent ou illisible (l.530).
        // source: src/pages/ContratMission.tsx:530
        public static let introuvable = "Contrat introuvable"

        // source: src/pages/ContratMission.tsx:611
        public static let telecharger = "Télécharger le contrat"

        // source: src/pages/ContratMission.tsx:614
        public static let imprimer = "Imprimer"

        /// Aucun original contrôlé à partager (l.427-429).
        // source: src/pages/ContratMission.tsx:428
        public static let aucunTelechargeable = "Aucun contrat téléchargeable pour le moment."

        /// Masque date-fns des dates du contrat (l.623, l.679, l.698), appliqué en heure de Paris.
        // source: src/pages/ContratMission.tsx:623
        public static let formatDateHeure = "dd/MM/yyyy 'à' HH:mm"

        /// Section Signatures (l.666-706) : voir `ligneSignature(_:signee:dateFormatee:)`.
        // source: src/pages/ContratMission.tsx:667
        public static let signaturesTitre = "Signatures"

        // source: src/pages/ContratMission.tsx:678
        public static let partieEtablissement = "Établissement :"

        // source: src/pages/ContratMission.tsx:697
        public static let partieSoignant = "Soignant(e) :"

        // source: src/pages/ContratMission.tsx:679
        public static let signatureSignee = "✅ Signé"

        // source: src/pages/ContratMission.tsx:679
        public static let signatureLe = "le"

        // source: src/pages/ContratMission.tsx:680
        public static let signatureEnAttente = "⏳ En attente"

        /// Zone de signature (l.711) ; T9a : renvoi web jusqu'à T9b.
        // source: src/pages/ContratMission.tsx:711
        public static let votreSignature = "Votre signature"

        /// Rendu serveur refusé (l.372-377) : voir `renduRefuse(messageServeur:)`.
        // source: src/pages/ContratMission.tsx:377
        public static let renduImpossible = "Le document contractuel final n’a pas pu être préparé."

        // source: src/pages/ContratMission.tsx:377
        public static let reessayerAvantDeSigner = "Réessayez avant de signer."

        /// Document final encore incomplet après le rendu (l.387-388).
        // source: src/pages/ContratMission.tsx:388
        public static let renduIncomplet = "Le document contractuel final est encore incomplet. Réessayez avant de signer."

        /// En-tête « Contrat <numéro> » (l.591), sans repli : un numéro NULL laisse « Contrat ».
        public static func titre(numero: String?) -> String {
            titrePrefixe + " " + (numero ?? "")
        }

        /// Statut de l'en-tête (l.593-596) : signé, annulé, sinon en attente de signatures.
        public static func statut(_ statut: StatutContratAffiche) -> String {
            let valeur: String
            switch statut {
            case .signe: valeur = statutSigne
            case .annule: valeur = statutAnnule
            case .enAttente: valeur = statutEnAttente
            }
            return statutPrefixe + " " + valeur
        }

        /// Ligne d'une partie (l.677-681, l.696-700) : « ✅ Signé », suivi de « le <date> » quand la date de
        /// signature est lisible, sinon « ⏳ En attente ».
        public static func ligneSignature(_ partie: Partie, signee: Bool, dateFormatee: String?) -> String {
            let libelle: String
            switch partie {
            case .etablissement: libelle = partieEtablissement
            case .soignant: libelle = partieSoignant
            }
            guard signee else { return libelle + " " + signatureEnAttente }
            guard let dateFormatee, !dateFormatee.isEmpty else { return libelle + " " + signatureSignee }
            return libelle + " " + signatureSignee + " " + signatureLe + " " + dateFormatee
        }

        /// Rendu serveur refusé (l.373-377) : motif serveur (180 unités UTF-16 au plus) entre les deux phrases ;
        /// sans motif, les deux phrases seules (même texte que l.394).
        public static func renduRefuse(messageServeur: String?) -> String {
            guard let messageServeur, !messageServeur.isEmpty else { return renduImpossible + " " + reessayerAvantDeSigner }
            let motif = String(decoding: Array(messageServeur.utf16.prefix(180)), as: UTF16.self)
            return renduImpossible + " " + motif + " " + reessayerAvantDeSigner
        }
    }

    /// En-tête de la page `/contrat/:id/certificat` (`CertificatSignaturePage.tsx` l.186). Titre,
    /// certificat et empreinte : `TextesWeb.Certificat`.
    public enum Certificat {
        // source: src/pages/CertificatSignaturePage.tsx:186
        public static let contratPrefixe = "Contrat"

        /// Masque date-fns de l'heure d'une signature (`CertificatSignature.tsx` l.130), en heure de Paris.
        // source: src/components/CertificatSignature.tsx:130
        public static let formatDateHeure = "dd/MM/yyyy 'à' HH:mm:ss"

        /// Export PDF de la page (l.195) : renvoi web, jamais porté (LOT2_PLAN §1.2).
        // source: src/pages/CertificatSignaturePage.tsx:195
        public static let telechargerPdf = "Télécharger PDF"

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
        .init(cle: "Contrats.titre", texte: Contrats.titre),
        .init(cle: "Contrats.filtreEnAttente", texte: Contrats.filtreEnAttente),
        .init(cle: "Contrats.filtreSignes", texte: Contrats.filtreSignes),
        .init(cle: "Contrats.filtreAnnules", texte: Contrats.filtreAnnules),
        .init(cle: "Contrats.badgeSigne", texte: Contrats.badgeSigne),
        .init(cle: "Contrats.badgeAnnule", texte: Contrats.badgeAnnule),
        .init(cle: "Contrats.badgeEnAttente", texte: Contrats.badgeEnAttente),
        .init(cle: "Contrats.videTitre", texte: Contrats.videTitre),
        .init(cle: "Contrats.videEnAttenteTitre", texte: Contrats.videEnAttenteTitre),
        .init(cle: "Contrats.videEnAttente", texte: Contrats.videEnAttente),
        .init(cle: "Contrats.videSignes", texte: Contrats.videSignes),
        .init(cle: "Contrats.videAnnules", texte: Contrats.videAnnules),
        .init(cle: "Contrats.videTous", texte: Contrats.videTous),
        .init(cle: "Contrats.sansValeur", texte: Contrats.sansValeur),
        .init(cle: "Contrats.pictoMission", texte: Contrats.pictoMission),
        .init(cle: "Contrats.creeLe", texte: Contrats.creeLe),
        .init(cle: "Contrats.formatDateCreation", texte: Contrats.formatDateCreation),
        .init(cle: "Contrats.signerLeContrat", texte: Contrats.signerLeContrat),
        .init(cle: "Contrats.voirLeContrat", texte: Contrats.voirLeContrat),
        .init(cle: "Contrats.indisponiblesTitre", texte: Contrats.indisponiblesTitre),
        .init(cle: "Contrats.chargementNAbouti", texte: Contrats.chargementNAbouti),
        .init(cle: "Contrats.reessayer", texte: Contrats.reessayer),
        .init(cle: "Contrat.titrePrefixe", texte: Contrat.titrePrefixe),
        .init(cle: "Contrat.statutPrefixe", texte: Contrat.statutPrefixe),
        .init(cle: "Contrat.statutSigne", texte: Contrat.statutSigne),
        .init(cle: "Contrat.statutAnnule", texte: Contrat.statutAnnule),
        .init(cle: "Contrat.statutEnAttente", texte: Contrat.statutEnAttente),
        .init(cle: "Contrat.introuvable", texte: Contrat.introuvable),
        .init(cle: "Contrat.telecharger", texte: Contrat.telecharger),
        .init(cle: "Contrat.imprimer", texte: Contrat.imprimer),
        .init(cle: "Contrat.aucunTelechargeable", texte: Contrat.aucunTelechargeable),
        .init(cle: "Contrat.formatDateHeure", texte: Contrat.formatDateHeure),
        .init(cle: "Contrat.signaturesTitre", texte: Contrat.signaturesTitre),
        .init(cle: "Contrat.partieEtablissement", texte: Contrat.partieEtablissement),
        .init(cle: "Contrat.partieSoignant", texte: Contrat.partieSoignant),
        .init(cle: "Contrat.signatureSignee", texte: Contrat.signatureSignee),
        .init(cle: "Contrat.signatureLe", texte: Contrat.signatureLe),
        .init(cle: "Contrat.signatureEnAttente", texte: Contrat.signatureEnAttente),
        .init(cle: "Contrat.votreSignature", texte: Contrat.votreSignature),
        .init(cle: "Contrat.renduImpossible", texte: Contrat.renduImpossible),
        .init(cle: "Contrat.reessayerAvantDeSigner", texte: Contrat.reessayerAvantDeSigner),
        .init(cle: "Contrat.renduIncomplet", texte: Contrat.renduIncomplet),
        .init(cle: "Certificat.contratPrefixe", texte: Certificat.contratPrefixe),
        .init(cle: "Certificat.formatDateHeure", texte: Certificat.formatDateHeure),
        .init(cle: "Certificat.telechargerPdf", texte: Certificat.telechargerPdf),
    ]
}
