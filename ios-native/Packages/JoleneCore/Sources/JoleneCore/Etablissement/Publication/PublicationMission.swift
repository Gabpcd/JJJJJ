import Foundation

// Publication d'une mission simple ou urgente par l'établissement (lot 5, T9 ; `docs/mobile-swift/LOT5_PLAN.md` §2.6,
// §3 T9, décisions D8 et D9). Périmètre natif : mission au taux horaire, toutes professions sauf `MEDECIN`, une période
// → jours dérivés → créneaux (`PlanningDerive`, T3). Tout le reste (autres types de contrat, médecin, sélection rapide
// des dates, duplication) est renvoyé au web (`PublicationPresentation.RenvoiWeb`).
//
// Zéro règle juridique (§2.9, HARD STOP n°4) : ce dossier ne choisit ni n'affiche aucun mode d'exercice, n'appelle ni ne
// décode la table paramétrée des modes d'exercice, et ne porte aucun contrôle du temps de travail (plafond hebdomadaire,
// repos, durée quotidienne) : le serveur les applique, son refus est affiché mot pour mot. Seuls les contrôles
// structurels sont locaux (champs obligatoires, période, créneau manquant ou invalide, chevauchement).

/// Mode de sélection d'une mission publiée (`p_mode_attribution`) : les deux valeurs que le serveur accepte
/// (`fn_creer_mission_multi_jours`, `supabase/schema/public.sql` l.27432), dans l'ordre du web
/// (`FormulaireMission.tsx` l.969-984).
public enum ModeAttributionPublication: String, CaseIterable, Sendable {
    case premierArrive = "PREMIER_ARRIVE"
    case candidature = "CANDIDATURE"
}

/// Saisie du formulaire de publication. Les jours ne sont jamais saisis à part : ils sont dérivés de la période par
/// `PublicationModel` (principe « État dérivé »), et les créneaux envoyés sont dérivés des jours.
public struct PublicationSaisie: Equatable, Sendable {
    public var intitule = ""
    public var description = ""
    /// Code de profession ; vide tant qu'aucune n'est choisie.
    public var profession = ""
    public var service = ""
    /// Taux horaire tel que saisi (virgule ou point).
    public var taux = ""
    /// État initial du web (`FormulaireMission.tsx` l.115).
    public var modeAttribution: ModeAttributionPublication = .premierArrive
    public var estUrgente = false
    /// État initial du web (l.114) ; n'est envoyé que si la mission est urgente.
    public var niveauUrgence = 1
    /// `YYYY-MM-DD`, jour civil de Paris ; vide tant que la date n'est pas choisie.
    public var dateDebut = ""
    public var dateFin = ""
    /// Jours de la période, dérivés ; chaque jour porte ses créneaux et ses exceptions.
    public var jours: [PlanningDerive.Jour] = []

    public init() {}
}

/// Règles structurelles de la publication native (aucune règle du travail, aucune règle de mode d'exercice).
public enum PublicationRules {
    /// Profession dont la publication reste sur le web (D8 : spécialité et choix d'accueil non portés).
    public static let professionRenvoyeeAuWeb = CandidaturesEtabRules.professionRenvoyeeAuWeb
    /// `length(btrim(p_intitule)) < 3` est refusé par le serveur (l.27418).
    public static let intituleMinimum = 3
    /// Longueur maximale de l'intitulé du web (`FormulaireMission.tsx` l.680, `slice(0, 120)`).
    public static let intituleMaximum = 120
    /// Niveaux d'urgence du web (l.959-961) ; le serveur borne aussi à 1…3 (l.27412).
    public static let niveauxUrgence: ClosedRange<Int> = 1...3

    /// Libellés de service suggérés, dans l'ordre du web ; la saisie reste libre.
    // source: src/components/FormulaireMission.tsx:740
    public static let services = [
        "Urgences", "Réanimation", "Soins intensifs", "Soins continus", "Médecine polyvalente",
        "Chirurgie", "Bloc opératoire", "Gériatrie", "Pédiatrie", "Cardiologie", "Maternité",
        "Rééducation", "EHPAD", "Psychiatrie", "Oncologie",
    ]

    /// Professions publiables en natif : la liste du web (`MissionPresentation.professions`) moins celle renvoyée au web.
    public static var professions: [(valeur: String, label: String)] {
        MissionPresentation.professions.filter { $0.valeur != professionRenvoyeeAuWeb }
    }

