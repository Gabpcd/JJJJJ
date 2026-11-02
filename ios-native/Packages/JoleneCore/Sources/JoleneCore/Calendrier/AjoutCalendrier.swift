import Foundation

// Ajout d'une mission au calendrier de l'appareil (lot 1, T5, décision 18). Règles pures et
// orchestration ici, sans EventKit : l'app fournit l'appareil (`CalendrierAppareil`, enveloppe
// `@MainActor` d'`EKEventStore`, `Jolene/Composition/CalendarWriter.swift`) et le journal. Mécanisme
// fixé en T0 (`RECETTE_DEVICE_LOT1.md` §4) : un événement par créneau PREVISIONNEL hors pause dont la
// fin est renseignée, comme l'ICS du web (`src/lib/ics-mission.ts` l.36-66) ; doublons évités par un
// journal local des créneaux déjà ajoutés (écriture seule sous iOS 17 : aucun événement relisible).

/// Événement à écrire : un créneau planifié de la mission.
public struct EvenementCalendrier: Equatable, Sendable {
    /// Clé du journal : `missionId|identifiant ou rang du créneau|debut|fin` (bornes serveur telles
    /// quelles) — un créneau dont l'horaire change est un nouvel événement.
    public var cle: String
    public var titre: String
    public var debut: Date
    public var fin: Date
    public var lieu: String?
    public var notes: String
    public var url: URL?
    /// Rappels en minutes avant le début (web : `alerts: [-1440, -60]`).
    public var alarmesMinutes: [Int]

    public init(cle: String, titre: String, debut: Date, fin: Date, lieu: String?, notes: String, url: URL?, alarmesMinutes: [Int]) {
        self.cle = cle; self.titre = titre; self.debut = debut; self.fin = fin; self.lieu = lieu
        self.notes = notes; self.url = url; self.alarmesMinutes = alarmesMinutes
    }
}

public enum CalendrierMission {
    public static let alarmesMinutes = [-1440, -60]

    /// Événements d'une mission : un par créneau planifié d'un planning **complet**
    /// (`MesMissionsPresentation.completude`, repli ponctuel de 24 h au plus compris). Un planning
    /// incomplet n'en produit aucun : jamais un horaire non confirmé présenté comme exact (même règle
    /// que le bouton de l'Accueil, affiché seulement sur un planning vérifié).
    public static func evenements(pour mission: Mission) -> [EvenementCalendrier] {
        let analyse = MesMissionsPresentation.completude(mission)
        guard analyse.complet else { return [] }
        let nom = mission.etablissement?.nom.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ville = mission.etablissement?.adresseVille?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = self.url(missionId: mission.id)
        return DisponibilitePointage.creneauxPrevisionnels(analyse.creneauxPlanifies).enumerated().compactMap { rang, creneau in
            guard let fin = creneau.finRenseignee, let debutDate = PlanningHorlogeParis.instant(creneau.debut),
                  let finDate = PlanningHorlogeParis.instant(fin), finDate > debutDate else { return nil }
            return EvenementCalendrier(
                cle: cle(missionId: mission.id, creneau: creneau, rang: rang),
                titre: mission.record.intitule, debut: debutDate, fin: finDate,
                // Le web joint `adresse_rue` et `adresse_ville` ; la projection du lot 0
                // (`EtablissementSummary`) ne lit pas la rue : la ville seule (écart consigné).
                lieu: ville.isEmpty ? nil : ville,
                notes: nom.isEmpty ? "Mission Jolene" : "Mission Jolene — \(nom)",
                url: url, alarmesMinutes: alarmesMinutes)
        }
    }

    /// `https://jolene.app/soignant/missions/{id}` (identifiant encodé comme `encodeURIComponent`).
    public static func url(missionId: String) -> URL? {
        var autorises = CharacterSet.alphanumerics
        autorises.insert(charactersIn: "-_.!~*'()")
        guard let id = missionId.addingPercentEncoding(withAllowedCharacters: autorises), !id.isEmpty else { return nil }
        return URL(string: "https://jolene.app/soignant/missions/\(id)")
    }

    static func cle(missionId: String, creneau: MissionSlot, rang: Int) -> String {
        let identifiant = (creneau.id?.isEmpty == false ? creneau.id : nil) ?? "rang-\(rang + 1)"
        return [missionId, identifiant, creneau.debut, creneau.finRenseignee ?? ""].joined(separator: "|")
    }
}

