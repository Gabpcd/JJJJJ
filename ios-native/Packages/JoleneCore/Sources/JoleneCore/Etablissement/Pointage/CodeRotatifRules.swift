import Foundation

/// Affichage du code de pointage rotatif côté établissement (lot 5, T3), port pur de
/// `src/components/pointage/AffichageCodeRotatifEtab.tsx` : association d'un segment EFFECTIF à
/// son créneau (`trouverCreneauAssocie`, l.49-70), durée d'un segment (l.72-78), décision
/// d'affichage (l.166-314) et lignes des pointages enregistrés (l.316-328), sur
/// `DisponibilitePointage.evaluerDisponibilitePointage` et `CompletudePlanning`.
///
/// Le code n'est montré que si le serveur le servirait au pointage : mission ASSIGNEE ou
/// EN_COURS, planning complet, contrat signé par les deux parties, dans la fenêtre du créneau
/// (15 minutes avant son début) ; un segment déjà ouvert garde toujours le code de sortie. En
/// plus du web, et avant toute autre règle, le natif masque le code à un membre sans la
/// permission `pointage` (blueprint lot 5 §2.7 : `fn_etat_pointage_mission` le renvoie à tout
/// membre, correction 4). Le code change à chaque scan (correction 18) : la valeur affichée est
/// toujours celle de la dernière lecture, jamais une valeur calculée.
///
/// Écart assumé : là où le web lève sur une date illisible (rendu interrompu), le port échoue
/// fermé (aucun créneau associé, libellé brut).
public enum CodeRotatifRules {
    /// Segment de présence renvoyé par `fn_etat_pointage_mission` (`segments[]`).
    public struct Segment: Codable, Equatable, Hashable, Sendable {
        public var id: String
        public var debut: String
        public var fin: String?

        public init(id: String, debut: String, fin: String?) {
            self.id = id; self.debut = debut; self.fin = fin
        }
    }

    /// Réponse de `fn_etat_pointage_mission` utile à l'affichage. `erreur` porte un refus jsonb
    /// (`{ error: 'Mission introuvable' | 'Accès interdit' }`). Décodage tolérant : `segments`
    /// absent vaut `[]`, `segment_ouvert` absent vaut `false`.
    public struct Etat: Codable, Equatable, Sendable {
        public var statut: String?
        public var prochainTypeScan: String?
        public var segmentOuvert: Bool
        public var segments: [Segment]
        public var codePointageActif: String?
        public var erreur: String?

        public init(statut: String?, prochainTypeScan: String?, segmentOuvert: Bool, segments: [Segment],
                    codePointageActif: String?, erreur: String? = nil) {
            self.statut = statut; self.prochainTypeScan = prochainTypeScan; self.segmentOuvert = segmentOuvert
            self.segments = segments; self.codePointageActif = codePointageActif; self.erreur = erreur
        }

        enum CodingKeys: String, CodingKey {
            case statut, segments
            case prochainTypeScan = "prochain_type_scan"
            case segmentOuvert = "segment_ouvert"
            case codePointageActif = "code_pointage_actif"
            case erreur = "error"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            statut = try c.decodeIfPresent(String.self, forKey: .statut)
            prochainTypeScan = try c.decodeIfPresent(String.self, forKey: .prochainTypeScan)
            segmentOuvert = try c.decodeIfPresent(Bool.self, forKey: .segmentOuvert) ?? false
            segments = try c.decodeIfPresent([Segment].self, forKey: .segments) ?? []
            codePointageActif = try c.decodeIfPresent(String.self, forKey: .codePointageActif)
            erreur = try c.decodeIfPresent(String.self, forKey: .erreur)
        }
    }

    /// Planning lu pour le pointage (web l.97-133) : indisponible si une lecture a échoué
    /// (mission, créneaux, signature illisible), sinon les créneaux planifiés retenus par
    /// `CompletudePlanning`, la complétude et la signature des deux parties
    /// (`fn_contrat_signe_pour_pointage`).
    public enum Planning: Equatable, Sendable {
        case indisponible
        case charge(creneaux: [MissionSlot], complet: Bool, contratSigne: Bool)

