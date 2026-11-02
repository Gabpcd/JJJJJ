import Foundation

// Contrats du tableau de bord soignant (lot 1, T3 ; blueprint §2.4, §2.6). Deux couches :
// - `DashboardCorps` : corps jsonb de `fn_dashboard_soignant_complet` (dump l.27920), décodé
//   sans décodeur strict. Une section NULL, absente ou qui n'est pas un tableau est vide ; une
//   ligne illisible (sans identifiant) est écartée seule ; `error` (HTTP 200) est conservé pour
//   être refusé, jamais pris pour un succès.
// - `DashboardSnapshot` : ce que l'écran affiche, assemblé par `AccueilAssemblage` avec les
//   lectures complémentaires (fiches missions + créneaux PREVISIONNEL, `fn_etablissements_safe`,
//   gains du mois relus). Montants et horaires restent des valeurs serveur.

// MARK: - Corps de fn_dashboard_soignant_complet

/// Profil renvoyé par le tableau de bord. Seuls les champs de la salutation et de l'accroche
/// sont décodés : état civil, téléphone et numéros professionnels du corps ne sont jamais lus.
/// Ne sert jamais à un contrôle d'accès (source unique du gating : `SoignantProfile`, §2.6).
public struct DashboardProfil: Decodable, Equatable, Sendable {
    public var prenom: String?
    public var profession: String?
    public var tousDocumentsValides: Bool?
    public var typeExercice: String?

    public init(prenom: String?, profession: String?, tousDocumentsValides: Bool?, typeExercice: String?) {
        self.prenom = prenom; self.profession = profession
        self.tousDocumentsValides = tousDocumentsValides; self.typeExercice = typeExercice
    }

    enum CodingKeys: String, CodingKey {
        case prenom, profession
        case tousDocumentsValides = "tous_documents_valides"
        case typeExercice = "type_exercice"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prenom = c.texte(.prenom)
        profession = c.texte(.profession)
        tousDocumentsValides = c.booleen(.tousDocumentsValides)
        typeExercice = c.texte(.typeExercice)
    }
}

/// Ligne de `mes_missions` (ASSIGNEE, EN_COURS), de `missions_ouvertes` ou mission jointe d'une
/// proposition. `id` et `intitule` conditionnent l'affichage ; tout le reste est optionnel.
/// `etab_nom` vient d'un LEFT JOIN sans filtre de cohorte : simple repli quand la ligne
/// `fn_etablissements_safe` manque (blueprint §2.6).
public struct DashboardMissionLigne: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var intitule: String
    public var service: String?
    public var debutLe: String?
    public var finLe: String?
    public var statut: String?
    public var estUrgente: Bool
    public var tauxHoraireBase: Double?
    public var etablissementId: String?
    public var etabNom: String?

    public init(id: String, intitule: String, service: String?, debutLe: String?, finLe: String?, statut: String?,
                estUrgente: Bool, tauxHoraireBase: Double?, etablissementId: String?, etabNom: String?) {
        self.id = id; self.intitule = intitule; self.service = service; self.debutLe = debutLe; self.finLe = finLe
        self.statut = statut; self.estUrgente = estUrgente; self.tauxHoraireBase = tauxHoraireBase
        self.etablissementId = etablissementId; self.etabNom = etabNom
    }

    enum CodingKeys: String, CodingKey {
        case id, intitule, service, statut
        case debutLe = "debut_le"
        case finLe = "fin_le"
        case estUrgente = "est_urgente"
        case tauxHoraireBase = "taux_horaire_base"
        case etablissementId = "etablissement_id"
        case etabNom = "etab_nom"
    }

    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, idParDefaut: nil)
    }

    /// `idParDefaut` : identifiant de la mission jointe d'une proposition quand l'objet joint
    /// n'en porte pas (la candidature porte toujours `mission_id`).
    init(from decoder: Decoder, idParDefaut: String?) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.texte(.id) ?? idParDefaut, let intitule = c.texte(.intitule) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "id ou intitule absent"))
        }
        self.id = id
        self.intitule = intitule
        service = c.texte(.service)
        debutLe = c.texte(.debutLe)
        finLe = c.texte(.finLe)
        statut = c.texte(.statut)
        estUrgente = c.booleen(.estUrgente) ?? false
        tauxHoraireBase = c.nombre(.tauxHoraireBase)
        etablissementId = c.texte(.etablissementId)
        etabNom = c.texte(.etabNom)
    }
}

