import Foundation

/// Textes et mise en forme de la publication d'une mission (lot 5, T9). Libellés d'interface repris du web
/// (`FormulaireMission.tsx`, `FormulaireRecurrence.tsx`, `LigneHoraireJour.tsx`, `ModalRecapMission.tsx`, annotés
/// `// source:`), sans leurs émojis décoratifs, et quelques textes natifs de navigation, sans qualification juridique.
/// Les refus du serveur (planning, blocage de publication) ne sont jamais écrits ici : ils viennent mot pour mot de
/// l'issue de la gateway.
///
/// **HARD STOP n°4, non affiché.** La description de l'option du web publiée en natif (`FormulaireMission.tsx` l.766 :
/// `TextesWeb.PublicationEtablissement.optionSalarieLibelle` et `.optionSalarieDescription`) est un texte à portée
/// juridique : elle reste verrouillée jusqu'à la validation d'écran de Gabrielle
/// (`tests/node/contrats-etablissement-ios.node.mjs`, liste `VALIDES`). `mentionContrat` vaut donc `nil` et le
/// récapitulatif n'affiche aucun type de contrat. À la validation : `mentionContrat` rend ces deux constantes,
/// `PublicationEtablissement` entre dans `VALIDES` et la référence de la validation est consignée dans
/// `DECISIONS_LOT5.md`. Tant que cette mention n'est pas affichée, l'espace établissement ne s'ouvre pas hors
/// démonstration (`PublicationPresentationTests.testMentionContratExigeeAvantToutEspaceOuvertHorsDemo`).
///
/// Non portés (D8, D9, D15) : choix du type de contrat, nature de TVA, spécialité et internes, taux conseillé,
/// estimation de rémunération, commission, contrôle par semaine civile, couleurs de durée, sélection rapide des dates.
public enum PublicationPresentation {
    // MARK: - Libellés repris du web (non juridiques)

    // source: src/pages/CreerMission.tsx:12
    public static let titreEcran = "Publier une mission"
    // source: src/components/FormulaireMission.tsx:679
    public static let intitule = "Intitulé *"
    // source: src/components/FormulaireMission.tsx:681
    public static let intituleExemple = "Ex: IDE de nuit — Service Urgences"
    // source: src/components/FormulaireMission.tsx:687
    public static let description = "Description"
    // source: src/components/FormulaireMission.tsx:689
    public static let descriptionExemple = "Informations complémentaires pour le soignant..."
    // source: src/components/FormulaireMission.tsx:694
    public static let profession = "Profession requise *"
    // source: src/components/FormulaireMission.tsx:699
    public static let professionAChoisir = "Sélectionnez la profession recherchée"
    // source: src/components/FormulaireMission.tsx:735
    public static let service = "Service"
    // source: src/components/FormulaireMission.tsx:738
    public static let serviceExemple = "Choisissez ou saisissez le service"
    // source: src/components/FormulaireMission.tsx:893
    public static let planningTitre = "Planning exact de la mission"
    // source: src/components/FormulaireMission.tsx:895
    public static let planningAide = "Vérifiez chaque date travaillée et chaque horaire. Les jours de repos et les gardes de nuit sont enregistrés tels qu’affichés."
    /// Libellé du taux quand l'option publiée en natif est choisie sur le web (D8) ; relu avec les textes de T9.
    // source: src/components/FormulaireMission.tsx:917
    public static let taux = "Taux horaire brut * (€/h)"
    // source: src/components/FormulaireMission.tsx:922
    public static let tauxExemple = "25.00"
    // source: src/components/FormulaireMission.tsx:948
    public static let urgente = "Mission urgente ?"
    // source: src/components/FormulaireMission.tsx:949
    public static let urgenteAide = "Mise en avant dans les recherches + notification immédiate aux soignants disponibles à proximité."
    // source: src/components/FormulaireMission.tsx:958
    public static let niveauUrgence = "Niveau d'urgence"
    // source: src/components/FormulaireMission.tsx:967
    public static let modeSelection = "Mode de sélection"
    // source: src/components/FormulaireMission.tsx:973
    public static let modePremierArrive = "Premier arrivé"
    // source: src/components/FormulaireMission.tsx:974
    public static let modePremierArriveAide = "Le premier soignant qui accepte remporte la mission."
    // source: src/components/FormulaireMission.tsx:981
    public static let modeCandidature = "Je choisis"
    // source: src/components/FormulaireMission.tsx:982
    public static let modeCandidatureAide = "Les soignants postulent, vous consultez les profils et choisissez."
    // source: src/components/FormulaireMission.tsx:1058
    public static let publicationEnCours = "Publication de la mission…"
    /// Succès du web sans son émoji ; affiché seulement après relecture de la mission créée.
    // source: src/components/FormulaireMission.tsx:472
    public static let succes = "Mission publiée ! Les soignants à proximité sont prévenus"

