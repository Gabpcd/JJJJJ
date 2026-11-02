import Foundation

// HARD STOP n°4 (CLAUDE.md) — textes juridiques et de consentement de l'app iOS, lot 2 (tranche TL,
// docs/mobile-swift/LOT2_PLAN.md §3 « TL », critère P9).
//
// Chaque constante est le texte EXACT que le web affiche à la ligne annoncée par son annotation
// « source » (fichier:ligne). La garde tests/node/textes-juridiques-ios.node.mjs (CI validate-pr)
// le prouve au caractère près, rejoue une mutation d'un caractère sur chaque constante et rougit
// si le texte web change ou se déplace. Aucune reformulation ici : un changement de wording part
// d'abord sur le web, puis dans une PR HARD STOP validée par Gabrielle. Les valeurs (dates,
// empreintes, durées) ne sont jamais des gabarits dans un texte : elles sont assemblées par les
// fonctions ci-dessous, qui reproduisent le rendu React (tests TextesWebTests).

/// Entrée du catalogue des textes (clé « Groupe.constante », texte verbatim du web).
public struct EntreeTexteWeb: Sendable, Hashable {
    public let cle: String
    public let texte: String

    public init(cle: String, texte: String) {
        self.cle = cle
        self.texte = texte
    }
}

/// Textes juridiques et de consentement affichés par les écrans du lot 2 (présences, pointage,
/// justificatifs, contrats). Les écrans les lisent ici, jamais dans un littéral local.
public enum TextesWeb {
    /// Écran de consentement à la géolocalisation (`ConsentementGPS.tsx` l.16-71), affiché avant le
    /// premier pointage quand `soignants.consentement_gps` est NULL (LOT2_PLAN §7 Q4). Titre,
    /// description, deux listes, base légale RGPD et boutons, dans l'ordre du web.
    public enum ConsentementGps {
        // source: src/components/ConsentementGPS.tsx:25
        public static let titre = "Autorisation de géolocalisation"

        // source: src/components/ConsentementGPS.tsx:28
        public static let description = "Jolene utilise votre position pour vérifier que vous êtes bien dans l'établissement lors du pointage."

        // source: src/components/ConsentementGPS.tsx:34
        public static let ceQueNousFaisonsTitre = "Ce que nous faisons :"

        // source: src/components/ConsentementGPS.tsx:36
        public static let ceQueNousFaisons1 = "Relevé ponctuel au moment du clic sur « Pointer »"

        // source: src/components/ConsentementGPS.tsx:37
        public static let ceQueNousFaisons2 = "Comparaison avec l'adresse de l'établissement"

        // source: src/components/ConsentementGPS.tsx:38
        public static let ceQueNousFaisons3 = "Données conservées 1 an puis supprimées"

        // source: src/components/ConsentementGPS.tsx:42
        public static let ceQueNousNeFaisonsPasTitre = "Ce que nous ne faisons pas :"

        // source: src/components/ConsentementGPS.tsx:44
        public static let ceQueNousNeFaisonsPas1 = "Votre position n'est pas suivie en continu"

        // source: src/components/ConsentementGPS.tsx:45
        public static let ceQueNousNeFaisonsPas2 = "Aucun traçage en arrière-plan"

        // source: src/components/ConsentementGPS.tsx:46
        public static let ceQueNousNeFaisonsPas3 = "Aucun partage avec des tiers"

        // source: src/components/ConsentementGPS.tsx:50
        public static let baseLegale = "Base légale : consentement (Art. 6.1.a RGPD). Vous pouvez retirer votre consentement à tout moment depuis votre profil."

        // source: src/components/ConsentementGPS.tsx:58
        public static let refuser = "Je refuse"

        // source: src/components/ConsentementGPS.tsx:64
        public static let accepter = "Autoriser la localisation"

        /// Liste « Ce que nous faisons », dans l'ordre du web (l.36-38).
        public static let ceQueNousFaisons = [ceQueNousFaisons1, ceQueNousFaisons2, ceQueNousFaisons3]

        /// Liste « Ce que nous ne faisons pas », dans l'ordre du web (l.44-46).
        public static let ceQueNousNeFaisonsPas = [ceQueNousNeFaisonsPas1, ceQueNousNeFaisonsPas2, ceQueNousNeFaisonsPas3]
    }

    /// Bandeau du pointage sans localisation (`BandeauSansGPS.tsx` l.4-13), après un refus.
    public enum BandeauSansGps {
        /// Tutoiement du web conservé verbatim : le passage au vouvoiement serait une reformulation
        /// (HARD STOP n°4), en attente de la décision de Gabrielle.
        // source: src/components/BandeauSansGPS.tsx:9
        public static let texte = "Pointage sans localisation activé. Lorsque tu pointeras, l'établissement validera manuellement ta présence."
    }

