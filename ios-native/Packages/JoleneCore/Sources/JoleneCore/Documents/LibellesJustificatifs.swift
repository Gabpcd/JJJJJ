import Foundation

/// Libellés de l'écran Justificatifs et de « Mes documents » (lot 2 T7). Aucun texte nouveau : chaque libellé est celui
/// du web à la ligne annoncée, repris tel quel ou vouvoyé quand le web tutoie (décision 9 du lot 1, même règle que
/// `MessagesDocuments` : seule la personne change, verbe, pronom et possessif). Garde : `LibellesJustificatifsTests`
/// relit les sources web ligne à ligne. Les textes juridiques de la page (attestation sur l'honneur) restent dans
/// `Legal/TextesWeb.swift` (HARD STOP n°4) ; ceux que le natif n'affiche pas encore (bandeau RCP, textes d'accès des
/// documents complémentaires, encart RIB) sont « En attente de Gabrielle » (`docs/mobile-swift/DECISIONS_LOT2.md`).
/// Les rares textes sans équivalent web (`textesOperationnels`) y sont inventoriés mot pour mot.
public enum LibellesJustificatifs {
    // MARK: - Mes documents (`src/pages/MesDocuments.tsx`)

    // source: src/pages/MesDocuments.tsx:27
    public static let titre = "Mes documents"
    // source: src/pages/MesDocuments.tsx:36
    public static let ongletJustificatifs = "Justificatifs"
    // source: src/pages/MesDocuments.tsx:40
    public static let ongletContrats = "Contrats"
    // source: src/pages/MesDocuments.tsx:44
    public static let ongletDpae = "DPAE"

    /// Onglet ou écran sans version native (DPAE, contrats avant T9a, drapeau `ios_natif_documents_actif` à faux) : texte
    /// du lot 0 (`MobileAccess.unsupportedRole`), repris tel quel.
    public static var espaceNonDisponible: String {
        MobileAccess.unsupportedRole(nil).message ?? ""
    }

    /// Renvoi web présenté par `PresentateurRenvoiWeb` : texte du lot 1. source: ios-native/Jolene/Screens/Accueil/AccueilScreen.swift:283
    public static let voirSurJoleneApp = "Voir sur jolene.app"
    /// Session expirée côté serveur : textes du lot 1 (`MissionsListScreen.swift` l.107-108).
    public static let sessionAVerifier = "Session à vérifier"
    public static let verifierMaSession = "Vérifier ma session"
    public static let messageSessionExpiree = SessionController.sessionExpiredMessage

    // MARK: - États de la page (`src/pages/DocumentsSoignant.tsx`)

    // source: src/pages/DocumentsSoignant.tsx:490
    public static let documentsIndisponibles = "Documents indisponibles"
    // source: src/pages/DocumentsSoignant.tsx:499 (et l.767)
    public static let reessayer = "Réessayer"
    // source: src/pages/DocumentsSoignant.tsx:509
    public static let dossierTitre = "Votre dossier, quand vous en aurez besoin"
    // source: src/pages/DocumentsSoignant.tsx:511
    public static let dossierTexte = "Vous pouvez découvrir les missions sans ajouter de document. Vous préparerez votre dossier professionnel lorsque vous souhaiterez candidater."
    // source: src/pages/DocumentsSoignant.tsx:534
    public static let professionNonDefinie = "Profession non définie"
    // source: src/pages/DocumentsSoignant.tsx:536 (vouvoyé)
    public static let professionNonDefinieTexte = "Renseignez votre profession dans votre profil pour voir les documents qui vous concernent."
    // source: src/pages/DocumentsSoignant.tsx:547
    public static let modeExerciceTitre = "Mode d’exercice à préciser"
    // source: src/pages/DocumentsSoignant.tsx:549 (vouvoyé)
    public static let modeExerciceTexte = "Les justificatifs communs sont affichés ici. Les pièces propres au salariat ou au libéral seront précisées quand vous renseignerez votre mode d’exercice. Vous pouvez continuer à explorer les missions."

    // MARK: - En-tête de progression (l.558-598)