    // source: src/components/FormulaireRecurrence.tsx:296
    public static let datesTitre = "Dates et horaires réels"
    // source: src/components/FormulaireRecurrence.tsx:298
    public static let datesAide = "Chaque date est indépendante. Vous pouvez prévoir des jours non travaillés, plusieurs créneaux et des gardes de nuit."
    // source: src/components/FormulaireRecurrence.tsx:304
    public static let dateDebut = "Première date affichée *"
    // source: src/components/FormulaireRecurrence.tsx:314
    public static let dateFin = "Dernière date affichée *"
    // source: src/components/FormulaireRecurrence.tsx:335
    public static let appliquerATous = "Appliquer le 1er horaire aux jours sélectionnés"
    // source: src/components/FormulaireRecurrence.tsx:382
    public static let jourTravaille = "Travaillé"
    // source: src/components/FormulaireRecurrence.tsx:382
    public static let jourRepos = "Repos"
    // source: src/components/FormulaireRecurrence.tsx:410
    public static let ajouterCreneau = "Ajouter un créneau ce jour"

    // source: src/components/LigneHoraireJour.tsx:47
    public static let heureDebut = "Début"
    // source: src/components/LigneHoraireJour.tsx:60
    public static let heureFin = "Fin"
    // source: src/components/LigneHoraireJour.tsx:71
    public static let dateDeFin = "Date de fin"

    /// Titre du récapitulatif du web, sans son émoji.
    // source: src/components/mission/ModalRecapMission.tsx:217
    public static let recapTitre = "Récapitulatif avant publication"
    // source: src/components/mission/ModalRecapMission.tsx:220
    public static let recapMessage = "Vérifiez les informations et chaque créneau avant de publier la mission."
    // source: src/components/mission/ModalRecapMission.tsx:238
    public static let recapIntitule = "Intitulé"
    // source: src/components/mission/ModalRecapMission.tsx:242
    public static let recapProfession = "Profession"
    // source: src/components/mission/ModalRecapMission.tsx:260
    public static let recapDuree = "Durée estimée"
    // source: src/components/mission/ModalRecapMission.tsx:303
    public static let recapUrgence = "Urgence"
    // source: src/components/mission/ModalRecapMission.tsx:194
    public static let recapModeCandidature = "Sur candidature"
    // source: src/components/FormulaireMission.tsx:1001
    public static let recapTaux = "Taux de base"
    /// « ← Modifier » du web, sans la flèche.
    // source: src/components/mission/ModalRecapMission.tsx:455
    public static let recapModifier = "Modifier"
    /// « 📤 Publier » du web, sans l'émoji.
    // source: src/components/mission/ModalRecapMission.tsx:464
    public static let recapPublier = "Publier"

    /// Niveaux d'urgence : premier mot des options du web (« Modéré — besoin sous … », l.959-961). Le délai qui suit
    /// n'est pas repris : sa forme est refusée hors de `Legal/TextesWeb.swift` par la garde des textes (marque d'un
    /// plafond d'heures, `check-textes-juridiques-ios.mjs`).
    // source: src/components/FormulaireMission.tsx:959
    public static let niveaux: [(niveau: Int, libelle: String)] = [(1, "Modéré"), (2, "Élevé"), (3, "Critique")]

