import Foundation

/// Règles pures du bloc de pointage rotatif et de la page Présences (blueprint lot 2 §3 T3), portées de
/// `src/components/pointage/PointageRotatifSoignant.tsx` et `src/pages/PresencesSoignant.tsx`. Aucun texte affiché
/// ici : les écrans (T4a, T4b) associent chaque cas à son libellé web (`LibellesWeb`, `TextesWeb`) ; seuls les
/// messages serveur traversent tels quels (décision 6).
public enum PointageRules {
    /// Statuts de mission pour lesquels le bloc de pointage s'affiche (`PointageRotatifSoignant.tsx` l.94).
    public static let statutsPointables: Set<String> = ["ASSIGNEE", "EN_COURS"]
    /// Longueur du code rotatif saisi (l.115).
    public static let longueurCode = 6
    /// La note est proposée au départ si la fin prévue est atteinte à 30 min près (l.158).
    public static let avanceNotationAvantFin: TimeInterval = 30 * 60
    /// Message serveur exact de `fn_scanner_code_pointage` pour un code inconnu (`public.sql` l.55649), seul message
    /// que le web surcharge (l.135-136) ; T4b affiche la forme vouvoyée de la décision 6.
    public static let messageServeurCodeInvalide = "Code de pointage invalide ou expiré."
    /// Début du refus anti-rejeu de 2 min (`public.sql` l.55711, SQLSTATE 23514).
    public static let debutMessageAntiRejeu = "Scan déjà pris en compte."

    /// Bloc de pointage affiché (l.94) ; tout autre statut, nul compris : « pas disponible pour le statut actuel ».
    public static func pointageDisponible(statut: String?) -> Bool {
        statut.map(statutsPointables.contains) ?? false
    }

    /// Code saisi ou lu : six chiffres ASCII après `trim`, sinon nil (aucun envoi, l.114-115). Même règle que
    /// `PayloadQR.codePointage(depuis:)`.
    public static func codeSaisi(_ saisie: String) -> String? {
        PayloadQR.codePointage(depuis: saisie)
    }

    /// Libellé du bouton (l.103-108).
    public enum ActionAffichee: Equatable, Sendable {
        /// Segment ouvert : « Pointer mon départ / pause ».
        case departOuPause
        /// Aucun segment ouvert mais un segment commencé aujourd'hui (Paris) : « Pointer mon arrivée / ma reprise ».
        case arriveeOuReprise
        /// Sinon : « Pointer mon arrivée ».
        case arrivee
    }

    public static func action(_ etat: EtatPointage, maintenant: Date) -> ActionAffichee {
        if etat.segmentOuvert == true { return .departOuPause }
        let aujourdhui = DateHeureParis.cleJour(maintenant)
        let dejaPointe = etat.segments.contains { cleJourParis($0.debut) == aujourdhui }
        return dejaPointe ? .arriveeOuReprise : .arrivee
    }

    /// Segment en cours (`fin` nulle, l.109).
    public static func segmentEnCours(_ etat: EtatPointage) -> SegmentPointage? {
        etat.segments.first { $0.fin == nil }
    }

    /// Les segments couvrent plusieurs jours civils de Paris (l.110-112) : l'écran affiche alors la date de chaque
    /// segment, pas seulement l'heure (l.265). Une borne illisible ne compte pour aucun jour (le web lèverait).
    public static func segmentsSurPlusieursJours(_ segments: [SegmentPointage]) -> Bool {
        Set(segments.compactMap { cleJourParis($0.debut) }).count > 1
    }

    /// Note proposée après une FERMETURE quand `maintenant ≥ fin_le − 30 min` (l.155-160). La mémoire « une fois par
    /// mission et par utilisateur » relève de la notation (T5a) ; une fin illisible ne propose rien.
    public static func notationAProposer(typeScan: TypeScan?, finLe: String?, maintenant: Date) -> Bool {
        guard typeScan == .fermeture, let finLe, let fin = try? DateHeureParis.instantJolene(finLe) else { return false }
        return maintenant >= fin.addingTimeInterval(-avanceNotationAvantFin)
    }

    /// Refus surchargé par le web (l.135-136) : `P0002` avec le message exact du code inconnu (l.55649). L'autre
    /// `P0002` de la RPC (« Aucun créneau effectif ouvert à fermer. », l.55775) reste verbatim.
    public static func estCodeInvalide(sqlstate: String?, message: String) -> Bool {
        sqlstate == "P0002" && message == messageServeurCodeInvalide
    }

    /// Refus anti-rejeu (`23514`, `public.sql` l.55710-55713) : juste après une réponse perdue, il prouve qu'un scan de ce terminal
    /// vient d'être enregistré ; le modèle relance alors la réconciliation (§2.5).
    public static func estAntiRejeu(sqlstate: String?, message: String) -> Bool {
        sqlstate == "23514" && message.hasPrefix(debutMessageAntiRejeu)
    }

    /// Relecture qui confirme un scan accepté (§2.3) : `nb_scans` = `numero_scan` et `prochain_type_scan` basculé.
    public static func etatConfirme(_ etat: EtatPointage, scan: ScanEnregistre) -> Bool {
        guard etat.nbScans == scan.numeroScan else { return false }
        guard let effectue = scan.typeScanEffectue else { return etat.prochainTypeScan != nil }
        return etat.prochainTypeScan == (effectue == .ouverture ? .fermeture : .ouverture)
    }

    // MARK: - Page Présences

    /// Onglets de la page, valeurs exactes de `?tab=` du web (`PresencesSoignant.tsx` l.520-523).
    public enum OngletPresences: String, CaseIterable, Sendable {
        case avenir, encours, aujourdhui, historique
    }

    /// Onglet initial (l.276-278) : `?tab=` du lien, sinon Aujourd'hui s'il y a une mission du jour, sinon Actives
    /// s'il y a une mission en cours, sinon À venir. Écart assumé (blueprint T4a) : une valeur inconnue retombe sur
    /// l'onglet dérivé, là où le web afficherait un onglet vide.
    public static func ongletInitial(parametre: String?, missionsAujourdhui: Int, missionsEnCours: Int) -> OngletPresences {
        if let parametre, let onglet = OngletPresences(rawValue: parametre) { return onglet }
        if missionsAujourdhui > 0 { return .aujourdhui }
        return missionsEnCours > 0 ? .encours : .avenir
    }

    /// `?filtre=a_valider` (l.279).
    public static func filtreAValider(_ parametre: String?) -> Bool {
        parametre == "a_valider"
    }

    /// Historique affiché (l.284-288).
    public static func historiqueAffiche(_ lignes: [LigneHistoriquePresence], aValider: Bool) -> [LigneHistoriquePresence] {
        aValider ? lignes.filter(\.aValider) : lignes
    }

    private static func cleJourParis(_ valeur: String) -> String? {
        guard let date = try? DateHeureParis.instantJolene(valeur) else { return nil }
        return DateHeureParis.cleJour(date)
    }
}
