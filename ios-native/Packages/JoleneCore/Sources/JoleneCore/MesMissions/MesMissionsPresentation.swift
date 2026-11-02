import Foundation

/// Onglets de « Mes missions » (lot 1, T5), dans l'ordre du web (`MissionsSoignant.tsx` l.330-334) :
/// Candidatures · À venir · Passées. La recherche de missions disponibles vit dans Explorer.
public enum MesMissionsOnglet: String, CaseIterable, Sendable, Identifiable {
    case candidatures
    case aVenir = "avenir"
    case passees

    public var id: String { rawValue }

    public var titre: String {
        switch self {
        case .candidatures: return "Candidatures"
        case .aVenir: return "À venir"
        case .passees: return "Passées"
        }
    }

    /// Identifiant d'accessibilité du bouton d'onglet (`missions-tab-candidatures|avenir|passees`).
    public var identifiant: String { "missions-tab-\(rawValue)" }

    /// Onglet initial du web (l.118-126) : `?tab=candidatures` → Candidatures ; `?tab=passees` ou
    /// l'ancien `?onglet=historique` → Passées ; tout le reste (dont `?tab=a-venir`, cible des
    /// redirections `/soignant/planning` et `/soignant/calendrier-sync`) → À venir. Point de fusion
    /// T10 : le coordinateur de liens choisit l'onglet par cette fonction, jamais par une table à lui.
    public static func initial(tab: String?, onglet: String?) -> MesMissionsOnglet {
        if tab == "candidatures" { return .candidatures }
        if tab == "passees" || onglet == "historique" { return .passees }
        return .aVenir
    }
}

/// Textes et lignes de « Mes missions », portés de `MissionsSoignant.tsx` (l.425-630). Vouvoiement
/// sobre (décision 9) pour les textes propres à l'app ; la note « net estimé » est reprise mot pour mot
/// (`AccueilPresentation.noteNetEstime`, HARD STOP n°4). Horaires en heure de Paris (`DateHeureParis`,
/// jetons date-fns) ; taux et montants = valeurs serveur, jamais recalculées (PRINCIPES §3).
public enum MesMissionsPresentation {
    /// Statuts lus par onglet, ceux des requêtes du web (l.183, l.219-225).
    public static let statutsCandidatures = ["EN_ATTENTE", "EN_ATTENTE_VALIDATION_ETAB"]
    public static let statutsAVenir = ["ASSIGNEE", "EN_COURS"]
    public static let statutsPassees = ["TERMINEE", "ANNULEE_PAR_SOIGNANT", "ANNULEE_PAR_ETABLISSEMENT", "ABSENCE"]

    public static let badgeEnAttente = "⏳ En attente de réponse"
    public static let badgePrioriteHistorique = "★ Priorité historique"
    public static let tousCreneauxTermines = "Tous les créneaux planifiés sont terminés"
    public static let titreErreur = "Missions momentanément indisponibles"
    public static let chargerPlus = "Charger plus de missions"

    // MARK: - Planning

    /// Port de `enrichirAvecPlanning` (l.56-99) : `analyserCompletudePlanningMission` sur les seuls
    /// créneaux PREVISIONNEL **relus** de la mission (ceux qui portent son id : pager du lot 0 côté
    /// Supabase, `mission_id` des fixtures en démo). Le repli ponctuel ajouté par le planning candidat
    /// (`MissionBusiness.enrich`, sans `mission_id`) n'est jamais compté deux fois : la complétude le
    /// reconstruit elle-même pour une mission ponctuelle sans créneau détaillé, comme le web.
    public static func completude(_ mission: Mission) -> CompletudePlanningMission {
        let relus = mission.creneauxPlanifies.filter { $0.missionId == mission.id }
        return CompletudePlanning.analyser(MissionAvecPlanningAttendu(record: mission.record), creneaux: relus)
    }

    /// `prochainCreneau` du web : créneau non terminé d'un planning complet, sinon `nil`.
    public static func prochainCreneau(_ mission: Mission, maintenant: Date) -> MissionSlot? {
        let analyse = completude(mission)
        guard analyse.complet else { return nil }
        return DisponibilitePointage.prochainCreneauPointage(analyse.creneauxPlanifies, maintenant: maintenant)
    }

    // MARK: - Lignes

