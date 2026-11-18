import Foundation

/// Port de `calculerCompletionProfil` (`src/lib/profil-soignant.ts` l.32-153), soft-gate client de la
/// candidature (décision 3, `LOT1_PLAN.md` §2.6). Source unique : le `SoignantProfile` relu par le SELECT
/// direct étendu (`MissionQuery.profileSelect`) ; aucune donnée de `fn_mon_profil_soignant_complet`.
///
/// Obligatoires : prénom, nom, date de naissance, téléphone, et RPPS vérifié sauf pour les professions
/// sans RPPS (`ProfessionsRpps.sansRpps`, `PROFESSIONS_SANS_RPPS` du web) ; une profession vide garde le
/// RPPS obligatoire. Recommandés : profession, adresse géolocalisée (latitude et longitude non nulles,
/// comme `!!adresse_lat && !!adresse_lng`). `fn_postuler_mission` ne vérifie aucun de ces champs : le
/// gate ne remplace jamais un refus serveur, affiché même gate vert.
public struct ProfilCompletion: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var cle: String
        public var label: String
        public var rempli: Bool
        public var obligatoire: Bool
        public var ordre: Int
    }

    /// Items dans l'ordre du web (`ordre`).
    public var items: [Item]
    /// Part des items remplis, arrondie comme `Math.round` ; 0 sans profil.
    public var pourcentage: Int
    public var peutCandidater: Bool
    public var estComplet: Bool
    /// Clés des items obligatoires manquants, dans l'ordre (`items_obligatoires_manquants`).
    public var obligatoiresManquants: [String]
    /// Clés des items recommandés manquants (`items_recommandes_manquants`).
    public var recommandesManquants: [String]

    /// Nombre d'items d'un profil absent (`total_items: 7` du web).
    public static let totalItemsSansProfil = 7

    public static func calculer(_ profil: SoignantProfile?) -> ProfilCompletion {
        guard let profil else {
            return ProfilCompletion(items: [], pourcentage: 0, peutCandidater: false, estComplet: false,
                                    obligatoiresManquants: [], recommandesManquants: [])
        }
        let sansRpps = !profil.profession.isEmpty && ProfessionsRpps.estSansRpps(profil.profession)
        var items: [Item] = [
            Item(cle: "prenom", label: "Prénom", rempli: rempli(profil.prenom), obligatoire: true, ordre: 1),
            Item(cle: "nom", label: "Nom", rempli: rempli(profil.nom), obligatoire: true, ordre: 2),
            Item(cle: "date_naissance", label: "Date de naissance", rempli: rempli(profil.dateNaissance), obligatoire: true, ordre: 3),
            Item(cle: "telephone", label: "Téléphone", rempli: rempli(profil.telephone), obligatoire: true, ordre: 4),
        ]
        if !sansRpps {
            items.append(Item(cle: "rpps", label: "RPPS vérifié", rempli: profil.rppsVerifie == true, obligatoire: true, ordre: 5))
        }
        items.append(Item(cle: "profession", label: "Profession", rempli: !profil.profession.isEmpty, obligatoire: false, ordre: 6))
        items.append(Item(cle: "adresse", label: "Adresse géolocalisée",
                          rempli: nonNul(profil.adresseLat) && nonNul(profil.adresseLng), obligatoire: false, ordre: 7))
        items.sort { $0.ordre < $1.ordre }

        let remplis = items.filter(\.rempli).count
        let pourcentage = Int((Double(remplis) / Double(items.count) * 100).rounded(.toNearestOrAwayFromZero))
        let obligatoiresManquants = items.filter { $0.obligatoire && !$0.rempli }.map(\.cle)
        return ProfilCompletion(items: items, pourcentage: pourcentage, peutCandidater: obligatoiresManquants.isEmpty,
                                estComplet: pourcentage == 100, obligatoiresManquants: obligatoiresManquants,
                                recommandesManquants: items.filter { !$0.obligatoire && !$0.rempli }.map(\.cle))
    }

    /// `!!valeur` du web pour une chaîne : absente ou vide → faux.
    private static func rempli(_ valeur: String?) -> Bool { !(valeur ?? "").isEmpty }

    /// `!!valeur` du web pour un nombre : absent ou 0 → faux.
    private static func nonNul(_ valeur: Double?) -> Bool { (valeur ?? 0) != 0 }
}
