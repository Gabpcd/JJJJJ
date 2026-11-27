import Foundation

/// Ligne de `fn_pool_urgence_missions_pour_soignant` (`supabase/schema/public.sql` l.47832-47880) : missions `OUVERTE`
/// urgentes, à venir, éligibles, hors exclusions, dans le rayon du soignant, triées par `debut_le`. La RPC ne renvoie ni
/// `etablissement_id`, ni `nb_creneaux`, ni `duree_heures` : ces deux dernières colonnes sont relues par PostgREST
/// `missions` (web l.72-75). Une ligne sans `id`, `intitule`, `debut_le` ou `fin_le` est écartée seule.
public struct LignePoolUrgence: Decodable, Equatable, Sendable {
    public var id: String
    public var intitule: String
    public var professionRequise: String?
    public var specialiteMedicaleRequise: String?
    public var typeContratRecherche: String?
    public var tauxHoraireBase: Double?
    public var debutLe: String
    public var finLe: String
    public var service: String?
    public var etablissementNom: String?
    public var etablissementVille: String?
    public var distanceKm: Double?
    public var dejaCandidate: Bool
    public var statutCandidature: String?

    enum CodingKeys: String, CodingKey {
        case id, intitule, service
        case professionRequise = "profession_requise"
        case specialiteMedicaleRequise = "specialite_medicale_requise"
        case typeContratRecherche = "type_contrat_recherche"
        case tauxHoraireBase = "taux_horaire_base"
        case debutLe = "debut_le"
        case finLe = "fin_le"
        case etablissementNom = "etablissement_nom"
        case etablissementVille = "etablissement_ville"
        case distanceKm = "distance_km"
        case dejaCandidate = "deja_candidate"
        case statutCandidature = "statut_candidature"
    }

    public init(id: String, intitule: String, professionRequise: String?, specialiteMedicaleRequise: String? = nil,
                typeContratRecherche: String?, tauxHoraireBase: Double?, debutLe: String, finLe: String, service: String?,
                etablissementNom: String?, etablissementVille: String?, distanceKm: Double?, dejaCandidate: Bool,
                statutCandidature: String?) {
        self.id = id; self.intitule = intitule; self.professionRequise = professionRequise
        self.specialiteMedicaleRequise = specialiteMedicaleRequise; self.typeContratRecherche = typeContratRecherche
        self.tauxHoraireBase = tauxHoraireBase; self.debutLe = debutLe; self.finLe = finLe; self.service = service
        self.etablissementNom = etablissementNom; self.etablissementVille = etablissementVille; self.distanceKm = distanceKm
        self.dejaCandidate = dejaCandidate; self.statutCandidature = statutCandidature
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        intitule = try c.decode(String.self, forKey: .intitule)
        debutLe = try c.decode(String.self, forKey: .debutLe)
        finLe = try c.decode(String.self, forKey: .finLe)
        professionRequise = try? c.decodeIfPresent(String.self, forKey: .professionRequise)
        specialiteMedicaleRequise = try? c.decodeIfPresent(String.self, forKey: .specialiteMedicaleRequise)
        typeContratRecherche = try? c.decodeIfPresent(String.self, forKey: .typeContratRecherche)
        tauxHoraireBase = try? c.decodeIfPresent(Double.self, forKey: .tauxHoraireBase)
        service = try? c.decodeIfPresent(String.self, forKey: .service)
        etablissementNom = try? c.decodeIfPresent(String.self, forKey: .etablissementNom)
        etablissementVille = try? c.decodeIfPresent(String.self, forKey: .etablissementVille)
        distanceKm = try? c.decodeIfPresent(Double.self, forKey: .distanceKm)
        dejaCandidate = (try? c.decodeIfPresent(Bool.self, forKey: .dejaCandidate)) ?? false
        statutCandidature = try? c.decodeIfPresent(String.self, forKey: .statutCandidature)
    }