    /// Nature d'une pastille, traduite en ton par l'écran (JoleneDesign).
    public enum TonBadge: Equatable, Sendable { case succes, attention, erreur, info }

    public struct Badge: Equatable, Sendable {
        public var texte: String
        public var ton: TonBadge
        public init(_ texte: String, ton: TonBadge) { self.texte = texte; self.ton = ton }
    }

    /// Ligne affichée d'un onglet : chaînes déjà formatées, la vue n'ajoute aucune règle.
    public struct Ligne: Equatable, Sendable, Identifiable {
        /// Identifiant de la mission (lien vers le détail, `mes-mission-{id}`).
        public var id: String
        public var badges: [Badge]
        public var titre: String
        public var lieu: String
        /// Pavé de date (`EEE`, `d`, `MMM`), `nil` pour une ligne de mission passée.
        public var jour: AccueilPresentation.Jour?
        /// Horaire (candidatures, à venir) ou période (passées).
        public var horaire: String
        /// Vrai si `horaire` vaut « Planning détaillé à confirmer » (ton d'avertissement).
        public var horaireAConfirmer: Bool
        public var remuneration: String?
        public var montant: String?

        /// Libellé VoiceOver (et preuve XCUITest) : tout ce que la ligne affiche, dans l'ordre.
        public var texteAccessible: String {
            (badges.map(\.texte) + [titre, lieu, horaire] + [remuneration, montant].compactMap { $0 }).joined(separator: ", ")
        }
    }

    /// Candidature en attente (l.428-485) ; `nil` sans mission relue (le web l'écarte, l.188).
    public static func ligne(candidature: CandidatureRecord, maintenant: Date) -> Ligne? {
        guard let mission = candidature.mission else { return nil }
        var badges = [Badge(badgeEnAttente, ton: .attention)]
        if estPrioriteHistorique(candidature) { badges.append(Badge(badgePrioriteHistorique, ton: .info)) }
        if let contrat = contratChoisi(candidature) { badges.append(Badge(contrat, ton: .info)) }
        let analyse = completude(mission)
        let affiche = analyse.complet
            ? (DisponibilitePointage.prochainCreneauPointage(analyse.creneauxPlanifies, maintenant: maintenant)
               ?? DisponibilitePointage.creneauxPrevisionnels(analyse.creneauxPlanifies).first)
            : nil
        let plage = affiche.flatMap(plageCourte)
        return Ligne(id: mission.id, badges: badges, titre: mission.record.intitule,
                     lieu: lieu(mission, avecVille: true),
                     jour: jour(affiche?.debut ?? mission.record.debutLe),
                     horaire: plage ?? AccueilPresentation.planningAConfirmer, horaireAConfirmer: plage == nil,
                     remuneration: AccueilPresentation.remuneration(mission.record.tauxHoraireBase), montant: nil)
    }

    /// Mission à venir (l.502-560) : statut, urgence, prochain créneau et sa durée.
    public static func ligneAVenir(_ mission: Mission, maintenant: Date) -> Ligne {
        var badges = [badgeStatut(mission.record.statut)]
        if mission.record.estUrgente { badges.append(Badge("Urgente", ton: .attention)) }
        let analyse = completude(mission)
        let prochain = analyse.complet
            ? DisponibilitePointage.prochainCreneauPointage(analyse.creneauxPlanifies, maintenant: maintenant) : nil
        let horaire: String
        let aConfirmer: Bool
        if let prochain, let plage = plageCourte(prochain) {
            horaire = "Prochain créneau : \(plage)\(duree(prochain).map { " (\($0)h)" } ?? "")"
            aConfirmer = false
        } else if analyse.nombrePlanifie > 0 {
            horaire = tousCreneauxTermines
            aConfirmer = false
        } else {
            horaire = AccueilPresentation.planningAConfirmer
            aConfirmer = true
        }
        return Ligne(id: mission.id, badges: badges, titre: mission.record.intitule, lieu: lieu(mission, avecVille: true),
                     jour: jour(prochain?.debut ?? mission.record.debutLe), horaire: horaire, horaireAConfirmer: aConfirmer,
                     remuneration: AccueilPresentation.remuneration(mission.record.tauxHoraireBase), montant: nil)
    }

