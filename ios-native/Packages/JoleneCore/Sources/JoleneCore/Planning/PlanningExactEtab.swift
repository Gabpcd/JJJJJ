import Foundation

/// Planning exact qu'un établissement confirme avant d'accepter une candidature (lot 5, T3) :
/// port de `verifierPlanningExact` et `empreintePlanning` (`src/components/ListeCandidatures.tsx`
/// l.60-106) et de la durée totale du récapitulatif (l.172-174).
///
/// Flux (blueprint lot 5 §2.6) : la lecture habilitée est vérifiée à l'ouverture, puis relue au
/// moment du récapitulatif et une seconde fois juste avant l'envoi ; si l'empreinte relue diffère
/// de celle du récapitulatif, le récapitulatif est remplacé et rien n'est envoyé
/// (`messagePlanningModifie`). La charge `p_creneaux_confirmes` est l'**écho exact** des chaînes
/// `debut`/`fin` relues (D26) : le serveur compare des instants à la microseconde, qu'une
/// conversion par `Date` tronquerait (écart assumé avec `CreneauxConfirmes.pourAction` du lot 1).
/// Messages repris mot pour mot du web, non juridiques.
public enum PlanningExactEtab {
    /// Résultat de la vérification : les créneaux PREVISIONNEL de travail triés par début, ou
    /// le message qui bloque l'acceptation (aucun créneau n'est alors exposé).
    public struct Verification: Equatable, Sendable {
        public var creneaux: [MissionSlot]
        public var erreur: String?

        public init(creneaux: [MissionSlot], erreur: String?) {
            self.creneaux = creneaux; self.erreur = erreur
        }

        public var exact: Bool { erreur == nil }

        static func refus(_ message: String) -> Verification { Verification(creneaux: [], erreur: message) }
    }

    /// Élément de l'empreinte `{ id: id ?? null, debut, fin }`, comparé chaîne pour chaîne.
    public struct Empreinte: Equatable, Hashable, Sendable {
        public var id: String?
        public var debut: String
        public var fin: String?

        public init(id: String?, debut: String, fin: String?) {
            self.id = id; self.debut = debut; self.fin = fin
        }
    }

    // MARK: - Messages repris du web (non juridiques)

    // source: src/components/ListeCandidatures.tsx:66
    public static let messageIndisponible = "Le planning détaillé est momentanément indisponible."
    // source: src/components/ListeCandidatures.tsx:71
    public static let messageNombreNonConfirme = "Le nombre de créneaux contractuels doit être confirmé."
    // source: src/components/ListeCandidatures.tsx:84
    public static let messageFinManquante = "Chaque créneau doit comporter une date et une heure de fin exactes."
    // source: src/components/ListeCandidatures.tsx:92
    public static let messageHorairesInvalides = "Le planning contient un créneau dont les horaires sont invalides."
    // source: src/components/ListeCandidatures.tsx:96
    public static let messageDateInvalide = "Le planning contient une date ou une heure invalide."
    // source: src/components/ListeCandidatures.tsx:246
    public static let messageAConfirmer = "Le planning détaillé doit être confirmé avant d’accepter une candidature."
    // source: src/components/ListeCandidatures.tsx:277
    public static let messagePlanningModifie = "Le planning a changé depuis l’ouverture. Vérifiez les nouveaux horaires puis confirmez de nouveau."
    // source: src/components/ListeCandidatures.tsx:378
    public static let titreBandeauAConfirmer = "Planning détaillé à confirmer avant toute acceptation."
    // source: src/components/ListeCandidatures.tsx:380
    public static let detailBandeauAConfirmer = "Aucun candidat ne sera assigné tant que chaque créneau ne comporte pas une date et une heure de fin exactes."

    /// `Planning incomplet : N créneau(x) attendu(s), M chargé(s).`
    // source: src/components/ListeCandidatures.tsx:80
    public static func messageIncomplet(attendus: Int, charges: Int) -> String {
        "Planning incomplet : \(attendus) créneau\(attendus > 1 ? "x" : "") attendu\(attendus > 1 ? "s" : ""), \(charges) chargé\(charges > 1 ? "s" : "")."
    }