    /// Présences : retour du consentement GPS (`PresencesSoignant.tsx` l.82, l.101), bandeau du filtre
    /// « à valider » (l.715-719) et relance de l'établissement (`DetailPresencesMission.tsx` l.695-703).
    public enum Presences {
        // source: src/pages/PresencesSoignant.tsx:82
        public static let consentementGpsEnregistre = "Consentement GPS enregistré."

        /// Tutoiement du web conservé verbatim : le passage au vouvoiement serait une reformulation
        /// (HARD STOP n°4), en attente de la décision de Gabrielle.
        // source: src/pages/PresencesSoignant.tsx:101
        public static let pointageSansGpsActive = "Pointage sans GPS activé — ton pointage sera validé manuellement par l'établissement, rien à faire de ton côté."

        // source: src/pages/PresencesSoignant.tsx:717
        public static let bandeauAValider = "⏳ Présences en attente de validation par l'établissement (validation automatique sous 72 h). La validation des heures est distincte du versement. En salarié, le salaire est versé par l'établissement employeur. En libéral, le paiement suit les modalités de la mission."

        /// Tutoiement du web conservé verbatim : le passage au vouvoiement serait une reformulation
        /// (HARD STOP n°4), en attente de la décision de Gabrielle.
        // source: src/pages/DetailPresencesMission.tsx:697
        public static let relanceTitre = "⏳ Tes présences attendent la validation de l'établissement"

        /// Tutoiement du web conservé verbatim : le passage au vouvoiement serait une reformulation
        /// (HARD STOP n°4), en attente de la décision de Gabrielle.
        // source: src/pages/DetailPresencesMission.tsx:698
        public static let relanceExplication = "La validation des heures (automatique sous 72 h) est distincte du versement. En salarié, le salaire est versé par l'établissement employeur. En libéral, le paiement suit les modalités de la mission. Tu peux envoyer un rappel."
    }

    /// Contestation d'une présence validée (`PanneauContestation.tsx` l.343-397).
    ///
    /// Délai (LOT2_PLAN correction 12, §7 Q9, en attente de Gabrielle) : le web annonce 72 h
    /// (`DELAI_CONTESTATION_MS` l.43-46), le serveur lit `parametres_litiges.delai_contestation_pointage_h`
    /// (48 h par défaut, `fn_fenetre_contestation_ouverte`). Ces textes restent ceux du web ; le refus
    /// du serveur, s'il survient, s'affiche tel quel.
    public enum Contestation {
        // source: src/components/PanneauContestation.tsx:366
        public static let contester = "Contester cette présence"

        // source: src/components/PanneauContestation.tsx:376
        public static let placeholderSoignant = "Les heures validées ne correspondent pas à ma présence réelle…"

        // source: src/components/PanneauContestation.tsx:387
        public static let envoyer = "Envoyer la contestation"

        // source: src/components/PanneauContestation.tsx:394
        public static let delaiContestation = "Vous avez 72 h après la validation pour contester. Sans résolution sous 72 h, l'admin plateforme tranchera."

        // source: src/components/PanneauContestation.tsx:347
        public static let delaiReponse = "72h pour répondre"

        // source: src/components/PanneauContestation.tsx:354
        public static let discussionEnCours = "Discussion en cours — si pas de résolution sous 72h, l'admin plateforme tranchera."
    }

    /// Attestation sur l'honneur de santé (`DocumentsSoignant.tsx` l.27-135), signée par
    /// `fn_signer_attestation_sante` (LOT2_PLAN §7 Q15).
    public enum AttestationSante {
        // source: src/pages/DocumentsSoignant.tsx:75
        public static let titre = "Attestation sur l'honneur"

        // source: src/pages/DocumentsSoignant.tsx:78
        public static let signee = "Signée"

        // source: src/pages/DocumentsSoignant.tsx:93
        public static let vaccinations = "J'atteste sur l'honneur que mes vaccinations obligatoires sont à jour conformément aux recommandations du calendrier vaccinal en vigueur et aux obligations de mon établissement d'exercice."

        // source: src/pages/DocumentsSoignant.tsx:106
        public static let medecineDuTravail = "J'atteste sur l'honneur avoir bénéficié d'une visite d'information et de prévention (médecine du travail) dans les délais réglementaires."

        // source: src/pages/DocumentsSoignant.tsx:112
        public static let faussesDeclarations = "Je reconnais que toute fausse déclaration est passible de poursuites (Art. 441-7 du Code pénal)."

        /// Suivi de la date au format `d MMMM yyyy` (fr) : voir `signeeLe(dateFormatee:)`.
        // source: src/pages/DocumentsSoignant.tsx:118
        public static let prefixeSigneeLe = "✅ Attestation signée le"

