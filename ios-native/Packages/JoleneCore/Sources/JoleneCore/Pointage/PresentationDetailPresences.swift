import Foundation

/// Détail des présences d'une mission (lot 2, T5a), port de `src/pages/DetailPresencesMission.tsx` pour le soignant :
/// en-tête (l.293-336), synthèse (l.338-462), créneaux travaillés par jour (l.498-656), contrôles du pointage
/// (l.658-692) et relance (l.247-254, l.694-703). État dérivé, une seule source : les créneaux EFFECTIF fermés font foi
/// pour le temps travaillé (`SynthesePresence`, golden `synthese-presence-mission`) ; `heures_reelles` du serveur n'est
/// jamais lue ; la ligne `presences` ne sert qu'à la validation et aux contrôles. Le récapitulatif financier (l.705-800,
/// montants calculés côté client) n'est pas porté (LOT2_PLAN §1.2, décision 11) : renvoi web.
///
/// Textes : fragments verbatim de `LibellesWeb.DetailPresences`, assemblés comme le rendu React (espaces, ordre).
/// Écart assumé : `planningIndisponible` du web (lecture des créneaux en échec) n'existe pas ici, la lecture des créneaux
/// en échec fait échouer le chargement (« Réessayer »).
public struct PresentationDetailPresences: Equatable, Sendable {
    /// Ton d'une carte ou d'une valeur (couleurs du web : neutre, `success`, `warning`, `destructive`, `primary`).
    public enum Ton: Equatable, Sendable { case neutre, succes, attention, alerte, accent }

    public struct Entete: Equatable, Sendable {
        public var intitule: String?
        public var service: String?
        /// « 📅 … » (l.298-301).
        public var periode: String
        /// « ⏱ … » (l.303-306) ; nil sans créneau planifié ni durée prévue.
        public var heures: String?
        /// Progression, clôture ou planning à confirmer (l.314-329).
        public var progression: String
    }

    public struct Valeur: Equatable, Sendable, Identifiable {
        public var id: String
        public var titre: String
        public var valeur: String
        public var ton: Ton
    }

    public struct Synthese: Equatable, Sendable {
        public var valeurs: [Valeur]
        /// Bilan non définitif (l.437-445).
        public var bilan: String?
        /// Mission clôturée avant la fin du planning (l.447-451).
        public var cloture: String?
        /// « 🚨 Alerte téléportation détectée », « ⚠️ Heures réelles inférieures à 90% du planifié » (l.453-458).
        public var alertes: [String]
    }

    public struct Ecart: Equatable, Sendable {
        public var texte: String
        public var ton: Ton
    }

    public struct Segment: Equatable, Sendable, Identifiable {
        public var id: String
        public var etiquette: String?
        public var interruption: String?
        /// Horaire prévu associé (l.576-589) ; sinon `sansHoraire` (l.590-597).
        public var horairePrevu: String?
        public var ecarts: [Ecart]
        public var sansHoraire: String?
        public var arrivee: String
        public var depart: String
        public var departPointe: Bool
        public var duree: String?
        public var validation: String
        public var tonValidation: Ton
        public var ton: Ton
    }

    public struct Jour: Equatable, Sendable, Identifiable {
        public var id: String
        public var titre: String
        public var segments: [Segment]
    }

    public struct LigneControle: Equatable, Sendable, Identifiable {
        public var id: String
        public var texte: String
        public var ton: Ton
        /// Distance de la première arrivée : `perimetre_gps_valide` (coche, croix), nil sans icône.
        public var perimetre: Bool?
    }

    public struct Controles: Equatable, Sendable {
        public var lignes: [LigneControle]
        public var alerteTeleportation: Bool
    }

    public var entete: Entete
    /// nil : `fn_presences_detail_mission` en refus ou illisible, carte masquée (blueprint §2.4), reste rendu.
    public var synthese: Synthese?
    public var titreSegments: String
    public var jours: [Jour]
    /// nil sans présence (ligne reconstruite depuis les segments).
    public var controles: Controles?
    /// `presenceEnAttente` (l.249-254) : relance proposée.
    public var relanceProposee: Bool