// MARK: - Appareil et journal

/// État de l'accord calendrier de l'appareil (sans demande).
public enum AccesCalendrier: Equatable, Sendable {
    case accorde
    case nonDetermine
    /// Refusé par l'utilisateur ou restreint : aucune nouvelle demande forcée.
    case refuse
}

/// Calendrier de l'appareil : EventKit dans l'app, double en mémoire en démo et dans les tests.
@MainActor
public protocol CalendrierAppareil: AnyObject {
    func acces() -> AccesCalendrier
    /// Demande système (iOS 16 accès complet, iOS 17+ écriture seule) ; `true` si accordée.
    func demanderAcces() async -> Bool
    func enregistrer(_ evenement: EvenementCalendrier) throws
}

/// Journal local des créneaux déjà ajoutés (dédoublonnage, `RECETTE_DEVICE_LOT1.md` §4).
@MainActor
public protocol JournalCalendrier: AnyObject {
    func contient(_ cle: String) -> Bool
    func noter(_ cle: String)
}

/// Journal persistant d'un compte : une clé `UserDefaults` par utilisateur, dont l'identifiant est un
/// segment entier (`jolene.calendrier.journal.<userId>`), purgée après une suppression de compte
/// confirmée (`CompteSuppression.purgerPreferencesLocales`, T8).
@MainActor
public final class JournalCalendrierPreferences: JournalCalendrier {
    public static func cle(userId: String) -> String { "jolene.calendrier.journal.\(userId)" }

    private let defaults: UserDefaults
    private let cle: String

    public init(userId: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cle = Self.cle(userId: userId)
    }

    public func contient(_ cle: String) -> Bool { entrees.contains(cle) }

    public func noter(_ cle: String) {
        guard !contient(cle) else { return }
        defaults.set(entrees + [cle], forKey: self.cle)
    }

    private var entrees: [String] { defaults.stringArray(forKey: cle) ?? [] }
}

/// Journal en mémoire (démo, tests) : vide à chaque lancement.
@MainActor
public final class JournalCalendrierMemoire: JournalCalendrier {
    public private(set) var entrees: [String] = []
    public init() {}
    public func contient(_ cle: String) -> Bool { entrees.contains(cle) }
    public func noter(_ cle: String) { if !contient(cle) { entrees.append(cle) } }
}

// MARK: - Orchestration

/// Issue présentée sous la liste (Accueil `accueil-calendrier-issue`, Mes missions
/// `missions-calendrier-issue`). Vouvoiement sobre, aucune donnée de la mission dans le message.
public struct IssueAjoutCalendrier: Equatable, Sendable {
    public var message: String
    public var succes: Bool
    public var ajoutes: Int
    public var dejaPresents: Int
    public var echecs: Int

    public init(message: String, succes: Bool, ajoutes: Int = 0, dejaPresents: Int = 0, echecs: Int = 0) {
        self.message = message; self.succes = succes; self.ajoutes = ajoutes; self.dejaPresents = dejaPresents; self.echecs = echecs
    }

    public static let planningNonConfirme = "Le planning de cette mission n'est pas encore confirmé : rien n'a été ajouté à votre calendrier."
    public static let accesRefuse = "L'accès au calendrier n'est pas autorisé. Vous pouvez l'activer dans les Réglages de l'appareil, rubrique Jolene."
    public static let dejaAjoutes = "Les créneaux de cette mission sont déjà dans votre calendrier."
    public static let echecTotal = "Le calendrier n'a pas pu enregistrer cette mission. Réessayez."

    static func ajout(_ ajoutes: Int, deja: Int) -> String {
        let base = ajoutes > 1 ? "\(ajoutes) créneaux ajoutés à votre calendrier" : "1 créneau ajouté à votre calendrier"
        guard deja > 0 else { return base + "." }
        return base + " (\(deja) déjà présent\(deja > 1 ? "s" : ""))."
    }

