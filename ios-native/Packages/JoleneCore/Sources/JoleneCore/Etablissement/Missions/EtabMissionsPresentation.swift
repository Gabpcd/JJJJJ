import Foundation

/// Textes et lignes de la liste et du détail des missions de l'établissement (lot 5, T5), portés de
/// `src/components/CarteMission.tsx` (carte) et `src/pages/DetailMission.tsx` (détail réellement monté par
/// `/etablissement/missions/:id`, correction 15). Libellés de l'interface, aucun texte juridique ; horaires en
/// heure de Paris (`DateHeureParis`, jetons date-fns) ; **aucun montant** (D15) ni note (D8).
///
/// Planning : la complétude est celle de `CompletudePlanning` (source contractuelle, plus stricte que le web, qui
/// affiche un repli ponctuel sur une carte au planning incomplet) ; un planning non exact est « à confirmer ».
///
/// Liens du détail (registre de T2a) : chaque lien vise une `EtabDestination` ; tant que sa tranche n'a pas livré
/// l'écran (`EtabDestination.ecranLivre`), il ouvre la page web équivalente (renvoi Safari, D16), jamais un écran
/// provisoire. Contrat (T10) : liste native des contrats de l'établissement (l'identifiant du contrat n'est pas lu
/// depuis la mission). Message (T11) : ouvre la conversation de la mission (`ContactSoignantModel`).
/// Chaque lien est soumis à sa permission servie (§2.7, fail-closed).
public enum EtabMissionsPresentation {
    public typealias Badge = MesMissionsPresentation.Badge

    public static let titreErreurListe = "Impossible de charger les missions"
    public static let titreErreurDetail = "Impossible de charger la mission"
    public static let chargerPlus = "Charger plus de missions"
    public static let enAttenteSoignant = "— En attente d'un soignant"
    public static let planningAConfirmer = "Planning détaillé à confirmer"
    public static let creneauIncomplet = "Un créneau incomplet reste à confirmer."
    public static let introuvableTitre = "Mission introuvable"
    public static let introuvableMessage = "Cette mission n'existe pas ou a été supprimée."
    public static let soignantIndisponible = "Soignant indisponible"
    public static let enAttenteSoignantDetail = "En attente d'un soignant"
    public static let enAttenteSoignantAide = "Les soignants qualifiés voient cette mission et peuvent postuler."
    public static let numeroJourMission = "Numéro disponible le jour de la mission"
    public static let nouveauSurJolene = "(nouveau sur Jolene)"
    /// Annonce des renvois web (D16) : la session de l'app n'est pas partagée avec Safari.
    public static let noteRenvoiWeb = "Ces actions s'ouvrent sur jolene.app, où une nouvelle connexion peut vous être demandée."

    // MARK: - Liste

    /// Libellé d'une pastille de filtre : « Ouvertes (3) » ; sans nombre si les compteurs n'ont pas été relus
    /// (jamais un « (0) » supposé).
    public static func libelle(_ filtre: EtabMissionsFiltre, compteurs: EtabMissionsCompteurs?) -> String {
        guard let compteurs else { return filtre.libelle }
        return "\(filtre.libelle) (\(compteurs.nombre(filtre)))"
    }

    /// « 12 missions trouvées » (web l.287) sur la liste affichée.
    public static func nombreTrouvees(_ nombre: Int) -> String {
        "\(nombre) mission\(nombre != 1 ? "s" : "") trouvée\(nombre != 1 ? "s" : "")"
    }

    public struct EtatVide: Equatable, Sendable {
        public var titre: String
        public var message: String
    }

    /// États vides du web (l.325-357) ; l'appel à l'action « Publier » reste le bouton de la barre (D13).
    public static func etatVide(_ filtre: EtabMissionsFiltre, compteurs: EtabMissionsCompteurs?) -> EtatVide {
        if filtre != .toutes {
            return EtatVide(titre: filtre.titreVide, message: "Essayez un autre filtre ou publiez une nouvelle mission.")
        }
        if let compteurs, compteurs.total > 0 {
            return EtatVide(titre: "Aucune mission récente", message: "Vos missions précédentes n'apparaissent pas dans ce filtre.")
        }
        return EtatVide(titre: "Publiez votre première mission", message: "Trouvez un soignant qualifié en quelques heures.")
    }

