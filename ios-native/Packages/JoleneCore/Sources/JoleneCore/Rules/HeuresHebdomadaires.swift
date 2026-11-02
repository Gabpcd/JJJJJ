import Foundation

/// Mission telle que lue par le calcul des heures hebdomadaires
/// (port de `MissionPourCalculHebdomadaire`). Les créneaux sont des `MissionSlot`.
public struct MissionPourCalculHebdomadaire: Equatable, Sendable {
    public var id: String
    public var debutLe: String
    public var finLe: String
    /// `nil`, `0` et `NaN` valent « inconnue » (`Number(x) || 0` côté web).
    public var dureeHeures: Double?
    public var nbCreneaux: Int?
    public var statut: String?
    public var typeContratApplique: String?
    public var choixContratSoignant: String?
    public var typeContratRecherche: String?

    public init(id: String, debutLe: String, finLe: String, dureeHeures: Double?, nbCreneaux: Int? = nil,
                statut: String? = nil, typeContratApplique: String? = nil, choixContratSoignant: String? = nil,
                typeContratRecherche: String? = nil) {
        self.id = id; self.debutLe = debutLe; self.finLe = finLe; self.dureeHeures = dureeHeures
        self.nbCreneaux = nbCreneaux; self.statut = statut; self.typeContratApplique = typeContratApplique
        self.choixContratSoignant = choixContratSoignant; self.typeContratRecherche = typeContratRecherche
    }
}

public extension MissionRecord {
    /// Projection de la ligne `missions` ; `type_contrat_applique` et
    /// `choix_contrat_soignant` ne font pas partie de `MISSION_SELECT` et restent à `nil`.
    var pourCalculHebdomadaire: MissionPourCalculHebdomadaire {
        MissionPourCalculHebdomadaire(
            id: id, debutLe: debutLe, finLe: finLe, dureeHeures: dureeHeures, nbCreneaux: nbCreneaux,
            statut: statut, typeContratRecherche: typeContratRecherche
        )
    }
}

public struct HeuresSemaineMission: Equatable, Sendable {
    /// Clé `YYYY-MM-DD` du lundi de la semaine civile française.
    public var cleSemaine: String
    public var debutSemaine: Date
    public var heures: Double

    public init(cleSemaine: String, debutSemaine: Date, heures: Double) {
        self.cleSemaine = cleSemaine; self.debutSemaine = debutSemaine; self.heures = heures
    }
}

/// Répartition des heures d'une mission sur ses semaines civiles réelles
/// (port de `src/lib/heures-hebdomadaires-mission.ts`). Sert au plafond
/// hebdomadaire salarié de 48 h, dont la décision finale reste serveur.
public enum HeuresHebdomadaires {
    static let millisecondesParHeure: Double = 3_600_000

    public static func debutSemaineCivile(_ date: Date) -> Date {
        DateHeureParis.debutSemaine(date)
    }

    public static func cleSemaineCivile(_ date: Date) -> String {
        DateHeureParis.cleSemaine(date)
    }

    public static func semaineSuivante(_ debutSemaine: Date) -> Date {
        DateHeureParis.semaineSuivante(debutSemaine)
    }

    /// Retient les créneaux prévisionnels lorsqu'ils existent. Les créneaux
    /// effectifs ne servent de repli que pour une mission historique sans
    /// planning prévisionnel, afin de ne jamais additionner deux fois la même
    /// journée. Une mission terminée retient ses heures effectives.
    static func creneauxDeReference(_ mission: MissionPourCalculHebdomadaire, _ creneaux: [MissionSlot]) -> [MissionSlot] {
        let lignesMission = creneaux.filter { $0.missionId == mission.id }
        let previsionnels = lignesMission.filter { $0.typeCreneau == "PREVISIONNEL" }
        let effectifs = lignesMission.filter { $0.typeCreneau == "EFFECTIF" }
        let reference: [MissionSlot]
        if mission.statut == "TERMINEE" && effectifs.contains(where: { !$0.estPause }) {
            reference = effectifs
        } else if previsionnels.contains(where: { !$0.estPause }) {
            reference = previsionnels
        } else {
            reference = effectifs
        }

        let travail = reference.filter { !$0.estPause }
        // nb_creneaux désigne uniquement les périodes travaillées : une pause ne
        // doit jamais masquer un créneau de travail absent.
        if travail.contains(where: { ($0.fin ?? "").isEmpty }) { return [] }
        let nbCreneaux = mission.nbCreneaux ?? 0
        if nbCreneaux > 1 && travail.count < nbCreneaux { return [] }
        return travail
    }

    public static func planningMissionHebdomadaireDisponible(_ mission: MissionPourCalculHebdomadaire, _ creneaux: [MissionSlot]) -> Bool {
        if (mission.nbCreneaux ?? 0) <= 1 {
            let lignesTravail = creneaux.filter { $0.missionId == mission.id && !$0.estPause }
            // Le repli enveloppe reste autorisé uniquement pour une mission
            // ponctuelle legacy sans aucune ligne ; une ligne ouverte échoue fermé.
            if lignesTravail.isEmpty { return true }
        }
        return !creneauxDeReference(mission, creneaux).isEmpty
    }