        // source: src/pages/DocumentsSoignant.tsx:127
        public static let signer = "✅ Signer mon attestation"

        // source: src/pages/DocumentsSoignant.tsx:127
        public static let signatureEnCours = "Signature en cours…"

        /// Tutoiement du web conservé verbatim : le passage au vouvoiement serait une reformulation
        /// (HARD STOP n°4), en attente de la décision de Gabrielle.
        // source: src/pages/DocumentsSoignant.tsx:132
        public static let documentsOriginaux = "Les documents originaux (carnet de vaccination, attestation de médecine du travail) sont vérifiés par l'établissement lors de ta première mission. Jolene enregistre uniquement ta déclaration et sa date de signature, avec un accès restreint."

        // source: src/pages/DocumentsSoignant.tsx:52
        public static let erreurSignature = "Erreur lors de la signature. Veuillez réessayer."

        // source: src/pages/DocumentsSoignant.tsx:56
        public static let succes = "Attestation signée avec succès !"

        /// « ✅ Attestation signée le <date> » (l.118), date déjà formatée `d MMMM yyyy` en français.
        public static func signeeLe(dateFormatee: String) -> String {
            prefixeSigneeLe + " " + dateFormatee
        }
    }

    /// Lecture d'un contrat (`ContratMission.tsx` l.552-837) : bandeaux de statut, CDD à préparer,
    /// document figé et empreinte, contenu indisponible, signature OTP, pied de page juridique.
    public enum Contrat {
        // source: src/pages/ContratMission.tsx:554
        public static let annule = "❌ Ce contrat a été annulé suite à l'annulation de la mission."

        // source: src/pages/ContratMission.tsx:559
        public static let expire = "⏰ Contrat expiré — non signé dans les 72h. La mission a été annulée."

        // source: src/pages/ContratMission.tsx:564
        public static let refuse = "❌ Ce contrat a été refusé par l'une des parties."

        // source: src/pages/ContratMission.tsx:571
        public static let autrePartieASigne = "⏳ L'autre partie a déjà signé"

        // source: src/pages/ContratMission.tsx:573
        public static let autrePartieASigneDetail = "Vous pouvez signer maintenant. Le contrat devient complet dès que les deux signatures sont enregistrées, quel que soit leur ordre."

        /// CDD sans original préparé par l'employeur (LOT2_PLAN §7 Q19) : aucune action soignant.
        // source: src/pages/ContratMission.tsx:603
        public static let cddAPreparer = "Le contrat doit être préparé et confirmé par un représentant autorisé de l’employeur avant les signatures."

        /// Suivi de la date `dd/MM/yyyy 'à' HH:mm` : voir `documentOfficielFige(dateFormatee:empreinte:)`.
        // source: src/pages/ContratMission.tsx:623
        public static let documentFigeLe = "Document officiel figé le"

        // source: src/pages/ContratMission.tsx:624
        public static let empreinteLibelle = "— empreinte"

        // source: src/pages/ContratMission.tsx:624
        public static let empreinteEllipse = "…"

        // source: src/pages/ContratMission.tsx:636
        public static let originalIndisponible = "Le document signé d’origine est indisponible. Aucune reconstitution automatique n’est effectuée."

        // source: src/pages/ContratMission.tsx:637
        public static let contenuPasDisponible = "Le contenu du contrat n'est pas encore disponible."

        // source: src/pages/ContratMission.tsx:740
        public static let otpLibelle = "📱 Signature électronique OTP SMS"

        // source: src/pages/ContratMission.tsx:743
        public static let otpDescription = "Code SMS à 6 chiffres + horodatage + hash document. Conforme art. 1366-1367 Code civil."

        // source: src/pages/ContratMission.tsx:822
        public static let dejaSigne = "✅ Vous avez déjà signé ce contrat"

        // source: src/pages/ContratMission.tsx:832
        public static let mentionCadreEmployeur = "Contrat salarié préparé selon le cadre déclaré par l’employeur."

        // source: src/pages/ContratMission.tsx:834
        public static let mentionSalarieEcrit = "Contrat salarié écrit — art. L.1242-12 du Code du travail."

        // source: src/pages/ContratMission.tsx:835
        public static let mentionPrestationLiberale = "Contrat de prestation entre l’établissement et le professionnel libéral."

        // source: src/pages/ContratMission.tsx:836
        public static let signatureElectroniqueSimple = "Signature électronique simple."

        // source: src/pages/ContratMission.tsx:836
        public static let regularisationMontants = "Les montants prévisionnels sont régularisés selon les heures validées et les éventuelles corrections contradictoires."