    // source: src/pages/DocumentsSoignant.tsx:561 (vouvoyé)
    public static let resteDebut = "Il vous reste"
    // source: src/pages/DocumentsSoignant.tsx:561
    public static let resteDocument = "document"
    // source: src/pages/DocumentsSoignant.tsx:561
    public static let resteFin = "— ~3 min, une photo suffit"
    // source: src/pages/DocumentsSoignant.tsx:566
    public static let prochaineEtape = "Prochaine étape :"
    // source: src/pages/DocumentsSoignant.tsx:575
    public static let televerserPrefixe = "Téléverser —"
    // source: src/pages/DocumentsSoignant.tsx:583 (vouvoyé)
    public static let postulerDesMaintenant = "Vous pouvez postuler dès maintenant — validez vos documents pour être accepté par les établissements."
    // source: src/pages/DocumentsSoignant.tsx:590 (vouvoyé)
    public static let aJourExercice = "Tous vos documents obligatoires sont à jour 🎉"
    // source: src/pages/DocumentsSoignant.tsx:590
    public static let aJourSansExercice = "Les justificatifs affichés sont à jour"
    // source: src/pages/DocumentsSoignant.tsx:591 (vouvoyé)
    public static let retrouvezIci = "Retrouvez ici vos justificatifs et leurs dates de validité."
    // source: src/pages/DocumentsSoignant.tsx:595
    public static let vosJustificatifs = "Vos justificatifs"
    // source: src/pages/DocumentsSoignant.tsx:596
    public static let aucunObligatoire = "Aucun document obligatoire n’est affiché pour votre profil actuellement."

    // MARK: - Expiration proche et incohérence (l.287-306, l.601-650)

    // source: src/pages/DocumentsSoignant.tsx:605 (vouvoyé)
    public static let expirePrefixe = "⏰ Votre"
    // source: src/pages/DocumentsSoignant.tsx:605
    public static let expireDans = "expire dans"
    // source: src/pages/DocumentsSoignant.tsx:605
    public static let jour = "jour"
    // source: src/pages/DocumentsSoignant.tsx:606
    public static let mettreAJour = "Mettre à jour →"
    // source: src/pages/DocumentsSoignant.tsx:293 (vouvoyé)
    public static let rcpExpireeCoherence = "Votre assurance RCP est expirée"
    // source: src/pages/DocumentsSoignant.tsx:647 (vouvoyé)
    public static let incoherencePrefixe = "⚠️ Incohérence détectée entre vos documents :"
    // source: src/pages/DocumentsSoignant.tsx:647 (vouvoyé)
    public static let incoherenceFin = "Vérifiez que tous vos documents sont à jour et au même nom."

    // MARK: - Cartes des exigences (l.654-811)

    // source: src/pages/DocumentsSoignant.tsx:671
    public static let documentsOptionnels = "Documents optionnels"
    // source: src/pages/DocumentsSoignant.tsx:684
    public static let obligatoire = "★ OBLIGATOIRE"
    // source: src/pages/DocumentsSoignant.tsx:693
    public static let televerseLe = "(téléversé le"
    // source: src/pages/DocumentsSoignant.tsx:697
    public static let verifie = "Vérifié ✅"
    // source: src/pages/DocumentsSoignant.tsx:702
    public static let qualificationDebut = "La qualification"
    // source: src/pages/DocumentsSoignant.tsx:702 (vouvoyé)
    public static let qualificationFin = "n’est pas confirmée par ce diplôme. Vous pouvez le remplacer ou demander une nouvelle vérification."
    // source: src/pages/DocumentsSoignant.tsx:708
    public static let verificationAutomatiqueEnCours = "Vérification automatique en cours (~30 s)"
    // source: src/pages/DocumentsSoignant.tsx:708
    public static let analyseNonConclue = "Analyse non conclue — revue humaine disponible"
    // source: src/pages/DocumentsSoignant.tsx:713
    public static let demandeRecue = "Demande reçue — en attente d’attribution"
    // source: src/pages/DocumentsSoignant.tsx:718
    public static let verificationIndisponible = "Vérification temporairement indisponible"
    // source: src/pages/DocumentsSoignant.tsx:722
    public static let delivreLe = "Délivré le"
    // source: src/pages/DocumentsSoignant.tsx:725
    public static let valideJusquau = "Valide jusqu'au"
    // source: src/pages/DocumentsSoignant.tsx:728
    public static let voirLeDocument = "Voir le document"
    // source: src/pages/DocumentsSoignant.tsx:736
    public static let reverifier = "Revérifier"
    // source: src/pages/DocumentsSoignant.tsx:745
    public static let demandeEnCours = "Demande en cours…"
    // source: src/pages/DocumentsSoignant.tsx:745
    public static let demanderRevue = "Demander une revue humaine"
    // source: src/pages/DocumentsSoignant.tsx:748
    public static let remplacer = "Remplacer"
    // source: src/pages/DocumentsSoignant.tsx:756
    public static let verificationEnCours = "Vérification en cours (~30 s)"
    // source: src/pages/DocumentsSoignant.tsx:761
    public static let documentNonValide = "Document non valide"
    // source: src/pages/DocumentsSoignant.tsx:761 (vouvoyé)
    public static let documentNonValideFin = ". Vous pouvez le remplacer ou demander une revue humaine."
    // source: src/pages/DocumentsSoignant.tsx:763
    public static let rejete = "Rejeté"
    // source: src/pages/DocumentsSoignant.tsx:768
    public static let voir = "Voir"
    // source: src/pages/DocumentsSoignant.tsx:788
    public static let expireDepuis = "Document expiré depuis le"
    // source: src/pages/DocumentsSoignant.tsx:788
    public static let expireDepuisFin = ". Veuillez en téléverser un récent."
    // source: src/pages/DocumentsSoignant.tsx:789
    public static let expire = "Expiré"
    // source: src/pages/DocumentsSoignant.tsx:791
    public static let televerserNouveau = "Téléverser un nouveau document"
    // source: src/pages/DocumentsSoignant.tsx:804
    public static let aTeleverser = "Document à téléverser — une photo suffit"
    // source: src/pages/DocumentsSoignant.tsx:806
    public static let plusTeleverser = "+ Téléverser"

