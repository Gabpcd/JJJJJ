import Foundation

/// Règles pures de l'annulation d'une participation (lot 1, T7, `docs/mobile-swift/LOT1_PLAN.md` §3 T7 et décision 4).
///
/// **Aucun barème côté client** : les points, le caractère libre et la contestabilité viennent du serveur
/// (`fn_annuler_candidature_soignant`, `fn_annuler_mission_soignant`), affichés après la confirmation. Le minuteur de
/// rétractation du web (`AnnulationCandidatureTimer.tsx`, barème recopié côté client) et le message de pénalité de la
/// confirmation sans candidature (`DetailMissionSoignant.tsx` l.1634-1641 : -25 / -15 / -8, contredit par le serveur :
/// -8 seulement à moins de 24 h) ne sont pas portés : écart consigné hors lot (décision 4), textes listés pour Gabrielle
/// (HARD STOP n°4). Ces fonctions disent seulement quel parcours ouvrir, quand le formulaire est complet et ce qu'une
/// relecture doit montrer pour qu'une annulation soit annoncée (PRINCIPES §3).
public enum AnnulationRules {
    /// Parcours d'annulation d'une mission assignée au soignant, comme le web (l.1516-1520) : modale de candidature si une
    /// candidature `ACCEPTEE` existe (`candidatureRec`, l.486-504), confirmation simple sinon.
    public enum Entree: Equatable, Sendable {
        case candidature(id: String)
        case mission
    }

    /// Motifs admis par le serveur (`fn_annuler_candidature_soignant` : `MOTIF_INVALIDE` sinon), dans l'ordre du web
    /// (`MOTIFS`, `ModaleAnnulationCandidature.tsx` l.33-40).
    public enum Motif: String, CaseIterable, Sendable, Identifiable {
        case urgencePersonnelle = "URGENCE_PERSONNELLE"
        case urgenceMedicale = "URGENCE_MEDICALE"
        case deuil = "DEUIL"
        case problemeTransport = "PROBLEME_TRANSPORT"
        case changementAvis = "CHANGEMENT_AVIS"
        case autre = "AUTRE"

        public var id: String { rawValue }

        /// Libellé du web, tel quel (l.34-39).
        public var libelle: String {
            switch self {
            case .urgencePersonnelle: return "🆘 Urgence personnelle"
            case .urgenceMedicale: return "🏥 Urgence médicale"
            case .deuil: return "🕊️ Deuil"
            case .problemeTransport: return "🚗 Problème de transport"
            case .changementAvis: return "🤔 Changement d'avis"
            case .autre: return "❓ Autre"
            }
        }
    }

    /// Seuil de l'explication côté app : 20 caractères après `trim()`, comme le web (l.100, l.249) ; le serveur exige 10
    /// (`TEXTE_REQUIS`), jamais moins strict que lui.
    public static let texteMinimum = 20
    public static let texteMinimumServeur = 10

    public static let statutAssignee = CandidatureRules.statutAssignee
    public static let statutAcceptee = "ACCEPTEE"
    public static let statutAnnulee = "ANNULEE"

    /// Le bouton « Annuler ma participation » n'existe que pour une mission `ASSIGNEE` au soignant de la session
    /// (l.1516 ; `fn_annuler_mission_soignant` refuse tout autre statut).
    public static func annulable(_ mission: MissionRecord, userId: String) -> Bool {
        CandidatureRules.assignationRelue(statut: mission.statut, soignantAssigneId: mission.soignantAssigneId, userId: userId)
    }

    /// Parcours à ouvrir pour cette mission, la candidature du soignant relue (nil si aucune) ; nil si la mission n'est
    /// pas annulable par lui.
    public static func entree(mission: MissionRecord, userId: String, candidature: CandidatureRecord?) -> Entree? {
        guard annulable(mission, userId: userId) else { return nil }
        if let candidature, candidature.missionId.caseInsensitiveCompare(mission.id) == .orderedSame,
           candidature.statut == statutAcceptee {
            return .candidature(id: candidature.id)
        }
        return .mission
    }

    /// Texte libre envoyé : `texte.trim()` du web (l.118).
    public static func texteNettoye(_ texte: String) -> String {
        JSTexte.trim(texte)
    }

    /// Premier manque du formulaire, message du web dans l'ordre de `confirmer()` (l.96-107) ; nil si complet.
    public static func manque(motif: Motif?, texte: String, accepte: Bool) -> String? {
        guard motif != nil else { return LibellesAnnulation.motifRequis }
        guard texteNettoye(texte).utf16.count >= texteMinimum else { return LibellesAnnulation.explicationRequise }
        guard accepte else { return LibellesAnnulation.confirmationRequise }
        return nil
    }

    /// Bouton de confirmation actif (l.249 : `!motif || texte.trim().length < 20 || !accepte` le désactive).
    public static func peutConfirmer(motif: Motif?, texte: String, accepte: Bool) -> Bool {
        manque(motif: motif, texte: texte, accepte: accepte) == nil
    }

    /// Compteur affiché sous l'explication (l.189 : `{texte.length} / 20+`, longueur brute).
    public static func compteur(_ texte: String) -> String {
        "\(texte.utf16.count) / \(texteMinimum)+"
    }