        /// Mention du pied de page (l.832-835). Le choix est celui du web : cadre déclaré par
        /// l'employeur, sinon contrat salarié (`CDD`, `SALARIE`), sinon prestation libérale.
        public enum MentionPiedDePage: Sendable, CaseIterable {
            case cadreEmployeur
            case salarieEcrit
            case prestationLiberale

            public var texte: String {
                switch self {
                case .cadreEmployeur: return TextesWeb.Contrat.mentionCadreEmployeur
                case .salarieEcrit: return TextesWeb.Contrat.mentionSalarieEcrit
                case .prestationLiberale: return TextesWeb.Contrat.mentionPrestationLiberale
                }
            }
        }

        /// Pied de page rendu par le web (l.831-837) : mention, « Signature électronique simple. »,
        /// puis la régularisation des montants, sauf pour un contrat au cadre déclaré par l'employeur.
        public static func piedDePage(_ mention: MentionPiedDePage) -> String {
            let base = mention.texte + " " + signatureElectroniqueSimple
            return mention == .cadreEmployeur ? base : base + " " + regularisationMontants
        }

        /// « Document officiel figé le <date> — empreinte <8 premiers>…<4 derniers> » (l.623-624) ;
        /// sans empreinte (NULL ou vide), la date seule, comme le web.
        public static func documentOfficielFige(dateFormatee: String, empreinte: String?) -> String {
            let base = documentFigeLe + " " + dateFormatee
            guard let empreinte, !empreinte.isEmpty else { return base }
            return base + " " + empreinteLibelle + " " + String(empreinte.prefix(8)) + empreinteEllipse
                + String(empreinte.suffix(4))
        }
    }

    /// Signature OTP SMS (`SignerContratOtp.tsx`) : messages d'erreur par code (`MESSAGES_ERREUR`
    /// l.30-44), codes bloquants (l.115-119), consentement lié au document affiché, confirmation.
    public enum SignatureOtp {
        // source: src/components/SignerContratOtp.tsx:31
        public static let nonAuthentifie = "Session expirée. Reconnectez-vous puis réessayez."

        // source: src/components/SignerContratOtp.tsx:32
        public static let nonAutorise = "Vous n'êtes pas autorisé(e) à signer ce contrat."

        // source: src/components/SignerContratOtp.tsx:33
        public static let contratIntrouvable = "Contrat introuvable. Rechargez la page."

        // source: src/components/SignerContratOtp.tsx:34
        public static let contratInactif = "Ce contrat a été annulé ou a expiré et ne peut plus être signé."

        // source: src/components/SignerContratOtp.tsx:35
        public static let contratDejaComplet = "Ce contrat est déjà entièrement signé par les deux parties."

        // source: src/components/SignerContratOtp.tsx:36
        public static let telephoneManquant = "Votre numéro de téléphone est manquant. Mettez à jour votre profil avant de signer."

        // source: src/components/SignerContratOtp.tsx:37
        public static let tropDeSms = "Trop de SMS envoyés (3 max / 24h). Réessayez plus tard ou contactez le support."

        // source: src/components/SignerContratOtp.tsx:38
        public static let otpNonDemande = "Demandez d'abord un code SMS en cliquant sur le bouton."

        // source: src/components/SignerContratOtp.tsx:39
        public static let otpExpire = "Le code SMS a expiré (10 min). Demandez un nouveau code."

        // source: src/components/SignerContratOtp.tsx:40
        public static let otpIncorrect = "Code incorrect. Vérifiez votre SMS et réessayez."

        // source: src/components/SignerContratOtp.tsx:41
        public static let tropDeTentatives = "Trop de tentatives. Renvoyez un nouveau code SMS."

        // source: src/components/SignerContratOtp.tsx:42
        public static let dejaSigne = "Vous avez déjà signé ce contrat."

        // source: src/components/SignerContratOtp.tsx:43
        public static let hashDocumentChange = "Le contrat a été modifié depuis votre chargement. Rechargez la page avant de signer."

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

        // source: src/components/SignerContratOtp.tsx:171
        public static let consentementRequis = "Vous devez accepter les termes du contrat avant de signer."

        // source: src/components/SignerContratOtp.tsx:242
        public static let titre = "Signature électronique sécurisée"

        // source: src/components/SignerContratOtp.tsx:244-245
        public static let explication = "Recevez un code à 6 chiffres par SMS et saisissez-le ci-dessous pour signer. La signature inclut horodatage, IP et hash SHA-256 du document (preuve juridique art. 1366 Code civil)."

        /// Case à cocher : le consentement vaut pour la révision affichée (clé contrat + empreinte, l.62-63).
        // source: src/components/SignerContratOtp.tsx:276
        public static let consentement = "J'ai lu l'intégralité du contrat affiché ci-dessus et j'accepte ses termes."