    /// Ligne `missions` reconstituée : statut `OUVERTE` et `est_urgente` par construction de la RPC ; aucune colonne
    /// absente du payload n'est inventée (`etablissement_id` inconnu : chaîne vide, jamais lue par le pool).
    public func record(nbCreneaux: Int?, dureeHeures: Double?) -> MissionRecord {
        MissionRecord(id: id, intitule: intitule, description: nil, service: service, professionRequise: professionRequise ?? "",
                      specialiteMedicaleRequise: specialiteMedicaleRequise, accepteNonSpecialises: nil, debutLe: debutLe,
                      finLe: finLe, dureeHeures: dureeHeures, nbCreneaux: nbCreneaux, tauxHoraireBase: tauxHoraireBase,
                      tauxRistPlafonne: nil, ristPlafondApplique: nil, totalBrut: nil, netAPayer: nil, estUrgente: true,
                      niveauUrgence: nil, statut: "OUVERTE", etablissementId: "", typeContratRecherche: typeContratRecherche,
                      boosteeLe: nil, modeRemuneration: nil, retrocessionPct: nil)
    }

    /// Mission urgente enrichie comme `MissionBusiness.enrich` : créneaux PREVISIONNEL hors pauses triés par début puis id,
    /// planning candidat dérivé (`planningExact`, seule condition d'acceptation, web l.100-104). `erreurPlanning` : la
    /// lecture des créneaux a échoué (web l.85-87) → planning non exact, jamais un planning vide accepté.
    public func missionUrgente(nbCreneaux: Int?, dureeHeures: Double?, creneaux: [MissionSlot],
                               erreurPlanning: Bool = false) -> MissionUrgente {
        let record = record(nbCreneaux: nbCreneaux, dureeHeures: dureeHeures)
        let tries = creneaux.filter { ($0.missionId == nil || $0.missionId == id) && $0.typeCreneau == "PREVISIONNEL" && !$0.estPause }
            .sorted { ($0.debut, $0.id ?? "") < ($1.debut, $1.id ?? "") }
        let planning = PlanningCandidatRules.construirePlanningCandidat(
            PlanningCandidatInput(record: record, creneaux: tries, erreurPlanning: erreurPlanning))
        let etablissement = EtablissementSummary(id: "", nom: etablissementNom ?? "", adresseVille: etablissementVille)
        let mission = Mission(record: record, etablissement: etablissement, distanceKm: distanceKm,
                              creneauxPlanifies: tries.isEmpty ? planning.creneaux : tries, planningExact: planning.exact,
                              erreurPlanning: erreurPlanning)
        var urgente = MissionUrgente(id: id, mission: mission, statutCandidature: statutCandidature)
        urgente.dejaCandidate = dejaCandidate
        return urgente
    }
}

/// Corps de `fn_pool_urgence_missions_pour_soignant` : `{missions, pool_actif, rayon_km, sms_opt_in}` (pas de `success`),
/// ou `{error}` (« Non authentifié », « Profil soignant introuvable »).
public struct ReponsePoolUrgence: Decodable, Equatable, Sendable {
    public var missions: [LignePoolUrgence]?
    public var poolActif: Bool?
    public var rayonKm: Int?
    public var smsOptIn: Bool?
    public var error: String?
    /// Lignes écartées au décodage (clé requise absente).
    public var lignesEcartees = 0

    enum CodingKeys: String, CodingKey {
        case missions, error
        case poolActif = "pool_actif"
        case rayonKm = "rayon_km"
        case smsOptIn = "sms_opt_in"
    }

    private struct Tolerante: Decodable {
        var ligne: LignePoolUrgence?
        init(from decoder: Decoder) throws { ligne = try? LignePoolUrgence(from: decoder) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        poolActif = try? c.decodeIfPresent(Bool.self, forKey: .poolActif)
        rayonKm = try? c.decodeIfPresent(Int.self, forKey: .rayonKm)
        smsOptIn = try? c.decodeIfPresent(Bool.self, forKey: .smsOptIn)
        if let lignes = try? c.decodeIfPresent([Tolerante].self, forKey: .missions) {
            missions = lignes.compactMap(\.ligne)
            lignesEcartees = lignes.count - (missions?.count ?? 0)
        } else {
            missions = nil
        }
    }