    private static func ajouterHeures(_ resultat: inout [String: HeuresSemaineMission], _ ordre: inout [String],
                                      cle: String, debut: Date, heures: Double) {
        if var courant = resultat[cle] {
            courant.heures += heures
            resultat[cle] = courant
        } else {
            resultat[cle] = HeuresSemaineMission(cleSemaine: cle, debutSemaine: debut, heures: heures)
            ordre.append(cle)
        }
    }

    /// Répartit une mission sur ses semaines civiles (lundi → dimanche). Un
    /// créneau de nuit qui franchit un lundi est scindé au bon endroit. Pour les
    /// anciennes missions mono-créneau, `dureeHeures` reste le repli historique.
    public static func heuresMissionParSemaine(_ mission: MissionPourCalculHebdomadaire, _ creneaux: [MissionSlot]) -> [HeuresSemaineMission] {
        var resultat: [String: HeuresSemaineMission] = [:]
        var ordre: [String] = []

        for creneau in creneauxDeReference(mission, creneaux) {
            guard let finISO = creneau.fin,
                  let debutCreneau = try? DateHeureParis.instantJolene(creneau.debut),
                  let fin = try? DateHeureParis.instantJolene(finISO) else { continue }
            var curseur = DateHeureParis.millisecondes(debutCreneau)
            let finMs = DateHeureParis.millisecondes(fin)
            guard finMs > curseur else { continue }

            while curseur < finMs {
                let dateCurseur = DateHeureParis.date(millisecondes: curseur)
                let debutSemaine = debutSemaineCivile(dateCurseur)
                let prochaine = DateHeureParis.millisecondes(semaineSuivante(debutSemaine))
                let finSegment = finMs < prochaine ? finMs : prochaine
                ajouterHeures(&resultat, &ordre, cle: cleSemaineCivile(dateCurseur), debut: debutSemaine,
                              heures: Double(finSegment - curseur) / millisecondesParHeure)
                curseur = finSegment
            }
        }

        if resultat.isEmpty {
            // Une mission annoncée multi-créneaux ne retombe jamais sur sa durée
            // globale : sans les créneaux, la ventilation est indisponible.
            if (mission.nbCreneaux ?? 0) > 1 { return [] }
            let heures = FormatMission.nombre(mission.dureeHeures)
            if let debut = try? DateHeureParis.instantJolene(mission.debutLe), heures > 0 {
                ajouterHeures(&resultat, &ordre, cle: cleSemaineCivile(debut), debut: debutSemaineCivile(debut), heures: heures)
            }
        }

        return ordre.compactMap { resultat[$0] }
            .map { HeuresSemaineMission(cleSemaine: $0.cleSemaine, debutSemaine: $0.debutSemaine,
                                        heures: CalendrierCivil.arrondiJS($0.heures * 100) / 100) }
            .sorted { $0.cleSemaine < $1.cleSemaine }
    }

    /// Total par semaine civile, toutes missions confondues, indexé par clé de semaine.
    public static func additionnerHeuresParSemaine(_ missions: [MissionPourCalculHebdomadaire], _ creneaux: [MissionSlot]) -> [String: HeuresSemaineMission] {
        var resultat: [String: HeuresSemaineMission] = [:]
        var ordre: [String] = []
        for mission in missions {
            for semaine in heuresMissionParSemaine(mission, creneaux) {
                ajouterHeures(&resultat, &ordre, cle: semaine.cleSemaine, debut: semaine.debutSemaine, heures: semaine.heures)
            }
        }
        return resultat
    }

    /// Reproduit la résolution des gardes SQL du plafond de 48 h : contrat
    /// appliqué, puis choix du soignant, puis LIBERAL uniquement lorsque la
    /// mission le demande explicitement. `TOUS` et toute valeur absente restent
    /// salariées par défaut.
    public static func missionComptePourPlafond48h(_ mission: MissionPourCalculHebdomadaire) -> Bool {
        let choix = normalise(mission.choixContratSoignant)?.uppercased()
        let regime = mission.typeContratApplique
            ?? choix
            ?? (mission.typeContratRecherche == "LIBERAL" ? "LIBERAL" : "SALARIE")
        return regime != "LIBERAL"
    }

    /// Une mission TOUS encore ouverte doit laisser choisir le régime au CTA.
    public static func missionPlafond48hConditionnel(_ mission: MissionPourCalculHebdomadaire) -> Bool {
        (mission.typeContratApplique ?? "").isEmpty
            && normalise(mission.choixContratSoignant) == nil
            && mission.typeContratRecherche == "TOUS"
    }

    public static func additionnerHeuresSalarieesParSemaine(_ missions: [MissionPourCalculHebdomadaire], _ creneaux: [MissionSlot]) -> [String: HeuresSemaineMission] {
        additionnerHeuresParSemaine(missions.filter(missionComptePourPlafond48h), creneaux)
    }

    /// `valeur?.trim() || null`.
    private static func normalise(_ valeur: String?) -> String? {
        guard let valeur else { return nil }
        let nettoye = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
        return nettoye.isEmpty ? nil : nettoye
    }
}
