import Foundation

// Dérivations d'affichage de la page Présences (blueprint `docs/mobile-swift/LOT2_PLAN.md` §3 T4a), sans texte : les
// écrans associent chaque cas à son libellé web (`LibellesWeb`, `LibellesPresences`). État dérivé : recalculé à chaque
// lecture depuis l'instantané (`InstantanePresences`) et l'horloge, jamais stocké.

/// État du bloc de pointage d'une mission (`BlocPointageMission.tsx` l.38-127), évalué sur l'horloge de l'appareil
/// toutes les 30 s (l.38-42, décision 25). `pointable` : la zone de pointage (T4b) remplace les motifs.
public enum BlocPointageAffichage: Equatable, Sendable {
    /// Fenêtre ouverte (15 min avant un créneau prévu) ou segment ouvert : arrivée ou départ possibles.
    case pointable(EtatDisponibilitePointage.Action?)
    /// Motif CONTRAT : contrat absent ou pas encore signé par les deux parties. `contratId` : contrat retenu pour le
    /// pointage, s'il existe (« Voir le contrat », l.90) ; `prochainAutreJour` : début du prochain créneau quand il
    /// n'est pas le jour même à Paris (l.84).
    case contratNonSigne(contratId: String?, prochainAutreJour: Date?)
    /// Motif AUCUN_CRENEAU : aucun créneau prévu, ni repli ponctuel.
    case aucunCreneau
    /// Motif HORS_CRENEAU, prochain créneau le jour même (Paris) : le pointage ouvrira 15 min avant `debut`.
    case pasEncoreOuvert(debut: Date)
    /// Motif HORS_CRENEAU, rien à pointer aujourd'hui : `prochain` créneau, ou nil quand tous sont terminés.
    case aucunAujourdhui(prochain: Date?)

    /// Bloc d'une mission des listes (`ListesPresences` : créneaux déjà complétés du repli ponctuel).
    public static func evaluer<Mission: MissionPresenceRepresentable, Etablissement>(
        _ mission: MissionPresenceEnrichie<Mission, Etablissement>, contrat: ContratPointage?, maintenant: Date
    ) -> BlocPointageAffichage {
        evaluer(creneaux: mission.creneaux,
                mission: PeriodeMissionPointage(id: mission.mission.id, debutLe: mission.mission.debutLe, finLe: mission.mission.finLe),
                contrat: contrat, maintenant: maintenant)
    }

    /// Port des conditions de `BlocPointageMission` (l.43-50, l.69-123). Le repli ponctuel est réappliqué comme le web
    /// (l.43) : sans effet quand des créneaux prévus existent. Une date de créneau illisible vaut « aucune ».
    public static func evaluer(creneaux: [MissionSlot], mission: PeriodeMissionPointage, contrat: ContratPointage?,
                               maintenant: Date) -> BlocPointageAffichage {
        let disponibilite = DisponibilitePointage.evaluerDisponibilitePointage(
            creneaux: DisponibilitePointage.ajouterRepliMissionPonctuelle(creneaux, mission: mission),
            contratStatut: contrat?.statut, maintenant: maintenant)
        if disponibilite.peutPointer { return .pointable(disponibilite.action) }
        let prochain = disponibilite.prochainCreneau.flatMap { try? DateHeureParis.instantJolene($0.debut) }
        let memeJour = prochain.map { DateHeureParis.memeJour($0, maintenant) } ?? false
        switch disponibilite.motif {
        case .contrat:
            return .contratNonSigne(contratId: contrat?.id, prochainAutreJour: memeJour ? nil : prochain)
        case .aucunCreneau:
            return .aucunCreneau
        case .horsCreneau, .none:
            if let prochain, memeJour { return .pasEncoreOuvert(debut: prochain) }
            return .aucunAujourdhui(prochain: prochain)
        }
    }
}