    public static func construire(mission: MissionPresenceLue, creneaux: [MissionSlot], resume: ResumePresencesServeur?,
                                  presence: PresenceControlee?, maintenant: Date) -> PresentationDetailPresences {
        let calcul = Calcul(mission: mission, creneaux: creneaux, presence: presence, maintenant: maintenant)
        return PresentationDetailPresences(entete: calcul.entete(),
                                           synthese: resume.map { calcul.synthese($0) },
                                           titreSegments: calcul.titreSegments(),
                                           jours: calcul.jours(),
                                           controles: presence.map(Calcul.controles),
                                           relanceProposee: calcul.relanceProposee)
    }

    /// `mesureGpsDisponible` (`presencesSoignantUi.ts` l.69-71) : nombre fini, positif ou nul.
    static func mesureDisponible(_ valeur: Double?) -> Double? {
        guard let valeur, valeur.isFinite, valeur >= 0 else { return nil }
        return valeur
    }

    /// `differenceInMinutes(gauche, droite)` de date-fns : minutes entières, tronquées vers zéro.
    static func minutes(_ gauche: Date, _ droite: Date) -> Int {
        let ecart = DateHeureParis.millisecondes(gauche) - DateHeureParis.millisecondes(droite)
        return Int(ecart / 60_000)
    }
}

// MARK: - Calcul (port des dérivations du web, l.193-273)

private struct Calcul {
    typealias Web = LibellesWeb.DetailPresences

    struct Associe { let index: Int; let total: Int; let debut: Date; let fin: Date }

    let mission: MissionPresenceLue
    let presence: PresenceControlee?
    let maintenant: Date
    let base: SynthesePresenceMission
    let planifies: [MissionSlot]
    let missionTerminee: Bool
    let clotureAvantFinPlanning: Bool
    /// EFFECTIF fermés puis ouverts, triés par début, regroupés par jour de Paris (clé `yyyy-MM-dd`, triée).
    let parJour: [(cle: String, segments: [MissionSlot])]

    init(mission: MissionPresenceLue, creneaux: [MissionSlot], presence: PresenceControlee?, maintenant: Date) {
        self.mission = mission
        self.presence = presence
        self.maintenant = maintenant
        // `.eq('est_pause', false)` (l.145) puis le repli des missions ponctuelles (l.165).
        let travail = DisponibilitePointage.ajouterRepliMissionPonctuelle(
            creneaux.filter { !$0.estPause },
            mission: PeriodeMissionPointage(id: mission.id, debutLe: mission.debutLe, finLe: mission.finLe))
        base = SynthesePresence.construire(travail, maintenant: maintenant)
        planifies = base.previsionnels
        missionTerminee = mission.statut == "TERMINEE"
        clotureAvantFinPlanning = missionTerminee && !base.planningTermine && !planifies.isEmpty
        let effectifs = triStableCroissant(base.effectifsFermes + base.effectifsOuverts) { DisponibilitePointage.temps($0.debut) }
        var groupes: [String: [MissionSlot]] = [:]
        for effectif in effectifs {
            groupes[Self.cleJour(effectif.debut), default: []].append(effectif)
        }
        parJour = groupes.keys.sorted().map { (cle: $0, segments: groupes[$0] ?? []) }
    }

    var relanceProposee: Bool {
        guard let presence else { return false }
        return presence.valideParEtablissement != true && base.validationPossible
    }

    // MARK: En-tête

    func entete() -> PresentationDetailPresences.Entete {
        let periode: String
        if let planning = periodePlanning() {
            periode = planning
        } else {
            periode = [Self.date(mission.debutLe), Self.date(mission.finLe)]
                .map { $0.map { DateHeureParis.format($0, "dd/MM/yyyy HH:mm") } ?? "" }
                .joined(separator: " " + Web.flechePeriode + " ")
        }
        let heures: String?
        if !planifies.isEmpty {
            let n = planifies.count
            heures = LibellesDetailPresences.heures(base.minutesPlanifiees / 60) + Web.heuresSur + " " + String(n) + " "
                + Web.creneau + (n > 1 ? Web.creneauPluriel : "")
        } else {
            heures = mission.dureeHeures.map { LibellesPresences.nombreJS($0) + Web.heuresPrevues }
        }
        return PresentationDetailPresences.Entete(intitule: mission.intitule, service: mission.service,
                                                  periode: Web.pictoPeriode + " " + periode,
                                                  heures: heures.map { Web.pictoHeures + " " + $0 },
                                                  progression: progression())
    }