/// Élément de `propositions` : candidature PROPOSEE de moins de 2 h (filtre serveur), mission
/// jointe sous `missions`. Une proposition sans mission lisible n'est jamais affichée (le web
/// rend `null` sans intitulé ni dates).
public struct DashboardProposition: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var missionId: String
    public var creeLe: String
    public var typeContratChoisi: String?
    public var mission: DashboardMissionLigne

    public init(id: String, missionId: String, creeLe: String, typeContratChoisi: String?, mission: DashboardMissionLigne) {
        self.id = id; self.missionId = missionId; self.creeLe = creeLe
        self.typeContratChoisi = typeContratChoisi; self.mission = mission
    }

    enum CodingKeys: String, CodingKey {
        case id
        case missionId = "mission_id"
        case creeLe = "cree_le"
        case typeContratChoisi = "type_contrat_choisi"
        case mission = "missions"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.texte(.id), let missionId = c.texte(.missionId), let creeLe = c.texte(.creeLe) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "proposition incomplète"))
        }
        self.id = id
        self.missionId = missionId
        self.creeLe = creeLe
        typeContratChoisi = c.texte(.typeContratChoisi)
        mission = try DashboardMissionLigne(from: c.superDecoder(forKey: .mission), idParDefaut: missionId)
    }
}

/// Élément de `documents` (décodé pour les lots suivants ; l'Accueil du lot 1 ne l'affiche pas).
public struct DashboardDocument: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var typeDocument: String?
    public var valideJusqua: String?
    public var statutVerification: String?

    enum CodingKeys: String, CodingKey {
        case id
        case typeDocument = "type_document"
        case valideJusqua = "valide_jusqua"
        case statutVerification = "statut_verification"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.texte(.id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "document sans id"))
        }
        self.id = id
        typeDocument = c.texte(.typeDocument)
        valideJusqua = c.texte(.valideJusqua)
        statutVerification = c.texte(.statutVerification)
    }
}

/// Corps de `fn_dashboard_soignant_complet`. `gains_mois.net_total` et `brut_total` ne sont pas
/// décodés : le web ne les affiche pas (le total historique agrégeait parfois le brut salarié),
/// les montants affichés sont relus mission par mission (décision 10, `GainsDuMois`).
/// `heures_semaine` est décodé mais n'est pas affiché (`BandeauAlerte48h` exclu, HARD STOP n°4).
public struct DashboardCorps: Decodable, Equatable, Sendable {
    /// `{"error": "..."}` renvoyé en HTTP 200 (« Non authentifié ») : jamais un succès.
    public var erreur: String?
    public var profil: DashboardProfil?
    public var missionsOuvertes: [DashboardMissionLigne]
    public var mesMissions: [DashboardMissionLigne]
    public var propositions: [DashboardProposition]
    public var documents: [DashboardDocument]
    public var heuresSemaine: Double
    public var gainsMoisNbMissions: Int
    public var missionsOublieesCount: Int
    public var notifsNonLues: Int

    public init(erreur: String? = nil, profil: DashboardProfil? = nil, missionsOuvertes: [DashboardMissionLigne] = [],
                mesMissions: [DashboardMissionLigne] = [], propositions: [DashboardProposition] = [],
                documents: [DashboardDocument] = [], heuresSemaine: Double = 0, gainsMoisNbMissions: Int = 0,
                missionsOublieesCount: Int = 0, notifsNonLues: Int = 0) {
        self.erreur = erreur; self.profil = profil; self.missionsOuvertes = missionsOuvertes; self.mesMissions = mesMissions
        self.propositions = propositions; self.documents = documents; self.heuresSemaine = heuresSemaine
        self.gainsMoisNbMissions = gainsMoisNbMissions; self.missionsOublieesCount = missionsOublieesCount
        self.notifsNonLues = notifsNonLues
    }

    enum CodingKeys: String, CodingKey {
        case erreur = "error"
        case profil, documents, propositions
        case missionsOuvertes = "missions_ouvertes"
        case mesMissions = "mes_missions"
        case heuresSemaine = "heures_semaine"
        case gainsMois = "gains_mois"
        case missionsOublieesCount = "missions_oubliees_count"
        case notifsNonLues = "notifs_non_lues"
    }

