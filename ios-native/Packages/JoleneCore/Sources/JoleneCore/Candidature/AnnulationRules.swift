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

    /// Motifs PROPOSÉS par l'app, dans l'ordre du web (`MOTIFS`, `ModaleAnnulationCandidature.tsx` l.33-40), **sans
    /// « 🏥 Urgence médicale »** (`URGENCE_MEDICALE`, l.35) : décision 21 de `LOT1_PLAN.md` §7, application de la décision
    /// de Gabrielle du 09/07/2026 (`docs/CONFORMITE.md` §1.4, l.69-72 : un motif de santé générique n'est pas stocké, le
    /// seul fait d'être malade étant une donnée de santé, RGPD art. 9). Le serveur l'admet encore et l'écrit dans
    /// `candidatures`, `evenements_score_soignant` et `journaux_audit` (`motifsServeur`) : correction web et serveur dans
    /// une PR B9 / HARD STOP séparée. Aucun texte de remplacement.
    public enum Motif: String, CaseIterable, Sendable, Identifiable {
        case urgencePersonnelle = "URGENCE_PERSONNELLE"
        case deuil = "DEUIL"
        case problemeTransport = "PROBLEME_TRANSPORT"
        case changementAvis = "CHANGEMENT_AVIS"
        case autre = "AUTRE"

        public var id: String { rawValue }

        /// Libellé du web, tel quel (`LibellesWeb.Annulation`, sous la garde des textes).
        public var libelle: String {
            switch self {
            case .urgencePersonnelle: return LibellesWeb.Annulation.motifUrgencePersonnelle
            case .deuil: return LibellesWeb.Annulation.motifDeuil
            case .problemeTransport: return LibellesWeb.Annulation.motifProblemeTransport
            case .changementAvis: return LibellesWeb.Annulation.motifChangementAvis
            case .autre: return LibellesWeb.Annulation.motifAutre
            }
        }
    }

    /// Motifs admis par le serveur (`fn_annuler_candidature_soignant`, `public.sql` l.17945-17951 : `MOTIF_INVALIDE`
    /// sinon), relus par le monde démo qui le simule ; l'app n'en propose que `Motif.allCases`.
    public static let motifsServeur: Set<String> = [
        "URGENCE_PERSONNELLE", "URGENCE_MEDICALE", "DEUIL", "PROBLEME_TRANSPORT", "CHANGEMENT_AVIS", "AUTRE",
    ]

    /// Seuil de l'explication côté app : 20 caractères après `trim()`, comme le web (l.100, l.249) ; le serveur exige 10
    /// (`TEXTE_REQUIS`), jamais moins strict que lui.
    public static let texteMinimum = 20
    public static let texteMinimumServeur = 10

    public static let statutAssignee = CandidatureRules.statutAssignee
    public static let statutAcceptee = "ACCEPTEE"
    public static let statutAnnulee = "ANNULEE"
    /// `error_code` d'une candidature qui n'est plus annulable (`ANNULEE` comprise) : relue avant tout message.
    public static let codeStatutInvalide = "STATUT_INVALIDE"

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

    /// Preuve d'une annulation de mission : la mission relue n'est plus attribuée au soignant de la session
    /// (`soignant_assigne_id != userId`, quel que soit le statut : une mission `EN_COURS` encore à lui n'est pas annulée).
    /// Une ligne absente le prouve aussi : sous RLS (`pol_mission_select`), le soignant assigné lit toujours sa mission.
    public static func missionAnnuleeRelue(soignantAssigneId: String?, userId: String, ligneLue: Bool) -> Bool {
        guard ligneLue, let soignantAssigneId else { return true }
        return soignantAssigneId.caseInsensitiveCompare(userId) != .orderedSame
    }

    /// Voie de récupération d'un journal de reçus illisible (consigne « Lot 1 T7 » de `DECISIONS_LOT2.md`) : annulation
    /// depuis le détail web de la mission, qui n'utilise pas ce journal. Route forcée web (le détail est natif).
    public static func routeRenvoiWeb(missionId: String) -> JoleneRoute? {
        JoleneLink.canonicalURL(link: "/soignant/missions/" + missionId).map(JoleneRoute.safari)
    }
}

/// Libellés de l'annulation hors HARD STOP (textes de consentement, de pénalité et de rétractation :
/// `TextesWeb.Annulation`). Les textes repris du web tels quels vivent dans `LibellesWeb.Annulation`, sous la garde
/// `check-textes-juridiques-ios` (ancre vérifiée au caractère près) ; ce fichier n'en garde que des alias, le titre vouvoyé
/// (décision 9 du lot 1) et les textes opérationnels propres à l'app (reçu, reprise), sans portée juridique.
public enum LibellesAnnulation {
    private typealias W = LibellesWeb.Annulation
    public static let annulerMaParticipation = W.annulerMaParticipation
    /// `DetailMissionSoignant.tsx` l.1633 vouvoyé (« ⚠️ Annuler ta participation ? ») ; message de pénalité non porté.
    public static let titreConfirmationMission = "⚠️ Annuler votre participation ?"
    public static let nonGarder = W.nonGarder
    public static let titreCandidature = W.titreCandidature
    public static let motifLibelle = W.motifLibelle
    public static let explicationLibelle = W.explicationLibelle
    public static let explicationExemple = W.explicationExemple
    public static let choisirFichier = W.choisirFichier
    public static let garderCandidature = W.garderCandidature
    public static let motifRequis = W.motifRequis
    public static let explicationRequise = W.explicationRequise
    public static let confirmationRequise = W.confirmationRequise
    /// Repli sans `error` serveur.
    public static let erreurAnnulation = W.erreurAnnulation
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