    /// Carte d'une mission de la liste : chaînes formatées, la vue n'ajoute aucune règle.
    public struct Carte: Equatable, Sendable, Identifiable {
        public var id: String
        public var badges: [Badge]
        public var titre: String
        public var sousTitre: String
        public var periode: String
        public var planning: String
        /// Vrai si le planning n'est pas exact (« Planning détaillé à confirmer », ton d'avertissement).
        public var planningAConfirmer: Bool
        /// « — En attente d'un soignant » pour une mission sans soignant assigné.
        public var soignant: String?

        /// Libellé VoiceOver (et preuve XCUITest) : tout ce que la carte affiche, dans l'ordre.
        public var texteAccessible: String {
            (badges.map(\.texteAccessible) + [titre, sousTitre, periode, planning] + [soignant].compactMap { $0 })
                .joined(separator: ", ")
        }
    }

    /// Port de `CarteMission.tsx` (l.129-300) sans montant ni nom de soignant (lu au détail seulement).
    public static func carte(_ mission: EtabMissionResume, creneaux: [MissionSlot], candidaturesEnAttente: Int?) -> Carte {
        var badges: [Badge] = []
        if mission.estUrgente == true { badges.append(badgeUrgence(mission.niveauUrgence)) }
        badges.append(MesMissionsPresentation.badgeStatut(mission.statut ?? ""))
        if mission.statut == "OUVERTE", let nombre = candidaturesEnAttente, nombre > 0 {
            badges.append(Badge("\(nombre) candidature\(nombre > 1 ? "s" : "") à traiter", ton: .attention))
        }
        badges.append(badgeContrat(mission.typeContratRecherche))
        let analyse = CompletudePlanning.analyser(mission.planningAttendu, creneaux: creneaux)
        let planning: String
        if analyse.complet {
            let nombre = analyse.creneauxPlanifies.count
            planning = "\(nombre) créneau\(nombre > 1 ? "x" : "") · \(duree(analyse.dureeTotaleHeures)) h planifiées"
        } else {
            planning = planningAConfirmer
        }
        let soignant = (mission.soignantAssigneId ?? "").isEmpty ? enAttenteSoignant : nil
        return Carte(id: mission.id, badges: badges, titre: mission.intitule, sousTitre: sousTitre(mission),
                     periode: periode(mission, creneaux: analyse.creneauxPlanifies, moisLong: false),
                     planning: planning, planningAConfirmer: !analyse.complet, soignant: soignant)
    }

    /// « URGENT · critique » (niveau 3), « URGENT · élevé » (2), « URGENT » sinon (web l.208-212).
    public static func badgeUrgence(_ niveau: Int?) -> Badge {
        switch niveau {
        case 3: return Badge("URGENT · critique", ton: .erreur, texteAccessible: "Urgence niveau critique")
        case 2: return Badge("URGENT · élevé", ton: .erreur, texteAccessible: "Urgence niveau élevé")
        default: return Badge("URGENT", ton: .erreur, texteAccessible: "Urgence niveau standard")
        }
    }

    /// Contrat recherché (`getTypeContratRechercheBadge`, `src/lib/constantes.ts` l.116-121).
    public static func badgeContrat(_ type: String?) -> Badge {
        switch type {
        case "LIBERAL": return Badge("🏥 Libéral", ton: .info, texteAccessible: "Libéral")
        case "SALARIE": return Badge("💼 Salarié", ton: .info, texteAccessible: "Salarié")
        default: return Badge("👥 Tous profils", ton: .info, texteAccessible: "Tous profils")
        }
    }

    /// « Soins de suite · Infirmier(e) diplômé(e) d'État » (web l.226-229).
    public static func sousTitre(_ mission: EtabMissionResume) -> String {
        let profession = mission.professionRequise.map(MissionPresentation.professionLabel) ?? ""
        guard let service = mission.service, !service.isEmpty else { return profession }
        return profession.isEmpty ? service : "\(service) · \(profession)"
    }