        /// Analyse de complétude du web (l.122-130).
        public static func depuis(mission: MissionAvecPlanningAttendu, creneaux: [MissionSlot], contratSigne: Bool) -> Planning {
            let analyse = CompletudePlanning.analyser(mission, creneaux: creneaux)
            return .charge(creneaux: analyse.creneauxPlanifies, complet: analyse.complet, contratSigne: contratSigne)
        }
    }

    /// Créneau annoncé au-dessus du code : « Créneau i/n · <date> à <heure> → <heure> ».
    public struct CreneauActif: Equatable, Sendable {
        /// Rang à partir de 1 (0 si le créneau n'est pas retrouvé, comme `indexOf + 1` du web).
        public var rang: Int
        public var total: Int
        public var creneau: MissionSlot
        public var libelle: String

        public init(rang: Int, total: Int, creneau: MissionSlot, libelle: String) {
            self.rang = rang; self.total = total; self.creneau = creneau; self.libelle = libelle
        }
    }

    /// Code présenté au soignant (chiffres groupés et QR de la valeur brute).
    public struct CodeVisible: Equatable, Sendable {
        /// Valeur brute de `code_pointage_actif`, encodée telle quelle dans le QR (D4).
        public var valeur: String
        /// « 123 456 ».
        public var chiffres: String
        /// « Arrivée », « Reprise (fin de pause) » ou « Départ ou pause ».
        public var prochainPointage: String
        /// `segment_ouvert` du serveur : badge « Segment en cours ».
        public var segmentEnCours: Bool

        public init(valeur: String, chiffres: String, prochainPointage: String, segmentEnCours: Bool) {
            self.valeur = valeur; self.chiffres = chiffres; self.prochainPointage = prochainPointage; self.segmentEnCours = segmentEnCours
        }
    }

    /// Ce que l'écran rend.
    public struct Affichage: Equatable, Sendable {
        public enum Bloc: Equatable, Sendable {
            /// Membre sans la permission `pointage` : aucun code (`messageReservePointage`).
            case reservePointage
            /// État serveur illisible ou refusé : `titreIndisponible` + message + « Réessayer ».
            case indisponible(message: String)
            /// Mission hors ASSIGNEE / EN_COURS : rien à afficher.
            case aucun
            /// Planning indisponible ou incomplet sans segment ouvert : `titreMasque` + message.
            case planningInutilisable(message: String)
            /// Code présenté.
            case code(CodeVisible)
            /// Pointage possible mais code absent de la lecture.
            case momentanementIndisponible
            /// Hors créneau ou contrat non signé.
            case masque(titre: String, detail: String)
        }

        public var bloc: Bloc
        public var creneauActif: CreneauActif?

        public init(bloc: Bloc, creneauActif: CreneauActif?) {
            self.bloc = bloc; self.creneauActif = creneauActif
        }

        public var codeVisible: CodeVisible? {
            if case .code(let code) = bloc { return code }
            return nil
        }

        /// Valeur brute du code effectivement présentée, `nil` dès qu'il est masqué.
        public var codeAffiche: String? { codeVisible?.valeur }
    }

    /// Ligne « Pointages enregistrés ».
    public struct LigneSegment: Equatable, Sendable {
        public var id: String
        public var libelle: String
        public var duree: String

        public init(id: String, libelle: String, duree: String) {
            self.id = id; self.libelle = libelle; self.duree = duree
        }
    }