    /// Mission passée (l.566-598) : statut, période, établissement, montant serveur selon le régime.
    public static func lignePassee(_ mission: Mission, finance: MissionGainLigne?) -> Ligne {
        Ligne(id: mission.id, badges: [badgeStatut(mission.record.statut)], titre: mission.record.intitule,
              lieu: lieu(mission, avecVille: false), jour: nil, horaire: periodePassee(mission), horaireAConfirmer: false,
              remuneration: nil, montant: montantPassee(mission, finance: finance))
    }

    // MARK: - Pastilles

    /// Libellé de `BadgeStatut` (`BADGES_STATUT`, `src/lib/constantes.ts` l.66-78) ; code inconnu rendu tel quel.
    public static func statut(_ code: String) -> String {
        switch code {
        case "OUVERTE": return "Ouverte"
        case "ASSIGNEE": return "Assignée"
        case "EN_COURS": return "Active"
        case "TERMINEE": return "Terminée"
        case "EXPIREE": return "Expirée (non pourvue)"
        case "ANNULEE_PAR_ETABLISSEMENT": return "Annulée"
        case "ANNULEE_PAR_SOIGNANT": return "Annulée (soignant)"
        case "ABSENCE": return "Absence"
        case "LITIGE": return "Litige"
        default: return code
        }
    }

    public static func badgeStatut(_ code: String) -> Badge {
        let ton: TonBadge
        switch code {
        case "ASSIGNEE", "EN_COURS", "TERMINEE": ton = .succes
        case "ANNULEE_PAR_SOIGNANT", "ABSENCE": ton = .erreur
        case "LITIGE", "EXPIREE": ton = .attention
        default: ton = .info
        }
        return Badge(statut(code), ton: ton)
    }

    /// « ★ Priorité historique » : message de candidature contenant « super-like » (l.434, casse ignorée).
    public static func estPrioriteHistorique(_ candidature: CandidatureRecord) -> Bool {
        (candidature.message ?? "").lowercased().contains("super-like")
    }

    /// Mode de contrat choisi (l.443) : « Libéral » pour `LIBERAL`, « Salarié » pour toute autre valeur.
    public static func contratChoisi(_ candidature: CandidatureRecord) -> String? {
        guard let choisi = candidature.typeContratChoisi, !choisi.isEmpty else { return nil }
        return choisi == "LIBERAL" ? "Libéral" : "Salarié"
    }

    // MARK: - Lieu, dates, montants

    /// Nom de l'établissement relu par `fn_etablissements_safe` (seule source, §2.6), sinon
    /// « Établissement » ; suivi de la ville pour les candidatures et les missions à venir.
    public static func lieu(_ mission: Mission, avecVille: Bool) -> String {
        let nom = etablissementNom(mission)
        guard avecVille, let ville = mission.etablissement?.adresseVille, !ville.isEmpty else { return nom }
        return "\(nom) · \(ville)"
    }

    public static func etablissementNom(_ mission: Mission) -> String {
        AccueilAssemblage.nom(etablissement: mission.etablissement, repli: nil)
    }

    /// Période d'une mission passée : « 20 oct. → 21 oct. 2026 » (multi-jours) ou « 1 nov. 2026 ».
    public static func periodePassee(_ mission: Mission) -> String {
        guard let debut = PlanningHorlogeParis.instant(mission.record.debutLe) else { return "—" }
        if FormatMission.estMultiJours(mission.record.horaires), let fin = PlanningHorlogeParis.instant(mission.record.finLe) {
            return "\(DateHeureParis.format(debut, "d MMM")) → \(DateHeureParis.format(fin, "d MMM yyyy"))"
        }
        return DateHeureParis.format(debut, "d MMM yyyy")
    }

    /// Port de `montantFinanceAfficheMission` (`src/lib/missionFinanceDisplay.ts`) : montant stocké
    /// choisi selon le régime (`GainsDuMois.montant`), libellé du web, « ~ » quand il est approximatif ;
    /// `nil` sans montant positif. **Écart assumé** : la correction client d'un ancien plafond Rist du
    /// web (`corrigerAncienPlafondImpossible`, proportion taux publié / taux plafonné) n'est jamais
    /// reproduite (PRINCIPES §3) ; quand elle s'appliquerait, aucun montant n'est affiché plutôt qu'une
    /// valeur différente de celle du web (`PARITE_SOIGNANT.md`).
    public static func montantPassee(_ mission: Mission, finance: MissionGainLigne?) -> String? {
        guard let finance, finance.id == mission.id, let affiche = GainsDuMois.montant(finance), affiche.montant > 0 else { return nil }
        guard !correctionAncienPlafond(mission.record, finance: finance) else { return nil }
        let euros = MissionPresentation.euros(affiche.montant)
        switch affiche.nature {
        case .honorairesLiberaux: return "Honoraires bruts : \(euros)"
        case .netSalarieEstime: return "Net salarié estimé* : ~\(euros)"
        case .brutIndicatif: return "Rémunération brute indicative : ~\(euros)"
        }
    }