    public static func libelleNiveau(_ niveau: Int) -> String {
        niveaux.first { $0.niveau == niveau }?.libelle ?? String(niveau)
    }

    public static func libelleMode(_ mode: ModeAttributionPublication) -> String {
        mode == .premierArrive ? modePremierArrive : modeCandidature
    }

    public static func aideMode(_ mode: ModeAttributionPublication) -> String {
        mode == .premierArrive ? modePremierArriveAide : modeCandidatureAide
    }

    /// Mode de sélection au récapitulatif (`ModalRecapMission.tsx` l.194, sans les émojis).
    public static func recapMode(_ mode: ModeAttributionPublication) -> String {
        mode == .premierArrive ? modePremierArrive : recapModeCandidature
    }

    /// « Publier la mission », « Publier la mission (3 créneaux) » (`FormulaireMission.tsx` l.1044).
    public static func boutonPublier(creneaux: Int) -> String {
        "Publier la mission" + (creneaux > 1 ? " (\(creneaux) créneaux)" : "")
    }

    /// « 2 dates travaillées sur 5 » (`FormulaireRecurrence.tsx` l.347-348).
    public static func resumeJours(travailles: Int, total: Int) -> String {
        let pluriel = travailles > 1 ? "s" : ""
        return "\(travailles) date\(pluriel) travaillée\(pluriel) sur \(total)"
    }

    /// « Planning exact · 2 créneaux » (`ModalRecapMission.tsx` l.269).
    public static func resumeRecap(creneaux: Int) -> String {
        "Planning exact · \(creneaux) créneau\(creneaux > 1 ? "x" : "")"
    }

    // MARK: - Mention du type de contrat (HARD STOP n°4)

    /// Libellé et description de l'option publiée, repris du web. `nil` : non affichés (voir l'en-tête du fichier).
    public struct MentionContrat: Equatable, Sendable {
        public var libelle: String
        public var description: String

        public init(libelle: String, description: String) {
            self.libelle = libelle; self.description = description
        }
    }

    public static let mentionContrat: MentionContrat? = nil

    // MARK: - Textes natifs (navigation, non juridiques)

    /// Texte neutre des renvois web de la publication (D8), tel que décidé dans `LOT5_PLAN.md` §3 T9.
    public static let renvoiWebMessage = "Cette option se configure sur jolene.app."
    public static let renvoiWebTitre = "Autres options"
    public static let renvoiWebOuvrir = "Ouvrir sur jolene.app"
    public static let choisirDate = "Choisir la date"
    public static let jourPrecedent = "Jour précédent"
    public static let jourSuivant = "Jour suivant"
    public static let voirMissions = "Voir mes missions"
    public static let voirMission = "Voir la mission"
    public static let nouvellePublication = "Publier une autre mission"
    /// Bouton du renvoi après un blocage de publication (message serveur mot pour mot au-dessus).
    public static let blocageOuvrir = "Voir sur jolene.app"
    /// Issue inconnue ou relecture qui ne confirme pas (PRINCIPES §3 : jamais un succès supposé, jamais un renvoi).
    public static let nonConfirmee = "La publication n'a pas pu être confirmée par une relecture. Vérifiez vos missions avant de recommencer."
    public static let planningIllisible = "Le planning n'a pas pu être préparé. Vérifiez les dates et les horaires."
    public static let messageErreurGenerique = "La publication n'a pas pu aboutir. Vérifiez votre connexion."

    /// Texte d'une issue non confirmée : le détail de l'erreur s'il existe, puis la consigne de vérification.
    public static func texteNonConfirmee(detail: String?) -> String {
        guard let detail, !detail.isEmpty, detail != nonConfirmee else { return nonConfirmee }
        return "\(detail)\n\(nonConfirmee)"
    }