    /// `formatPeriodePlanning` (l.80-90) ; nil sans créneau planifié lisible.
    private func periodePlanning() -> String? {
        guard let premier = planifies.first, let dernier = planifies.last,
              let debut = Self.date(premier.debut), let fin = Self.date(dernier.fin) else { return nil }
        if planifies.count == 1 || DateHeureParis.memeJour(debut, fin) { return Self.plageExacte(debut, fin) }
        return String(planifies.count) + " " + Web.datesPlanifiees + " " + DateHeureParis.format(debut, "d MMM yyyy") + " "
            + Web.flecheDates + " " + DateHeureParis.format(fin, "d MMM yyyy")
    }

    private func progression() -> String {
        guard !planifies.isEmpty else { return Web.planningAConfirmer }
        let n = planifies.count
        let echus = planifies.filter { creneau in Self.date(creneau.fin).map { $0 <= maintenant } ?? false }.count
        if clotureAvantFinPlanning {
            return Web.clotureePrefixe + " " + String(echus) + Web.clotureeBarre + String(n) + " "
                + (n > 1 ? Web.clotureeEchusPluriel : Web.clotureeEchuSingulier)
        }
        var texte = Web.progression + " " + String(echus) + Web.progressionBarre + String(n) + " "
            + (n > 1 ? Web.creneauxEchus : Web.creneauEchu)
        if let prochain = planifies.first(where: { Self.date($0.fin).map { $0 > maintenant } ?? false }),
           let debut = Self.date(prochain.debut), let fin = Self.date(prochain.fin) {
            texte += " " + Web.prochain + " " + Self.plageExacte(debut, fin)
        } else {
            texte += " " + Web.planningTermine
        }
        return texte
    }

    // MARK: Synthèse