    enum GainsMoisKeys: String, CodingKey {
        case nbMissions = "nb_missions"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        erreur = c.texte(.erreur)
        profil = try? c.decodeIfPresent(DashboardProfil.self, forKey: .profil)
        missionsOuvertes = c.lignes(.missionsOuvertes)
        mesMissions = c.lignes(.mesMissions)
        propositions = c.lignes(.propositions)
        documents = c.lignes(.documents)
        heuresSemaine = c.nombre(.heuresSemaine) ?? 0
        let gains = try? c.nestedContainer(keyedBy: GainsMoisKeys.self, forKey: .gainsMois)
        gainsMoisNbMissions = gains?.entier(.nbMissions) ?? 0
        missionsOublieesCount = c.entier(.missionsOublieesCount) ?? 0
        notifsNonLues = c.entier(.notifsNonLues) ?? 0
    }

    /// Décodage d'un corps JSON : tout corps qui n'est pas un objet est un refus de contrat.
    public static func decoder(_ data: Data) throws -> DashboardCorps {
        do {
            return try JSONDecoder().decode(DashboardCorps.self, from: data)
        } catch {
            throw JoleneError(.contract, AccueilAssemblage.contratMessage)
        }
    }
}

// MARK: - Gains du mois (décision 10)

/// Mission TERMINEE du mois relue sous RLS, avec les seules colonnes de la relecture web
/// (`DashboardSoignant.tsx` l.115-120 : `id, type_contrat_applique, type_contrat_recherche,
/// total_brut, net_a_payer, net_estime`).
public struct MissionGainLigne: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var typeContratApplique: String?
    public var typeContratRecherche: String?
    public var totalBrut: Double?
    public var netAPayer: Double?
    public var netEstime: Double?

    public init(id: String, typeContratApplique: String?, typeContratRecherche: String?, totalBrut: Double?,
                netAPayer: Double?, netEstime: Double?) {
        self.id = id; self.typeContratApplique = typeContratApplique; self.typeContratRecherche = typeContratRecherche
        self.totalBrut = totalBrut; self.netAPayer = netAPayer; self.netEstime = netEstime
    }

    enum CodingKeys: String, CodingKey {
        case id
        case typeContratApplique = "type_contrat_applique"
        case typeContratRecherche = "type_contrat_recherche"
        case totalBrut = "total_brut"
        case netAPayer = "net_a_payer"
        case netEstime = "net_estime"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.texte(.id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "mission sans id"))
        }
        self.id = id
        typeContratApplique = c.texte(.typeContratApplique)
        typeContratRecherche = c.texte(.typeContratRecherche)
        totalBrut = c.nombre(.totalBrut)
        netAPayer = c.nombre(.netAPayer)
        netEstime = c.nombre(.netEstime)
    }
}

/// Gains du mois affichés sur l'Accueil : sommes, par nature, des montants SERVEUR des missions
/// relues, comme `gainsCeMois` du web (l.322-339) qui applique `montantFinanceAfficheMission`
/// (`src/lib/missionFinanceDisplay.ts`). Aucun montant n'est recalculé : chaque mission apporte une
/// valeur stockée choisie selon son régime ; la correction d'ancien plafond du web
/// (`corrigerAncienPlafondImpossible`) ne s'applique jamais ici, la relecture web ne sélectionnant
/// ni `rist_plafond_applique` ni les taux.
public struct GainsDuMois: Equatable, Sendable {
    public enum Nature: Equatable, Sendable { case honorairesLiberaux, netSalarieEstime, brutIndicatif }

    public var honoraires: Double
    public var netSalarie: Double
    public var brutIndicatif: Double
    /// Missions relues porteuses d'un montant (le « sur N missions » du web).
    public var nombreMissions: Int

    public init(honoraires: Double, netSalarie: Double, brutIndicatif: Double, nombreMissions: Int) {
        self.honoraires = honoraires; self.netSalarie = netSalarie
        self.brutIndicatif = brutIndicatif; self.nombreMissions = nombreMissions
    }