    /// Options de publication qui restent sur le web (D8). Le titre nomme l'option avec les libellés du web
    /// (`FormulaireMission.tsx` l.694, l.751, l.765, l.767 ; `FormulaireRecurrence.tsx` l.328, l.331-332), le message est
    /// le texte neutre commun ; aucune explication de la raison du renvoi.
    public enum RenvoiWeb: String, CaseIterable, Sendable, Identifiable {
        case liberal, medecin, recurrence, dupliquer

        public var id: String { rawValue }
        public var identifiant: String { "publier-renvoi-web-\(rawValue)" }

        public var titre: String {
            switch self {
            case .liberal: return "Type de contrat proposé : Tous profils ou Libéral"
            case .medecin: return "Profession requise : \(MissionPresentation.professionLabel(PublicationRules.professionRenvoyeeAuWeb))"
            case .recurrence: return "Sélection rapide des dates : Lundi–vendredi, 1 semaine civile sur 2"
            case .dupliquer: return "Dupliquer une mission"
            }
        }

        /// Page web de l'option : le formulaire de publication, ou la liste des missions pour en dupliquer une.
        public var url: URL {
            switch self {
            case .liberal, .medecin, .recurrence: return EtabDestination.publication.urlWeb
            case .dupliquer: return PublicationPresentation.urlWeb("/etablissement/missions")
            }
        }
    }

    // MARK: - URL des renvois (Safari, D16)

    /// Codes de `fn_blocage_publication_etab` dont le web renvoie vers la facturation (`FormulaireMission.tsx` l.658) ;
    /// les autres blocages mènent à l'activation de l'établissement (l.620, l.629).
    static let codesBlocageFacturation: Set<String> = ["PUBLICATION_SUSPENDUE", "FACTURES_IMPAYEES"]

    public static func urlBlocage(code: String) -> URL {
        urlWeb(codesBlocageFacturation.contains(code) ? "/etablissement/facturation" : "/etablissement/activer")
    }

    fileprivate static func urlWeb(_ chemin: String) -> URL {
        // Chemin constant : la construction ne peut pas échouer.
        URL(string: "https://jolene.app\(chemin)")!
    }

    // MARK: - Dates et heures (jour civil de Paris, heure murale)

    /// « Lundi 2 novembre 2026 » (`libelleDate`, première lettre en capitale comme l'en-tête du web) ; la clé telle
    /// quelle si elle est illisible.
    public static func libelleJour(_ date: String) -> String {
        guard let libelle = try? PlanningDerive.libelleDate(date), let initiale = libelle.first else { return date }
        return initiale.uppercased() + libelle.dropFirst()
    }

    /// « Lundi 2 novembre 2026 travaillé » (`aria-label` de la case du web, `FormulaireRecurrence.tsx` l.376).
    public static func libelleJourTravaille(_ date: String) -> String {
        "\(libelleJour(date)) travaillé"
    }

    public static func etatJour(_ actif: Bool) -> String { actif ? jourTravaille : jourRepos }

    /// « Même jour · lun. 2 nov. » (`LigneHoraireJour.tsx` l.81).
    public static func memeJour(_ date: String) -> String {
        "Même jour · \((try? PlanningDerive.libelleDateCourte(date)) ?? date)"
    }

    /// « Lendemain · mar. 3 nov. » (`LigneHoraireJour.tsx` l.82).
    public static func lendemain(_ date: String) -> String {
        let suivant = (try? PlanningDerive.dateFinCreneau(date, finJourSuivant: true)) ?? date
        return "Lendemain · \((try? PlanningDerive.libelleDateCourte(suivant)) ?? suivant)"
    }