/// Arrivée, départ et heures travaillées d'une ligne d'historique (`PresencesSoignant.tsx` l.664-682) : les segments
/// EFFECTIF fermés hors pause font foi (triés par début, état dérivé), les pointages de la présence legacy ne servent
/// qu'à défaut. `heures` : somme des segments, sinon départ − arrivée ; nil quand rien ne permet de la calculer (le web
/// affiche « — »). Une date illisible n'est jamais affichée.
public struct ResumeLignePresence: Equatable, Sendable {
    public var arrivee: Date?
    public var depart: Date?
    public var heures: Double?

    public init(arrivee: Date?, depart: Date?, heures: Double?) {
        self.arrivee = arrivee; self.depart = depart; self.heures = heures
    }

    public static func construire(creneaux: [MissionSlot], pointageArriveeLe: String?, pointageDepartLe: String?) -> ResumeLignePresence {
        let segments = triStableCroissant(creneaux.filter {
            $0.typeCreneau == "EFFECTIF" && !$0.estPause && !($0.fin ?? "").isEmpty
        }) { DisponibilitePointage.temps($0.debut) }
        let arrivee = lire(segments.first?.debut) ?? lire(pointageArriveeLe)
        let depart = lire(segments.last?.fin) ?? lire(pointageDepartLe)
        let heures: Double?
        if !segments.isEmpty {
            heures = segments.reduce(0) { $0 + (DisponibilitePointage.temps($1.fin) - DisponibilitePointage.temps($1.debut)) / 3_600_000 }
        } else if let arrivee, let depart {
            heures = depart.timeIntervalSince(arrivee) / 3600
        } else {
            heures = nil
        }
        return ResumeLignePresence(arrivee: arrivee, depart: depart, heures: heures.flatMap { $0.isFinite ? $0 : nil })
    }

    private static func lire(_ valeur: String?) -> Date? {
        guard let valeur, !valeur.isEmpty else { return nil }
        return try? DateHeureParis.instantJolene(valeur)
    }
}

/// Mission d'une ligne d'historique telle que la ligne l'affiche (`m?.intitule`, `m?.debut_le`, l.689-693).
public struct MissionDeLigne: Equatable, Sendable {
    public var intitule: String?
    public var debutLe: String?

    public init(intitule: String?, debutLe: String?) {
        self.intitule = intitule; self.debutLe = debutLe
    }
}

public extension LigneHistoriquePresence {
    /// Créneaux de la mission (tous types) : source du résumé.
    var creneaux: [MissionSlot] {
        switch self {
        case let .presence(_, creneaux, _): return creneaux
        case let .effectifs(ligne): return ligne.creneaux
        }
    }

    var pointageArriveeLe: String? {
        switch self {
        case let .presence(presence, _, _): return presence.pointageArriveeLe
        case let .effectifs(ligne): return ligne.pointageArriveeLe
        }
    }

    /// Établissement résolu par `fn_etablissements_safe`.
    var etablissement: EtablissementSummary? {
        switch self {
        case let .presence(_, _, etablissement): return etablissement
        case let .effectifs(ligne): return ligne.etablissement
        }
    }

    /// Ligne reconstruite depuis les segments EFFECTIF (`origine_effectifs_sans_presence`, l.741) : jamais validable.
    var origineEffectifsSansPresence: Bool {
        if case .effectifs = self { return true }
        return false
    }

    var methodeArrivee: String? {
        switch self {
        case let .presence(presence, _, _): return presence.methodePointageArrivee
        case let .effectifs(ligne): return ligne.methodePointageArrivee
        }
    }

    var methodeDepart: String? {
        switch self {
        case let .presence(presence, _, _): return presence.methodePointageDepart
        case let .effectifs(ligne): return ligne.methodePointageDepart
        }
    }

    var resume: ResumeLignePresence {
        ResumeLignePresence.construire(creneaux: creneaux, pointageArriveeLe: pointageArriveeLe, pointageDepartLe: pointageDepartLe)
    }
}