    /// Régime effectif : appliqué puis recherché, seulement `LIBERAL` ou `SALARIE` (`contratEffectif`).
    static func contrat(_ ligne: MissionGainLigne) -> String? {
        for valeur in [ligne.typeContratApplique, ligne.typeContratRecherche] where valeur == "LIBERAL" || valeur == "SALARIE" {
            return valeur
        }
        return nil
    }

    /// Montant affiché d'une mission : libéral → `net_a_payer` puis `total_brut` (honoraires) ;
    /// salarié → `net_estime` seul (jamais `net_a_payer`, qui n'est pas un net) ; régime non choisi
    /// → `total_brut` puis `net_a_payer` (brut indicatif). Sans valeur serveur : aucun montant.
    public static func montant(_ ligne: MissionGainLigne) -> (nature: Nature, montant: Double)? {
        switch contrat(ligne) {
        case "LIBERAL":
            return (ligne.netAPayer ?? ligne.totalBrut).map { (nature: Nature.honorairesLiberaux, montant: $0) }
        case "SALARIE":
            return ligne.netEstime.map { (nature: Nature.netSalarieEstime, montant: $0) }
        default:
            return (ligne.totalBrut ?? ligne.netAPayer).map { (nature: Nature.brutIndicatif, montant: $0) }
        }
    }

    public static func agreger(_ lignes: [MissionGainLigne]) -> GainsDuMois {
        var gains = GainsDuMois(honoraires: 0, netSalarie: 0, brutIndicatif: 0, nombreMissions: 0)
        for ligne in lignes {
            guard let affiche = montant(ligne) else { continue }
            gains.nombreMissions += 1
            switch affiche.nature {
            case .honorairesLiberaux: gains.honoraires += affiche.montant
            case .netSalarieEstime: gains.netSalarie += affiche.montant
            case .brutIndicatif: gains.brutIndicatif += affiche.montant
            }
        }
        return gains
    }
}

// MARK: - Instantané affiché

/// Planning d'une mission de l'Accueil, port de `enrichirPlanning` (web l.168-201) : vérifié
/// par `CompletudePlanning` sur les créneaux PREVISIONNEL relus et `nb_creneaux` de la fiche.
public enum PlanningAccueil: Equatable, Sendable {
    /// `planning_indisponible` : lecture en échec, fiche absente ou planning incomplet. Rendu
    /// partiel (« Planning détaillé à confirmer »), jamais une erreur d'écran.
    case indisponible
    /// Planning vérifié : prochain créneau non terminé (`prochainCreneauPointage`), son rang
    /// (1…`nombre`) et le nombre de créneaux planifiés.
    case planifie(prochain: MissionSlot?, rang: Int?, nombre: Int)
}

/// Mission de l'Accueil (prochaines missions, missions pour vous).
public struct AccueilMission: Equatable, Sendable, Identifiable {
    public var ligne: DashboardMissionLigne
    /// `fn_etablissements_safe`, puis `etab_nom` du tableau de bord, puis « Établissement ».
    public var etablissementNom: String
    public var etablissementVille: String?
    public var planning: PlanningAccueil
    /// Mission relue et enrichie (`MissionBusiness.enrich`) : valeur initiale du détail et
    /// entrée de l'ajout au calendrier ; `nil` si la fiche n'a pas pu être relue.
    public var mission: Mission?

    public var id: String { ligne.id }

    public init(ligne: DashboardMissionLigne, etablissementNom: String, etablissementVille: String?,
                planning: PlanningAccueil, mission: Mission?) {
        self.ligne = ligne; self.etablissementNom = etablissementNom; self.etablissementVille = etablissementVille
        self.planning = planning; self.mission = mission
    }
}

/// Proposition non expirée (moins de 2 h, `AccueilAssemblage.expirationPropositionMinutes`).
public struct AccueilProposition: Equatable, Sendable, Identifiable {
    public var proposition: DashboardProposition
    public var etablissementNom: String
    public var expireLe: Date
    public var mission: Mission?

    public var id: String { proposition.id }

    public init(proposition: DashboardProposition, etablissementNom: String, expireLe: Date, mission: Mission?) {
        self.proposition = proposition; self.etablissementNom = etablissementNom; self.expireLe = expireLe; self.mission = mission
    }
}