    // MARK: - Documents complémentaires et attestation (l.852-911)

    // source: src/pages/DocumentsSoignant.tsx:862
    public static let etudiantInterne = "Étudiant / interne en santé"
    // source: src/pages/DocumentsSoignant.tsx:865
    public static let titreScolarite = "🎓 Attestation de scolarité / passage en année supérieure"
    // source: src/pages/DocumentsSoignant.tsx:880
    public static let titreLicence = "🩺 Licence de remplacement (interne en médecine)"
    // source: src/pages/DocumentsSoignant.tsx:895
    public static let titreQualification = "Inscription à l’Ordre après l’internat"
    // source: src/pages/DocumentsSoignant.tsx:896 (vouvoyé)
    public static let descriptionQualification = "Vous êtes désormais médecin inscrit à l’Ordre ? Ajoutez l’attestation précisant votre qualification. L’équipe vérifiera cette preuve pour mettre à jour votre parcours."
    // source: src/pages/DocumentsSoignant.tsx:897
    public static let statutAActualiser = "Statut à actualiser"
    // source: src/pages/DocumentsSoignant.tsx:899
    public static let remplacerAttestation = "Remplacer l’attestation"
    // source: src/pages/DocumentsSoignant.tsx:899
    public static let ajouterAttestation = "+ Ajouter l’attestation"
    // source: src/pages/DocumentsSoignant.tsx:908
    public static let derniereEtape = "Dernière étape"

    // MARK: - Issues (toasts du web, l.318-430)

    // source: src/pages/DocumentsSoignant.tsx:428
    public static let verificationDemandee = "Document téléversé — vérification en cours (~30 s)."
    // source: src/pages/DocumentsSoignant.tsx:419 (et l.425)
    public static let verificationManuelle = "Document téléversé. Vérification manuelle en attente."
    // source: src/pages/DocumentsSoignant.tsx:377 (suivi du message d'erreur, ici le repli `extraireMessageErreur`)
    public static let televersementImpossible = "Téléversement impossible :"
    // source: src/pages/DocumentsSoignant.tsx:354
    public static let revueEnvoyee = "Demande envoyée. Un membre de l’équipe vérifiera le document."
    // source: src/pages/DocumentsSoignant.tsx:318
    public static let reverificationVerifie = "✅ Document vérifié automatiquement !"
    // source: src/pages/DocumentsSoignant.tsx:320
    public static let reverificationRejete = "❌ Document rejeté :"
    // source: src/pages/DocumentsSoignant.tsx:320
    public static let reverificationNonConforme = "Non conforme"
    // source: src/pages/DocumentsSoignant.tsx:322
    public static let reverificationRevue = "Document reçu. Une revue humaine est en attente d’attribution."
    // source: src/pages/DocumentsSoignant.tsx:324
    public static let reverificationAttente = "⏳ Vérification en attente..."

    // MARK: - Feuille de téléversement (`src/components/ModalTeleversement.tsx`)