    func synthese(_ resume: ResumePresencesServeur) -> PresentationDetailPresences.Synthese {
        let heuresReelles = base.minutesTravaillees / 60
        let heuresPlanifiees = planifies.isEmpty ? (mission.dureeHeures ?? 0) : base.minutesPlanifiees / 60
        var retard = 0, departAnticipe = 0
        for (index, creneau) in planifies.enumerated() {
            guard let debutPrevu = Self.date(creneau.debut), let finPrevue = Self.date(creneau.fin) else { continue }
            let associes = base.effectifsFermes.filter { associe(Self.date($0.debut))?.index == index }
            let tries = triStableCroissant(associes) { DisponibilitePointage.temps($0.debut) }
            guard let arrivee = tries.first.flatMap({ Self.date($0.debut) }), let depart = tries.last.flatMap({ Self.date($0.fin) }) else {
                continue
            }
            retard += max(PresentationDetailPresences.minutes(arrivee, debutPrevu), 0)
            if finPrevue <= maintenant { departAnticipe += max(PresentationDetailPresences.minutes(finPrevue, depart), 0) }
        }
        let interruptions = parJour.reduce(0) { total, jour in
            let fermes = jour.segments.filter { !($0.fin ?? "").isEmpty }
            return total + zip(fermes, fermes.dropFirst()).reduce(0) { sousTotal, paire in
                guard let finPrecedente = Self.date(paire.0.fin), let debut = Self.date(paire.1.debut) else { return sousTotal }
                return sousTotal + max(PresentationDetailPresences.minutes(debut, finPrecedente), 0)
            }
        }
        let pauses: Double? = interruptions > 0 ? Double(interruptions) : resume.dureePauseMin
        let distance = resume.distanceM
        let methode = resume.methodeArrivee ?? resume.methodeDepart
        let bilanFinalisable = (base.planningTermine || missionTerminee) && base.effectifsOuverts.isEmpty
        let deficit = bilanFinalisable && !clotureAvantFinPlanning && heuresReelles < heuresPlanifiees * 0.9
        let alerteTeleportation = resume.alerteTeleportation == true

        typealias Valeur = PresentationDetailPresences.Valeur
        var valeurs = [
            Valeur(id: "planifiees", titre: Web.heuresPlanifiees,
                   valeur: LibellesDetailPresences.heures(heuresPlanifiees) + Web.uniteHeures, ton: .neutre),
            Valeur(id: "reelles", titre: Web.heuresReelles,
                   valeur: LibellesDetailPresences.heures(heuresReelles) + Web.uniteHeures, ton: deficit ? .alerte : .neutre),
        ]
        if let ajustees = presence?.heuresAjusteesLitige {
            valeurs.append(Valeur(id: "retenues", titre: Web.heuresRetenues,
                                  valeur: LibellesDetailPresences.heures(ajustees) + Web.uniteHeures, ton: .accent))
        }
        if retard > 0 {
            valeurs.append(Valeur(id: "retard", titre: Web.retard, valeur: Web.plus + String(retard) + " " + Web.uniteMinutes,
                                  ton: .attention))
        }
        if departAnticipe > 0 {
            valeurs.append(Valeur(id: "depart-anticipe", titre: Web.departAnticipe,
                                  valeur: Web.moins + String(departAnticipe) + " " + Web.uniteMinutes, ton: .attention))
        }
        if let pauses, pauses > 0 {
            valeurs.append(Valeur(id: "pauses", titre: Web.pauses,
                                  valeur: LibellesDetailPresences.arrondi(pauses) + " " + Web.uniteMinutes, ton: .neutre))
        }
        if let distance, distance.isFinite {
            valeurs.append(Valeur(id: "distance", titre: Web.distance,
                                  valeur: LibellesDetailPresences.arrondi(distance) + Web.uniteMetres, ton: distance > 500 ? .alerte : .neutre))
        }
        if let methode, !methode.isEmpty {
            valeurs.append(Valeur(id: "methode", titre: Web.methode, valeur: methode, ton: .neutre))
        }

        var bilan: String?
        if !bilanFinalisable {
            if !base.effectifsOuverts.isEmpty {
                bilan = Web.bilanPointageEnCours
            } else if let fin = base.dernierPrevisionnelFin {
                bilan = Web.bilanApresDernierCreneau + " " + DateHeureParis.format(fin, "dd/MM/yyyy à HH:mm") + Web.bilanAucunDeficit
            } else {
                bilan = Web.bilanIndisponible
            }
        }
        var alertes: [String] = []
        if alerteTeleportation { alertes.append(Web.alerteTeleportation) }
        if deficit { alertes.append(Web.alerteDeficit) }
        return PresentationDetailPresences.Synthese(
            valeurs: valeurs, bilan: bilan,
            cloture: clotureAvantFinPlanning && base.effectifsOuverts.isEmpty ? Web.clotureAvantFin : nil,
            alertes: alertes)
    }

    // MARK: Créneaux travaillés

    func titreSegments() -> String {
        let n = parJour.reduce(0) { $0 + $1.segments.count }
        return Web.segmentsTitre + String(n) + " " + Web.segmentMot + (n > 1 ? Web.segmentPluriel : "") + Web.parentheseFermante
    }

    func jours() -> [PresentationDetailPresences.Jour] {
        parJour.map { jour in
            let titre: String
            if jour.cle != Self.sansDate, let date = jour.segments.first.flatMap({ Self.date($0.debut) }) {
                titre = Web.pictoJour + " " + DateHeureParis.format(date, "EEEE d MMMM yyyy")
            } else {
                titre = Web.pictoJour + " " + Web.dateInconnue
            }
            let segments = jour.segments.enumerated().map { position, effectif in
                segment(effectif, position: position, jour: jour.segments)
            }
            return PresentationDetailPresences.Jour(id: jour.cle, titre: titre, segments: segments)
        }
    }