    /// Forme complète d'un succès : les trois drapeaux et la liste présents. Sinon la réponse n'est pas lisible.
    public var estLisible: Bool { error == nil && missions != nil && poolActif != nil && rayonKm != nil && smsOptIn != nil }
}

/// Règles du pool urgence (port de `PoolUrgenceSoignant.tsx` et `PoolUrgenceToggle.tsx`).
public enum PoolUrgenceRegles {
    /// Curseur du web (l.161-176) : 5 à 50 km par pas de 1. La borne serveur (1-200) reste vérifiée par la RPC.
    public static let rayonMin = 5
    public static let rayonMax = 50
    /// Rayon envoyé par défaut quand le serveur n'en a aucun (`useState(rayonKm ?? 15)`, l.25) ; la RPC de lecture rend
    /// déjà `COALESCE(urgence_rayon_km, 30)`.
    public static let rayonParDefaut = 15
    /// Statut posé par `fn_accepter_mission_urgence` (l.5368) : seule preuve d'une acceptation rapide relue.
    public static let statutEnAttenteValidation = "EN_ATTENTE_VALIDATION_ETAB"
    /// Refus de `fn_toggle_pool_urgence` (`public.sql` l.62162), restitué verbatim.
    public static let refusRayon = "Le rayon doit être compris entre 1 et 200 km."
    /// Refus « documents » de `fn_toggle_pool_urgence` (l.62171), restitué verbatim, avec un lien vers les documents.
    public static let refusDocuments = "Validez les documents d’au moins un type de mission (salariée ou libérale) pour rejoindre le pool urgence."
    /// Bornes serveur du rayon (`p_rayon_km < 1 OR p_rayon_km > 200`).
    public static let rayonServeur = 1...200

    /// Rayon du curseur borné à [5, 50] (un rayon serveur hors curseur s'affiche borné, il n'est envoyé qu'au geste).
    public static func rayonCurseur(_ rayon: Int?) -> Int {
        min(rayonMax, max(rayonMin, rayon ?? rayonParDefaut))
    }

    /// Libellé du statut d'une candidature déjà posée (l.206-221), `nil` si aucune candidature.
    public static func libelleStatut(_ mission: MissionUrgente) -> String? {
        guard mission.dejaCandidate || mission.statutCandidature != nil else { return nil }
        switch mission.statutCandidature {
        case statutEnAttenteValidation: return PoolUrgenceTextes.statutEnAttente
        case "ACCEPTEE": return PoolUrgenceTextes.statutValidee
        case "REFUSEE": return PoolUrgenceTextes.statutRefusee
        case nil, "EN_ATTENTE": return PoolUrgenceTextes.statutDejaCandidate
        default: return nil
        }
    }

