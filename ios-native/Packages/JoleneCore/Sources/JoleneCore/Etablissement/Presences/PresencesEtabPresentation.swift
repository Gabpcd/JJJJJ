import Foundation

/// Textes et mise en forme de l'écran des présences de l'établissement (lot 5, T8). Libellés d'interface repris du web
/// (`src/pages/PresencesEtablissement.tsx`, `src/components/CarteValidation.tsx`, `NotationRapide.tsx`,
/// `pointage/AffichageCodeRotatifEtab.tsx`, annotés `// source:`, non juridiques ; dérive gardée par
/// `PresencesEtabRulesTests`) et quelques textes natifs de navigation. Les refus du serveur ne sont jamais écrits ici :
/// ils viennent mot pour mot de l'issue de la gateway.
///
/// Aucun montant, aucune durée facturée : « Prévu » et « Réel » sont les sommes de `SynthesePresence` (port doré de
/// `synthese-presence-mission.ts`) sur les créneaux relus au serveur. Non portés : écart en minutes, précision GPS,
/// contact du soignant, litige formel et panneau de contestation d'une présence validée (renvoi web, §1.2).
public enum PresencesEtabPresentation {
    public typealias Badge = MesMissionsPresentation.Badge

    // MARK: - Écran et onglets

    // source: src/pages/PresencesEtablissement.tsx:43
    public static let titreEcran = "Présences"
    // source: src/pages/PresencesEtablissement.tsx:497
    public static let sousTitre = "Vérifiez et validez les pointages de vos soignants"
    // source: src/pages/PresencesEtablissement.tsx:400
    public static let titreErreur = "Impossible de charger les présences"
    // source: src/pages/PresencesEtablissement.tsx:403
    public static let reessayer = "Réessayer"
    public static let chargement = "Chargement des présences…"
    public static let messageErreurGenerique = "Les présences n'ont pas pu être chargées. Vérifiez votre connexion puis réessayez."

    /// « À valider (2) », « En cours (1) », « Validées (0) », « Alertes (3) » (l.510-519).
    public static func libelle(_ onglet: OngletPresencesEtab, nombre: Int) -> String {
        switch onglet {
        case .aValider: return "À valider (\(nombre))"
        case .enCours: return "En cours (\(nombre))"
        case .validees: return "Validées (\(nombre))"
        case .alertes: return "Alertes (\(nombre))"
        }
    }

    public struct EtatVide: Equatable, Sendable {
        public var titre: String
        public var message: String
    }

    /// États vides du web (l.543, l.554, l.565, l.601).
    public static func etatVide(_ onglet: OngletPresencesEtab, sansPointage: Bool) -> EtatVide {
        switch onglet {
        case .aValider: return EtatVide(titre: "Aucune présence à valider", message: "Les pointages de vos soignants apparaîtront ici.")
        case .enCours: return EtatVide(titre: "Aucune mission en cours", message: "Les soignants actuellement en mission apparaîtront ici.")
        case .validees: return EtatVide(titre: "Aucune présence validée", message: "Les présences validées seront archivées ici.")
        case .alertes:
            return sansPointage
                ? EtatVide(titre: "Aucune autre alerte", message: "Les missions sans pointage sont listées ci-dessus.")
                : EtatVide(titre: "Aucune alerte", message: "Les présences avec des alertes de fraude apparaîtront ici.")
        }
    }

    // MARK: - Missions terminées sans pointage

    // source: src/pages/PresencesEtablissement.tsx:575
    public static let sansPointageTitre = "Missions terminées sans pointage"
    // source: src/pages/PresencesEtablissement.tsx:578
    public static let sansPointageMessage = "Ces missions bloquent l'export de paie : aucune arrivée ni aucun départ n'a été enregistré. Ouvrez la mission pour régulariser la présence avant de générer la paie."

    /// « 27/10/2026 07:00 → 27/10/2026 15:00 » (l.590) ; bornes illisibles → vide.
    public static func periodeSansPointage(_ mission: EtabMissionResume) -> String {
        guard let debut = instant(mission.debutLe), let fin = instant(mission.finLe) else { return "" }
        return "\(DateHeureParis.format(debut, "dd/MM/yyyy HH:mm")) → \(DateHeureParis.format(fin, "dd/MM/yyyy HH:mm"))"
    }

    // MARK: - Carte d'une présence