    private func segment(_ effectif: MissionSlot, position: Int, jour: [MissionSlot]) -> PresentationDetailPresences.Segment {
        typealias Ecart = PresentationDetailPresences.Ecart
        let arrivee = Self.date(effectif.debut)
        let depart = Self.date(effectif.fin)
        let precedente = position > 0 ? Self.date(jour[position - 1].fin) : nil
        let interruption = arrivee.flatMap { debut in precedente.map { max(PresentationDetailPresences.minutes(debut, $0), 0) } } ?? 0
        let associe = associe(arrivee)
        let positionsAssociees = associe.map { cible in
            jour.indices.filter { self.associe(Self.date(jour[$0].debut))?.index == cible.index }
        } ?? []
        let indexAssocie = positionsAssociees.firstIndex(of: position) ?? -1
        let premier = indexAssocie <= 0
        let dernier = indexAssocie == positionsAssociees.count - 1

        var etiquette: String?
        if jour.count > 1 {
            var texte = Web.segmentTravaille + " " + String(position + 1) + " " + Web.segmentBarre + " " + String(jour.count)
            if position > 0 { texte += " " + Web.reprise }
            if let associe {
                texte += " " + Web.creneauPlanifieSuffixe + " " + String(associe.index + 1) + Web.creneauPlanifieSuffixeBarre
                    + String(associe.total)
            }
            etiquette = texte
        } else if let associe {
            etiquette = Web.creneauPlanifie + " " + String(associe.index + 1) + " " + Web.creneauPlanifieBarre + " " + String(associe.total)
        }

        var horairePrevu: String?
        var ecarts: [Ecart] = []
        var sansHoraire: String?
        if let associe {
            horairePrevu = Self.plageExacte(associe.debut, associe.fin)
            let retard = premier ? arrivee.map { max(PresentationDetailPresences.minutes($0, associe.debut), 0) } ?? 0 : 0
            let finEchue = associe.fin <= maintenant
            let departAnticipe = finEchue && dernier ? depart.map { max(PresentationDetailPresences.minutes(associe.fin, $0), 0) } ?? 0 : 0
            let enAttente = !missionTerminee && dernier && !finEchue && (depart.map { $0 < associe.fin } ?? false)
            if retard > 0 { ecarts.append(Ecart(texte: Web.retardSegment + String(retard) + " " + Web.uniteMinutes, ton: .attention)) }
            if departAnticipe > 0 {
                ecarts.append(Ecart(texte: Web.departAnticipeSegment + String(departAnticipe) + " " + Web.uniteMinutes, ton: .attention))
            }
            if enAttente {
                ecarts.append(Ecart(texte: Web.bilanApresEcheance + " " + DateHeureParis.format(associe.fin, "HH:mm"), ton: .neutre))
            }
        } else {
            sansHoraire = planifies.isEmpty ? Web.planningAConfirmer : Web.aucunCreneauCeJour
        }

        let duree = arrivee.flatMap { debut in depart.map { PresentationDetailPresences.minutes($0, debut) } }
        let validation = validation()
        return PresentationDetailPresences.Segment(
            id: effectif.id ?? "\(effectif.debut)-\(position)",
            etiquette: etiquette,
            interruption: interruption > 0
                ? Web.interruption + " " + SynthesePresence.formatDureeMinutes(Double(interruption)) : nil,
            horairePrevu: horairePrevu, ecarts: ecarts, sansHoraire: sansHoraire,
            arrivee: Web.arrivee + " " + (arrivee.map { DateHeureParis.format($0, "dd/MM/yyyy HH:mm:ss") } ?? ""),
            depart: depart.map { Web.depart + " " + DateHeureParis.format($0, "dd/MM/yyyy HH:mm:ss") } ?? Web.departNonPointe,
            departPointe: depart != nil,
            duree: duree.map { Web.duree + " " + Self.duree($0) },
            validation: validation.texte, tonValidation: validation.ton, ton: tonSegment())
    }

    /// Statut de validation d'un segment (l.632-648).
    private func validation() -> (texte: String, ton: PresentationDetailPresences.Ton) {
        if presence?.valideParEtablissement == true {
            let date = presence?.valideLe.flatMap { Self.date($0) }.map { " " + Web.valideLe + " " + DateHeureParis.format($0, "dd/MM/yyyy HH:mm") }
            return (Web.valide + (date ?? ""), .succes)
        }
        if missionTerminee {
            return (presence?.heuresAjusteesLitige != nil ? Web.releveClotureApresArbitrage : Web.releveCloture, .succes)
        }
        if base.validationPossible { return (Web.enAttenteValidation, .attention) }
        if !base.effectifsOuverts.isEmpty { return (Web.pointageEnCours, .attention) }
        return (Web.missionEnCours, .neutre)
    }