    /// Acceptation possible : aucune candidature et planning exact (bouton désactivé sinon, l.242).
    public static func acceptable(_ mission: MissionUrgente) -> Bool {
        !(mission.dejaCandidate || mission.statutCandidature != nil) && mission.mission.planningExact
    }
}

/// Libellés non juridiques du pool urgence, repris du web (source en commentaire) ; tutoiement du web passé au
/// vouvoiement (décision 9 du lot 1 : seule la personne change). Les textes de consentement (SMS, engagement,
/// disponibilité) sont dans `TextesWeb.PoolUrgence` (HARD STOP n°4, verbatim).
public enum PoolUrgenceTextes {
    // source: src/pages/PoolUrgenceSoignant.tsx:47 (`usePageTitle`)
    public static let titre = "Pool urgence"
    // source: src/pages/PoolUrgenceSoignant.tsx:136 (vouvoyé : « ton profil »)
    public static let sousTitre = "Missions de remplacement de dernière minute correspondant à votre profil. Acceptation 1-clic, validation étab sous 1h."
    /// Sous-titre affiché (revue B8 des textes de la vague D, M1) : la première phrase de `sousTitre` seulement. La
    /// seconde, « Acceptation 1-clic, validation étab sous 1h. », promet un délai de validation par l'établissement
    /// qu'aucun mécanisme serveur ne garantit (même classe que le « sous 72h » du score, précision 16 de
    /// `DECISIONS_LOT4.md`) : non affichée, la constante verbatim reste pour suivre le web. Dérivé, aucun texte réécrit.
    public static var sousTitreAffiche: String {
        guard let fin = sousTitre.range(of: ". ") else { return sousTitre }
        return String(sousTitre[..<fin.lowerBound]) + "."
    }
    // source: src/components/PoolUrgenceToggle.tsx:104
    public static let carteTitre = "Disponibilité urgence"
    // source: src/components/PoolUrgenceToggle.tsx:159
    public static let rayonLibelle = "Rayon maximum :"
    // source: src/components/PoolUrgenceToggle.tsx:162 (`aria-label`)
    public static let rayonAccessibilite = "Rayon maximum des alertes d’urgence"
    // source: src/components/PoolUrgenceToggle.tsx:191 (`aria-label`)
    public static let smsAccessibilite = "Recevoir les alertes du pool urgence par SMS"
    // source: src/components/PoolUrgenceToggle.tsx:205
    public static let badge = "Soignant Urgence 🔥"
    // source: src/components/PoolUrgenceToggle.tsx:207 (vouvoyé : « ton profil »)
    public static let badgeVisible = "Badge visible sur votre profil"
    // source: src/components/PoolUrgenceToggle.tsx:212
    public static let avantages = "Avantages :"
    // source: src/components/PoolUrgenceToggle.tsx:219
    public static let avantagePrioritaire = "Accès prioritaire aux missions urgentes"
    // source: src/components/PoolUrgenceToggle.tsx:223
    public static let avantageBadge = "Badge Urgence visible par les établissements"
    // source: src/components/PoolUrgenceToggle.tsx:79
    public static let active = "Pool urgence activé !"
    public static let desactive = "Pool urgence désactivé."
    // source: src/components/PoolUrgenceToggle.tsx:95
    public static let smsActives = "SMS d'urgence activés"
    public static let smsDesactives = "SMS d'urgence désactivés"
    // source: src/pages/PoolUrgenceSoignant.tsx:158
    public static let inactifTitre = "Pool urgence désactivé"
    // source: src/pages/PoolUrgenceSoignant.tsx:160 (vouvoyé ; « à gauche » du web devient « ci-dessus », le réglage est
    // au-dessus de la liste sur iPhone)
    public static let inactifTexte = "Activez le réglage ci-dessus pour recevoir les alertes urgentes et voir les missions disponibles."
    // source: src/pages/PoolUrgenceSoignant.tsx:166
    public static let videTitre = "Aucune mission urgente pour le moment"
    // source: src/pages/PoolUrgenceSoignant.tsx:186
    public static let urgent = "URGENT"
    // source: src/pages/PoolUrgenceSoignant.tsx:210
    public static let statutEnAttente = "En attente de validation étab"
    // source: src/pages/PoolUrgenceSoignant.tsx:213
    public static let statutValidee = "Validée par étab"
    // source: src/pages/PoolUrgenceSoignant.tsx:216
    public static let statutRefusee = "Refusée par étab"
    // source: src/pages/PoolUrgenceSoignant.tsx:219 (vouvoyé : « Tu as »)
    public static let statutDejaCandidate = "Vous avez déjà candidaté"
    // source: src/pages/PoolUrgenceSoignant.tsx:227
    public static let voirMission = "Voir mission"
    // source: src/pages/PoolUrgenceSoignant.tsx:237
    public static let voirDetail = "Voir détail"
    // source: src/pages/PoolUrgenceSoignant.tsx:246
    public static let accepter = "J'accepte"
    public static let acceptationEnCours = "Acceptation…"
    // source: src/pages/PoolUrgenceSoignant.tsx:102
    public static let planningARecharger = "Le planning exact doit être rechargé avant d’accepter."
    // source: src/pages/PoolUrgenceSoignant.tsx:263 (`actionLabel` du récapitulatif)
    public static let confirmerAcceptation = "Confirmer mon acceptation urgente"
    // source: supabase/schema/public.sql l.5385 (`message` du succès de `fn_accepter_mission_urgence`), affiché après la
    // relecture du statut, comme le toast web (l.121)
    public static let acceptationEnregistree = "Acceptation enregistrée. En attente de validation par l'établissement."
    // source: supabase/schema/public.sql l.55148 (`error` du `choix_requis` de `fn_resoudre_contrat_mission`, relayé par
    // `fn_accepter_mission_urgence` et affiché par le toast web l.125) ; l'acceptation rapide ne le rejoue jamais : le
    // choix se fait sur le détail de la mission (lot 1)
    public static let choixContratRequis = "Choisissez votre mode de contrat."
    // source: src/pages/PoolUrgenceSoignant.tsx:59 (repli du toast de chargement)
    public static let chargementImpossible = "Erreur de chargement"
    /// Texte opérationnel hors web : l'action a été envoyée mais la relecture ne la confirme pas (PRINCIPES §3).
    public static let nonConfirmee = "La modification n'a pas pu être relue. Vérifiez l'écran avant de réessayer."
    public static let reessayer = "Réessayer"