    public static func professionPubliable(_ code: String) -> Bool {
        professions.contains { $0.valeur == code }
    }

    /// Champ obligatoire manquant ou invalide.
    public enum Champ: String, CaseIterable, Sendable {
        case intitule, profession, taux, niveauUrgence = "niveau"
    }

    /// Intitulé limité à la longueur du web, sans autre transformation (le serveur retire les espaces de bord).
    public static func intitule(_ saisie: String) -> String {
        String(saisie.prefix(intituleMaximum))
    }

    /// Plancher du taux horaire (revue B8 des textes de la vague D, M4) : `min` du champ du web hors libéral
    /// (`FormulaireMission.tsx` l.921), repris par `LibellesWeb.Publication.tauxMinimumHorsLiberal` ; la publication
    /// native est salariée (D8, `PublicationPayload.typeContratRecherche`). Parité provisoire : le serveur ne refuse
    /// qu'un taux ≤ 0. Valeur illisible : rien n'est publiable (fermé par défaut).
    public static let tauxMinimum: Double = Double(LibellesWeb.Publication.tauxMinimumHorsLiberal) ?? .infinity

    /// Taux lisible mais sous le plancher : l'écran l'explique sous le champ (`PublicationPresentation.tauxSousLeMinimum`).
    public static func tauxSousLeMinimum(_ saisie: String) -> Bool {
        guard let valeur = taux(saisie) else { return false }
        return valeur < tauxMinimum
    }

    /// Taux horaire saisi : chiffres, puis au plus deux décimales après une virgule ou un point (`step="0.01"` du web,
    /// l.921) ; `nil` pour toute autre saisie, pour zéro et pour un nombre négatif (« supérieur à zéro », l.27339).
    /// Le plancher (`tauxMinimum`) est appliqué par `champsInvalides`, pas ici.
    public static func taux(_ saisie: String) -> Double? {
        let texte = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        let octets = Array(texte.utf8)
        guard !octets.isEmpty, octets.count <= 10 else { return nil }
        var entiere = 0, decimales = 0, separateurs = 0
        for octet in octets {
            switch octet {
            case 0x30...0x39: if separateurs == 0 { entiere += 1 } else { decimales += 1 }
            case 0x2C, 0x2E: separateurs += 1
            default: return nil
            }
        }
        guard entiere >= 1, separateurs <= 1, decimales <= 2, separateurs == 0 || decimales >= 1,
              let valeur = Double(texte.replacingOccurrences(of: ",", with: ".")), valeur.isFinite, valeur > 0 else { return nil }
        return valeur
    }

    /// Champs obligatoires invalides d'une saisie, dans l'ordre du formulaire.
    public static func champsInvalides(_ saisie: PublicationSaisie) -> [Champ] {
        champsInvalides(intitule: saisie.intitule, profession: saisie.profession, taux: taux(saisie.taux),
                        estUrgente: saisie.estUrgente, niveauUrgence: saisie.niveauUrgence)
    }

    /// Mêmes contrôles sur un brouillon prêt à l'envoi : la gateway les rejoue avant tout appel (fail-closed, D8 :
    /// jamais une profession renvoyée au web, jamais un niveau hors bornes).
    public static func champsInvalides(_ brouillon: PublicationMission) -> [Champ] {
        champsInvalides(intitule: brouillon.intitule, profession: brouillon.professionRequise,
                        taux: brouillon.tauxHoraireBase.isFinite && brouillon.tauxHoraireBase > 0 ? brouillon.tauxHoraireBase : nil,
                        estUrgente: brouillon.estUrgente, niveauUrgence: brouillon.niveauUrgence)
    }

    private static func champsInvalides(intitule: String, profession: String, taux: Double?, estUrgente: Bool,
                                        niveauUrgence: Int) -> [Champ] {
        var champs: [Champ] = []
        if intitule.trimmingCharacters(in: .whitespacesAndNewlines).count < intituleMinimum { champs.append(.intitule) }
        if !professionPubliable(profession) { champs.append(.profession) }
        if taux.map({ $0 < tauxMinimum }) ?? true { champs.append(.taux) }
        if estUrgente && !niveauxUrgence.contains(niveauUrgence) { champs.append(.niveauUrgence) }
        return champs
    }
}
