import Foundation

/// Fiches `missions` et créneaux PREVISIONNEL relus pour les missions du tableau de bord (web :
/// `chargerCreneauxMissionsPagines` + `missions.select('id, nb_creneaux')`, l.147-166). `nil`
/// côté appelant = lecture en échec : tout le planning est « à confirmer ».
public struct LectureMissionsAccueil: Equatable, Sendable {
    public var records: [MissionRecord]
    public var creneaux: [MissionSlot]

    public init(records: [MissionRecord], creneaux: [MissionSlot]) {
        self.records = records; self.creneaux = creneaux
    }
}

/// Assemblage de l'instantané Accueil, partagé par les mondes démo et Supabase : une seule
/// implémentation des règles de `DashboardSoignant.tsx` (cohorte de test, planning vérifié, nom
/// d'établissement, propositions encore valides, gains relus). Aucune règle juridique, aucun
/// montant recalculé.
public enum AccueilAssemblage {
    public static let contratMessage = "Cette version de l'application n'est plus compatible avec le service. Mettez-la à jour."
    /// Fenêtre de réponse d'une proposition (`CarteProposition.tsx` `EXPIRATION_MINUTES`, filtre
    /// serveur `cree_le >= now() - interval '2 hours'`).
    public static let expirationPropositionMinutes = 120
    public static let etablissementParDefaut = "Établissement"

    /// Lignes affichées : missions de test Playwright masquées aux comptes ordinaires
    /// (`filtrerMissionsPlaywright`, comme le web sur `mes_missions` et `missions_ouvertes`).
    static func visibles(_ lignes: [DashboardMissionLigne], email: String?) -> [DashboardMissionLigne] {
        guard !MissionBusiness.estComptePlaywright(email: email) else { return lignes }
        return lignes.filter { !MissionBusiness.estMissionPlaywright(intitule: $0.intitule) }
    }

    /// Missions dont la fiche et les créneaux doivent être relus : prochaines, pour vous, puis
    /// missions proposées, sans doublon, dans l'ordre du tableau de bord.
    public static func identifiantsMissions(_ corps: DashboardCorps, email: String?) -> [String] {
        let ids = visibles(corps.mesMissions, email: email).map(\.id)
            + visibles(corps.missionsOuvertes, email: email).map(\.id)
            + corps.propositions.map(\.missionId)
        return dedoublonner(ids)
    }

    /// Établissements à demander à `fn_etablissements_safe` (seule source du nom, §2.6).
    public static func identifiantsEtablissements(_ corps: DashboardCorps) -> [String] {
        dedoublonner((corps.mesMissions + corps.missionsOuvertes + corps.propositions.map(\.mission)).compactMap(\.etablissementId))
    }