    /// Preuve d'une annulation de candidature : la candidature relue est `ANNULEE`.
    public static func candidatureAnnuleeRelue(_ relue: CandidatureRecord?, id: String) -> Bool {
        guard let relue else { return false }
        return relue.id.caseInsensitiveCompare(id) == .orderedSame && relue.statut == statutAnnulee
    }

    /// Preuve d'une annulation de mission : la mission relue n'est plus attribuée au soignant de la session. Une ligne
    /// absente le prouve aussi : sous RLS (`pol_mission_select`), le soignant assigné lit toujours sa mission.
    public static func missionAnnuleeRelue(statut: String?, soignantAssigneId: String?, userId: String, ligneLue: Bool) -> Bool {
        guard ligneLue else { return true }
        return !CandidatureRules.assignationRelue(statut: statut, soignantAssigneId: soignantAssigneId, userId: userId)
    }

    /// Voie de récupération d'un journal de reçus illisible (consigne « Lot 1 T7 » de `DECISIONS_LOT2.md`) : annulation
    /// depuis le détail web de la mission, qui n'utilise pas ce journal. Route forcée web (le détail est natif).
    public static func routeRenvoiWeb(missionId: String) -> JoleneRoute? {
        JoleneLink.canonicalURL(link: "/soignant/missions/" + missionId).map(JoleneRoute.safari)
    }
}

/// Libellés de l'annulation hors HARD STOP (textes de consentement, de pénalité et de rétractation :
/// `TextesWeb.Annulation`). Repris du web tels quels, vouvoyés quand le web tutoie (décision 9 du lot 1), ou nouveaux
/// pour un état propre à l'app (reçu, reprise), sans portée juridique.
public enum LibellesAnnulation {
    // source: src/pages/DetailMissionSoignant.tsx:1521 (tel quel)
    public static let annulerMaParticipation = "Annuler ma participation"
    // source: src/pages/DetailMissionSoignant.tsx:1633 (vouvoyé : « ta participation »). Message de pénalité non porté.
    public static let titreConfirmationMission = "⚠️ Annuler votre participation ?"
    // source: src/pages/DetailMissionSoignant.tsx:1643 (tel quel)
    public static let nonGarder = "Non, garder"
    // source: src/components/soignant/ModaleAnnulationCandidature.tsx:147 (tel quel)
    public static let titreCandidature = "Annuler votre candidature"
    // source: src/components/soignant/ModaleAnnulationCandidature.tsx:170 (tel quel)
    public static let motifLibelle = "Motif de l'annulation *"
    // source: src/components/soignant/ModaleAnnulationCandidature.tsx:181 (tel quel)
    public static let explicationLibelle = "Explication détaillée * (min 20 caractères)"
    // source: src/components/soignant/ModaleAnnulationCandidature.tsx:187 (tel quel)
    public static let explicationExemple = "Expliquez la situation : que s'est-il passé, pourquoi vous devez annuler maintenant…"
    // source: src/components/soignant/ModaleAnnulationCandidature.tsx:198 (tel quel)
    public static let choisirFichier = "Choisir un fichier"
    // source: src/components/soignant/ModaleAnnulationCandidature.tsx:245 (tel quel)
    public static let garderCandidature = "Garder la candidature"
    // source: src/components/soignant/ModaleAnnulationCandidature.tsx:97 (tel quel)
    public static let motifRequis = "Sélectionnez un motif."
    // source: src/components/soignant/ModaleAnnulationCandidature.tsx:101 (tel quel)
    public static let explicationRequise = "Veuillez ajouter une explication (min 20 caractères)."
    // source: src/components/soignant/ModaleAnnulationCandidature.tsx:105 (tel quel)
    public static let confirmationRequise = "Veuillez cocher la case de confirmation."
    // source: src/components/soignant/ModaleAnnulationCandidature.tsx:125 (tel quel), repli sans `error` serveur
    public static let erreurAnnulation = "Erreur lors de l'annulation."
    /// Choix dans la photothèque (même libellé que la feuille de téléversement des justificatifs, lot 2).
    public static let choisirPhototheque = LibellesJustificatifs.choisirGalerie

    // Nouveaux textes opérationnels de l'app (aucune portée juridique) : reçu, reprise et relecture.
    public static let chargementImpossible = "Les options d'annulation de cette mission n'ont pas pu être chargées. Réessayez."
    public static let reessayer = "Réessayer"
    public static let ouvrirSurLeWeb = "Ouvrir sur jolene.app"
    public static let fichierDejaEnvoye = "Justificatif déjà envoyé :"
    public static let depotImpossible = "Le justificatif n'a pas pu être envoyé. Réessayez."
    public static let depotIncertain = "L'envoi du justificatif n'a pas pu être vérifié. Réessayez : il ne sera pas envoyé deux fois."
    public static let suiviIllisible = "Le suivi sécurisé du justificatif ne peut pas être vérifié sur cet appareil. Annulez depuis jolene.app."
    public static let recuEnCours = "Un autre envoi de justificatif doit être vérifié avant de continuer."
    public static let indisponibleSurCetEcran = "L'envoi d'un justificatif n'est pas disponible sur cet écran. Annulez depuis jolene.app."
}
