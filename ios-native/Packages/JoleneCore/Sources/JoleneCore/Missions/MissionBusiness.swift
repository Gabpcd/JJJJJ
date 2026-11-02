import Foundation

/// Port de `mobile-native/src/data/business.ts` : enrichissement et filtres de
/// présentation des missions. Ces filtres ne remplacent jamais la RLS ; les
/// montants restent des valeurs serveur.
public enum MissionBusiness {
    public static let messageContexteInvalide = "Le profil soignant ne correspond pas à la session. Reconnectez-vous."
    static let prefixesMissionTest = ["[playwright-test]", "[pw-test:"]

    /// Port de `validateContext` : le profil doit porter l'identité de la session.
    public static func validateContext(_ context: MissionReadContext) throws {
        if context.userId.isEmpty || context.profile.id != context.userId || context.profile.profession.isEmpty {
            throw JoleneError(.contract, messageContexteInvalide)
        }
    }

    /// Port de `defaultFilters` : rayon 50 km et taux minimum 0 quand le profil n'en fixe pas
    /// (`||` JavaScript : 0 ou absent → défaut).
    public static func defaultFilters(profile: SoignantProfile) -> MissionFilters {
        let rayon = profile.rayonDeplacementKm ?? 0
        let taux = profile.tauxHoraireMinimum ?? 0
        return MissionFilters(ville: "", rayonKm: rayon == 0 ? 50 : rayon, tauxMin: taux, profession: "",
                              urgentesOnly: false, typeContrat: .tous, horaire: .tous, etablissementId: nil)
    }

    /// Port de `estComptePlaywright` (donnees-test.ts).
    public static func estComptePlaywright(email: String?) -> Bool {
        email?.hasPrefix("playwright-") ?? false
    }

    /// Port de `estMissionPlaywright`.
    public static func estMissionPlaywright(intitule: String?) -> Bool {
        let intitule = intitule ?? ""
        return prefixesMissionTest.contains { intitule.hasPrefix($0) }
    }

    /// Port de `filtrerMissionsPlaywright` : les fixtures de test restent visibles des seuls comptes Playwright.
    public static func filtrerMissionsPlaywright(_ missions: [Mission], email: String?) -> [Mission] {
        estComptePlaywright(email: email) ? missions : missions.filter { !estMissionPlaywright(intitule: $0.record.intitule) }
    }

    /// Port de `enrichMission` : établissement, distance Haversine et planning dérivé.
    /// Les créneaux chargés sont conservés tels quels ; sans créneau, le repli ponctuel
    /// calculé devient le planning affichable.
    public static func enrich(record: MissionRecord, context: MissionReadContext,
                              etablissement: EtablissementSummary?, slots: [MissionSlot]) -> Mission {
        let planning = PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(record: record, creneaux: slots))
        let distance = Geo.distanceKm(lat1: context.profile.adresseLat, lng1: context.profile.adresseLng,
                                      lat2: etablissement?.adresseLat, lng2: etablissement?.adresseLng)
        return Mission(record: record, etablissement: etablissement, distanceKm: distance,
                       creneauxPlanifies: slots.isEmpty ? planning.creneaux : slots,
                       planningExact: planning.exact, erreurPlanning: false)
    }

    /// Port de `filterMissions` : mêmes règles, même ordre, tri par distance croissante
    /// (distance inconnue = 999). La stabilité du tri est contractuelle (départage par
    /// position d'origine), comme le tri stable de V8 sur lequel s'appuie le pilote ;
    /// `Array.sorted` de Swift ne la garantit pas par contrat.
    public static func filter(_ missions: [Mission], context: MissionReadContext, filters input: MissionFilters = MissionFilters()) -> [Mission] {
        let defaults = defaultFilters(profile: context.profile)
        let ville = (input.ville ?? defaults.ville ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rayonKm = input.rayonKm ?? defaults.rayonKm ?? 50
        let tauxMin = input.tauxMin ?? defaults.tauxMin ?? 0
        let urgentesOnly = input.urgentesOnly ?? defaults.urgentesOnly ?? false
        let typeContrat = input.typeContrat ?? defaults.typeContrat ?? .tous
        let horaire = input.horaire ?? defaults.horaire ?? .tous
        let etablissementId = (input.etablissementId ?? "").isEmpty ? nil : input.etablissementId
        let professionExplicite = (input.profession ?? "").isEmpty ? nil : input.profession
        let profession = professionExplicite ?? context.profile.profession
        let compatibles = professionExplicite == nil
            ? ProfessionHierarchy.professionsCompatibles(soignant: profession) : [profession]
        let typesContrat = ContratCompatibilite.typesContratSoignant(context.profile)

        return filtrerMissionsPlaywright(missions, email: context.email).filter { mission in
            let record = mission.record
            if !compatibles.contains(record.professionRequise) { return false }
            if let etablissementId, record.etablissementId != etablissementId { return false }
            if urgentesOnly && !record.estUrgente { return false }
            if tauxMin > 0 && (record.tauxHoraireBase ?? 0) < tauxMin { return false }
            if !ville.isEmpty
                && !(mission.etablissement?.adresseVille ?? "").lowercased().contains(ville)
                && !(mission.etablissement?.adresseCodePostal ?? "").lowercased().hasPrefix(ville) { return false }
            if let distance = mission.distanceKm, distance > rayonKm { return false }
            let contrat = ContratCompatibilite.contratEffectif(record)
            if !ContratCompatibilite.missionCompatible(preference: contrat, typesContratSoignant: typesContrat) { return false }
            if typeContrat == .cdd && contrat == "LIBERAL" { return false }
            if typeContrat == .liberal && contrat == "SALARIE" { return false }
            return PlanningCandidatRules.planningCorrespondAuFiltre(PlanningCandidatInput(mission: mission), filtre: horaire)
        }.enumerated().sorted { a, b in
            let distanceA = a.element.distanceKm ?? 999
            let distanceB = b.element.distanceKm ?? 999
            if distanceA != distanceB { return distanceA < distanceB }
            return a.offset < b.offset
        }.map(\.element)
    }
}