    /// Condition de `corrigerAncienPlafondImpossible` pour une mission assignée au soignant (toute
    /// mission passée l'est) : plafond Rist appliqué à une mission libérale (`type_contrat_applique`
    /// puis `type_contrat_recherche`, sans filtre de valeur), taux publié supérieur au taux plafonné.
    static func correctionAncienPlafond(_ record: MissionRecord, finance: MissionGainLigne) -> Bool {
        guard record.ristPlafondApplique == true,
              (finance.typeContratApplique ?? finance.typeContratRecherche) == "LIBERAL",
              let publie = record.tauxHoraireBase, let plafonne = record.tauxRistPlafonne,
              plafonne > 0, publie > plafonne else { return false }
        return true
    }

    // MARK: - États

    public struct EtatVide: Equatable, Sendable {
        public var titre: String
        public var message: String
        public var action: String
    }

    /// États vides du web (l.488-490, l.562, l.602-604), au vouvoiement ; chacun renvoie vers Explorer.
    public static func etatVide(_ onglet: MesMissionsOnglet) -> EtatVide {
        switch onglet {
        case .candidatures:
            return EtatVide(titre: "Aucune candidature en attente",
                            message: "Postulez à une mission : vos candidatures en attente de réponse de l’établissement apparaîtront ici.",
                            action: "Trouver une mission")
        case .aVenir:
            return EtatVide(titre: "Aucune mission à venir",
                            message: "Découvrez les missions disponibles et postulez.",
                            action: "Voir les missions disponibles")
        case .passees:
            return EtatVide(titre: "Aucune mission dans l'historique",
                            message: "Vos missions terminées et annulées apparaîtront ici.",
                            action: "Trouver une mission")
        }
    }

    /// Message de chargement du web (l.391-395).
    public static func chargement(_ onglet: MesMissionsOnglet) -> String {
        onglet == .candidatures
            ? "Chargement des candidatures — En attente de réponse de l’établissement…"
            : "Chargement des missions…"
    }

    // MARK: - Interne

    /// « 5 nov. · 08h00 → 16h00 » (`"d MMM · HH'h'mm"` → `"HH'h'mm"`) ; `nil` sans fin lisible.
    static func plageCourte(_ creneau: MissionSlot) -> String? {
        guard let fin = creneau.finRenseignee, let debut = PlanningHorlogeParis.instant(creneau.debut),
              let finDate = PlanningHorlogeParis.instant(fin) else { return nil }
        return "\(DateHeureParis.format(debut, "d MMM · HH'h'mm")) → \(DateHeureParis.format(finDate, "HH'h'mm"))"
    }

    /// Durée du créneau en heures, `toLocaleString('fr-FR', { maximumFractionDigits: 2 })` : « 8 », « 7,5 ».
    static func duree(_ creneau: MissionSlot) -> String? {
        guard let fin = creneau.finRenseignee, let debut = PlanningHorlogeParis.instant(creneau.debut),
              let finDate = PlanningHorlogeParis.instant(fin) else { return nil }
        let heures = Double(DateHeureParis.millisecondes(finDate) - DateHeureParis.millisecondes(debut)) / 3_600_000
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = ","
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: heures))
    }

    /// Pavé de date (`EEE`, `d`, `MMM`) d'un instant ISO 8601 ; `nil` si la date est illisible.
    static func jour(_ iso: String) -> AccueilPresentation.Jour? {
        guard let date = PlanningHorlogeParis.instant(iso) else { return nil }
        return AccueilPresentation.Jour(semaine: DateHeureParis.format(date, "EEE"), jour: DateHeureParis.format(date, "d"),
                                        mois: DateHeureParis.format(date, "MMM"))
    }
}
