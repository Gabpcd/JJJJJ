import Foundation

/// Critères d'Explorer tels que l'écran les édite (lot 1, T4a), port de l'état de
/// `src/pages/RechercheMissions.tsx` : état initial (l.101-109), chips rapides (l.335-358),
/// badge du bouton filtres (l.287-293), action de l'état vide (l.471-486), « Réinitialiser »
/// (l.609-623) et saisie du taux (l.574-581).
///
/// Source unique de l'état des filtres (principe « État dérivé ») : les `MissionFilters` envoyés
/// au port en sont dérivés (`missionFilters`), jamais stockés à côté. Ces critères ne remplacent
/// jamais la RLS ; la partie serveur (profession, taux, urgentes, établissement) et la partie
/// présentation (ville, rayon, contrat, horaire) restent celles de `SupabaseMissionsGateway`
/// et de `MissionBusiness.filter`.
public struct ExplorerFiltres: Equatable, Sendable {
    /// Curseur du rayon du web : `min={5} max={100} step={5}`.
    public static let rayonMinimumKm: Double = 5
    public static let rayonMaximumKm: Double = 100
    public static let rayonPasKm: Double = 5
    /// `Math.min(100, r + 20)` de l'état vide.
    public static let elargissementRayonKm: Double = 20

    public var ville: String
    public var rayonKm: Double
    public var tauxMin: Double
    /// `""` = profession du profil avec ses équivalences (IADE et IBODE voient les missions IDE).
    public var profession: String
    public var urgentesOnly: Bool
    public var typeContrat: MissionFilters.TypeContrat
    public var horaire: MissionFilters.Horaire
    /// Filtre établissement venu d'un lien (`?etablissement=`), conservé par « Réinitialiser ».
    public var etablissementId: String?

    public init(ville: String, rayonKm: Double, tauxMin: Double, profession: String, urgentesOnly: Bool,
                typeContrat: MissionFilters.TypeContrat, horaire: MissionFilters.Horaire, etablissementId: String?) {
        self.ville = ville; self.rayonKm = rayonKm; self.tauxMin = tauxMin; self.profession = profession
        self.urgentesOnly = urgentesOnly; self.typeContrat = typeContrat; self.horaire = horaire
        self.etablissementId = (etablissementId?.isEmpty ?? true) ? nil : etablissementId
    }

    /// État initial : `MissionBusiness.defaultFilters(profile:)` du lot 0 (rayon du profil ou
    /// 50 km, taux minimum du profil), si bien que la première lecture d'Explorer est inchangée.
    public static func initiaux(profile: SoignantProfile, etablissementId: String? = nil) -> ExplorerFiltres {
        let defauts = MissionBusiness.defaultFilters(profile: profile)
        return ExplorerFiltres(ville: defauts.ville ?? "", rayonKm: defauts.rayonKm ?? 50, tauxMin: defauts.tauxMin ?? 0,
                               profession: defauts.profession ?? "", urgentesOnly: defauts.urgentesOnly ?? false,
                               typeContrat: defauts.typeContrat ?? .tous, horaire: defauts.horaire ?? .tous,
                               etablissementId: etablissementId)
    }

    /// Filtres passés au port, dérivés à chaque lecture.
    public var missionFilters: MissionFilters {
        MissionFilters(ville: ville, rayonKm: rayonKm, tauxMin: tauxMin, profession: profession, urgentesOnly: urgentesOnly,
                       typeContrat: typeContrat, horaire: horaire, etablissementId: etablissementId)
    }

    /// « Réinitialiser » du web : profession du profil, rayon du profil (`|| 50`), **taux à 0**
    /// (`setTauxMin(0)`, le taux minimum du profil n'est pas rétabli), contrat et horaires « Tous »,
    /// urgentes désactivées, ville vide. Le filtre établissement (lien) est conservé.
    public func reinitialises(profile: SoignantProfile) -> ExplorerFiltres {
        var remis = ExplorerFiltres.initiaux(profile: profile, etablissementId: etablissementId)
        remis.tauxMin = 0
        return remis
    }

    // MARK: Chips rapides

    /// Chip 1-tap au-dessus de la liste : urgentes, ou une valeur d'horaire.
    public struct ChipRapide: Equatable, Sendable, Identifiable {
        public enum Cible: Equatable, Sendable {
            case urgentes
            case horaire(MissionFilters.Horaire)
        }

        public var cible: Cible
        public var titre: String
        public var identifiant: String

        public var id: String { identifiant }

        /// Horaire porté par la chip, `nil` pour « Urgentes ».
        public var horaire: MissionFilters.Horaire? {
            if case let .horaire(horaire) = cible { return horaire }
            return nil
        }
    }

    /// Chips du web, dans l'ordre et avec leurs libellés (emoji compris, lus sans emoji par VoiceOver).
    public static let chipsRapides: [ChipRapide] = [
        ChipRapide(cible: .urgentes, titre: "🔥 Urgentes", identifiant: "chip-urgentes"),
        ChipRapide(cible: .horaire(.weekend), titre: "📅 Week-end", identifiant: "chip-weekend"),
        ChipRapide(cible: .horaire(.nuit), titre: "🌙 Nuit", identifiant: "chip-nuit"),
        ChipRapide(cible: .horaire(.jour), titre: "☀️ Jour", identifiant: "chip-jour"),
    ]

    public func basculantUrgentes() -> ExplorerFiltres {
        var copie = self
        copie.urgentesOnly.toggle()
        return copie
    }

