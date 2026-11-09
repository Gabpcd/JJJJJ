import Foundation

// HARD STOP n°4 (CLAUDE.md) — textes juridiques et de consentement de l'app iOS, lot 2 (tranche TL,
// docs/mobile-swift/LOT2_PLAN.md §3 « TL », critère P9 ; décisions docs/mobile-swift/DECISIONS_LOT2.md ;
// ces deux documents sont livrés par la tranche T0, intégrée avant TL).
//
// Ce fichier ne porte QUE des textes soumis à la validation de Gabrielle : les textes listés par le
// blueprint v2 (§3 TL) et ceux qui citent un texte de loi, énoncent un droit, une obligation, un
// délai, un effet contractuel ou une preuve, ou formulent un consentement, une attestation, une
// acceptation ou une signature (y compris le bouton qui accomplit l'acte), plus les fragments de
// leurs assemblages. Les autres libellés des mêmes écrans (boutons de navigation, états d'envoi,
// erreurs génériques, compteurs, minuteurs) sont dans `Libelles/LibellesWeb.swift`, gardé par la
// même machinerie mais hors HARD STOP.
//
// Chaque constante est le texte EXACT que le web affiche à la ligne annoncée par son annotation
// « source » (fichier:ligne), suivie de sa nature entre crochets : juridique, consentement,
// libellé (texte non juridique listé par le blueprint) ou fragment (morceau affiché seulement dans
// un assemblage : il se valide par ses rendus). La garde tests/node/textes-juridiques-ios.node.mjs
// (CI validate-pr, check requis Typecheck + build) le prouve au caractère près et rejoue une mutation
// d'un caractère sur chaque constante. Un texte web modifié fait rougir la garde ; un texte inchangé
// qui s'est seulement déplacé dans son fichier est toléré avec un avertissement (réannotation par
// `node scripts/mobile/check-textes-juridiques-ios.mjs --corriger-lignes`). Aucune reformulation ici :
// un changement de wording part d'abord sur le web, puis dans une PR HARD STOP validée par Gabrielle.
//
// Les valeurs (dates, empreintes, durées, compteurs) ne sont jamais des gabarits dans un texte : les
// fonctions ci-dessous les assemblent comme le rendu React. Le code web de chaque assemblage
// (conditions, ordre, séparateurs) est ancré par son contenu dans scripts/mobile/textes-web-ios-rendus.json :
// s'il change, la garde rougit en nommant la fonction à relire. Les rendus exacts sont assertés par
// TextesWebTests et listés pour Gabrielle (`--liste`).

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
        // source: src/components/ConsentementGPS.tsx:25 [consentement]
        public static let titre = "Autorisation de géolocalisation"

        // source: src/components/ConsentementGPS.tsx:28 [consentement]
        public static let description = "Jolene utilise votre position pour vérifier que vous êtes bien dans l'établissement lors du pointage."

        // source: src/components/ConsentementGPS.tsx:34 [consentement]
        public static let ceQueNousFaisonsTitre = "Ce que nous faisons :"

        // source: src/components/ConsentementGPS.tsx:36 [consentement]
        public static let ceQueNousFaisons1 = "Relevé ponctuel au moment du clic sur « Pointer »"

        // source: src/components/ConsentementGPS.tsx:37 [consentement]
        public static let ceQueNousFaisons2 = "Comparaison avec l'adresse de l'établissement"

        // source: src/components/ConsentementGPS.tsx:38 [consentement]
        public static let ceQueNousFaisons3 = "Données conservées 1 an puis supprimées"

        // source: src/components/ConsentementGPS.tsx:42 [consentement]
        public static let ceQueNousNeFaisonsPasTitre = "Ce que nous ne faisons pas :"

        // source: src/components/ConsentementGPS.tsx:44 [consentement]
        public static let ceQueNousNeFaisonsPas1 = "Votre position n'est pas suivie en continu"

        // source: src/components/ConsentementGPS.tsx:45 [consentement]
        public static let ceQueNousNeFaisonsPas2 = "Aucun traçage en arrière-plan"

        // source: src/components/ConsentementGPS.tsx:46 [consentement]
        public static let ceQueNousNeFaisonsPas3 = "Aucun partage avec des tiers"

        // source: src/components/ConsentementGPS.tsx:50 [juridique]
        public static let baseLegale = "Base légale : consentement (Art. 6.1.a RGPD). Vous pouvez retirer votre consentement à tout moment depuis votre profil."

        // source: src/components/ConsentementGPS.tsx:58 [consentement]
        public static let refuser = "Je refuse"

        // source: src/components/ConsentementGPS.tsx:64 [consentement]
        public static let accepter = "Autoriser la localisation"

        /// Liste « Ce que nous faisons », dans l'ordre du web (l.35-39).
        public static let ceQueNousFaisons = [ceQueNousFaisons1, ceQueNousFaisons2, ceQueNousFaisons3]

        /// Liste « Ce que nous ne faisons pas », dans l'ordre du web (l.43-47).
        public static let ceQueNousNeFaisonsPas = [ceQueNousNeFaisonsPas1, ceQueNousNeFaisonsPas2, ceQueNousNeFaisonsPas3]
    }

    /// Bandeau du pointage sans localisation (`BandeauSansGPS.tsx` l.4-13), après un refus.
    public enum BandeauSansGps {
        /// Tutoiement du web conservé verbatim : le passage au vouvoiement serait une reformulation
        /// (HARD STOP n°4), en attente de la décision de Gabrielle.
        // source: src/components/BandeauSansGPS.tsx:9 [consentement]
        public static let texte = "Pointage sans localisation activé. Lorsque tu pointeras, l'établissement validera manuellement ta présence."
    }

    /// Consentement GPS du Profil (`SectionPreferences.tsx` l.128-168) : retrait et réactivation que
    /// promet le texte de consentement (« depuis votre profil », `ConsentementGPS.tsx` l.50 ;
    /// LOT2_PLAN correction 15, §7 Q4). Interrupteur, explication selon l'état, retour après bascule.
    public enum ProfilConsentementGps {
        // source: src/components/profil-soignant/SectionPreferences.tsx:129 [consentement]
        public static let titre = "Consentement GPS"

        // source: src/components/profil-soignant/SectionPreferences.tsx:132 [consentement]
        public static let libelle = "Autoriser la géolocalisation lors des pointages"

        /// Libellé d'accessibilité de l'interrupteur (`aria-label`) : la formule du consentement lue
        /// par VoiceOver.
        // source: src/components/profil-soignant/SectionPreferences.tsx:140 [consentement]
        public static let libelleAccessibilite = "Autoriser la géolocalisation lors des pointages"

        /// Tutoiement du web conservé verbatim : le passage au vouvoiement serait une reformulation
        /// (HARD STOP n°4), en attente de la décision de Gabrielle.
        // source: src/components/profil-soignant/SectionPreferences.tsx:135 [consentement]
        public static let explicationActive = "Ta position sera capturée uniquement au moment de l'arrivée et du départ."

        /// Tutoiement du web conservé verbatim : le passage au vouvoiement serait une reformulation
        /// (HARD STOP n°4), en attente de la décision de Gabrielle.
        // source: src/components/profil-soignant/SectionPreferences.tsx:136 [consentement]
        public static let explicationRetiree = "Sans GPS, tes pointages seront validés manuellement par l'établissement — rien à faire de ton côté."

        // source: src/components/profil-soignant/SectionPreferences.tsx:161 [consentement]
        public static let active = "Consentement GPS activé."

        /// Tutoiement du web conservé verbatim : le passage au vouvoiement serait une reformulation
        /// (HARD STOP n°4), en attente de la décision de Gabrielle.
        // source: src/components/profil-soignant/SectionPreferences.tsx:161 [consentement]
        public static let retire = "Consentement GPS retiré — tes pointages seront validés manuellement par l'établissement."

        /// Explication sous l'interrupteur selon le consentement relu (l.134-136).
        public static func explication(consentementActif: Bool) -> String {
            consentementActif ? explicationActive : explicationRetiree
        }

        /// Retour affiché après une bascule acceptée par `fn_consentir_gps` (l.159-162).
        public static func retourBascule(consentementActif: Bool) -> String {
            consentementActif ? active : retire
        }
    }

    /// Présences : retour du consentement GPS (`PresencesSoignant.tsx` l.76, l.95), bandeau du filtre
    /// « à valider » (l.656-660) et relance de l'établissement (`DetailPresencesMission.tsx` l.695-703 ;
    /// bouton et retours de la relance : `LibellesWeb.Presences`).
    public enum Presences {
        // source: src/pages/PresencesSoignant.tsx:76 [consentement]
        public static let consentementGpsEnregistre = "Consentement GPS enregistré."

        /// Tutoiement du web conservé verbatim : le passage au vouvoiement serait une reformulation
        /// (HARD STOP n°4), en attente de la décision de Gabrielle.
        // source: src/pages/PresencesSoignant.tsx:95 [consentement]
        public static let pointageSansGpsActive = "Pointage sans GPS activé — ton pointage sera validé manuellement par l'établissement, rien à faire de ton côté."

        // source: src/pages/PresencesSoignant.tsx:658 [juridique]
        public static let bandeauAValider = "⏳ Présences en attente de validation par l'établissement (validation automatique sous 72 h). La validation des heures est distincte du versement. En salarié, le salaire est versé par l'établissement employeur. En libéral, le paiement suit les modalités de la mission."

        /// Affiché tel quel, tutoiement compris, par le détail des présences (T5a) : décision déléguée « Relance de
        /// l'établissement » (`docs/mobile-swift/DECISIONS_LOT2.md`, « Décisions déléguées du 8 novembre 2026 », T5a,
        /// l.1001) ; le vouvoiement des textes juridiques partira du web (décision de la vague 4).
        // source: src/pages/DetailPresencesMission.tsx:697 [libellé]
        public static let relanceTitre = "⏳ Tes présences attendent la validation de l'établissement"

        /// Affiché tel quel, tutoiement compris : même décision déléguée (l.1001), qui source chaque
        /// phrase (CGU de production, `src/pages/PageCGU.tsx` l.48, l.109, l.115 ; `dec_definir_type_paiement`).
        // source: src/pages/DetailPresencesMission.tsx:698 [juridique]
        public static let relanceExplication = "La validation des heures (automatique sous 72 h) est distincte du versement. En salarié, le salaire est versé par l'établissement employeur. En libéral, le paiement suit les modalités de la mission. Tu peux envoyer un rappel."
    }

    /// Contestation d'une présence validée (`PanneauContestation.tsx`) : libellés de statut
    /// (`STATUT_CONFIG` l.48-62), listés par le blueprint. Titre et formulaire : `LibellesWeb.Contestation`.
    ///
    /// Aucun texte de délai tant que Q9 n'est pas tranchée par Gabrielle (LOT2_PLAN v2 §1.2,
    /// correction 14, §7 Q9 ; DECISIONS_LOT2 « En attente de Gabrielle ») : les textes de délai du
    /// panneau (« 72h pour répondre », « l'admin plateforme tranchera », « Vous avez 72 h après la
    /// validation pour contester… ») contredisent le serveur (`parametres_litiges.delai_contestation_pointage_h`,
    /// 48 h par défaut ; escalade vers `EN_MEDIATION`). Ils ne sont pas repris : la garde Node les
    /// refuse (`ANCRES_Q9`), comme tout texte qui associe contestation ou litige et délai. La fenêtre
    /// est décidée par `fn_fenetre_contestation_ouverte` ; un refus du serveur s'affiche tel quel.
    public enum Contestation {
        // source: src/components/PanneauContestation.tsx:49 [libellé]
        public static let statutOuvert = "Ouvert"

        // source: src/components/PanneauContestation.tsx:50 [libellé]
        public static let statutEnDiscussion = "En discussion"

        // source: src/components/PanneauContestation.tsx:51 [libellé]
        public static let statutEnMediation = "En médiation"

        // source: src/components/PanneauContestation.tsx:52 [libellé]
        public static let statutMediationEnCours = "Médiation en cours"

        // source: src/components/PanneauContestation.tsx:53 [libellé]
        public static let statutRevueAdmin = "Revue admin"

        // source: src/components/PanneauContestation.tsx:54 [libellé]
        public static let statutResoluSoignant = "Résolu (soignant)"

        // source: src/components/PanneauContestation.tsx:55 [libellé]
        public static let statutResoluEtablissement = "Résolu (établissement)"

        // source: src/components/PanneauContestation.tsx:56 [libellé]
        public static let statutResoluAdmin = "Résolu (admin)"

        // source: src/components/PanneauContestation.tsx:57 [libellé]
        public static let statutResoluAccordParties = "Résolu par accord"

        // source: src/components/PanneauContestation.tsx:58 [libellé]
        public static let statutResoluFaveurSoignant = "Résolu en faveur du soignant"

        // source: src/components/PanneauContestation.tsx:59 [libellé]
        public static let statutResoluFaveurEtab = "Résolu en faveur de l’établissement"

        // source: src/components/PanneauContestation.tsx:60 [libellé]
        public static let statutResoluPartage = "Résolution partagée"

        // source: src/components/PanneauContestation.tsx:61 [libellé]
        public static let statutFerme = "Fermé"

        /// Libellé de chaque statut de litige (`STATUT_CONFIG[statut].label`).
        // source-objet: src/components/PanneauContestation.tsx:48 STATUT_CONFIG.label
        public static let libellesStatut: [String: String] = [
            "OUVERT": statutOuvert,
            "EN_DISCUSSION": statutEnDiscussion,
            "EN_MEDIATION": statutEnMediation,
            "MEDIATION_EN_COURS": statutMediationEnCours,
            "REVUE_ADMIN": statutRevueAdmin,
            "RESOLU_SOIGNANT": statutResoluSoignant,
            "RESOLU_ETABLISSEMENT": statutResoluEtablissement,
            "RESOLU_ADMIN": statutResoluAdmin,
            "RESOLU_ACCORD_PARTIES": statutResoluAccordParties,
            "RESOLU_FAVEUR_SOIGNANT": statutResoluFaveurSoignant,
            "RESOLU_FAVEUR_ETAB": statutResoluFaveurEtab,
            "RESOLU_PARTAGE": statutResoluPartage,
            "FERME": statutFerme,
        ]

        /// `STATUT_CONFIG[litige.statut]?.label || litige.statut` (l.266) : un statut inconnu
        /// s'affiche tel quel.
        public static func libelleStatut(code: String) -> String {
            libellesStatut[code] ?? code
        }
    }

    /// Attestation sur l'honneur de santé (`DocumentsSoignant.tsx` l.27-135), signée par
    /// `fn_signer_attestation_sante` (LOT2_PLAN §7 Q15). Badge, état d'envoi et erreur :
    /// `LibellesWeb.AttestationSante`.
    public enum AttestationSante {
        // source: src/pages/DocumentsSoignant.tsx:75 [juridique]
        public static let titre = "Attestation sur l'honneur"

        // source: src/pages/DocumentsSoignant.tsx:93 [consentement]
        public static let vaccinations = "J'atteste sur l'honneur que mes vaccinations obligatoires sont à jour conformément aux recommandations du calendrier vaccinal en vigueur et aux obligations de mon établissement d'exercice."

        // source: src/pages/DocumentsSoignant.tsx:106 [consentement]
        public static let medecineDuTravail = "J'atteste sur l'honneur avoir bénéficié d'une visite d'information et de prévention (médecine du travail) dans les délais réglementaires."

        // source: src/pages/DocumentsSoignant.tsx:112 [juridique]
        public static let faussesDeclarations = "Je reconnais que toute fausse déclaration est passible de poursuites (Art. 441-7 du Code pénal)."

        /// Suivi de la date au format `d MMMM yyyy` (fr) : voir `signeeLe(dateFormatee:)`.
        // source: src/pages/DocumentsSoignant.tsx:118 [fragment]
        public static let prefixeSigneeLe = "✅ Attestation signée le"

        /// Bouton qui accomplit l'attestation.
        // source: src/pages/DocumentsSoignant.tsx:127 [consentement]
        public static let signer = "✅ Signer mon attestation"

        /// Tutoiement du web conservé verbatim : le passage au vouvoiement serait une reformulation
        /// (HARD STOP n°4), en attente de la décision de Gabrielle.
        // source: src/pages/DocumentsSoignant.tsx:132 [juridique]
        public static let documentsOriginaux = "Les documents originaux (carnet de vaccination, attestation de médecine du travail) sont vérifiés par l'établissement lors de ta première mission. Jolene enregistre uniquement ta déclaration et sa date de signature, avec un accès restreint."

        // source: src/pages/DocumentsSoignant.tsx:56 [juridique]
        public static let succes = "Attestation signée avec succès !"

        /// « ✅ Attestation signée le <date> » (l.118), date déjà formatée `d MMMM yyyy` en français.
        public static func signeeLe(dateFormatee: String) -> String {
            prefixeSigneeLe + " " + dateFormatee
        }
    }

    /// Lecture d'un contrat (`ContratMission.tsx` l.552-837) : bandeaux de statut, CDD à préparer,
    /// document figé et empreinte, contenu indisponible, mode OTP, pied de page juridique.
    public enum Contrat {
        // source: src/pages/ContratMission.tsx:554 [juridique]
        public static let annule = "❌ Ce contrat a été annulé suite à l'annulation de la mission."

        // source: src/pages/ContratMission.tsx:559 [juridique]
        public static let expire = "⏰ Contrat expiré — non signé dans les 72h. La mission a été annulée."

        // source: src/pages/ContratMission.tsx:564 [juridique]
        public static let refuse = "❌ Ce contrat a été refusé par l'une des parties."

        // source: src/pages/ContratMission.tsx:571 [juridique]
        public static let autrePartieASigne = "⏳ L'autre partie a déjà signé"

        // source: src/pages/ContratMission.tsx:573 [juridique]
        public static let autrePartieASigneDetail = "Vous pouvez signer maintenant. Le contrat devient complet dès que les deux signatures sont enregistrées, quel que soit leur ordre."

        /// CDD sans original préparé par l'employeur (LOT2_PLAN §7 Q19) : aucune action soignant.
        // source: src/pages/ContratMission.tsx:603 [juridique]
        public static let cddAPreparer = "Le contrat doit être préparé et confirmé par un représentant autorisé de l’employeur avant les signatures."

        /// Suivi de la date `dd/MM/yyyy 'à' HH:mm` : voir `documentOfficielFige(dateFormatee:empreinte:)`.
        // source: src/pages/ContratMission.tsx:623 [fragment]
        public static let documentFigeLe = "Document officiel figé le"

        // source: src/pages/ContratMission.tsx:624 [fragment]
        public static let empreinteLibelle = "— empreinte"

        // source: src/pages/ContratMission.tsx:624 [fragment]
        public static let empreinteEllipse = "…"

        // source: src/pages/ContratMission.tsx:636 [juridique]
        public static let originalIndisponible = "Le document signé d’origine est indisponible. Aucune reconstitution automatique n’est effectuée."

        // source: src/pages/ContratMission.tsx:637 [libellé]
        public static let contenuPasDisponible = "Le contenu du contrat n'est pas encore disponible."

        // source: src/pages/ContratMission.tsx:740 [juridique]
        public static let otpLibelle = "📱 Signature électronique OTP SMS"

        // source: src/pages/ContratMission.tsx:743 [juridique]
        public static let otpDescription = "Code SMS à 6 chiffres + horodatage + hash document. Conforme art. 1366-1367 Code civil."

        // source: src/pages/ContratMission.tsx:822 [juridique]
        public static let dejaSigne = "✅ Vous avez déjà signé ce contrat"

        // source: src/pages/ContratMission.tsx:832 [fragment]
        public static let mentionCadreEmployeur = "Contrat salarié préparé selon le cadre déclaré par l’employeur."

        // source: src/pages/ContratMission.tsx:834 [fragment]
        public static let mentionSalarieEcrit = "Contrat salarié écrit — art. L.1242-12 du Code du travail."

        // source: src/pages/ContratMission.tsx:835 [fragment]
        public static let mentionPrestationLiberale = "Contrat de prestation entre l’établissement et le professionnel libéral."

        // source: src/pages/ContratMission.tsx:836 [fragment]
        public static let signatureElectroniqueSimple = "Signature électronique simple."

        // source: src/pages/ContratMission.tsx:836 [fragment]
        public static let regularisationMontants = "Les montants prévisionnels sont régularisés selon les heures validées et les éventuelles corrections contradictoires."

        /// Mention du pied de page (l.832-835), choisie comme le web : `cadreEmployeur` quand
        /// `texteEmployeur` est vrai (CDD au cadre déclaré par l'employeur, l.535-537), sinon
        /// `salarieEcrit` pour `type_contrat` CDD ou SALARIE (l.833), sinon `prestationLiberale`.
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
        /// puis la régularisation des montants, sauf pour un contrat au cadre déclaré par l'employeur
        /// (`{!texteEmployeur && …}`, l.836).
        public static func piedDePage(_ mention: MentionPiedDePage) -> String {
            let base = mention.texte + " " + signatureElectroniqueSimple
            return mention == .cadreEmployeur ? base : base + " " + regularisationMontants
        }

        /// « Document officiel figé le <date> — empreinte <8 premiers>…<4 derniers> » (l.620-625),
        /// affiché quand `contenu_html_rendu_le` existe ; sans empreinte (NULL ou vide), la date
        /// seule, comme le web.
        public static func documentOfficielFige(dateFormatee: String, empreinte: String?) -> String {
            let base = documentFigeLe + " " + dateFormatee
            guard let empreinte, !empreinte.isEmpty else { return base }
            return base + " " + empreinteLibelle + " " + String(empreinte.prefix(8)) + empreinteEllipse
                + String(empreinte.suffix(4))
        }
    }

    /// Signature OTP SMS (`SignerContratOtp.tsx`) : messages d'erreur par code (`MESSAGES_ERREUR`
    /// l.30-44), codes bloquants (l.115-119), consentement lié au document affiché, bouton de
    /// signature, confirmation, tentatives restantes. Minuteur, envoi du code, renvoi et erreurs
    /// génériques : `LibellesWeb.SignatureOtp`.
    public enum SignatureOtp {
        // source: src/components/SignerContratOtp.tsx:31 [libellé]
        public static let nonAuthentifie = "Session expirée. Reconnectez-vous puis réessayez."

        // source: src/components/SignerContratOtp.tsx:32 [juridique]
        public static let nonAutorise = "Vous n'êtes pas autorisé(e) à signer ce contrat."

        // source: src/components/SignerContratOtp.tsx:33 [libellé]
        public static let contratIntrouvable = "Contrat introuvable. Rechargez la page."

        // source: src/components/SignerContratOtp.tsx:34 [juridique]
        public static let contratInactif = "Ce contrat a été annulé ou a expiré et ne peut plus être signé."

        // source: src/components/SignerContratOtp.tsx:35 [juridique]
        public static let contratDejaComplet = "Ce contrat est déjà entièrement signé par les deux parties."

        // source: src/components/SignerContratOtp.tsx:36 [libellé]
        public static let telephoneManquant = "Votre numéro de téléphone est manquant. Mettez à jour votre profil avant de signer."

        // source: src/components/SignerContratOtp.tsx:37 [libellé]
        public static let tropDeSms = "Trop de SMS envoyés (3 max / 24h). Réessayez plus tard ou contactez le support."

        // source: src/components/SignerContratOtp.tsx:38 [libellé]
        public static let otpNonDemande = "Demandez d'abord un code SMS en cliquant sur le bouton."

        // source: src/components/SignerContratOtp.tsx:39 [libellé]
        public static let otpExpire = "Le code SMS a expiré (10 min). Demandez un nouveau code."

        // source: src/components/SignerContratOtp.tsx:40 [libellé]
        public static let otpIncorrect = "Code incorrect. Vérifiez votre SMS et réessayez."

        // source: src/components/SignerContratOtp.tsx:41 [libellé]
        public static let tropDeTentatives = "Trop de tentatives. Renvoyez un nouveau code SMS."

        // source: src/components/SignerContratOtp.tsx:42 [juridique]
        public static let dejaSigne = "Vous avez déjà signé ce contrat."

        // source: src/components/SignerContratOtp.tsx:43 [juridique]
        public static let hashDocumentChange = "Le contrat a été modifié depuis votre chargement. Rechargez la page avant de signer."

        // source: src/components/SignerContratOtp.tsx:171 [consentement]
        public static let consentementRequis = "Vous devez accepter les termes du contrat avant de signer."

        // source: src/components/SignerContratOtp.tsx:242 [juridique]
        public static let titre = "Signature électronique sécurisée"

        // source: src/components/SignerContratOtp.tsx:244-245 [juridique]
        public static let explication = "Recevez un code à 6 chiffres par SMS et saisissez-le ci-dessous pour signer. La signature inclut horodatage, IP et hash SHA-256 du document (preuve juridique art. 1366 Code civil)."

        /// Case à cocher : le consentement vaut pour la révision affichée (clé contrat + empreinte, l.62-63).
        // source: src/components/SignerContratOtp.tsx:276 [consentement]
        public static let consentement = "J'ai lu l'intégralité du contrat affiché ci-dessus et j'accepte ses termes."

        // source: src/components/SignerContratOtp.tsx:288 [libellé]
        public static let recevoirCode = "Recevoir le code SMS pour signer"

        /// Bouton qui accomplit la signature.
        // source: src/components/SignerContratOtp.tsx:348 [consentement]
        public static let signer = "Signer"

        /// Message posé après une signature acceptée (l.197) : voir `confirmationSignature(contratComplet:)`.
        // source: src/components/SignerContratOtp.tsx:197 [juridique]
        public static let contratSigneMessage = "Contrat signé ✅"

        // source: src/components/SignerContratOtp.tsx:197 [fragment]
        public static let missionConfirmee = "— Mission confirmée par les 2 parties."

        /// Repli de l'écran signé quand aucun message n'a été posé (l.214).
        // source: src/components/SignerContratOtp.tsx:214 [juridique]
        public static let contratSigne = "Contrat signé ✅"

        // source: src/components/SignerContratOtp.tsx:216 [juridique]
        public static let signeAvecSucces = "Signé avec succès. Horodatage, IP et hash du document conservés (art. 1366-1367 Code civil)."

        /// Tentatives restantes après un code faux (l.322-328) : voir `tentativesRestantes(n:)`.
        // source: src/components/SignerContratOtp.tsx:326 [fragment]
        public static let tentativesCodeIncorrect = "Code incorrect."

        // source: src/components/SignerContratOtp.tsx:326 [fragment]
        public static let tentativesMot = "tentative"

        // source: src/components/SignerContratOtp.tsx:326 [fragment]
        public static let tentativesPlurielTentative = "s"

        // source: src/components/SignerContratOtp.tsx:326 [fragment]
        public static let tentativesRestanteMot = "restante"

        // source: src/components/SignerContratOtp.tsx:326 [fragment]
        public static let tentativesPlurielRestante = "s"

        // source: src/components/SignerContratOtp.tsx:326 [fragment]
        public static let tentativesPoint = "."

        // source: src/components/SignerContratOtp.tsx:327 [libellé]
        public static let tentativesEpuisees = "Trop de tentatives. Renvoyez un nouveau code SMS."

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
        /// s'il est connu, sinon le message du serveur verbatim, sinon le repli
        /// (`LibellesWeb.SignatureOtp.repliEnvoi` ou `repliSignature`), sinon le défaut du web.
        public static func message(code: String?, erreurServeur: String?, repli: String) -> String {
            if let code, let texte = parCode[code] { return texte }
            let secours = erreurServeur.flatMap { $0.isEmpty ? nil : $0 } ?? repli
            return secours.isEmpty ? LibellesWeb.SignatureOtp.messageParDefaut : secours
        }

        /// Confirmation après signature (l.195-198, affichée l.214) : « Contrat signé ✅ », complétée
        /// quand les deux parties ont signé.
        public static func confirmationSignature(contratComplet: Bool) -> String {
            contratComplet ? contratSigneMessage + " " + missionConfirmee : contratSigneMessage
        }

        /// Tentatives restantes (l.322-328) : rien à partir de 5 ; « Code incorrect. <n> tentative(s)
        /// restante(s). » au-dessus de 0 (pluriel au-delà de 1) ; sinon les tentatives épuisées.
        public static func tentativesRestantes(n: Int) -> String? {
            guard n < 5 else { return nil }
            guard n > 0 else { return tentativesEpuisees }
            let tentative = tentativesMot + (n > 1 ? tentativesPlurielTentative : "")
            let restante = tentativesRestanteMot + (n > 1 ? tentativesPlurielRestante : "")
            return tentativesCodeIncorrect + " " + String(n) + " " + tentative + " " + restante + tentativesPoint
        }
    }

    /// Compte à rebours de 72 h de la signature (`Countdown72hSignature.tsx`), dérivé de
    /// `contrats_mission.cree_le` (LOT2_PLAN correction 13), jamais stocké. Unités de la durée :
    /// `LibellesWeb.CompteARebours`.
    public enum CompteARebours {
        // source: src/components/Countdown72hSignature.tsx:43 [juridique]
        public static let expire = "⚠\u{FE0F} Délai de signature expiré (72h dépassées)."

        // source: src/components/Countdown72hSignature.tsx:69 [fragment]
        public static let urgent = "Signature urgente — moins de 24h restantes !"

        // source: src/components/Countdown72hSignature.tsx:70 [fragment]
        public static let aFinaliserSous = "Signature à finaliser sous"

        /// Texte du compte à rebours (l.38-75) : expiré à zéro ; sinon l'alerte urgente sous 24 h
        /// (couleur `destructive`, l.53-56) ou « Signature à finaliser sous », suivi de la durée
        /// restante (l.71-73).
        public static func texte(restantSecondes: Int) -> String {
            guard restantSecondes > 0 else { return expire }
            let duree = LibellesWeb.CompteARebours.duree(restantSecondes: restantSecondes)
            return (restantSecondes / 3600 < 24 ? urgent : aFinaliserSous) + " " + duree
        }
    }

    /// Certificat des signatures (`CertificatSignature.tsx`, variante « résumé » des parties) et page
    /// `/contrat/:id/certificat` qui le monte (`CertificatSignaturePage.tsx` l.176-219). Document
    /// probatoire : chacun de ses textes affirme une preuve, il est donc entièrement HARD STOP
    /// (sauf « Contrat <numéro> », `LibellesWeb.Certificat`).
    public enum Certificat {
        // source: src/components/CertificatSignature.tsx:95 [juridique]
        public static let titre = "Certificat de signature Jolene"

        /// Statut d'une signature : voir `statut(estSigne:codeBrut:)`.
        // source: src/components/CertificatSignature.tsx:121 [juridique]
        public static let signe = "✅ Signé"

        // source: src/components/CertificatSignature.tsx:128 [juridique]
        public static let dateHeure = "Date / heure"

        // source: src/components/CertificatSignature.tsx:136 [juridique]
        public static let otpValide = "OTP validé"

        // source: src/components/CertificatSignature.tsx:137 [juridique]
        public static let codeSmsVerifie = "✓ Code SMS vérifié"

        // source: src/components/CertificatSignature.tsx:162 [juridique]
        public static let rppsVerifie = "RPPS vérifié"

        // source: src/components/CertificatSignature.tsx:163 [fragment]
        public static let rppsOui = "✓"

        // source: src/components/CertificatSignature.tsx:163 [fragment]
        public static let rppsNon = "—"

        // source: src/components/CertificatSignature.tsx:164 [juridique]
        public static let pscActif = "PSC actif"

        // source: src/components/CertificatSignature.tsx:165 [fragment]
        public static let pscOui = "✓"

        // source: src/components/CertificatSignature.tsx:165 [fragment]
        public static let pscNon = "—"

        // source: src/components/CertificatSignature.tsx:172-175 [juridique]
        public static let mention = "Signature électronique sécurisée Jolene — conforme art. 1366-1367 Code civil (signature électronique simple/avancée renforcée par OTP SMS + horodatage + IP). Pour une signature qualifiée eIDAS, contactez un Prestataire de Services de Confiance qualifié."

        // source: src/pages/CertificatSignaturePage.tsx:185 [juridique]
        public static let titrePage = "Certificat de signature"

        /// Bloc affiché quand le contrat porte une empreinte (l.201-211) : titre, empreinte complète,
        /// explication (voir `explicationEmpreinte(storagePath:)`).
        // source: src/pages/CertificatSignaturePage.tsx:203 [juridique]
        public static let empreinteTitre = "Empreinte du document signé"

        // source: src/pages/CertificatSignaturePage.tsx:206-207 [fragment]
        public static let empreinteExplicationDebut = "SHA-256 du contrat figé au moment de la signature. Si vous recalculez le hash du contenu HTML stocké (storage_path :"

        // source: src/pages/CertificatSignaturePage.tsx:207 [fragment]
        public static let empreinteStorageAbsent = "—"

        // source: src/pages/CertificatSignaturePage.tsx:207-208 [fragment]
        public static let empreinteExplicationFin = "), vous devez retrouver cette empreinte — c'est la preuve que le document n'a pas été modifié depuis la signature."

        // source: src/pages/CertificatSignaturePage.tsx:214-215 [juridique]
        public static let mentionPage = "Conforme art. 1366-1367 Code civil — Signature électronique sécurisée Jolene renforcée par OTP SMS + horodatage + IP + hash SHA-256. Audit trail complet disponible sur demande pour les admins plateforme."

        /// Statut d'une signature (l.121) : « ✅ Signé » quand `statut_signature` vaut `signe`
        /// (`estSigne`), sinon la valeur brute du serveur.
        public static func statut(estSigne: Bool, codeBrut: String) -> String {
            estSigne ? signe : codeBrut
        }

        /// Valeur de « RPPS vérifié » (l.162-163).
        public static func rpps(verifie: Bool) -> String {
            verifie ? rppsOui : rppsNon
        }

        /// Valeur de « PSC actif » (l.164-165).
        public static func psc(actif: Bool) -> String {
            actif ? pscOui : pscNon
        }

        /// Explication sous l'empreinte (l.205-209) : le chemin Storage du contrat
        /// (`contrat.storage_path || '—'`) entre les deux phrases, comme le rendu React.
        public static func explicationEmpreinte(storagePath: String?) -> String {
            let chemin = storagePath.flatMap { $0.isEmpty ? nil : $0 } ?? empreinteStorageAbsent
            return empreinteExplicationDebut + " " + chemin + empreinteExplicationFin
        }
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
        .init(cle: "ProfilConsentementGps.titre", texte: ProfilConsentementGps.titre),
        .init(cle: "ProfilConsentementGps.libelle", texte: ProfilConsentementGps.libelle),
        .init(cle: "ProfilConsentementGps.libelleAccessibilite", texte: ProfilConsentementGps.libelleAccessibilite),
        .init(cle: "ProfilConsentementGps.explicationActive", texte: ProfilConsentementGps.explicationActive),
        .init(cle: "ProfilConsentementGps.explicationRetiree", texte: ProfilConsentementGps.explicationRetiree),
        .init(cle: "ProfilConsentementGps.active", texte: ProfilConsentementGps.active),
        .init(cle: "ProfilConsentementGps.retire", texte: ProfilConsentementGps.retire),
        .init(cle: "Presences.consentementGpsEnregistre", texte: Presences.consentementGpsEnregistre),
        .init(cle: "Presences.pointageSansGpsActive", texte: Presences.pointageSansGpsActive),
        .init(cle: "Presences.bandeauAValider", texte: Presences.bandeauAValider),
        .init(cle: "Presences.relanceTitre", texte: Presences.relanceTitre),
        .init(cle: "Presences.relanceExplication", texte: Presences.relanceExplication),
        .init(cle: "Contestation.statutOuvert", texte: Contestation.statutOuvert),
        .init(cle: "Contestation.statutEnDiscussion", texte: Contestation.statutEnDiscussion),
        .init(cle: "Contestation.statutEnMediation", texte: Contestation.statutEnMediation),
        .init(cle: "Contestation.statutMediationEnCours", texte: Contestation.statutMediationEnCours),
        .init(cle: "Contestation.statutRevueAdmin", texte: Contestation.statutRevueAdmin),
        .init(cle: "Contestation.statutResoluSoignant", texte: Contestation.statutResoluSoignant),
        .init(cle: "Contestation.statutResoluEtablissement", texte: Contestation.statutResoluEtablissement),
        .init(cle: "Contestation.statutResoluAdmin", texte: Contestation.statutResoluAdmin),
        .init(cle: "Contestation.statutResoluAccordParties", texte: Contestation.statutResoluAccordParties),
        .init(cle: "Contestation.statutResoluFaveurSoignant", texte: Contestation.statutResoluFaveurSoignant),
        .init(cle: "Contestation.statutResoluFaveurEtab", texte: Contestation.statutResoluFaveurEtab),
        .init(cle: "Contestation.statutResoluPartage", texte: Contestation.statutResoluPartage),
        .init(cle: "Contestation.statutFerme", texte: Contestation.statutFerme),
        .init(cle: "AttestationSante.titre", texte: AttestationSante.titre),
        .init(cle: "AttestationSante.vaccinations", texte: AttestationSante.vaccinations),
        .init(cle: "AttestationSante.medecineDuTravail", texte: AttestationSante.medecineDuTravail),
        .init(cle: "AttestationSante.faussesDeclarations", texte: AttestationSante.faussesDeclarations),
        .init(cle: "AttestationSante.prefixeSigneeLe", texte: AttestationSante.prefixeSigneeLe),
        .init(cle: "AttestationSante.signer", texte: AttestationSante.signer),
        .init(cle: "AttestationSante.documentsOriginaux", texte: AttestationSante.documentsOriginaux),
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
        .init(cle: "SignatureOtp.consentementRequis", texte: SignatureOtp.consentementRequis),
        .init(cle: "SignatureOtp.titre", texte: SignatureOtp.titre),
        .init(cle: "SignatureOtp.explication", texte: SignatureOtp.explication),
        .init(cle: "SignatureOtp.consentement", texte: SignatureOtp.consentement),
        .init(cle: "SignatureOtp.recevoirCode", texte: SignatureOtp.recevoirCode),
        .init(cle: "SignatureOtp.signer", texte: SignatureOtp.signer),
        .init(cle: "SignatureOtp.contratSigneMessage", texte: SignatureOtp.contratSigneMessage),
        .init(cle: "SignatureOtp.missionConfirmee", texte: SignatureOtp.missionConfirmee),
        .init(cle: "SignatureOtp.contratSigne", texte: SignatureOtp.contratSigne),
        .init(cle: "SignatureOtp.signeAvecSucces", texte: SignatureOtp.signeAvecSucces),
        .init(cle: "SignatureOtp.tentativesCodeIncorrect", texte: SignatureOtp.tentativesCodeIncorrect),
        .init(cle: "SignatureOtp.tentativesMot", texte: SignatureOtp.tentativesMot),
        .init(cle: "SignatureOtp.tentativesPlurielTentative", texte: SignatureOtp.tentativesPlurielTentative),
        .init(cle: "SignatureOtp.tentativesRestanteMot", texte: SignatureOtp.tentativesRestanteMot),
        .init(cle: "SignatureOtp.tentativesPlurielRestante", texte: SignatureOtp.tentativesPlurielRestante),
        .init(cle: "SignatureOtp.tentativesPoint", texte: SignatureOtp.tentativesPoint),
        .init(cle: "SignatureOtp.tentativesEpuisees", texte: SignatureOtp.tentativesEpuisees),
        .init(cle: "CompteARebours.expire", texte: CompteARebours.expire),
        .init(cle: "CompteARebours.urgent", texte: CompteARebours.urgent),
        .init(cle: "CompteARebours.aFinaliserSous", texte: CompteARebours.aFinaliserSous),
        .init(cle: "Certificat.titre", texte: Certificat.titre),
        .init(cle: "Certificat.signe", texte: Certificat.signe),
        .init(cle: "Certificat.dateHeure", texte: Certificat.dateHeure),
        .init(cle: "Certificat.otpValide", texte: Certificat.otpValide),
        .init(cle: "Certificat.codeSmsVerifie", texte: Certificat.codeSmsVerifie),
        .init(cle: "Certificat.rppsVerifie", texte: Certificat.rppsVerifie),
        .init(cle: "Certificat.rppsOui", texte: Certificat.rppsOui),
        .init(cle: "Certificat.rppsNon", texte: Certificat.rppsNon),
        .init(cle: "Certificat.pscActif", texte: Certificat.pscActif),
        .init(cle: "Certificat.pscOui", texte: Certificat.pscOui),
        .init(cle: "Certificat.pscNon", texte: Certificat.pscNon),
        .init(cle: "Certificat.mention", texte: Certificat.mention),
        .init(cle: "Certificat.titrePage", texte: Certificat.titrePage),
        .init(cle: "Certificat.empreinteTitre", texte: Certificat.empreinteTitre),
        .init(cle: "Certificat.empreinteExplicationDebut", texte: Certificat.empreinteExplicationDebut),
        .init(cle: "Certificat.empreinteStorageAbsent", texte: Certificat.empreinteStorageAbsent),
        .init(cle: "Certificat.empreinteExplicationFin", texte: Certificat.empreinteExplicationFin),
        .init(cle: "Certificat.mentionPage", texte: Certificat.mentionPage),
    ]
}