    // source: src/pages/PresencesEtablissement.tsx:430
    public static let soignantInconnu = "Soignant"
    // source: src/pages/PresencesEtablissement.tsx:459
    public static let statutValidee = "Validée"
    // source: src/pages/PresencesEtablissement.tsx:460
    public static let statutAValider = "À valider"
    // source: src/pages/PresencesEtablissement.tsx:461
    public static let statutEnCours = "En cours"
    // source: src/components/presence/BadgesAntiTrichePresence.tsx:65
    public static let alerteTeleportation = "Téléportation"
    // source: src/pages/PresencesEtablissement.tsx:457
    public static let alerteHorsZone = "Hors zone"
    // source: src/pages/PresencesEtablissement.tsx:458
    public static let alerteGpsTruque = "GPS truqué"
    // source: src/components/CarteValidation.tsx:197
    public static let detailTeleportation = "Téléportation détectée"
    // source: src/components/CarteValidation.tsx:121
    public static let planningIndisponible = "Planning détaillé indisponible"
    // source: src/components/CarteValidation.tsx:122
    public static let planningAConfirmer = "Planning détaillé à confirmer"
    // source: src/components/CarteValidation.tsx:152
    public static let explicationPlanningIndisponible = "Validation indisponible tant que le planning détaillé ne peut pas être vérifié."
    // source: src/components/CarteValidation.tsx:154
    public static let explicationPointageOuvert = "Pointage en cours : la validation sera disponible après le départ et la fin du dernier créneau prévu."
    // source: src/components/CarteValidation.tsx:158
    public static let explicationAucunSegment = "Aucun segment de travail terminé à valider."
    // source: src/components/CarteValidation.tsx:159
    public static let explicationPlanningNonConfirme = "Validation indisponible tant que le planning n’est pas confirmé."

    /// Pastille d'alerte affichée (`etab-presence-alerte-{id}-{cle}`).
    public struct AlerteAffichee: Equatable, Sendable, Identifiable {
        public var cle: PresencesEtabRules.Alerte
        public var badge: Badge
        public var id: String { cle.rawValue }
    }

    /// Carte d'une présence : chaînes déjà formatées, la vue n'ajoute aucune règle.
    public struct Carte: Equatable, Sendable, Identifiable {
        public var id: String
        public var missionId: String
        public var titre: String
        public var sousTitre: String
        public var prevu: String
        public var prevuDetail: String
        public var reel: String?
        public var reelDetail: String?
        public var reelPeriode: String?
        /// Pourquoi la validation n'est pas encore proposée (`CarteValidation.tsx` l.149-160).
        public var explication: String?
        public var statut: Badge
        public var alertes: [AlerteAffichee]
        public var detailsAlertes: [String]
        /// « ⚠️ Litige : … » (`motif_litige` relu au serveur).
        public var litige: String?
        /// Présence « à valider » : non validée et validable (seul état où valider et contester sont proposés).
        public var aValider: Bool
        /// Un segment EFFECTIF est ouvert : la clôture rétroactive est proposée.
        public var segmentOuvert: Bool
        public var prenom: String?
    }

    public static func carte(_ presence: PresenceEtab, soignant: SoignantPourEtab?, maintenant: Date) -> Carte {
        let analyse = PresencesEtabRules.analyser(presence, maintenant: maintenant)
        let synthese = analyse.synthese
        let aValider = !presence.valideParEtablissement && analyse.validationPossible
        let statut: Badge
        if presence.valideParEtablissement {
            statut = Badge(statutValidee, ton: .succes)
        } else {
            statut = Badge(aValider ? statutAValider : statutEnCours, ton: .info)
        }
        var details: [String] = []
        if presence.perimetreGpsValide == false { details.append(detailHorsPerimetre(presence.distanceEtablissementM)) }
        if presence.alerteTeleportation == true { details.append(detailTeleportation) }
        let reel = lignesReel(synthese)
        let motif = presence.motifLitige?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Carte(
            id: presence.id, missionId: presence.missionId, titre: titre(soignant), sousTitre: sousTitre(presence.mission),
            prevu: titrePrevu(synthese.previsionnels.count), prevuDetail: detailPrevu(analyse),
            reel: reel?.titre, reelDetail: reel?.detail, reelPeriode: reel?.periode,
            explication: presence.valideParEtablissement || analyse.validationPossible ? nil : explication(analyse),
            statut: statut,
            alertes: PresencesEtabRules.alertes(presence).map { AlerteAffichee(cle: $0, badge: badge($0)) },
            detailsAlertes: details, litige: motif.isEmpty ? nil : litige(motif), aValider: aValider,
            segmentOuvert: !synthese.effectifsOuverts.isEmpty, prenom: prenom(soignant))
    }

    /// « Camille Démo · Infirmier(ère) » (`CarteValidation.tsx` l.82), « Soignant » sans soignant lu (l.430).
    public static func titre(_ soignant: SoignantPourEtab?) -> String {
        guard let soignant else { return soignantInconnu }
        let nom = [soignant.prenom, soignant.nom].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        let profession = soignant.profession.map(MissionPresentation.professionLabel) ?? ""
        let parties = [nom.isEmpty ? soignantInconnu : nom, profession].filter { !$0.isEmpty }
        return parties.joined(separator: " · ")
    }