    static func partiel(_ ajoutes: Int, echecs: Int) -> String {
        let base = ajoutes > 1 ? "\(ajoutes) créneaux ajoutés à votre calendrier" : "1 créneau ajouté à votre calendrier"
        let reste = echecs > 1 ? "\(echecs) n'ont pas pu l'être" : "1 n'a pas pu l'être"
        return "\(base), \(reste). Réessayez pour compléter."
    }
}

/// Ajout au calendrier d'une mission : événements du planning complet, journal, accord, écriture.
/// - aucun événement (planning non confirmé) → aucune demande d'accès ;
/// - tous déjà notés au journal → message d'information, aucune demande ni écriture ;
/// - accord refusé (ou restreint) → message, aucune écriture, aucune nouvelle demande forcée ;
/// - chaque créneau écrit est noté au journal aussitôt : un échec partiel se complète au tap suivant
///   sans doublon.
/// Deux taps rapprochés sur la même mission partagent la même opération (aucun doublon).
@MainActor
public final class AjoutCalendrier {
    private let appareil: CalendrierAppareil
    private let journal: JournalCalendrier
    private var enCours: [String: Task<IssueAjoutCalendrier, Never>] = [:]

    public init(appareil: CalendrierAppareil, journal: JournalCalendrier) {
        self.appareil = appareil
        self.journal = journal
    }

    public func ajouter(_ mission: Mission) async -> IssueAjoutCalendrier {
        if let tache = enCours[mission.id] { return await tache.value }
        let tache = Task { await self.executer(mission) }
        enCours[mission.id] = tache
        let issue = await tache.value
        enCours[mission.id] = nil
        return issue
    }

    private func executer(_ mission: Mission) async -> IssueAjoutCalendrier {
        let evenements = CalendrierMission.evenements(pour: mission)
        guard !evenements.isEmpty else { return IssueAjoutCalendrier(message: IssueAjoutCalendrier.planningNonConfirme, succes: false) }
        let nouveaux = evenements.filter { !journal.contient($0.cle) }
        let deja = evenements.count - nouveaux.count
        guard !nouveaux.isEmpty else {
            return IssueAjoutCalendrier(message: IssueAjoutCalendrier.dejaAjoutes, succes: true, dejaPresents: deja)
        }
        switch appareil.acces() {
        case .accorde:
            break
        case .refuse:
            return IssueAjoutCalendrier(message: IssueAjoutCalendrier.accesRefuse, succes: false)
        case .nonDetermine:
            guard await appareil.demanderAcces() else {
                return IssueAjoutCalendrier(message: IssueAjoutCalendrier.accesRefuse, succes: false)
            }
        }
        var ajoutes = 0
        var echecs = 0
        for evenement in nouveaux {
            do {
                try appareil.enregistrer(evenement)
                journal.noter(evenement.cle)
                ajoutes += 1
            } catch {
                echecs += 1
            }
        }
        if ajoutes == 0 {
            return IssueAjoutCalendrier(message: IssueAjoutCalendrier.echecTotal, succes: false, dejaPresents: deja, echecs: echecs)
        }
        if echecs > 0 {
            return IssueAjoutCalendrier(message: IssueAjoutCalendrier.partiel(ajoutes, echecs: echecs), succes: false,
                                        ajoutes: ajoutes, dejaPresents: deja, echecs: echecs)
        }
        return IssueAjoutCalendrier(message: IssueAjoutCalendrier.ajout(ajoutes, deja: deja), succes: true,
                                    ajoutes: ajoutes, dejaPresents: deja)
    }
}

// MARK: - Démonstration

/// Calendrier du monde démo : aucun accès système, aucune écriture réelle ; les événements « écrits »
/// sont gardés en mémoire (preuve XCUITest par le message d'issue). `refuse` (surcharge DEBUG
/// `JOLENE_FORCE_CALENDRIER_REFUS`) simule un accès refusé.
@MainActor
public final class CalendrierAppareilDemo: CalendrierAppareil {
    public private(set) var evenements: [EvenementCalendrier] = []
    public private(set) var demandes = 0
    private let refuse: Bool

    public init(refuse: Bool = false) { self.refuse = refuse }

    public func acces() -> AccesCalendrier { refuse ? .refuse : .accorde }

    public func demanderAcces() async -> Bool {
        demandes += 1
        return !refuse
    }

    public func enregistrer(_ evenement: EvenementCalendrier) throws {
        evenements.append(evenement)
    }
}