    // MARK: - Textes repris du web (non juridiques)

    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:172
    public static let titreIndisponible = "Code de pointage indisponible"
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:174
    public static let messageEtatIndisponible = "Impossible de charger l’état du pointage."
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:207
    public static let titreMasque = "Code masqué"
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:210
    public static let messagePlanningIndisponible = "Le planning détaillé est momentanément indisponible. Réessayez avant de présenter un code au soignant."
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:211
    public static let messagePlanningIncomplet = "Le planning détaillé est incomplet ou ne correspond pas au nombre de créneaux prévu. Confirmez-le avant de présenter un code d’arrivée."
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:250
    public static let libelleReprise = "Reprise (fin de pause)"
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:250
    public static let libelleArrivee = "Arrivée"
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:251
    public static let libelleDepartOuPause = "Départ ou pause"
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:260
    public static let libelleChangeAChaqueScan = "change à chaque scan"
    /// Suivie du libellé du prochain pointage puis d'un point (web l.267-268).
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:267
    public static let consignePresentation = "Montrez ce code (ou le QR) au soignant à chaque pointage. Prochain pointage attendu :"
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:288
    public static let libelleSegmentEnCours = "Segment en cours"
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:293
    public static let messageMomentanementIndisponible = "Code momentanément indisponible. Actualisez dans quelques secondes."
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:300
    public static let titreMasqueContrat = "Code masqué — contrat non signé"
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:300
    public static let titreMasqueHorsCreneau = "Code masqué hors créneau"
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:304
    public static let detailContratNonSigne = "Le code d’arrivée sera disponible lorsque le contrat aura été signé par les deux parties."
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:306
    public static let detailAucunCreneau = "Aucun créneau détaillé n’est planifié pour cette mission. Le code sera disponible après confirmation du planning."
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:309
    public static let detailTousTermines = "Tous les créneaux planifiés sont terminés."
    // source: src/components/pointage/AffichageCodeRotatifEtab.tsx:318
    public static let titreSegments = "Pointages enregistrés"
    /// Texte natif (blueprint lot 5 §2.7), sans équivalent web : le web ne filtre pas par permission.
    public static let messageReservePointage = "Code réservé aux membres habilités au pointage"

    /// Statuts de mission pour lesquels un code est affiché (web l.182).
    public static let statutsAffiches: Set<String> = ["ASSIGNEE", "EN_COURS"]

    private static let masqueDateHeure = "EEEE d MMMM yyyy à HH:mm"
    private static let masqueSegment = "dd/MM/yyyy HH'h'mm"

    // MARK: - Décision d'affichage (l.166-314)

