import Foundation

/// Colonnes financières d'une mission lues par l'écran Revenus (`MissionFinanceAffichee` du web,
/// `src/lib/missionFinanceDisplay.ts` l.1-12), clés PostgREST. Domaine : nombre JSON ou null,
/// booléen ou null, texte ou null ; une valeur d'un autre type est refusée au décodage.
/// Décision 5 du lot 3 : l'écran lit exactement les colonnes de `MesGains.tsx` l.95, sans les
/// colonnes Rist, de sorte que la correction ci-dessous reste inactive comme sur le web.
public struct MissionFinanceAffichee: Equatable, Sendable, Decodable {
    public var professionRequise: String?
    public var typeContratRecherche: String?
    public var typeContratApplique: String?
    public var soignantAssigneId: String?
    public var tauxHoraireBase: Double?
    public var tauxRistPlafonne: Double?
    public var ristPlafondApplique: Bool?
    public var netEstime: Double?
    public var netAPayer: Double?
    public var totalBrut: Double?

    public init(professionRequise: String? = nil, typeContratRecherche: String? = nil, typeContratApplique: String? = nil,
                soignantAssigneId: String? = nil, tauxHoraireBase: Double? = nil, tauxRistPlafonne: Double? = nil,
                ristPlafondApplique: Bool? = nil, netEstime: Double? = nil, netAPayer: Double? = nil, totalBrut: Double? = nil) {
        self.professionRequise = professionRequise; self.typeContratRecherche = typeContratRecherche
        self.typeContratApplique = typeContratApplique; self.soignantAssigneId = soignantAssigneId
        self.tauxHoraireBase = tauxHoraireBase; self.tauxRistPlafonne = tauxRistPlafonne
        self.ristPlafondApplique = ristPlafondApplique; self.netEstime = netEstime
        self.netAPayer = netAPayer; self.totalBrut = totalBrut
    }

    enum CodingKeys: String, CodingKey {
        case professionRequise = "profession_requise"
        case typeContratRecherche = "type_contrat_recherche"
        case typeContratApplique = "type_contrat_applique"
        case soignantAssigneId = "soignant_assigne_id"
        case tauxHoraireBase = "taux_horaire_base"
        case tauxRistPlafonne = "taux_rist_plafonne"
        case ristPlafondApplique = "rist_plafond_applique"
        case netEstime = "net_estime"
        case netAPayer = "net_a_payer"
        case totalBrut = "total_brut"
    }
}

/// Nature du montant affiché (`NatureMontantMissionAffiche`).
public enum NatureMontantMission: String, CaseIterable, Sendable {
    case honorairesLiberaux = "HONORAIRES_LIBERAUX"
    case netSalarieEstime = "NET_SALARIE_ESTIME"
    case brutIndicatif = "BRUT_INDICATIF"
}

/// Montant d'une mission et ses libellés verbatim (`MontantMissionAffiche`).
public struct MontantMissionAffiche: Equatable, Sendable {
    public var montant: Double
    public var nature: NatureMontantMission
    public var libelle: String
    public var libelleCourt: String
    /// Vrai pour un net estimé ou un brut indicatif (astérisque ou mention « indicatif »).
    public var approximatif: Bool

    public init(montant: Double, nature: NatureMontantMission, libelle: String, libelleCourt: String, approximatif: Bool) {
        self.montant = montant; self.nature = nature; self.libelle = libelle
        self.libelleCourt = libelleCourt; self.approximatif = approximatif
    }
}

/// Port de `src/lib/missionFinanceDisplay.ts` : montant cohérent avec le régime de LA mission
/// (`type_contrat_applique`, puis `type_contrat_recherche` ; jamais `soignants.type_exercice`, règle
/// « régime/contrat » de `CLAUDE.md`). Aucun montant n'est calculé hors de la correction historique
/// du plafond Rist, portée à l'identique et consignée comme candidate RPC (décision 5 du lot 3).
public enum MontantMission {
    /// `netEstimeAfficheMission` : `net_estime` seul ; `net_a_payer` n'est jamais un net salarié.
    public static func netEstimeAffiche(_ mission: MissionFinanceAffichee) -> Double? {
        guard let net = nombreFini(mission.netEstime) else { return nil }
        return corrigerAncienPlafondImpossible(mission, montant: net)
    }

    /// `montantFinanceAfficheMission` : honoraires bruts (libéral), net estimé (salarié) ou brut
    /// indicatif (contrat non choisi). Libellés verbatim de `missionFinanceDisplay.ts` l.103-104,
    /// l.115-116, l.126-127.
    public static func montantAffiche(_ mission: MissionFinanceAffichee) -> MontantMissionAffiche? {
        switch contratEffectif(mission) {
        case "LIBERAL"?:
            guard let honoraires = nombreFini(mission.netAPayer) ?? nombreFini(mission.totalBrut) else { return nil }
            return MontantMissionAffiche(montant: corrigerAncienPlafondImpossible(mission, montant: honoraires),
                                         nature: .honorairesLiberaux, libelle: "Honoraires bruts",
                                         libelleCourt: "honoraires", approximatif: false)
        case "SALARIE"?:
            guard let net = netEstimeAffiche(mission) else { return nil }
            return MontantMissionAffiche(montant: net, nature: .netSalarieEstime, libelle: "Net salarié estimé*",
                                         libelleCourt: "net estimé*", approximatif: true)
        default:
            guard let brut = nombreFini(mission.totalBrut) ?? nombreFini(mission.netAPayer) else { return nil }
            return MontantMissionAffiche(montant: corrigerAncienPlafondImpossible(mission, montant: brut),
                                         nature: .brutIndicatif, libelle: "Rémunération brute indicative",
                                         libelleCourt: "brut indicatif", approximatif: true)
        }
    }

    /// `contratEffectif` : seuls `LIBERAL` et `SALARIE` comptent, l'appliqué avant le recherché.
    static func contratEffectif(_ mission: MissionFinanceAffichee) -> String? {
        for contrat in [mission.typeContratApplique, mission.typeContratRecherche] where contrat == "LIBERAL" || contrat == "SALARIE" {
            return contrat
        }
        return nil
    }

    /// `corrigerAncienPlafondImpossible` : l'ancien moteur (supprimé en juillet 2026) a pu plafonner
    /// une mission non assignée ou libérale ; le montant est alors rétabli au prorata du taux publié,
    /// `Math.round(montant × (publié / plafonné) × 100) / 100`, sans toucher à la donnée stockée.
    static func corrigerAncienPlafondImpossible(_ mission: MissionFinanceAffichee, montant: Double) -> Double {
        // `??` JavaScript : seul `null` cède la place, un texte vide reste le contrat lu.
        let contrat = mission.typeContratApplique ?? mission.typeContratRecherche
        let plafondImpossible = contrat == "LIBERAL" || (mission.soignantAssigneId ?? "").isEmpty
        guard mission.ristPlafondApplique == true, plafondImpossible,
              let tauxPublie = nombreFini(mission.tauxHoraireBase),
              let tauxPlafonne = nombreFini(mission.tauxRistPlafonne),
              tauxPlafonne > 0, tauxPublie > tauxPlafonne else { return montant }
        return CalendrierCivil.arrondiJS(montant * (tauxPublie / tauxPlafonne) * 100) / 100
    }

    private static func nombreFini(_ valeur: Double?) -> Double? {
        guard let valeur, valeur.isFinite else { return nil }
        return valeur
    }
}