/// Instantané de l'onglet Accueil (port `DashboardPort`, tranche T3).
public struct DashboardSnapshot: Equatable, Sendable {
    public var notifsNonLues: Int
    public var missionsOublieesCount: Int
    public var profil: DashboardProfil?
    /// `mes_missions` (ASSIGNEE, EN_COURS ; 3 au plus, ordre serveur).
    public var prochaines: [AccueilMission]
    /// `missions_ouvertes` (3 au plus, ordre serveur) ; l'écran en affiche
    /// `AccueilPresentation.nombrePourToiAffiches`, l'accroche les compte toutes.
    public var pourToi: [AccueilMission]
    public var propositions: [AccueilProposition]
    /// Gains relus mission par mission ; `nil` si la relecture a échoué (carte masquée, comme le web).
    public var gains: GainsDuMois?
    /// `gains_mois.nb_missions` du serveur (missions TERMINEE débutées dans le mois), conservé tel
    /// quel mais jamais affiché : « sur N missions » compte les missions relues porteuses d'un
    /// montant (`GainsDuMois.nombreMissions`, comme `gainsCeMois.nb` du web ; décision 10 amendée).
    public var gainsMoisNbMissions: Int
    /// Décodé, jamais affiché au lot 1 (`BandeauAlerte48h` exclu, HARD STOP n°4).
    public var heuresSemaine: Double
    /// Décodés pour les lots suivants (documents : lot 2).
    public var documents: [DashboardDocument]
    /// Lecture des fiches ou des créneaux en échec : tout le planning est « à confirmer ».
    public var planningIndisponible: Bool

    public init(notifsNonLues: Int = 0, missionsOublieesCount: Int = 0, profil: DashboardProfil? = nil,
                prochaines: [AccueilMission] = [], pourToi: [AccueilMission] = [], propositions: [AccueilProposition] = [],
                gains: GainsDuMois? = nil, gainsMoisNbMissions: Int = 0, heuresSemaine: Double = 0,
                documents: [DashboardDocument] = [], planningIndisponible: Bool = false) {
        self.notifsNonLues = notifsNonLues; self.missionsOublieesCount = missionsOublieesCount; self.profil = profil
        self.prochaines = prochaines; self.pourToi = pourToi; self.propositions = propositions; self.gains = gains
        self.gainsMoisNbMissions = gainsMoisNbMissions; self.heuresSemaine = heuresSemaine; self.documents = documents
        self.planningIndisponible = planningIndisponible
    }

    /// Mission relue portant cet identifiant (valeur initiale de l'écran de détail).
    public func mission(id: String) -> Mission? {
        if let mission = (prochaines + pourToi).first(where: { $0.id == id })?.mission { return mission }
        return propositions.first(where: { $0.proposition.missionId == id })?.mission
    }
}

// MARK: - Décodage tolérant (interne)

/// Élément de tableau décodé sans faire échouer le tableau.
private struct ElementTolerant<T: Decodable>: Decodable {
    let valeur: T?
    init(from decoder: Decoder) throws { valeur = try? T(from: decoder) }
}

private extension KeyedDecodingContainer {
    func texte(_ cle: Key) -> String? {
        guard let valeur = try? decodeIfPresent(String.self, forKey: cle) else { return nil }
        return valeur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : valeur
    }

    func booleen(_ cle: Key) -> Bool? { (try? decodeIfPresent(Bool.self, forKey: cle)) ?? nil }

    /// Nombre JSON (entier ou réel) ou chaîne numérique (`numeric` sérialisé en texte).
    func nombre(_ cle: Key) -> Double? {
        if let reel = (try? decodeIfPresent(Double.self, forKey: cle)) ?? nil, reel.isFinite { return reel }
        if let chaine = (try? decodeIfPresent(String.self, forKey: cle)) ?? nil,
           let reel = Double(chaine.trimmingCharacters(in: .whitespaces)), reel.isFinite { return reel }
        return nil
    }

    /// Compteur (`count(*)`, bigint) : entier exact, sinon `nil`.
    func entier(_ cle: Key) -> Int? {
        guard let reel = nombre(cle), reel.rounded() == reel, abs(reel) < 9_007_199_254_740_992 else { return nil }
        return Int(reel)
    }

    func lignes<T: Decodable>(_ cle: Key) -> [T] {
        guard let elements = (try? decodeIfPresent([ElementTolerant<T>].self, forKey: cle)) ?? nil else { return [] }
        return elements.compactMap(\.valeur)
    }
}