        // source: src/components/SignerContratOtp.tsx:288
        public static let recevoirCode = "Recevoir le code SMS pour signer"

        // source: src/components/SignerContratOtp.tsx:348
        public static let signer = "Signer"

        // source: src/components/SignerContratOtp.tsx:214
        public static let contratSigne = "Contrat signé ✅"

        // source: src/components/SignerContratOtp.tsx:197
        public static let missionConfirmee = "— Mission confirmée par les 2 parties."

        // source: src/components/SignerContratOtp.tsx:216
        public static let signeAvecSucces = "Signé avec succès. Horodatage, IP et hash du document conservés (art. 1366-1367 Code civil)."

        // source: src/components/SignerContratOtp.tsx:230
        public static let signatureNonDisponible = "Signature non disponible pour le moment"

        /// Message du web pour chaque `error_code` de `fn_envoyer_otp_signature` / `fn_signer_contrat_otp`.
        // source-objet: src/components/SignerContratOtp.tsx:30 MESSAGES_ERREUR
        public static let parCode: [String: String] = [
            "NON_AUTHENTIFIE": nonAuthentifie,
            "NON_AUTORISE": nonAutorise,
            "CONTRAT_INTROUVABLE": contratIntrouvable,
            "CONTRAT_INACTIF": contratInactif,
            "CONTRAT_DEJA_COMPLET": contratDejaComplet,
            "TELEPHONE_MANQUANT": telephoneManquant,
            "TROP_DE_SMS": tropDeSms,
            "OTP_NON_DEMANDE": otpNonDemande,
            "OTP_EXPIRE": otpExpire,
            "OTP_INCORRECT": otpIncorrect,
            "TROP_DE_TENTATIVES": tropDeTentatives,
            "DEJA_SIGNE": dejaSigne,
            "HASH_DOCUMENT_CHANGE": hashDocumentChange,
        ]

        /// Codes qui bloquent la signature (l.115-119) : message en alerte, plus d'envoi ni de signature.
        // source-ensemble: src/components/SignerContratOtp.tsx:115-119
        public static let codesBloquants: Set<String> = [
            "TELEPHONE_MANQUANT",
            "TROP_DE_SMS",
            "CONTRAT_INACTIF",
            "CONTRAT_DEJA_COMPLET",
            "DEJA_SIGNE",
            "NON_AUTORISE",
            "HASH_DOCUMENT_CHANGE",
        ]

        /// `messageDepuisCode(code, result?.error || repli)` (l.46-49, l.112-114) : le message du code
        /// s'il est connu, sinon le message du serveur verbatim, sinon le repli, sinon le défaut.
        public static func message(code: String?, erreurServeur: String?, repli: String) -> String {
            if let code, let texte = parCode[code] { return texte }
            let secours = erreurServeur.flatMap { $0.isEmpty ? nil : $0 } ?? repli
            return secours.isEmpty ? messageParDefaut : secours
        }

        /// Confirmation après signature (l.195-198) : « Contrat signé ✅ », complétée quand les deux
        /// parties ont signé.
        public static func confirmationSignature(contratComplet: Bool) -> String {
            contratComplet ? contratSigne + " " + missionConfirmee : contratSigne
        }
    }

    /// Compte à rebours de 72 h de la signature (`Countdown72hSignature.tsx`), dérivé de
    /// `contrats_mission.cree_le` (LOT2_PLAN correction 13), jamais stocké.
    public enum CompteARebours {
        // source: src/components/Countdown72hSignature.tsx:43
        public static let expire = "⚠\u{FE0F} Délai de signature expiré (72h dépassées)."

        // source: src/components/Countdown72hSignature.tsx:69
        public static let urgent = "Signature urgente — moins de 24h restantes !"

        /// Suivi de la durée restante « <h>h <mm>m <ss>s » (l.71-73).
        // source: src/components/Countdown72hSignature.tsx:70
        public static let aFinaliserSous = "Signature à finaliser sous"
    }

    /// Certificat des signatures (`CertificatSignature.tsx`, variante « résumé » des parties) :
    /// titre, libellés des preuves et mention juridique (l.171-176).
    public enum Certificat {
        // source: src/components/CertificatSignature.tsx:95
        public static let titre = "Certificat de signature Jolene"

        // source: src/components/CertificatSignature.tsx:121
        public static let signe = "✅ Signé"

        // source: src/components/CertificatSignature.tsx:128
        public static let dateHeure = "Date / heure"

        // source: src/components/CertificatSignature.tsx:136
        public static let otpValide = "OTP validé"

        // source: src/components/CertificatSignature.tsx:137
        public static let codeSmsVerifie = "✓ Code SMS vérifié"

        // source: src/components/CertificatSignature.tsx:162
        public static let rppsVerifie = "RPPS vérifié"