    /// Ligne de contrôle d'un créneau saisi (`LigneHoraireJour.tsx` l.96-100) : « lun. 2 nov. 07:00 → lun. 2 nov. 19:00
    /// · 12 h », ou le message d'erreur structurelle du web ; `valide` dit lequel.
    public static func controleCreneau(date: String, creneau: PlanningDerive.Creneau) -> (texte: String, valide: Bool) {
        guard let resultat = try? PlanningDerive.materialiserCreneau(date: date, creneau: creneau) else {
            return (PlanningDerive.messageHeuresInvalides, false)
        }
        guard let valeur = resultat.valeur else { return (resultat.erreur ?? PlanningDerive.messageHeuresInvalides, false) }
        let debut = (try? PlanningDerive.libelleDateCourte(valeur.date)) ?? valeur.date
        let fin = (try? PlanningDerive.libelleDateCourte(valeur.dateFin)) ?? valeur.dateFin
        return ("\(debut) \(creneau.heureDebut) → \(fin) \(creneau.heureFin) · \(CandidaturesEtabPresentation.heures(valeur.dureeHeures)) h", true)
    }

    /// Ligne d'un créneau du récapitulatif (`ModalRecapMission.tsx` l.273-278) :
    /// « lundi 2 novembre 2026 · 07:00 → lundi 2 novembre 2026 · 19:00 ». `nil` sans bornes lisibles.
    public static func ligneRecap(_ creneau: PlanningDerive.CreneauMaterialise) -> String? {
        guard let debut = try? DateHeureParis.instantJolene(creneau.debut),
              let fin = try? DateHeureParis.instantJolene(creneau.fin) else { return nil }
        let masque = "EEEE d MMMM yyyy"
        return "\(DateHeureParis.format(debut, masque)) · \(DateHeureParis.format(debut, "HH:mm")) → "
            + "\(DateHeureParis.format(fin, masque)) · \(DateHeureParis.format(fin, "HH:mm"))"
    }

    /// « 12h00 », « 7h30 » (`ModalRecapMission.tsx` l.262-263).
    public static func duree(heures: Double) -> String {
        guard heures.isFinite, heures >= 0 else { return "0h00" }
        let entieres = Int(heures.rounded(.down))
        let minutes = Int(((heures - Double(entieres)) * 60).rounded())
        return "\(entieres)h" + String(format: "%02d", minutes)
    }

    /// « 25.00 €/h » (`taux.toFixed(2)`, `FormulaireMission.tsx` l.1002) : le taux saisi, seul montant affiché (D15).
    public static func tauxAffiche(_ valeur: Double) -> String {
        String(format: "%.2f €/h", locale: Locale(identifier: "en_US_POSIX"), valeur)
    }

    /// Jour civil de Paris d'un instant (`YYYY-MM-DD`), pour les sélecteurs de date.
    public static func cleJour(_ date: Date) -> String { DateHeureParis.cleJour(date) }

    /// Midi à Paris du jour `cle`, pour afficher la date choisie dans un sélecteur réglé sur le fuseau de Paris.
    public static func dateDuJour(_ cle: String) -> Date? {
        guard PlanningDerive.estDate(cle) else { return nil }
        return try? DateHeureParis.instantDepuisSaisie("\(cle)T12:00")
    }

    /// Fuseau des sélecteurs d'heure : une heure murale sans date, lue et écrite en UTC sur un jour de référence
    /// (aucun changement d'heure). L'heure réelle à Paris est validée par `PlanningDerive.materialiserCreneau`.
    public static let fuseauHeures = TimeZone(identifier: "UTC")!

    /// Instant de référence d'une heure murale `HH:mm` ; `nil` si la saisie est illisible.
    public static func dateDeLHeure(_ heure: String) -> Date? {
        guard PlanningDerive.estHeure(heure) else { return nil }
        let parties = heure.split(separator: ":").compactMap { Int($0) }
        guard parties.count == 2 else { return nil }
        return Date(timeIntervalSinceReferenceDate: TimeInterval(parties[0] * 3_600 + parties[1] * 60))
    }

    /// Heure murale `HH:mm` d'un instant de référence rendu par un sélecteur réglé sur `fuseauHeures`.
    public static func heure(_ date: Date) -> String {
        let secondes = Int(date.timeIntervalSinceReferenceDate.rounded(.down))
        let duJour = ((secondes % 86_400) + 86_400) % 86_400
        return String(format: "%02d:%02d", duJour / 3_600, (duJour % 3_600) / 60)
    }
}