    /// Période (web carte l.145-148, détail l.1031-1033) : « Période prévue : 3 nov. → 5 nov. 2026 » (ou « Période
    /// active » en cours) si la mission dépasse 24 h ou compte plusieurs créneaux, sinon « mardi 3 novembre 2026 ».
    public static func periode(_ mission: EtabMissionResume, creneaux planifies: [MissionSlot], moisLong: Bool) -> String {
        guard let debutISO = mission.debutLe, let debut = PlanningHorlogeParis.instant(debutISO) else { return "—" }
        let fin = mission.finLe.flatMap(PlanningHorlogeParis.instant)
        let etendue = planifies.count > 1
            || fin.map { DateHeureParis.millisecondes($0) - DateHeureParis.millisecondes(debut) > 24 * 3_600_000 } == true
        guard etendue, let fin else { return DateHeureParis.format(debut, "EEEE d MMMM yyyy") }
        let prefixe = mission.statut == "EN_COURS" ? "Période active" : "Période prévue"
        let masque = moisLong ? "d MMMM yyyy" : "d MMM"
        return "\(prefixe) : \(DateHeureParis.format(debut, masque)) → \(DateHeureParis.format(fin, moisLong ? "d MMMM yyyy" : "d MMM yyyy"))"
    }

    /// `formatDuree` du web : entier tel quel, sinon une décimale à la virgule (« 7,5 »).
    public static func duree(_ heures: Double) -> String {
        guard heures.isFinite else { return "0" }
        if heures.rounded() == heures { return String(Int(heures)) }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), heures).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Détail : planning

    /// Planning du détail (web l.1034-1065).
    public enum PlanningDetail: Equatable, Sendable {
        /// Lecture du planning en échec : message serveur verbatim.
        case indisponible(message: String)
        /// Planning exact : résumé « 3 créneaux · 21 h planifiées au total » et lignes.
        case exact(resume: String, lignes: [String])
        /// Planning non exact : créneaux complets relus (peut être vide), à confirmer.
        case aConfirmer(lignes: [String])
    }

    public static func planning(_ detail: EtabMissionDetail) -> PlanningDetail {
        if let erreur = detail.erreurPlanning { return .indisponible(message: "Planning détaillé momentanément indisponible : \(erreur)") }
        let analyse = CompletudePlanning.analyser(detail.mission.planningAttendu, creneaux: detail.creneaux)
        if analyse.complet {
            let nombre = analyse.creneauxPlanifies.count
            let resume = "\(nombre) créneau\(nombre > 1 ? "x" : "") · \(duree(analyse.dureeTotaleHeures)) h planifiées au total"
            return .exact(resume: resume, lignes: analyse.creneauxPlanifies.compactMap(ligneCreneau))
        }
        let complets = DisponibilitePointage.creneauxPrevisionnels(
            detail.creneaux.filter { $0.typeCreneau == "PREVISIONNEL" && !$0.estPause && $0.finRenseignee != nil })
        return .aConfirmer(lignes: complets.compactMap(ligneCreneau))
    }

    /// « lundi 3 novembre 2026 · 08:00 → 16:00 · 8 h » ; fin un autre jour : « … → mar. 4 nov. · 07:00 · 8 h »
    /// (`formatFinCreneau`, web l.104-108). `nil` sans bornes lisibles.
    public static func ligneCreneau(_ creneau: MissionSlot) -> String? {
        guard let debut = PlanningHorlogeParis.instant(creneau.debut), let finISO = creneau.finRenseignee,
              let fin = PlanningHorlogeParis.instant(finISO) else { return nil }
        let finTexte = DateHeureParis.memeJour(debut, fin) ? DateHeureParis.format(fin, "HH:mm") : DateHeureParis.format(fin, "EEE d MMM · HH:mm")
        let heures = max(0, Double(DateHeureParis.millisecondes(fin) - DateHeureParis.millisecondes(debut)) / 3_600_000)
        return "\(DateHeureParis.format(debut, "EEEE d MMMM yyyy")) · \(DateHeureParis.format(debut, "HH:mm")) → \(finTexte) · \(duree(heures)) h"
    }

    /// « Créée le 2 nov. 2026 à 09:30 » (web l.1166).
    public static func creeLe(_ mission: EtabMissionResume) -> String? {
        guard let iso = mission.creeLe, let date = PlanningHorlogeParis.instant(iso) else { return nil }
        return "Créée le \(DateHeureParis.format(date, "d MMM yyyy 'à' HH:mm"))"
    }

    /// Bandeau « 2 candidatures en attente » (action prioritaire du web l.788-795).
    public static func candidaturesEnAttente(_ nombre: Int?) -> String? {
        guard let nombre, nombre > 0 else { return nil }
        return "\(nombre) candidature\(nombre > 1 ? "s" : "") en attente"
    }

    // MARK: - Détail : soignant

    public struct FicheSoignant: Equatable, Sendable {
        public var nom: String
        public var profession: String?
        public var fiabilite: String?
        public var telephone: String
        public var rpps: String?
    }

    /// Soignant assigné tel que servi (web l.1070-1125) : nom à l'initiale hors relation contractuelle, score de
    /// fiabilité seulement s'il porte sur au moins une mission terminée, téléphone seulement s'il est servi.
    public static func fiche(_ soignant: SoignantPourEtab, statutMission: String?) -> FicheSoignant {
        let nom = [soignant.prenom, soignant.nom].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        let fiabilite: String?
        if let score = soignant.scoreFiabilite, (soignant.totalMissionsTerminees ?? 0) > 0 {
            fiabilite = "\(score)/100 (\(libelleFiabilite(score)))"
        } else if statutMission == "TERMINEE" {
            fiabilite = nil   // « Évaluer ce soignant » : évaluation sur le web (D8)
        } else {
            fiabilite = nouveauSurJolene
        }
        let telephone = soignant.telephone.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let rpps = soignant.numeroRpps.flatMap { $0.isEmpty ? nil : "RPPS : \($0)" }
        return FicheSoignant(nom: nom.isEmpty ? "Soignant" : nom,
                             profession: soignant.profession.map(MissionPresentation.professionLabel),
                             fiabilite: fiabilite, telephone: telephone ?? numeroJourMission, rpps: rpps)
    }

    /// `scoreLabel` du web (l.84-88).
    public static func libelleFiabilite(_ score: Int) -> String {
        if score >= 70 { return "Fiable" }
        if score >= 40 { return "Moyen" }
        return "À surveiller"
    }

    // MARK: - Détail : liens et renvois web

    /// Lien d'un écran voisin, soumis à sa permission ; écran natif livré ou page web équivalente.
    public struct Lien: Equatable, Sendable, Identifiable {
        public enum Cle: String, CaseIterable, Sendable { case candidatures, pointage, presences, contrat, message }
        public enum Cible: Equatable, Sendable {
            case ecran(EtabDestination)
            case web(URL)
            /// Lot 5 (T11) : conversation de la mission obtenue par `fn_obtenir_conversation` (`ContactSoignantModel`),
            /// puis `EtabDestination.conversation(id:)`.
            case contactSoignant(missionId: String, soignantId: String)
        }

        public var cle: Cle
        public var titre: String
        public var detail: String?
        public var cible: Cible

        public var id: String { cle.rawValue }
        public var identifiant: String { "etab-mission-lien-\(cle.rawValue)" }
        public var estWeb: Bool { if case .web = cible { return true } else { return false } }
    }

    /// Action de gestion servie par le web seulement (§1.2) : modification, annulation, duplication.
    public struct ActionWeb: Equatable, Sendable, Identifiable {
        public enum Cle: String, CaseIterable, Sendable { case modifier, annuler, dupliquer }
        public var cle: Cle
        public var titre: String
        public var url: URL

        public var id: String { cle.rawValue }
        public var identifiant: String { "etab-mission-web-\(cle.rawValue)" }
    }

    static let statutsAvecSoignant: Set<String> = ["ASSIGNEE", "EN_COURS", "TERMINEE", "ABSENCE", "LITIGE"]

    /// Liens du détail (web : candidatures l.973, code de pointage l.1347, conversation l.1358 ; présences et contrat
    /// depuis la mission assignée), filtrés par les permissions servies.
    public static func liens(_ detail: EtabMissionDetail, permissions: PermissionsEtab) -> [Lien] {
        let mission = detail.mission
        let statut = mission.statut ?? ""
        let assigne = !(detail.soignantAssigneId ?? mission.soignantAssigneId ?? "").isEmpty
        var liens: [Lien] = []
        if mission.modeAttribution == "CANDIDATURE", statut == "OUVERTE", permissions.candidatures {
            liens.append(lien(.candidatures, "Candidatures", detail: candidaturesEnAttente(detail.candidaturesEnAttente),
                              destination: .candidatures(missionId: mission.id)))
        }
        if statut == "ASSIGNEE" || statut == "EN_COURS", permissions.pointage {
            liens.append(lien(.pointage, "Code de pointage", destination: .pointage(missionId: mission.id)))
        }
        if assigne, ["EN_COURS", "TERMINEE", "ABSENCE", "LITIGE"].contains(statut), permissions.lecture {
            liens.append(lien(.presences, "Présences", destination: .presencesMission(missionId: mission.id)))
        }
        if assigne, permissions.contrats {
            // T10 : liste native des contrats de l'établissement (même cible que le lien web d'avant la tranche,
            // `/etablissement/contrats`) ; le contrat s'y ouvre et s'y signe.
            liens.append(lien(.contrat, "Contrats", destination: .contrats(statut: nil)))
        }
        if assigne, statutsAvecSoignant.contains(statut), permissions.lecture {
            // T11 : conversation de la mission ouverte par `fn_obtenir_conversation` (web l.1083) ; messagerie web tant
            // que l'écran n'est pas livré ou sans soignant assigné lu.
            let soignant = detail.soignantAssigneId ?? mission.soignantAssigneId ?? ""
            if EtabDestination.conversation(id: "").ecranLivre, !soignant.isEmpty {
                // source: src/pages/DetailMission.tsx:1085 (aria-label du bouton)
                liens.append(Lien(cle: .message, titre: "Contacter le soignant", detail: nil,
                                  cible: .contactSoignant(missionId: mission.id, soignantId: soignant)))
            } else {
                liens.append(Lien(cle: .message, titre: "Message au soignant sur jolene.app", detail: nil,
                                  cible: .web(urlWeb("/etablissement/messagerie"))))
            }
        }
        return liens
    }

    /// Actions de gestion du web (barre du bas, l.1463-1500), réservées à la permission `missions` (RLS
    /// `pol_mission_update`) : modifier une mission ouverte, annuler une mission ouverte ou assignée, dupliquer.
    public static func actionsWeb(_ mission: EtabMissionResume, permissions: PermissionsEtab) -> [ActionWeb] {
        guard permissions.missions else { return [] }
        let detail = EtabDestination.detailMission(id: mission.id).cheminWeb
        var actions: [ActionWeb] = []
        if mission.statut == "OUVERTE" {
            actions.append(ActionWeb(cle: .modifier, titre: "Modifier sur jolene.app", url: urlWeb("\(detail)/modifier")))
        }
        actions.append(ActionWeb(cle: .dupliquer, titre: "Dupliquer sur jolene.app",
                                 url: urlWeb("/etablissement/missions/creer?dupliquer=\(composant(mission.id))")))
        if mission.statut == "OUVERTE" || mission.statut == "ASSIGNEE" {
            actions.append(ActionWeb(cle: .annuler, titre: "Annuler sur jolene.app", url: urlWeb(detail)))
        }
        return actions
    }

    private static func lien(_ cle: Lien.Cle, _ titre: String, detail: String? = nil, destination: EtabDestination) -> Lien {
        destination.ecranLivre
            ? Lien(cle: cle, titre: titre, detail: detail, cible: .ecran(destination))
            : Lien(cle: cle, titre: "\(titre) sur jolene.app", detail: detail, cible: .web(destination.urlWeb))
    }

    private static func urlWeb(_ chemin: String) -> URL {
        // Chemin construit depuis des segments encodés : la construction ne peut pas échouer.
        URL(string: "https://jolene.app\(chemin)")!
    }

    /// `encodeURIComponent` (caractères non réservés de RFC 3986).
    private static func composant(_ valeur: String) -> String {
        let nonReserves = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return valeur.addingPercentEncoding(withAllowedCharacters: nonReserves) ?? ""
    }
}