    // source: src/components/ModalTeleversement.tsx:121
    public static let televerserTitre = "📤 Téléverser"
    // source: src/components/ModalTeleversement.tsx:124
    public static let aidePhoto = "Une photo nette suffit — les dates de validité sont lues automatiquement sur votre document."
    // source: src/components/ModalTeleversement.tsx:138
    public static let prendrePhoto = "Prendre une photo"
    // source: src/components/ModalTeleversement.tsx:163
    public static let choisirGalerie = "Choisir dans la galerie"
    // source: src/components/ModalTeleversement.tsx:200
    public static let choisirFichier = "ou choisissez un fichier"
    // source: src/components/ModalTeleversement.tsx:183
    public static let choisirFichierAccessibilite = "Choisir un document à téléverser"
    // source: src/components/ModalTeleversement.tsx:201
    public static let formats = "PDF, JPEG, PNG ou WebP · 10 Mo max"
    // source: src/components/ModalTeleversement.tsx:191
    public static let formatsAccessibilite = "Formats autorisés : PDF, JPEG, PNG ou WebP, 10 Mo maximum."
    // source: src/components/ModalTeleversement.tsx:194
    public static let fichierChoisi = "📎"
    // source: src/components/ModalTeleversement.tsx:195
    public static let ko = "Ko"
    // source: src/components/ModalTeleversement.tsx:208
    public static let libelleOptionnel = "Libellé (optionnel)"
    // source: src/components/ModalTeleversement.tsx:52
    public static let placeholderParDefaut = "Ex : Description du document"
    // source: src/components/ModalTeleversement.tsx:213
    public static let annuler = "Annuler"
    // source: src/components/ModalTeleversement.tsx:215
    public static let envoi = "Envoi…"
    // source: src/components/ModalTeleversement.tsx:215
    public static let televerser = "Téléverser"
    // source: src/components/ModalTeleversement.tsx:117
    public static let fermerAccessibilite = "Fermer la fenêtre de téléversement"
    // source: src/components/ModalTeleversement.tsx:106
    public static let cameraImpossible = "Impossible d'accéder à la caméra."
    // source: src/components/ModalTeleversement.tsx:158
    public static let galerieImpossible = "Impossible d'accéder à la galerie."

    /// Borne du libellé saisi (`fn_remplacer_document_soignant`, `RecuDocument.libelleMax`).
    public static let libelleMax = RecuDocument.longueurMaxLibelle

    // MARK: - Dictionnaires du web

    // source-objet: src/lib/documents.ts:4 TYPES_DOCUMENTS
    public static let typesDocuments: [String: String] = [
        "CARTE_IDENTITE": "Pièce d'identité",
        "PASSEPORT": "Passeport",
        "TITRE_SEJOUR": "Titre de séjour",
        "DIPLOME": "Diplôme d'État",
        "ATTESTATION_SCOLARITE": "Attestation de scolarité / passage en année supérieure (étudiant)",
        "LICENCE_REMPLACEMENT": "Licence de remplacement (interne en médecine — Ordre des médecins)",
        "CARTE_ORDRE": "Attestation d’inscription à l’Ordre / carte professionnelle",
        "RPPS_ADELI": "Attestation RPPS / ADELI",
        "RCP_ASSURANCE": "Assurance RCP",
        "VACCINATIONS": "Carnet de vaccination",
        "CASIER_JUDICIAIRE": "Extrait de casier judiciaire",
        "RIB": "RIB",
        "KBIS": "KBIS",
        "ATTESTATION_URSSAF": "Attestation URSSAF",
        "AUTORISATION_EXERCICE": "Autorisation d'exercice",
        "MEDECINE_TRAVAIL": "Médecine du travail",
        "FORMATION_OBLIGATOIRE": "Formation obligatoire",
        "AUTRE": "Autre document",
    ]

    // source-objet: src/lib/documents.ts:28 STATUTS_VERIFICATION.label
    public static let statutsVerification: [String: String] = [
        "EN_ATTENTE": "En attente de vérification",
        "VERIFIE": "Vérifié ✓",
        "REJETE": "Rejeté ✗",
        "EXPIRE": "Expiré ⏰",
        "REVUE_MANUELLE_REQUISE": "En cours de vérification",
        "API_INDISPONIBLE": "Vérification temporairement indisponible",
    ]