        // source: src/components/CertificatSignature.tsx:164
        public static let pscActif = "PSC actif"

        // source: src/components/CertificatSignature.tsx:172-175
        public static let mention = "Signature électronique sécurisée Jolene — conforme art. 1366-1367 Code civil (signature électronique simple/avancée renforcée par OTP SMS + horodatage + IP). Pour une signature qualifiée eIDAS, contactez un Prestataire de Services de Confiance qualifié."
    }

    // MARK: - Lot 5 — espace établissement (LOT5_PLAN §2.9, tranche T0, D30)
    //
    // Repris verbatim du web pour les écrans T4, T6 et T9 ; chaque écran exige la validation de
    // Gabrielle (HARD STOP n°4, LOT5_PLAN §6.4). La mention de l'écran de signature OTP
    // établissement (« Conforme art. 1366-1367 Code civil », T10) est `Contrat.otpDescription`.

    /// Revue des candidatures (`ListeCandidatures.tsx` l.386-398, T6, D10) : rappel des conditions
    /// de non-contournement avant l'acceptation, lien vers l'article 8 des CGV ouvert dans Safari.
    public enum CandidaturesEtablissement {
        // source: src/components/ListeCandidatures.tsx:393
        public static let cgvAvantLien = "Avant d’accepter un candidat, consultez les conditions de"

        // source: src/components/ListeCandidatures.tsx:394
        public static let cgvCheminLien = "/cgv#art8"

        // source: src/components/ListeCandidatures.tsx:395
        public static let cgvLien = "non-contournement et de recrutement direct — CGV art. 8"

        // source: src/components/ListeCandidatures.tsx:397
        public static let cgvApresLien = ". Elles précisent les situations concernées, les durées applicables et le calcul des frais de recrutement."

        /// Mention rendue par React : texte, `{' '}`, lien, puis la suite collée au lien.
        public static var cgvMention: String { cgvAvantLien + " " + cgvLien + cgvApresLien }
    }

    /// Blocages de publication de l'Accueil (T4) : titre du bandeau de suspension automatique
    /// (`BandeauBlocageAuto.tsx` l.60-62, montants non portés) et bandeau de vérification
    /// (`DashboardEtablissement.tsx` l.564-565, `peut_publier_missions == false`).
    public enum BlocageEtablissement {
        // source: src/components/BandeauBlocageAuto.tsx:61
        public static let publicationSuspendue = "Publication de missions suspendue"

        // source: src/pages/DashboardEtablissement.tsx:564
        public static let verificationEnCoursTitre = "Votre compte est en cours de vérification"

        // source: src/pages/DashboardEtablissement.tsx:565
        public static let verificationEnCoursDetail = "Vérifiez votre établissement (FINESS + rattachement du représentant) pour pouvoir publier des missions. À défaut, l'équipe Jolene valide votre dossier."
    }

    /// Récapitulatif de publication (T9, D8) : seule l'option « Salarié » est publiée en natif ;
    /// sa description est celle du web (`FormulaireMission.tsx` l.766).
    public enum PublicationEtablissement {
        // source: src/components/FormulaireMission.tsx:766
        public static let optionSalarieLibelle = "Salarié"

        // source: src/components/FormulaireMission.tsx:766
        public static let optionSalarieDescription = "Vous êtes l’employeur : CDD, bulletin de paie, plafond légal 48 h/semaine"
    }