    /// Décide ce que l'écran établissement rend pour `etat` (dernière lecture de
    /// `fn_etat_pointage_mission`, `nil` si elle a échoué), le planning lu et la permission
    /// `pointage` de `fn_mes_permissions_etab`, à l'instant `maintenant`.
    public static func affichage(etat: Etat?, planning: Planning, autoriseAuPointage: Bool, maintenant: Date) -> Affichage {
        guard autoriseAuPointage else { return Affichage(bloc: .reservePointage, creneauActif: nil) }
        guard let etat else { return Affichage(bloc: .indisponible(message: messageEtatIndisponible), creneauActif: nil) }
        if let erreur = etat.erreur, !erreur.isEmpty { return Affichage(bloc: .indisponible(message: erreur), creneauActif: nil) }
        guard let statut = etat.statut, statutsAffiches.contains(statut) else { return Affichage(bloc: .aucun, creneauActif: nil) }

        let segmentsOuverts = etat.segments.filter { ($0.fin ?? "").isEmpty }.map {
            MissionSlot(id: $0.id, debut: $0.debut, fin: $0.fin, estPause: false, typeCreneau: "EFFECTIF")
        }
        let departToujoursPossible = !segmentsOuverts.isEmpty

        let creneauxPlanning: [MissionSlot]
        let contratStatut: String?
        let planningUtilisable: Bool
        let planningLu: Bool
        switch planning {
        case .indisponible:
            creneauxPlanning = []; contratStatut = nil; planningUtilisable = false; planningLu = false
        case .charge(let creneaux, let complet, let contratSigne):
            creneauxPlanning = creneaux; contratStatut = contratSigne ? "SIGNE_COMPLET" : nil
            planningUtilisable = complet; planningLu = true
        }
        // Une arrivée n'est jamais autorisée depuis un planning incomplet ; un départ reste
        // possible lorsqu'un EFFECTIF est déjà ouvert.
        if !planningUtilisable && !departToujoursPossible {
            return Affichage(bloc: .planningInutilisable(message: planningLu ? messagePlanningIncomplet : messagePlanningIndisponible),
                             creneauActif: nil)
        }

        let planifies = DisponibilitePointage.creneauxPrevisionnels(creneauxPlanning)
        let disponibilite = DisponibilitePointage.evaluerDisponibilitePointage(
            creneaux: creneauxPlanning + segmentsOuverts, contratStatut: contratStatut, maintenant: maintenant
        )
        let code = etat.codePointageActif ?? ""
        let afficherCode = !code.isEmpty && disponibilite.peutPointer

        let creneauActif: MissionSlot?
        if let segmentOuvert = segmentsOuverts.first {
            creneauActif = trouverCreneauAssocie(planifies, debutEffectif: segmentOuvert.debut)
        } else {
            creneauActif = disponibilite.creneauCourant
        }
        let actif = creneauActif.flatMap { annonce($0, planifies: planifies) }

        if afficherCode {
            let visible = CodeVisible(valeur: code, chiffres: formatCode(code),
                                      prochainPointage: prochainPointage(etat: etat, planifies: planifies,
                                                                         creneauCourant: disponibilite.creneauCourant, maintenant: maintenant),
                                      segmentEnCours: etat.segmentOuvert)
            return Affichage(bloc: .code(visible), creneauActif: actif)
        }
        if disponibilite.peutPointer { return Affichage(bloc: .momentanementIndisponible, creneauActif: actif) }

        let titre = disponibilite.motif == .contrat ? titreMasqueContrat : titreMasqueHorsCreneau
        let detail: String
        if disponibilite.motif == .contrat {
            detail = detailContratNonSigne
        } else if planifies.isEmpty {
            detail = detailAucunCreneau
        } else if let prochain = disponibilite.prochainCreneau, prochain.finRenseignee != nil {
            let rang = (planifies.firstIndex(of: prochain) ?? -1) + 1
            detail = "Le code sera affiché \(DisponibilitePointage.fenetreOuvertureMinutes) minutes avant le créneau \(rang)/\(planifies.count), le \(formater(prochain.debut, masqueDateHeure))."
        } else {
            detail = detailTousTermines
        }
        return Affichage(bloc: .masque(titre: titre, detail: detail), creneauActif: actif)
    }

    /// « Créneau i/n · … » (l.272-278), seulement pour un créneau dont la fin est connue.
    private static func annonce(_ creneau: MissionSlot, planifies: [MissionSlot]) -> CreneauActif? {
        guard let fin = creneau.finRenseignee,
              let debutDate = try? DateHeureParis.instantJolene(creneau.debut),
              let finDate = try? DateHeureParis.instantJolene(fin) else { return nil }
        let rang = (planifies.firstIndex(of: creneau) ?? -1) + 1
        let libelle = "Créneau \(rang)/\(planifies.count) · \(DateHeureParis.format(debutDate, masqueDateHeure)) → \(DateHeureParis.format(finDate, "HH:mm"))"
        return CreneauActif(rang: rang, total: planifies.count, creneau: creneau, libelle: libelle)
    }

    /// Libellé du prochain pointage (l.236-251) : une ouverture est une « reprise » si le dernier
    /// segment fermé date du même jour et appartient au créneau courant, sinon une « arrivée ».
    private static func prochainPointage(etat: Etat, planifies: [MissionSlot], creneauCourant: MissionSlot?, maintenant: Date) -> String {
        guard etat.prochainTypeScan == "OUVERTURE" else { return libelleDepartOuPause }
        let fermes = triStable(etat.segments.filter { !($0.fin ?? "").isEmpty }) { temps($0.debut) }
        guard let dernier = fermes.last, let creneauCourant,
              let debutDernier = try? DateHeureParis.instantJolene(dernier.debut),
              DateHeureParis.memeJour(debutDernier, maintenant),
              let creneauDuDernier = trouverCreneauAssocie(planifies, debutEffectif: dernier.debut),
              creneauDuDernier == creneauCourant else { return libelleArrivee }
        return libelleReprise
    }

