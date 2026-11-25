import Foundation

// Disponibilités du soignant (L4-T5, `docs/mobile-swift/LOT4_PLAN.md` §3 T5). Les types d'échange du port
// (`JourParis`, `CreneauDispo`, `DispoCle`, `IssueDisponibilite`) restent dans `Models/Lot4Results.swift`, posés par T1 ;
// ce fichier porte ce que la tranche y ajoute : jours civils (validité, décalage, semaine) et lecture des lignes de
// `disponibilites_soignant`.
//
// Contrat de `DisponibilitesPort.definir` : `IssueDisponibilite.relue` rend les cases de la **semaine civile** du jour
// basculé (`JourParis.semaine`, du lundi au dimanche), relues après l'écriture ; le modèle remplace cette semaine dans
// la grille ou, si d'autres appels se chevauchent, n'en retient que la case basculée (`DisponibilitesModel`).

extension JourParis {
    /// Composantes civiles si `iso` est une date réelle écrite `yyyy-MM-dd` (dix caractères, chiffres ASCII) ; sinon
    /// `nil` : « 2026-02-30 », « 2026-11-3 » ou un horodatage ne sont pas des jours.
    var civil: (annee: Int, mois: Int, jour: Int)? {
        let octets = Array(iso.utf8)
        guard octets.count == 10, octets[4] == UInt8(ascii: "-"), octets[7] == UInt8(ascii: "-") else { return nil }
        func nombre(_ plage: Range<Int>) -> Int? {
            var valeur = 0
            for octet in octets[plage] {
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(octet) else { return nil }
                valeur = valeur * 10 + Int(octet - UInt8(ascii: "0"))
            }
            return valeur
        }
        guard let annee = nombre(0..<4), let mois = nombre(5..<7), let jour = nombre(8..<10),
              (1...12).contains(mois), (1...31).contains(jour) else { return nil }
        // Aller-retour par le calendrier : un 30 février ne retombe pas sur lui-même.
        let relu = CalendrierCivil.civilDepuisJours(CalendrierCivil.joursDepuisCivil(annee: annee, mois: mois, jour: jour))
        guard relu.annee == annee, relu.mois == mois, relu.jour == jour else { return nil }
        return (annee, mois, jour)
    }

    /// Vrai si `iso` est un jour civil réel au format du serveur (`date` PostgreSQL, `p_jour`).
    public var estValide: Bool { civil != nil }

    /// Jour civil situé `jours` jours plus loin (plus tôt si négatif) ; `nil` si `iso` n'est pas un jour.
    public func decale(de jours: Int) -> JourParis? {
        guard let civil else { return nil }
        let cible = CalendrierCivil.civilDepuisJours(
            CalendrierCivil.joursDepuisCivil(annee: civil.annee, mois: civil.mois, jour: civil.jour) + jours)
        return JourParis(iso: String(format: "%04d-%02d-%02d", cible.annee, cible.mois, cible.jour))
    }

    /// Semaine civile du jour, du lundi au dimanche (semaines de la grille, `SemainesDisponibilites`). Des jours, aucune
    /// heure : les changements d'heure n'y changent rien. `nil` si `iso` n'est pas un jour.
    public var semaine: ClosedRange<JourParis>? {
        guard let civil else { return nil }
        // `CalendrierCivil.jourSemaine` : 0 = dimanche … 6 = samedi.
        let jourSemaine = CalendrierCivil.jourSemaine(annee: civil.annee, mois: civil.mois, jour: civil.jour)
        guard let lundi = decale(de: -(jourSemaine == 0 ? 6 : jourSemaine - 1)), let dimanche = lundi.decale(de: 6) else { return nil }
        return lundi...dimanche
    }
}

/// Ligne de `disponibilites_soignant` lue par PostgREST (`select=jour,creneau`, comme le web,
/// `src/pages/MesDisponibilites.tsx` l.51-53). Les deux colonnes sont `NOT NULL` : une ligne sans l'une d'elles n'est
/// pas décodée.
public struct LigneDisponibilite: Decodable, Equatable, Sendable {
    public var jour: String
    public var creneau: String

    public init(jour: String, creneau: String) {
        self.jour = jour; self.creneau = creneau
    }
}

/// Lecture des lignes de `disponibilites_soignant` en cases de la grille.
public enum DisponibilitesLecture {
    /// Colonnes lues (`select` du web, l.52).
    public static let colonnes = "jour,creneau"

    /// Cases déclarées. `nil` si un `jour` n'est pas une date `yyyy-MM-dd` : la réponse est refusée, jamais rendue en
    /// grille plausible. Un créneau hors grille est ignoré : la RPC admet aussi `MATIN` et `APRES_MIDI`
    /// (`fn_definir_disponibilite`), que ni le web ni l'app n'écrivent ni n'affichent (`DECISIONS_LOT4.md`,
    /// précision 5).
    public static func cles(_ lignes: [LigneDisponibilite]) -> Set<DispoCle>? {
        var cles = Set<DispoCle>()
        for ligne in lignes {
            let jour = JourParis(iso: ligne.jour)
            guard jour.estValide else { return nil }
            guard let creneau = CreneauDispo(rawValue: ligne.creneau) else { continue }
            cles.insert(DispoCle(jour: jour, creneau: creneau))
        }
        return cles
    }
}