    /// Bordure d'un segment (l.551-556).
    private func tonSegment() -> PresentationDetailPresences.Ton {
        if presence?.alerteTeleportation == true { return .alerte }
        if presence?.perimetreGpsValide == false, PresentationDetailPresences.mesureDisponible(presence?.distanceEtablissementM) != nil {
            return .attention
        }
        return presence?.valideParEtablissement == true ? .succes : .neutre
    }

    // MARK: Contrôles du pointage

    static func controles(_ presence: PresenceControlee) -> PresentationDetailPresences.Controles {
        typealias Ligne = PresentationDetailPresences.LigneControle
        var lignes: [Ligne] = []
        if let distance = PresentationDetailPresences.mesureDisponible(presence.distanceEtablissementM) {
            let ton: PresentationDetailPresences.Ton = presence.perimetreGpsValide == true
                ? .succes : (presence.perimetreGpsValide == false ? .attention : .neutre)
            lignes.append(Ligne(id: "distance", texte: Web.premiereArrivee + " " + LibellesDetailPresences.arrondi(distance) + Web.uniteMetres,
                                ton: ton, perimetre: presence.perimetreGpsValide))
        }
        if let precision = PresentationDetailPresences.mesureDisponible(presence.arriveePrecisionGpsM) {
            lignes.append(Ligne(id: "precision-arrivee",
                                texte: Web.precisionArrivee + " " + LibellesDetailPresences.arrondi(precision) + Web.uniteMetres,
                                ton: .neutre, perimetre: nil))
        }
        if let precision = PresentationDetailPresences.mesureDisponible(presence.departPrecisionGpsM) {
            lignes.append(Ligne(id: "precision-depart",
                                texte: Web.precisionDepart + " " + LibellesDetailPresences.arrondi(precision) + Web.uniteMetres,
                                ton: .neutre, perimetre: nil))
        }
        return PresentationDetailPresences.Controles(lignes: lignes, alerteTeleportation: presence.alerteTeleportation == true)
    }

    // MARK: Outils

    /// `trouverCreneauDuJour` (l.53-70) : créneau planifié du jour de Paris de `date` le plus proche par son début.
    func associe(_ date: Date?) -> Associe? {
        guard let date else { return nil }
        let debutJour = DateHeureParis.debutJour(date)
        let finJour = DateHeureParis.ajouterJoursCivils(debutJour, 1)
        let candidats = planifies.enumerated().filter {
            DisponibilitePointage.creneauChevauchePeriode($0.element, debutPeriode: debutJour, finPeriode: finJour)
        }
        let ecart = { (creneau: MissionSlot) in abs(DisponibilitePointage.temps(creneau.debut) - DisponibilitePointage.temps(date)) }
        guard let retenu = triStableCroissant(candidats, cle: { ecart($0.element) }).first,
              let debut = Self.date(retenu.element.debut), let fin = Self.date(retenu.element.fin) else { return nil }
        return Associe(index: retenu.offset, total: planifies.count, debut: debut, fin: fin)
    }

    static let sansDate = "sans-date"

    static func cleJour(_ iso: String) -> String {
        date(iso).map(DateHeureParis.cleJour) ?? sansDate
    }

    static func date(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        return try? DateHeureParis.instantJolene(iso)
    }

    /// `formatPlageExacte` (l.72-78).
    static func plageExacte(_ debut: Date, _ fin: Date) -> String {
        let finFormatee = DateHeureParis.memeJour(debut, fin)
            ? DateHeureParis.format(fin, "HH:mm") : DateHeureParis.format(fin, "EEE d MMM yyyy · HH:mm")
        return DateHeureParis.format(debut, "EEE d MMM yyyy · HH:mm") + " " + Web.flechePlage + " " + finFormatee
    }

    /// `{Math.floor(dureeMin / 60)}h{String(dureeMin % 60).padStart(2, '0')}` (l.627).
    static func duree(_ minutes: Int) -> String {
        let heures = Int((Double(minutes) / 60).rounded(.down))
        let reste = String(minutes % 60)
        return String(heures) + Web.dureeHeures + (reste.count < 2 ? "0" + reste : reste)
    }
}