    public static func prenom(_ soignant: SoignantPourEtab?) -> String? {
        guard let prenom = soignant?.prenom?.trimmingCharacters(in: .whitespaces), !prenom.isEmpty else { return nil }
        return prenom
    }

    /// `${intitule}${service ? ` · ${service}` : ''}` (`CarteValidation.tsx` l.83).
    public static func sousTitre(_ mission: MissionPresenceEtab?) -> String {
        [mission?.intitule, mission?.service].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// `Prévu · ${n} créneau${n > 1 ? 'x' : ''}` (`CarteValidation.tsx` l.112).
    public static func titrePrevu(_ nombre: Int) -> String { "Prévu · \(nombre) créneau\(nombre > 1 ? "x" : "")" }

    /// Plage exacte et durée planifiée (l.113-117), sinon planning indisponible ou à confirmer (l.119-123).
    static func detailPrevu(_ analyse: PresencesEtabRules.Analyse) -> String {
        let previsionnels = analyse.synthese.previsionnels
        guard let debut = instant(previsionnels.first?.debut), instant(previsionnels.first?.fin) != nil,
              let fin = instant(previsionnels.last?.fin) else {
            return analyse.planningIndisponible ? planningIndisponible : planningAConfirmer
        }
        return "\(plageExacte(debut, fin)) · \(SynthesePresence.formatDureeMinutes(analyse.synthese.minutesPlanifiees))"
    }

    /// `formatPlageExacte` (`CarteValidation.tsx` l.20-26).
    static func plageExacte(_ debut: Date, _ fin: Date) -> String {
        let masque = "EEE d MMM yyyy · HH:mm"
        let finFormatee = DateHeureParis.memeJour(debut, fin) ? DateHeureParis.format(fin, "HH:mm") : DateHeureParis.format(fin, masque)
        return "\(DateHeureParis.format(debut, masque)) → \(finFormatee)"
    }

    /// « Réel · 2 segments terminés », « 7h58 travaillées · pointage ouvert », « Du … au … » (l.126-141).
    static func lignesReel(_ synthese: SynthesePresenceMission) -> (titre: String, detail: String, periode: String?)? {
        let premier = synthese.effectifsFermes.first ?? synthese.effectifsOuverts.first
        guard premier != nil || !synthese.effectifsFermes.isEmpty else { return nil }
        let n = synthese.effectifsFermes.count
        let pluriel = n > 1 ? "s" : ""
        let ouvert = synthese.effectifsOuverts.isEmpty ? "" : " · pointage ouvert"
        var periode: String?
        if let debut = instant(premier?.debut), let fin = instant(synthese.effectifsFermes.last?.fin) {
            periode = "Du \(DateHeureParis.format(debut, "dd/MM/yyyy HH:mm")) au \(DateHeureParis.format(fin, "dd/MM/yyyy HH:mm"))"
        }
        return ("Réel · \(n) segment\(pluriel) terminé\(pluriel)",
                "\(SynthesePresence.formatDureeMinutes(synthese.minutesTravaillees)) travaillées\(ouvert)", periode)
    }

    /// Explication d'une présence non validable (`CarteValidation.tsx` l.151-159), dans l'ordre du web.
    static func explication(_ analyse: PresencesEtabRules.Analyse) -> String {
        let synthese = analyse.synthese
        if analyse.planningIndisponible { return explicationPlanningIndisponible }
        if !synthese.effectifsOuverts.isEmpty { return explicationPointageOuvert }
        if let fin = synthese.dernierPrevisionnelFin, !synthese.planningTermine {
            return "Mission en cours : validation après le dernier créneau, le \(DateHeureParis.format(fin, "dd/MM/yyyy 'à' HH:mm"))."
        }
        return synthese.effectifsFermes.isEmpty ? explicationAucunSegment : explicationPlanningNonConfirme
    }

    /// `Hors périmètre à l'arrivée (350m)` ou ` (distance indisponible)` (`CarteValidation.tsx` l.192), distance servie
    /// arrondie comme `Math.round`.
    static func detailHorsPerimetre(_ distance: Double?) -> String {
        guard let distance, distance.isFinite, distance >= 0 else { return "Hors périmètre à l'arrivée (distance indisponible)" }
        return "Hors périmètre à l'arrivée (\(Int(SynthesePresence.arrondiJS(distance)))m)"
    }

    static func badge(_ alerte: PresencesEtabRules.Alerte) -> Badge {
        switch alerte {
        case .teleportation: return Badge(alerteTeleportation, ton: .erreur)
        case .horsZone: return Badge(alerteHorsZone, ton: .attention)
        case .gpsTruque: return Badge(alerteGpsTruque, ton: .erreur)
        }
    }

    /// `⚠️ Litige : ${motif}` (`CarteValidation.tsx` l.206).
    public static func litige(_ motif: String) -> String { "⚠️ Litige : \(motif)" }

    // MARK: - Validation et note

    // source: src/pages/PresencesEtablissement.tsx:470
    public static let valider = "Valider"
    // source: src/pages/PresencesEtablissement.tsx:626
    public static let validationMessage = "Un tap suffit — la note alimente le score de fiabilité."
    // source: src/pages/PresencesEtablissement.tsx:644
    public static let validerEtNoter = "Valider et noter"
    // source: src/components/CarteValidation.tsx:248
    public static let noterPourValider = "Noter pour valider"
    // source: src/components/NotationRapide.tsx:78
    public static let groupeNote = "Note"
    // source: src/pages/PresencesEtablissement.tsx:261
    public static let plusEligible = "Cette mission ne peut être validée qu’après son dernier créneau et la fermeture de tous les pointages."
    // source: src/pages/PresencesEtablissement.tsx:306
    public static let succesValidation = "Présence validée !"
    public static let annuler = "Annuler"
    /// Issue non confirmée par la relecture (texte natif, non juridique).
    public static let nonConfirmee = "L'action n'a pas pu être confirmée par une relecture. Vérifiez les présences avant de recommencer."

    /// `Noter ${prenom ?? 'le soignant'} pour valider` (l.623).
    public static func validationTitre(prenom: String?) -> String { "Noter \(prenom ?? "le soignant") pour valider" }

    /// `Présence validée et note ${note}/5 envoyée !` (l.306).
    public static func succesValidationNotee(_ note: Int) -> String { "Présence validée et note \(note)/5 envoyée !" }

    /// `${n} étoile${n > 1 ? 's' : ''}` (`NotationRapide.tsx` l.88).
    public static func etoiles(_ n: Int) -> String { "\(n) étoile\(n > 1 ? "s" : "")" }

    // MARK: - Validation en lot

    // source: src/pages/PresencesEtablissement.tsx:535
    public static let lotNote = "Ce bouton valide uniquement les présences sans aucune alerte (géofence OK, pas de téléportation)."
    // source: src/pages/PresencesEtablissement.tsx:613
    public static let lotMessage = "Seules les présences sans alerte de fraude seront validées."
    // source: src/pages/PresencesEtablissement.tsx:335
    public static let lotAucuneEligible = "Aucune présence éligible à la validation automatique."
    // source: src/pages/PresencesEtablissement.tsx:351
    public static let lotPlusEligible = "Aucune présence n’est encore éligible : vérifiez la fin du planning et les pointages ouverts."

    /// `${n} présences à valider` (l.526).
    public static func lotResume(_ n: Int) -> String { "\(n) présences à valider" }
    /// `Tout valider (sans alerte) · ${n} présences` (l.532).
    public static func lotBouton(_ n: Int) -> String { "Tout valider (sans alerte) · \(n) présences" }
    /// `Valider ${n} présences ?` (l.612).
    public static func lotTitre(_ n: Int) -> String { "Valider \(n) présences ?" }
    /// `Valider ${n} présences` (l.614).
    public static func lotConfirmer(_ n: Int) -> String { "Valider \(n) présences" }

    /// Résultat **relu** d'un lot (texte natif, §2.5) : « 1 présence validée sur 2 sélectionnées. »
    public static func lotResultat(validees: Int, selectionnees: Int) -> String {
        "\(validees) présence\(validees > 1 ? "s" : "") validée\(validees > 1 ? "s" : "") sur "
            + "\(selectionnees) sélectionnée\(selectionnees > 1 ? "s" : "")."
    }

    // MARK: - Contestation

    // source: src/components/CarteValidation.tsx:254
    public static let contester = "Contester"
    // source: src/components/CarteValidation.tsx:272
    public static let contestationPlaceholder = "Motif de la contestation..."
    // source: src/components/CarteValidation.tsx:281
    public static let contestationEnvoyer = "Envoyer la contestation"
    // source: src/pages/PresencesEtablissement.tsx:328
    public static let succesContestation = "Contestation enregistrée."
    public static let contestationTitre = "Contester la présence"

    // MARK: - Clôture rétroactive

    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:378
    public static let clotureProposer = "Le soignant n'a pas pu scanner sa sortie ? Clôturer le segment →"
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:383
    public static let clotureMessage = "Saisissez l'heure de fin réelle. La saisie est tracée (oubli de scan)."
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:387
    public static let clotureHeure = "Heure de fin réelle"
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:394
    public static let cloturer = "Clôturer le segment"
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:189
    public static let succesCloture = "Segment clôturé."

    private static func instant(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        return try? DateHeureParis.instantJolene(iso)
    }
}
