import Foundation

/// Filtre du paquet de swipe (chips rapides 6c.1 : le paquet respecte les mêmes filtres 1-tap que la liste) : port de
/// `src/lib/filtre-paquet-swipe.ts` (prédicat extrait de `VueSwipeMissions.tsx` par la PR web W0), vecteurs
/// `filtre-paquet-swipe.json` (L4-T2, `LOT4_PLAN.md` §3 T2).
///
/// Chaînes comparées comme le web : `trim` d'ECMAScript (`PrimitivesJS.trim`), casse par `lowercased()` (même table
/// Unicode que `toLowerCase` pour l'alphabet latin, domaine golden), sous-chaîne et préfixe par unités UTF-16 : une
/// ville saisie en forme décomposée (« e + accent ») ne correspond pas à la forme composée, comme `includes`.
public struct FiltrePaquetSwipe: Equatable, Sendable {
    public var urgentesOnly: Bool
    public var horaire: MissionFilters.Horaire
    public var profession: String
    public var ville: String
    public var rayonKm: Double
    public var tauxMin: Double
    /// `TOUS`, `CDD` (écarte les missions `LIBERAL`) ou `LIBERAL` (écarte les missions `SALARIE`).
    public var typeContrat: String

    public init(urgentesOnly: Bool = false, horaire: MissionFilters.Horaire = .tous, profession: String = "", ville: String = "",
                rayonKm: Double, tauxMin: Double = 0, typeContrat: String = "TOUS") {
        self.urgentesOnly = urgentesOnly; self.horaire = horaire; self.profession = profession; self.ville = ville
        self.rayonKm = rayonKm; self.tauxMin = tauxMin; self.typeContrat = typeContrat
    }
}

/// Champs d'une carte de swipe lus par le filtre (`MissionPaquetSwipe` du web) ; le planning est celui de
/// `PlanningCandidatRules` (filtre horaire jour, nuit, week-end sur le planning exact).
public struct MissionPaquetSwipe: Equatable, Sendable {
    public var professionRequise: String?
    public var etablissementVille: String?
    public var etablissementCodePostal: String?
    public var distanceKm: Double?
    public var tauxHoraireBase: Double?
    public var typeContratRecherche: String?
    public var estUrgente: Bool
    public var planning: PlanningCandidatInput

    public init(professionRequise: String?, etablissementVille: String?, etablissementCodePostal: String?, distanceKm: Double?,
                tauxHoraireBase: Double?, typeContratRecherche: String?, estUrgente: Bool, planning: PlanningCandidatInput) {
        self.professionRequise = professionRequise; self.etablissementVille = etablissementVille
        self.etablissementCodePostal = etablissementCodePostal; self.distanceKm = distanceKm
        self.tauxHoraireBase = tauxHoraireBase; self.typeContratRecherche = typeContratRecherche
        self.estUrgente = estUrgente; self.planning = planning
    }

    /// Carte décodée (`CarteSwipe.mission`, T3a) : ville et code postal de l'établissement, distance calculée.
    public init(mission: Mission) {
        self.init(professionRequise: mission.record.professionRequise, etablissementVille: mission.etablissement?.adresseVille,
                  etablissementCodePostal: mission.etablissement?.adresseCodePostal, distanceKm: mission.distanceKm,
                  tauxHoraireBase: mission.record.tauxHoraireBase, typeContratRecherche: mission.record.typeContratRecherche,
                  estUrgente: mission.record.estUrgente, planning: PlanningCandidatInput(mission: mission))
    }
}

extension FiltrePaquetSwipe {
    /// Exploration avant inscription : la profession choisie prime ; sinon celle du compte, avec sa hiérarchie
    /// naturelle (IADE/IBODE → missions IDE, branche `HIERARCHIE_NATURELLE` de `getMissionMatchInfo`). Un compte sans
    /// profession voit tout.
    public static func missionCorrespondProfessionInscription(requise: String?, selection: String, compte: String) -> Bool {
        if !selection.isEmpty { return requise == selection }
        return compte.isEmpty || requise == compte
            || (requise == "IDE" && ProfessionHierarchy.professionsAvecHierarchie.contains(compte))
    }

    /// `missionPasseFiltrePaquet`. `professionParcours` : `nil` hors parcours d'inscription, sinon la profession du
    /// compte en cours d'inscription (chaîne vide si inconnue).
    public func laissePasser(_ mission: MissionPaquetSwipe, professionParcours: String?) -> Bool {
        if let professionParcours {
            guard Self.missionCorrespondProfessionInscription(requise: mission.professionRequise, selection: profession,
                                                               compte: professionParcours) else { return false }
        } else if !profession.isEmpty && mission.professionRequise != profession {
            return false
        }
        let villeFiltre = Array(PrimitivesJS.trim(ville).lowercased().utf16)
        if !villeFiltre.isEmpty {
            let villeMission = Array((mission.etablissementVille ?? "").lowercased().utf16)
            let codePostal = Array((mission.etablissementCodePostal ?? "").lowercased().utf16)
            if !Self.contient(villeMission, villeFiltre) && !codePostal.starts(with: villeFiltre) { return false }
        }
        if let distance = mission.distanceKm, distance > rayonKm { return false }
        if tauxMin > 0 && (mission.tauxHoraireBase ?? 0) < tauxMin { return false }
        if typeContrat == "CDD" && mission.typeContratRecherche == "LIBERAL" { return false }
        if typeContrat == "LIBERAL" && mission.typeContratRecherche == "SALARIE" { return false }
        if urgentesOnly && !mission.estUrgente { return false }
        return PlanningCandidatRules.planningCorrespondAuFiltre(mission.planning, filtre: horaire)
    }

    /// `filtrerPaquetSwipe` : sans filtre, le paquet est rendu tel quel ; sinon l'ordre du paquet est conservé.
    public static func filtrer<Carte>(_ paquet: [Carte], filtre: FiltrePaquetSwipe?, professionParcours: String?,
                                      mission: (Carte) -> MissionPaquetSwipe) -> [Carte] {
        guard let filtre else { return paquet }
        return paquet.filter { filtre.laissePasser(mission($0), professionParcours: professionParcours) }
    }

    /// `String.prototype.includes` sur unités UTF-16 (une chaîne vide est toujours contenue).
    static func contient(_ texte: [UInt16], _ motif: [UInt16]) -> Bool {
        guard !motif.isEmpty else { return true }
        guard texte.count >= motif.count else { return false }
        for debut in 0...(texte.count - motif.count) where texte[debut] == motif[0] {
            if texte[debut..<(debut + motif.count)].elementsEqual(motif) { return true }
        }
        return false
    }
}