    /// `setHoraire(h => h === X ? 'TOUS' : X)` : une seule dimension d'horaire à la fois.
    public func basculantHoraire(_ valeur: MissionFilters.Horaire) -> ExplorerFiltres {
        var copie = self
        copie.horaire = horaire == valeur ? .tous : valeur
        return copie
    }

    public func basculer(_ chip: ChipRapide) -> ExplorerFiltres {
        switch chip.cible {
        case .urgentes: return basculantUrgentes()
        case let .horaire(valeur): return basculantHoraire(valeur)
        }
    }

    public func estActif(_ chip: ChipRapide) -> Bool {
        switch chip.cible {
        case .urgentes: return urgentesOnly
        case let .horaire(valeur): return horaire == valeur
        }
    }

    // MARK: Badge du bouton filtres

    /// Critères actifs hors chips rapides et hors rayon : profession, ville, taux, contrat.
    public var nombreFiltresActifs: Int {
        [!profession.isEmpty,
         !ville.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
         tauxMin > 0,
         typeContrat != .tous].filter { $0 }.count
    }

    public static func libelleFiltresActifs(_ nombre: Int) -> String {
        switch nombre {
        case 0: return "Aucun filtre actif"
        case 1: return "1 filtre actif"
        default: return "\(nombre) filtres actifs"
        }
    }

    // MARK: État vide

    /// Action secondaire de l'état vide : effacer d'abord les chips (cause la plus probable),
    /// sinon élargir le rayon tant qu'il est sous 100 km.
    public enum ActionEtatVide: Equatable, Sendable {
        case effacerFiltresRapides, elargirRayon

        public var titre: String {
            switch self {
            case .effacerFiltresRapides: return "Effacer les filtres rapides"
            case .elargirRayon: return "Élargir le rayon (+20 km)"
            }
        }
    }

    public var actionEtatVide: ActionEtatVide? {
        if urgentesOnly || horaire != .tous { return .effacerFiltresRapides }
        if rayonKm < Self.rayonMaximumKm { return .elargirRayon }
        return nil
    }

    public func effacantFiltresRapides() -> ExplorerFiltres {
        var copie = self
        copie.urgentesOnly = false
        copie.horaire = .tous
        return copie
    }

    public func elargissantRayon() -> ExplorerFiltres {
        var copie = self
        copie.rayonKm = min(Self.rayonMaximumKm, rayonKm + Self.elargissementRayonKm)
        return copie
    }

    public func appliquant(_ action: ActionEtatVide) -> ExplorerFiltres {
        switch action {
        case .effacerFiltresRapides: return effacantFiltresRapides()
        case .elargirRayon: return elargissantRayon()
        }
    }

    // MARK: Libellés et saisies

    /// `Rayon : {rayonKm} km`, valeur rendue comme `String(number)` en JavaScript.
    public static func libelleRayon(_ rayonKm: Double) -> String {
        "Rayon : \(MissionPresentation.nombreJavaScript(rayonKm)) km"
    }

    /// Le rayon ne s'applique que si la position du soignant est connue (sinon toutes les
    /// distances sont inconnues et restent affichées) : le web ne l'annonce qu'à cette condition.
    public static func rayonApplicable(profile: SoignantProfile) -> Bool {
        profile.adresseLat != nil && profile.adresseLng != nil
    }

    /// Compteur de la liste (`missions-count`) : « 1 mission », « 30 missions ».
    public static func libelleCompteur(_ nombre: Int) -> String {
        "\(nombre) mission\(nombre > 1 ? "s" : "")"
    }

    /// `Number(e.target.value) || 0` : vide, illisible ou non fini → 0. Écarts assumés : la
    /// virgule décimale du clavier français est acceptée, et un taux négatif (inerte côté web,
    /// `tauxMin > 0`) est ramené à 0.
    public static func taux(depuisSaisie saisie: String) -> Double {
        let texte = saisie.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let valeur = Double(texte), valeur.isFinite, valeur > 0 else { return 0 }
        return valeur
    }

    /// `value={tauxMin || ''}` : un taux nul s'affiche comme un champ vide.
    public static func saisie(depuisTaux taux: Double) -> String {
        taux > 0 ? MissionPresentation.nombreJavaScript(taux) : ""
    }

    // MARK: Options des sélecteurs

    public struct Option<Valeur: Equatable & Sendable>: Equatable, Sendable {
        public var valeur: Valeur
        public var titre: String
    }

    /// Sélecteur « Type de contrat » du web, même ordre.
    public static let optionsContrat: [Option<MissionFilters.TypeContrat>] = [
        Option(valeur: .tous, titre: "Tous"), Option(valeur: .cdd, titre: "CDD"), Option(valeur: .liberal, titre: "Libéral"),
    ]

    /// Sélecteur « Horaires » du web, même ordre.
    public static let optionsHoraire: [Option<MissionFilters.Horaire>] = [
        Option(valeur: .tous, titre: "Tous"), Option(valeur: .jour, titre: "Jour"),
        Option(valeur: .nuit, titre: "Nuit"), Option(valeur: .weekend, titre: "Week-end"),
    ]

    /// Sélecteur « Profession » : la valeur vide (profession du profil, équivalences comprises)
    /// puis `PROFESSIONS` du web (`MissionPresentation.professions`).
    public static func optionsProfession(profile: SoignantProfile) -> [Option<String>] {
        [Option(valeur: "", titre: "Ma profession : \(MissionPresentation.professionLabel(profile.profession))")]
            + MissionPresentation.professions.map { Option(valeur: $0.valeur, titre: $0.label) }
    }
}
