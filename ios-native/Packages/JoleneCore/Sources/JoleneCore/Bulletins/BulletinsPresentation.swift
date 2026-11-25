import Foundation

/// Lignes affichées d'une copie officielle (L4-T10), assemblées à partir des fragments verbatim de
/// `LibellesWeb.CopiesBulletins` exactement comme `CopiesBulletinsListe.tsx` (l.14, l.25-27, l.65-73) ; aucune règle
/// métier ici, seulement la mise en forme et l'ordre du web.
public enum BulletinsPresentation {
    private typealias L = LibellesWeb.CopiesBulletins

    /// Libellé de statut (l.14).
    public static func statut(_ statut: StatutCopieBulletin) -> String {
        switch statut {
        case .publiee: return L.statutPubliee
        case .remplacee: return L.statutRemplacee
        case .retiree: return L.statutRetiree
        }
    }

    /// Libellé d'un motif de signalement (l.15).
    public static func motif(_ motif: MotifSignalementCopie) -> String {
        switch motif {
        case .destinataire: return L.motifDestinataire
        case .contenu: return L.motifContenu
        case .autre: return L.motifAutre
        }
    }

    /// Ordre des motifs de la feuille (`Object.keys(motifs)`, l.88).
    public static let motifs: [MotifSignalementCopie] = [.destinataire, .contenu, .autre]

    /// « Du 01/10/2026 au 31/10/2026 » (l.65) : dates civiles `yyyy-MM-dd` validées, rendues en `dd/MM/yyyy`.
    public static func periode(_ copie: CopieBulletin) -> String {
        "\(L.periodeDu) \(jour(copie.periodeDebut)) \(L.periodeAu) \(jour(copie.periodeFin))"
    }

    /// « Version 2 · publiée le 31/10/2026 à 10:30 · 2 missions liées » (l.69), heure de Paris.
    public static func meta(_ copie: CopieBulletin) -> String {
        let pluriel = copie.missionIds.count > 1 ? "s" : ""
        return "\(L.version) \(copie.version) \(L.publieeLe) \(instant(copie.publieLe)) \(L.separateur) "
            + "\(copie.missionIds.count) \(L.mission)\(pluriel) \(L.liee)\(pluriel)"
    }

    /// « Motif de remplacement : correction du contenu. » (l.70), nil sans motif.
    public static func motifRemplacement(_ copie: CopieBulletin) -> String? {
        guard let motif = copie.motifRemplacement else { return nil }
        let texte = motif == .contenu ? L.remplacementContenu : L.remplacementAutre
        return "\(L.motifRemplacement) \(texte)\(L.point)"
    }

    /// Libellé d'accessibilité de la carte (`aria-label`, l.61).
    public static func accessibilite(_ copie: CopieBulletin) -> String {
        "\(L.accessibiliteVersion) \(copie.version)"
    }

    /// Employeur du filtre (`etablissement_id`, `etablissement_nom`).
    public struct Employeur: Identifiable, Equatable, Sendable {
        public var id: String
        public var nom: String
    }

    /// Employeurs distincts, dans l'ordre de première apparition (`new Map(…)`, l.25) ; nom vide si absent.
    public static func employeurs(_ copies: [CopieBulletin]) -> [Employeur] {
        var vus = Set<String>()
        var resultat: [Employeur] = []
        for copie in copies where vus.insert(copie.etablissementId).inserted {
            resultat.append(Employeur(id: copie.etablissementId, nom: copie.employeurNom ?? ""))
        }
        return resultat
    }

    /// Filtre employeur (`nil` = « Tous les employeurs ») puis tri du web : `periode_debut` décroissant, puis
    /// `version` décroissante (l.26-27).
    public static func liste(_ copies: [CopieBulletin], employeur: String?) -> [CopieBulletin] {
        copies.filter { employeur == nil || $0.etablissementId == employeur }
            .enumerated()
            .sorted { a, b in
                if a.element.periodeDebut != b.element.periodeDebut { return a.element.periodeDebut > b.element.periodeDebut }
                if a.element.version != b.element.version { return a.element.version > b.element.version }
                return a.offset < b.offset // tri stable, comme `Array.prototype.sort`
            }
            .map(\.element)
    }

    // MARK: - Dates

    /// `yyyy-MM-dd` (déjà validé strictement) → `dd/MM/yyyy`.
    static func jour(_ valeur: String) -> String {
        let parties = valeur.split(separator: "-")
        guard parties.count == 3 else { return valeur }
        return "\(parties[2])/\(parties[1])/\(parties[0])"
    }

    /// Instant ISO → `dd/MM/yyyy à HH:mm`, heure de Paris (`formatParis(…, 'dd/MM/yyyy à HH:mm')`).
    static func instant(_ valeur: String) -> String {
        guard let date = try? DateHeureParis.instantJolene(valeur) else { return valeur }
        let p = DateHeureParis.parties(date)
        func deux(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return "\(deux(p.jour))/\(deux(p.mois))/\(p.annee) à \(deux(p.heure)):\(deux(p.minute))"
    }
}