    /// Instantané de l'écran. Lève sur `{error}` (« Non authentifié » → session expirée, sinon
    /// message serveur verbatim) ; les lectures complémentaires en échec dégradent l'affichage
    /// sans erreur : `lecture == nil` → planning « à confirmer », `gains == nil` → carte masquée,
    /// établissement absent → `etab_nom` puis « Établissement ».
    ///
    /// Écart assumé avec le web (consigné dans `PARITE_SOIGNANT.md` et `CONTRATS_RPC_SOIGNANT.md`) :
    /// une fiche absente de la lecture (RLS, mission retirée) ne rend « à confirmer » que **sa**
    /// mission, alors que le web met tout le planning « à confirmer » dès que `metas.length !==
    /// missionIds.length` (`DashboardSoignant.tsx` l.160-162). Chaque autre mission reste vérifiée
    /// par son propre `nb_creneaux` et par le pager (compte exact) : aucun planning n'est présenté
    /// comme exact sans vérification.
    public static func snapshot(corps: DashboardCorps, context: MissionReadContext, maintenant: Date,
                                lecture: LectureMissionsAccueil?, etablissements: [String: EtablissementSummary],
                                gains: [MissionGainLigne]?) throws -> DashboardSnapshot {
        if let erreur = corps.erreur {
            if estNonAuthentifie(erreur) { throw JoleneError(.unauthorized, SessionController.sessionExpiredMessage) }
            throw JoleneError(.unknown, erreur)
        }
        var records: [String: MissionRecord] = [:]
        var creneaux: [String: [MissionSlot]] = [:]
        for record in lecture?.records ?? [] where records[record.id] == nil { records[record.id] = record }
        for creneau in lecture?.creneaux ?? [] {
            guard let missionId = creneau.missionId else { continue }
            creneaux[missionId, default: []].append(creneau)
        }

        func mission(_ ligne: DashboardMissionLigne) -> AccueilMission {
            let etablissement = ligne.etablissementId.flatMap { etablissements[$0] }
            let slots = (creneaux[ligne.id] ?? []).sorted { ($0.debut, $0.id ?? "") < ($1.debut, $1.id ?? "") }
            let record = lecture == nil ? nil : records[ligne.id]
            return AccueilMission(
                ligne: ligne,
                etablissementNom: nom(etablissement: etablissement, repli: ligne.etabNom),
                etablissementVille: etablissement?.adresseVille,
                planning: planning(record: record, creneaux: slots, maintenant: maintenant),
                mission: record.map { MissionBusiness.enrich(record: $0, context: context, etablissement: etablissement, slots: slots) })
        }

        let propositions: [AccueilProposition] = corps.propositions.compactMap { proposition in
            guard let creeLe = PlanningHorlogeParis.instant(proposition.creeLe),
                  proposition.mission.debutLe != nil, proposition.mission.finLe != nil else { return nil }
            let expireLe = creeLe.addingTimeInterval(TimeInterval(expirationPropositionMinutes * 60))
            guard expireLe > maintenant else { return nil }
            let detail = mission(proposition.mission)
            return AccueilProposition(proposition: proposition, etablissementNom: detail.etablissementNom,
                                      expireLe: expireLe, mission: detail.mission)
        }

        return DashboardSnapshot(
            notifsNonLues: max(0, corps.notifsNonLues),
            missionsOublieesCount: max(0, corps.missionsOublieesCount),
            profil: corps.profil,
            prochaines: visibles(corps.mesMissions, email: context.email).map(mission),
            pourToi: visibles(corps.missionsOuvertes, email: context.email).map(mission),
            propositions: propositions,
            gains: gains.map(GainsDuMois.agreger),
            gainsMoisNbMissions: corps.gainsMoisNbMissions,
            heuresSemaine: corps.heuresSemaine,
            documents: corps.documents,
            planningIndisponible: lecture == nil)
    }

    /// Port de `enrichirPlanning` : fiche absente ou planning incomplet → indisponible ; sinon
    /// prochain créneau non terminé et son rang parmi les créneaux planifiés.
    static func planning(record: MissionRecord?, creneaux: [MissionSlot], maintenant: Date) -> PlanningAccueil {
        guard let record else { return .indisponible }
        let analyse = CompletudePlanning.analyser(MissionAvecPlanningAttendu(record: record), creneaux: creneaux)
        guard analyse.complet else { return .indisponible }
        let prochain = DisponibilitePointage.prochainCreneauPointage(analyse.creneauxPlanifies, maintenant: maintenant)
        let rang = prochain.flatMap { analyse.creneauxPlanifies.firstIndex(of: $0) }.map { $0 + 1 }
        return .planifie(prochain: prochain, rang: rang, nombre: analyse.nombrePlanifie)
    }

    static func nom(etablissement: EtablissementSummary?, repli: String?) -> String {
        for candidat in [etablissement?.nom, repli] {
            if let candidat, !candidat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return candidat }
        }
        return etablissementParDefaut
    }

    /// « Non authentifié » (casse, accents, espaces et point final ignorés), comme `RPCResponse`.
    static func estNonAuthentifie(_ message: String) -> Bool {
        var texte = message.trimmingCharacters(in: .whitespacesAndNewlines)
        while texte.hasSuffix(".") { texte.removeLast() }
        return texte.compare("Non authentifié", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static func dedoublonner(_ valeurs: [String]) -> [String] {
        var vus = Set<String>()
        return valeurs.filter { !$0.isEmpty && vus.insert($0).inserted }
    }
}