    // source-objet: src/components/ModalTeleversement.tsx:11 PLACEHOLDERS_LIBELLE
    public static let placeholders: [String: String] = [
        "CARTE_IDENTITE": "Ex : CNI recto-verso",
        "PASSEPORT": "Ex : Passeport page 2-3",
        "TITRE_SEJOUR": "Ex : Titre de séjour recto",
        "DIPLOME": "Ex : Diplôme IDE 2020",
        "RPPS_ADELI": "Ex : Attestation RPPS ordre infirmier",
        "RCP_ASSURANCE": "Ex : Attestation RCP 2025-2026",
        "VACCINATIONS": "Ex : Carnet de vaccination",
        "CASIER_JUDICIAIRE": "Ex : Extrait B3",
        "RIB": "Ex : RIB BNP",
        "KBIS": "Ex : KBIS janvier 2025",
        "ATTESTATION_URSSAF": "Ex : Attestation URSSAF trimestre",
        "AUTORISATION_EXERCICE": "Ex : Autorisation ARS",
        "FORMATION_OBLIGATOIRE": "Ex : Attestation AFGSU",
        "AUTRE": "Ex : Document complémentaire",
    ]

    /// `TYPES_DOCUMENTS[type] || type` (l.566, l.575, l.605) ; aussi pour le titre des cartes (l.685, sans repli sur le
    /// web : un type inconnu y laisse un titre vide, ici son code).
    public static func libelleType(_ typeDocument: String) -> String {
        typesDocuments[typeDocument] ?? typeDocument
    }

    /// `PLACEHOLDERS_LIBELLE[typeDocument] || 'Ex : Description du document'` (`ModalTeleversement.tsx` l.52).
    public static func placeholder(typeDocument: String) -> String {
        placeholders[typeDocument] ?? placeholderParDefaut
    }

    // MARK: - Textes opérationnels sans équivalent web

    // Le web n'a ni journal de reçus ni réconciliation (`DocumentsSoignant.tsx` l.361-431) : ces états n'existent pas
    // sur le web. Inventoriés dans `docs/mobile-swift/DECISIONS_LOT2.md` (« Textes opérationnels hors web (T7) »), sur le
    // modèle de `RecuScan.messageRecuEnCours` / `messageIllisible` (pilote `attemptJournal.ts`). Non juridiques.

    /// Réponse de l'envoi perdue, réconciliation en cours (`IssueEnvoiDocument.incertain`) : aucun renvoi automatique.
    public static let envoiAVerifier = "L'envoi du document est en cours de vérification. Ne le renvoyez pas : cette page se mettra à jour."
    /// Envoi prouvé non reçu (`IssueEnvoiDocument.nonEnvoye`) : aucun octet conservé, nouvelle sélection demandée (décision 14).
    public static let envoiNonRecu = "Le document n'a pas été reçu. Choisissez-le de nouveau puis réessayez."
    /// Un reçu d'un essai précédent reste à vérifier (`DocumentsModel.EtatEnvoi.recuEnCours`).
    public static let envoiPrecedentAVerifier = "Un autre envoi de document doit être vérifié avant de continuer."
    /// Journal de reçus illisible (`DocumentsModel.EtatEnvoi.suiviIllisible`) : envoi bloqué, renvoi web.
    public static let suiviIllisible = "Le suivi sécurisé des envois ne peut pas être vérifié. Aucun nouveau document ne peut être envoyé."
    /// Section « Mon espace » du Profil (blueprint §7 Q24) : titre de section, sans équivalent web (le web n'a pas d'onglet
    /// Profil regroupant présences, documents et contrats).
    public static let monEspace = "Mon espace"

    /// Les textes opérationnels, pour leur garde.
    public static let textesOperationnels = [envoiAVerifier, envoiNonRecu, envoiPrecedentAVerifier, suiviIllisible, monEspace]
}

/// Onglets de « Mes documents » (`src/pages/MesDocuments.tsx` l.13-24), dans l'ordre affiché (l.34-46).
public enum OngletDocuments: String, CaseIterable, Sendable {
    case justificatifs, contrats, dpae

    /// `TABS.includes(tab) ? tab : 'justificatifs'`.
    public init(parametre: String?) {
        self = parametre.flatMap(OngletDocuments.init(rawValue:)) ?? .justificatifs
    }

    public var libelle: String {
        switch self {
        case .justificatifs: return LibellesJustificatifs.ongletJustificatifs
        case .contrats: return LibellesJustificatifs.ongletContrats
        case .dpae: return LibellesJustificatifs.ongletDpae
        }
    }
}