public extension InstantanePresences {
    /// Mission d'une ligne : l'embed `missions` d'une présence, ou la mission terminée d'une ligne reconstruite
    /// (le web y étale la mission entière, `presencesSoignantUi.ts`).
    func mission(de ligne: LigneHistoriquePresence) -> MissionDeLigne {
        switch ligne {
        case let .presence(presence, _, _):
            return MissionDeLigne(intitule: presence.mission?.intitule, debutLe: presence.mission?.debutLe)
        case let .effectifs(effectifs):
            let mission = missionsHistorique.first { $0.id == effectifs.missionId }
            return MissionDeLigne(intitule: mission?.intitule, debutLe: mission?.debutLe)
        }
    }

    /// Établissement d'une présence validée récemment (l.629 : `m?.etablissements?.nom`).
    func etablissement(de presence: PresenceLue) -> EtablissementSummary? {
        presence.mission?.etablissementId.flatMap { etablissements[$0] }
    }
}

/// Renvois web de la page Présences tant que leurs écrans natifs ne sont pas livrés : contrat (T9a), litiges (lot 4).
/// Routes résolues par `LinkRouter` (`AccueilPresentation.renvoiWeb`, nil dès que la route devient native), jamais une
/// URL écrite en dur ; présentées seulement par le présentateur `.safari` injecté par T10.
///
/// Exception documentée : le récapitulatif financier du détail des présences (`recapitulatifFinancier`) est une route
/// FORCÉE web, indépendante du routage natif (même motif que `ContratPresentation.renvoiSignature`).
public enum PresencesRenvois {
    /// `navigate(`/contrat/${contrat.id}`)` (`BlocPointageMission.tsx` l.95).
    public static func contrat(id: String) -> JoleneRoute? {
        AccueilPresentation.renvoiWeb("/contrat/" + id)
    }

    /// `navigate('/soignant/litiges')` (`PresencesSoignant.tsx` l.752).
    public static var litiges: JoleneRoute? {
        AccueilPresentation.renvoiWeb("/soignant/litiges")
    }

    /// Récapitulatif financier d'une mission (`DetailPresencesMission.tsx` l.705-800 : taux, bruts, IFM/ICP calculés
    /// côté client, non portés : décision 11 de `DECISIONS_LOT2.md`, LOT2_PLAN §1.2) : page web de la mission,
    /// `https://jolene.app/soignant/presences/mission/<id>`. Route FORCÉE web : construite par
    /// `JoleneLink.canonicalURL`, jamais par `LinkRouter`, pour survivre au routage natif de
    /// `/soignant/presences/mission/:id` vers `DetailPresencesScreen` (T10) — `AccueilPresentation.renvoiWeb` rendrait
    /// alors nil et le renvoi disparaîtrait sans bruit (revue fraîche de T5a, M3). Ouverte par le présentateur `.safari`
    /// (SFSafariViewController), jamais par `openURL` : la page web s'affiche dans l'app sans retour par lien universel.
    /// Lot 3 : remplacée par le lien Revenus natif (décision 11). nil si l'identifiant n'est pas un segment sûr.
    public static func recapitulatifFinancier(missionId: String) -> JoleneRoute? {
        renvoiWebForce("/soignant/presences/mission/", identifiant: missionId)
    }

    /// `.safari` sur `préfixe + identifiant`, sans passer par `LinkRouter`. L'identifiant est un segment sûr
    /// (`[A-Za-z0-9-]`, comme `ContratPresentation.renvoi`) : aucun séparateur, requête, fragment, encodage ni
    /// traversée ne peut détourner le chemin.
    static func renvoiWebForce(_ prefixe: String, identifiant: String) -> JoleneRoute? {
        guard !identifiant.isEmpty, identifiant.unicodeScalars.allSatisfy({
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "-"
        }), let url = JoleneLink.canonicalURL(link: prefixe + identifiant) else { return nil }
        return .safari(url)
    }
}