    // MARK: - Association et formats

    /// Créneau planifié qui contient le début d'un segment EFFECTIF (fin exclusive : à l'heure
    /// exacte où un second shift démarre, il est choisi), sinon celui dont le début est le plus
    /// proche (l.49-70). `nil` si le début du segment est illisible ou s'il n'y a aucun créneau.
    public static func trouverCreneauAssocie(_ planifies: [MissionSlot], debutEffectif: String) -> MissionSlot? {
        let effectif = temps(debutEffectif)
        guard effectif.isFinite else { return nil }
        if let contenant = planifies.first(where: { creneau in
            guard let fin = creneau.finRenseignee else { return false }
            return effectif >= temps(creneau.debut) && effectif < temps(fin)
        }) {
            return contenant
        }
        return triStable(planifies) { abs(temps($0.debut) - effectif) }.first
    }

    /// « 123 456 » (`slice(0, 3) + ' ' + slice(3)`).
    public static func formatCode(_ code: String) -> String {
        "\(code.prefix(3)) \(code.dropFirst(3))"
    }

    /// Durée d'un segment, arrondie à la minute (`dureeSegment`, l.72-78) : « 4h00 », « 45 min ».
    /// Un segment ouvert court jusqu'à `maintenant`. Début illisible : « — » (le web afficherait
    /// « NaN min »).
    public static func dureeSegment(debut: String, fin: String?, maintenant: Date) -> String {
        let d = temps(debut)
        let f: Double
        if let fin, !fin.isEmpty { f = temps(fin) } else { f = Double(DateHeureParis.millisecondes(maintenant)) }
        guard d.isFinite, f.isFinite else { return "—" }
        let minutes = Int(max(0, CalendrierCivil.arrondiJS((f - d) / 60_000)))
        let heures = minutes / 60
        return heures > 0 ? "\(heures)h\(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }

    /// Lignes « Segment i · dd/MM/yyyy HHhmm → … » dans l'ordre du serveur (l.316-328).
    public static func lignesSegments(_ segments: [Segment], maintenant: Date) -> [LigneSegment] {
        segments.enumerated().map { index, segment in
            let fin = segment.fin.flatMap { $0.isEmpty ? nil : $0 }
            let suite = fin.map { " → \(formater($0, masqueSegment))" } ?? " → en cours"
            return LigneSegment(id: segment.id,
                                libelle: "Segment \(index + 1) · \(formater(segment.debut, masqueSegment))\(suite)",
                                duree: dureeSegment(debut: segment.debut, fin: fin, maintenant: maintenant))
        }
    }

    // MARK: - Outils

    /// `formatParis(iso, masque)` ; la chaîne brute si elle est illisible.
    private static func formater(_ iso: String, _ masque: String) -> String {
        guard let date = try? DateHeureParis.instantJolene(iso) else { return iso }
        return DateHeureParis.format(date, masque)
    }

    /// Millisecondes, NaN si illisible (les comparaisons avec NaN sont fausses).
    private static func temps(_ iso: String) -> Double {
        guard let date = try? DateHeureParis.instantJolene(iso) else { return .nan }
        return Double(DateHeureParis.millisecondes(date))
    }

    /// Tri stable croissant par clé numérique (`Array.prototype.sort`) ; NaN garde son rang.
    private static func triStable<T>(_ elements: [T], cle: (T) -> Double) -> [T] {
        elements.enumerated().sorted { a, b in
            let ka = cle(a.element), kb = cle(b.element)
            if ka < kb { return true }
            if kb < ka { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}