    // MARK: - Vérification (l.60-98)

    /// Le planning n'est exact que si `nb_creneaux` est un entier positif, égal au nombre de
    /// lignes PREVISIONNEL hors pause, toutes fermées, lisibles et de fin postérieure au début.
    /// `indisponible` : la lecture du planning a échoué.
    public static func verifier(_ creneaux: [MissionSlot], nbCreneauxAttendus: Int?, indisponible: Bool = false) -> Verification {
        if indisponible { return .refus(messageIndisponible) }
        guard let attendus = nbCreneauxAttendus, attendus > 0 else { return .refus(messageNombreNonConfirme) }

        let planifies = creneaux.filter { $0.typeCreneau == "PREVISIONNEL" && !$0.estPause }
        if planifies.count != attendus {
            return .refus(messageIncomplet(attendus: attendus, charges: planifies.count))
        }
        if planifies.contains(where: { $0.finRenseignee == nil }) { return .refus(messageFinManquante) }

        let complets = DisponibilitePointage.creneauxPrevisionnels(planifies)
        if complets.count != attendus { return .refus(messageHorairesInvalides) }
        // `complets.some(fin <= debut)` dans l'ordre du planning ; une date illisible lève
        // (`instantJolene`) et donne le message de date invalide.
        for creneau in complets {
            guard let fin = creneau.finRenseignee,
                  let finDate = try? DateHeureParis.instantJolene(fin),
                  let debutDate = try? DateHeureParis.instantJolene(creneau.debut) else {
                return .refus(messageDateInvalide)
            }
            if DateHeureParis.millisecondes(finDate) <= DateHeureParis.millisecondes(debutDate) {
                return .refus(messageHorairesInvalides)
            }
        }
        return Verification(creneaux: complets, erreur: nil)
    }

    // MARK: - Empreinte (l.100-106) et charge envoyée

    /// Empreinte `(id, debut, fin)` dans l'ordre des créneaux vérifiés (début, puis ordre serveur).
    public static func empreinte(_ creneaux: [MissionSlot]) -> [Empreinte] {
        creneaux.map { Empreinte(id: $0.id, debut: $0.debut, fin: $0.fin) }
    }

    /// Égalité stricte des empreintes (chaînes comparées telles quelles, comme `JSON.stringify`).
    public static func memeEmpreinte(_ a: [MissionSlot], _ b: [MissionSlot]) -> Bool {
        empreinte(a) == empreinte(b)
    }

    /// `p_creneaux_confirmes` de l'acceptation : écho exact des chaînes relues (web l.285), ou
    /// `nil` si le planning n'est pas exact (aucune charge approximative n'est jamais envoyée).
    public static func creneauxConfirmes(_ verification: Verification) -> [CreneauConfirmePayload]? {
        guard verification.exact else { return nil }
        var charge: [CreneauConfirmePayload] = []
        for creneau in verification.creneaux {
            guard let fin = creneau.finRenseignee else { return nil }
            charge.append(CreneauConfirmePayload(debut: creneau.debut, fin: fin))
        }
        return charge
    }

    /// Durée totale du récapitulatif (l.172-174) : somme des durées positives, en heures, calculée
    /// sur les instants serveur ; une borne illisible ne compte pas.
    public static func dureeTotaleHeures(_ creneaux: [MissionSlot]) -> Double {
        creneaux.reduce(0.0) { total, creneau in
            guard let fin = creneau.finRenseignee,
                  let finDate = try? DateHeureParis.instantJolene(fin),
                  let debutDate = try? DateHeureParis.instantJolene(creneau.debut) else { return total }
            let heures = Double(DateHeureParis.millisecondes(finDate) - DateHeureParis.millisecondes(debutDate)) / 3_600_000
            return total + max(0, heures)
        }
    }
}