    /// Tous les textes, pour les tests (la garde Node vérifie que la liste est complète et exacte).
    public static let catalogue: [EntreeTexteWeb] = [
        .init(cle: "ConsentementGps.titre", texte: ConsentementGps.titre),
        .init(cle: "ConsentementGps.description", texte: ConsentementGps.description),
        .init(cle: "ConsentementGps.ceQueNousFaisonsTitre", texte: ConsentementGps.ceQueNousFaisonsTitre),
        .init(cle: "ConsentementGps.ceQueNousFaisons1", texte: ConsentementGps.ceQueNousFaisons1),
        .init(cle: "ConsentementGps.ceQueNousFaisons2", texte: ConsentementGps.ceQueNousFaisons2),
        .init(cle: "ConsentementGps.ceQueNousFaisons3", texte: ConsentementGps.ceQueNousFaisons3),
        .init(cle: "ConsentementGps.ceQueNousNeFaisonsPasTitre", texte: ConsentementGps.ceQueNousNeFaisonsPasTitre),
        .init(cle: "ConsentementGps.ceQueNousNeFaisonsPas1", texte: ConsentementGps.ceQueNousNeFaisonsPas1),
        .init(cle: "ConsentementGps.ceQueNousNeFaisonsPas2", texte: ConsentementGps.ceQueNousNeFaisonsPas2),
        .init(cle: "ConsentementGps.ceQueNousNeFaisonsPas3", texte: ConsentementGps.ceQueNousNeFaisonsPas3),
        .init(cle: "ConsentementGps.baseLegale", texte: ConsentementGps.baseLegale),
        .init(cle: "ConsentementGps.refuser", texte: ConsentementGps.refuser),
        .init(cle: "ConsentementGps.accepter", texte: ConsentementGps.accepter),
        .init(cle: "BandeauSansGps.texte", texte: BandeauSansGps.texte),
        .init(cle: "Presences.consentementGpsEnregistre", texte: Presences.consentementGpsEnregistre),
        .init(cle: "Presences.pointageSansGpsActive", texte: Presences.pointageSansGpsActive),
        .init(cle: "Presences.bandeauAValider", texte: Presences.bandeauAValider),
        .init(cle: "Presences.relanceTitre", texte: Presences.relanceTitre),
        .init(cle: "Presences.relanceExplication", texte: Presences.relanceExplication),
        .init(cle: "Contestation.contester", texte: Contestation.contester),
        .init(cle: "Contestation.placeholderSoignant", texte: Contestation.placeholderSoignant),
        .init(cle: "Contestation.envoyer", texte: Contestation.envoyer),
        .init(cle: "Contestation.delaiContestation", texte: Contestation.delaiContestation),
        .init(cle: "Contestation.delaiReponse", texte: Contestation.delaiReponse),
        .init(cle: "Contestation.discussionEnCours", texte: Contestation.discussionEnCours),
        .init(cle: "AttestationSante.titre", texte: AttestationSante.titre),
        .init(cle: "AttestationSante.signee", texte: AttestationSante.signee),
        .init(cle: "AttestationSante.vaccinations", texte: AttestationSante.vaccinations),
        .init(cle: "AttestationSante.medecineDuTravail", texte: AttestationSante.medecineDuTravail),
        .init(cle: "AttestationSante.faussesDeclarations", texte: AttestationSante.faussesDeclarations),
        .init(cle: "AttestationSante.prefixeSigneeLe", texte: AttestationSante.prefixeSigneeLe),
        .init(cle: "AttestationSante.signer", texte: AttestationSante.signer),
        .init(cle: "AttestationSante.signatureEnCours", texte: AttestationSante.signatureEnCours),
        .init(cle: "AttestationSante.documentsOriginaux", texte: AttestationSante.documentsOriginaux),
        .init(cle: "AttestationSante.erreurSignature", texte: AttestationSante.erreurSignature),
        .init(cle: "AttestationSante.succes", texte: AttestationSante.succes),
        .init(cle: "Contrat.annule", texte: Contrat.annule),
        .init(cle: "Contrat.expire", texte: Contrat.expire),
        .init(cle: "Contrat.refuse", texte: Contrat.refuse),
        .init(cle: "Contrat.autrePartieASigne", texte: Contrat.autrePartieASigne),
        .init(cle: "Contrat.autrePartieASigneDetail", texte: Contrat.autrePartieASigneDetail),
        .init(cle: "Contrat.cddAPreparer", texte: Contrat.cddAPreparer),
        .init(cle: "Contrat.documentFigeLe", texte: Contrat.documentFigeLe),
        .init(cle: "Contrat.empreinteLibelle", texte: Contrat.empreinteLibelle),
        .init(cle: "Contrat.empreinteEllipse", texte: Contrat.empreinteEllipse),
        .init(cle: "Contrat.originalIndisponible", texte: Contrat.originalIndisponible),
        .init(cle: "Contrat.contenuPasDisponible", texte: Contrat.contenuPasDisponible),
        .init(cle: "Contrat.otpLibelle", texte: Contrat.otpLibelle),
        .init(cle: "Contrat.otpDescription", texte: Contrat.otpDescription),
        .init(cle: "Contrat.dejaSigne", texte: Contrat.dejaSigne),
        .init(cle: "Contrat.mentionCadreEmployeur", texte: Contrat.mentionCadreEmployeur),
        .init(cle: "Contrat.mentionSalarieEcrit", texte: Contrat.mentionSalarieEcrit),
        .init(cle: "Contrat.mentionPrestationLiberale", texte: Contrat.mentionPrestationLiberale),
        .init(cle: "Contrat.signatureElectroniqueSimple", texte: Contrat.signatureElectroniqueSimple),
        .init(cle: "Contrat.regularisationMontants", texte: Contrat.regularisationMontants),
        .init(cle: "SignatureOtp.nonAuthentifie", texte: SignatureOtp.nonAuthentifie),
        .init(cle: "SignatureOtp.nonAutorise", texte: SignatureOtp.nonAutorise),
        .init(cle: "SignatureOtp.contratIntrouvable", texte: SignatureOtp.contratIntrouvable),
        .init(cle: "SignatureOtp.contratInactif", texte: SignatureOtp.contratInactif),
        .init(cle: "SignatureOtp.contratDejaComplet", texte: SignatureOtp.contratDejaComplet),
        .init(cle: "SignatureOtp.telephoneManquant", texte: SignatureOtp.telephoneManquant),
        .init(cle: "SignatureOtp.tropDeSms", texte: SignatureOtp.tropDeSms),
        .init(cle: "SignatureOtp.otpNonDemande", texte: SignatureOtp.otpNonDemande),
        .init(cle: "SignatureOtp.otpExpire", texte: SignatureOtp.otpExpire),
        .init(cle: "SignatureOtp.otpIncorrect", texte: SignatureOtp.otpIncorrect),
        .init(cle: "SignatureOtp.tropDeTentatives", texte: SignatureOtp.tropDeTentatives),
        .init(cle: "SignatureOtp.dejaSigne", texte: SignatureOtp.dejaSigne),
        .init(cle: "SignatureOtp.hashDocumentChange", texte: SignatureOtp.hashDocumentChange),
        .init(cle: "SignatureOtp.messageParDefaut", texte: SignatureOtp.messageParDefaut),
        .init(cle: "SignatureOtp.repliEnvoi", texte: SignatureOtp.repliEnvoi),
        .init(cle: "SignatureOtp.repliSignature", texte: SignatureOtp.repliSignature),
        .init(cle: "SignatureOtp.codeSixChiffresRequis", texte: SignatureOtp.codeSixChiffresRequis),
        .init(cle: "SignatureOtp.consentementRequis", texte: SignatureOtp.consentementRequis),
        .init(cle: "SignatureOtp.titre", texte: SignatureOtp.titre),
        .init(cle: "SignatureOtp.explication", texte: SignatureOtp.explication),
        .init(cle: "SignatureOtp.consentement", texte: SignatureOtp.consentement),
        .init(cle: "SignatureOtp.recevoirCode", texte: SignatureOtp.recevoirCode),
        .init(cle: "SignatureOtp.signer", texte: SignatureOtp.signer),
        .init(cle: "SignatureOtp.contratSigne", texte: SignatureOtp.contratSigne),
        .init(cle: "SignatureOtp.missionConfirmee", texte: SignatureOtp.missionConfirmee),
        .init(cle: "SignatureOtp.signeAvecSucces", texte: SignatureOtp.signeAvecSucces),
        .init(cle: "SignatureOtp.signatureNonDisponible", texte: SignatureOtp.signatureNonDisponible),
        .init(cle: "CompteARebours.expire", texte: CompteARebours.expire),
        .init(cle: "CompteARebours.urgent", texte: CompteARebours.urgent),
        .init(cle: "CompteARebours.aFinaliserSous", texte: CompteARebours.aFinaliserSous),
        .init(cle: "Certificat.titre", texte: Certificat.titre),
        .init(cle: "Certificat.signe", texte: Certificat.signe),
        .init(cle: "Certificat.dateHeure", texte: Certificat.dateHeure),
        .init(cle: "Certificat.otpValide", texte: Certificat.otpValide),
        .init(cle: "Certificat.codeSmsVerifie", texte: Certificat.codeSmsVerifie),
        .init(cle: "Certificat.rppsVerifie", texte: Certificat.rppsVerifie),
        .init(cle: "Certificat.pscActif", texte: Certificat.pscActif),
        .init(cle: "Certificat.mention", texte: Certificat.mention),
        .init(cle: "CandidaturesEtablissement.cgvAvantLien", texte: CandidaturesEtablissement.cgvAvantLien),
        .init(cle: "CandidaturesEtablissement.cgvCheminLien", texte: CandidaturesEtablissement.cgvCheminLien),
        .init(cle: "CandidaturesEtablissement.cgvLien", texte: CandidaturesEtablissement.cgvLien),
        .init(cle: "CandidaturesEtablissement.cgvApresLien", texte: CandidaturesEtablissement.cgvApresLien),
        .init(cle: "BlocageEtablissement.publicationSuspendue", texte: BlocageEtablissement.publicationSuspendue),
        .init(cle: "BlocageEtablissement.verificationEnCoursTitre", texte: BlocageEtablissement.verificationEnCoursTitre),
        .init(cle: "BlocageEtablissement.verificationEnCoursDetail", texte: BlocageEtablissement.verificationEnCoursDetail),
        .init(cle: "PublicationEtablissement.optionSalarieLibelle", texte: PublicationEtablissement.optionSalarieLibelle),
        .init(cle: "PublicationEtablissement.optionSalarieDescription", texte: PublicationEtablissement.optionSalarieDescription),
    ]
}