    /// « {n} km » (l.159, l.168).
    public static func km(_ rayon: Int) -> String { "\(rayon) km" }

    /// « Tu seras notifié dès qu'une mission urgente correspondra à ton profil dans ton rayon ({rayon} km). » (l.168,
    /// vouvoyé).
    public static func videTexte(rayon: Int) -> String {
        "Vous serez notifié(e) dès qu'une mission urgente correspondra à votre profil dans votre rayon (\(rayon) km)."
    }

    /// « {n} mission(s) urgente(s) dans ton rayon · triée(s) par distance » (l.174, vouvoyé ; l'ordre affiché reste
    /// celui du serveur, comme le web).
    public static func compteur(_ nombre: Int) -> String {
        let s = nombre > 1 ? "s" : ""
        return "\(nombre) mission\(s) urgente\(s) dans votre rayon · triée\(s) par distance"
    }

    /// « {taux} €/h » (l.194, deux décimales comme `toFixed(2)`).
    public static func taux(_ taux: Double?) -> String {
        String(format: "%.2f €/h", locale: Locale(identifier: "en_US_POSIX"), taux ?? 0)
    }

    /// « {ville ?? '—'}{ · {distance} km} » (l.197-198).
    public static func lieu(ville: String?, distanceKm: Double?) -> String {
        var texte = (ville ?? "").isEmpty ? "—" : ville ?? "—"
        if let distanceKm {
            let arrondi = distanceKm == distanceKm.rounded() ? String(Int(distanceKm)) : String(distanceKm)
            texte += " · \(arrondi) km"
        }
        return texte
    }

    /// Texte d'engagement affiché (décision b de l'intégration de la vague D, `DECISIONS_LOT4.md` précision 17) : les deux
    /// premières phrases du paragraphe du web (`TextesWeb.PoolUrgence.engagementDebut`, verbatim), sans la dernière,
    /// « Chaque mission urgence terminée te rapporte +10 points de fiabilité. », que le score de production ne tient pas
    /// (bonus de 5). Dérivé du texte verbatim, coupé après le dernier point qui suit une phrase complète : aucun texte
    /// réécrit ici.
    public static var engagementAffiche: String {
        let debut = TextesWeb.PoolUrgence.engagementDebut
        guard let fin = debut.range(of: ". ", options: .backwards) else { return debut }
        return String(debut[..<fin.lowerBound]) + "."
    }
}
