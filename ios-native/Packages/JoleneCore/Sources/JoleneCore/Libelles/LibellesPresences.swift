import Foundation

/// Textes de la page Présences (lot 2, T4a) qui ne peuvent pas être repris tels quels dans `LibellesWeb` : textes que le
/// web tutoie, vouvoyés (décision 9 du lot 1 ; seule la personne change, comme la décision 6 du lot 2), assemblages
/// (dates, durées, compteurs, ordre et séparateurs du rendu React, fragments pris dans `LibellesWeb`) et textes
/// opérationnels inventoriés dans `docs/mobile-swift/DECISIONS_LOT2.md` (« Textes opérationnels hors web (T4a) »).
/// Garde : `LibellesPresencesTests` relit les sources web. Aucun texte juridique ici (garde `check-textes-juridiques-ios`,
/// `DOSSIERS_LOT2`) : le bandeau « à valider » vient de `TextesWeb.Presences`.
public enum LibellesPresences {
    /// Page et onglets (`PresencesSoignant.tsx`).
    public enum Liste {
        // source: src/pages/PresencesSoignant.tsx:515 (vouvoyé : « Pointe tes »)
        public static let sousTitre = "Pointez vos arrivées et départs pour chaque mission"

        // source: src/pages/PresencesSoignant.tsx:467 (vouvoyé : « tes »)
        public static let erreurTitre = "Impossible de charger vos présences"

        // source: src/pages/PresencesSoignant.tsx:565 (vouvoyé : « Tes »)
        public static let videAVenirDescription = "Vos prochaines missions assignées apparaîtront ici."

        // source: src/pages/PresencesSoignant.tsx:588 (vouvoyé : « Tes »)
        public static let videActivesDescription = "Vos missions actives apparaîtront ici, même entre deux créneaux."

        // source: src/pages/PresencesSoignant.tsx:611 (vouvoyé : « Tes »)
        public static let videAujourdhuiDescription = "Vos missions assignées apparaîtront ici le jour J pour le pointage."

        // source: src/pages/PresencesSoignant.tsx:764 (vouvoyé : « Ton »)
        public static let videHistoriqueDescription = "Votre historique de pointages apparaîtra ici."

        /// Coupe-circuit `ios_natif_presences_actif` à faux (D-FLAGS ; seconde revue fraîche de T4b, m3) : page Présences
        /// remplacée par un renvoi web. Texte du lot 0 (`MobileAccess.unsupportedRole`), repris tel quel, comme
        /// `LibellesJustificatifs.espaceNonDisponible` (T7).
        public static var ecranNonDisponible: String {
            MobileAccess.unsupportedRole(nil).message ?? ""
        }

        /// Libellé vocalisé du compteur de l'onglet « À venir » (l.520) : « <n> mission(s) à venir ».
        public static func badgeAVenir(_ nombre: Int) -> String {
            let web = LibellesWeb.ListePresences.self
            return String(nombre) + " " + web.badgeMission + (nombre > 1 ? web.badgePluriel : "") + " " + web.badgeAVenir
        }

        /// `etablissements?.nom || 'Établissement'` (l.546, l.690 ; `BlocPointageMission.tsx` l.65).
        public static func etablissement(_ etablissement: EtablissementSummary?) -> String {
            let nom = etablissement?.nom ?? ""
            return nom.isEmpty ? LibellesWeb.ListePresences.etablissement : nom
        }

        /// Nom puis « · ville » quand la ville est connue (l.546).
        public static func etablissementEtVille(_ etablissement: EtablissementSummary?) -> String {
            let ville = etablissement?.adresseVille ?? ""
            return self.etablissement(etablissement) + (ville.isEmpty ? "" : " " + LibellesWeb.ListePresences.separateurVille + " " + ville)
        }

        /// Horaire d'une mission à venir (l.552-553) : « 08h00 → 16h00 (8h) », durée omise quand elle est absente ou
        /// nulle (`dureeAffichageHeures ?`), écrite comme un nombre JavaScript ; nil si une borne est illisible.
        public static func horaire(debut: String?, fin: String?, dureeHeures: Double?) -> String? {
            guard let debut = lire(debut), let fin = lire(fin) else { return nil }
            let web = LibellesWeb.ListePresences.self
            var texte = DateHeureParis.format(debut, "HH'h'mm") + " " + web.fleche + " " + DateHeureParis.format(fin, "HH'h'mm")
            if let dureeHeures, dureeHeures != 0, dureeHeures.isFinite {
                texte += " " + web.parentheseDuree + nombreJS(dureeHeures) + web.uniteDuree
            }
            return texte
        }

        /// Pavé de date d'une mission à venir (`EEE`, `d`, `MMM`, l.536-539), même forme que l'Accueil.
        public static func jour(_ dateAffichage: String?) -> AccueilPresentation.Jour? {
            guard let date = lire(dateAffichage) else { return nil }
            return AccueilPresentation.Jour(semaine: DateHeureParis.format(date, "EEE"), jour: DateHeureParis.format(date, "d"),
                                            mois: DateHeureParis.format(date, "MMM"))
        }

        /// `BadgeStatut` (`BADGES_STATUT` de `constantes.ts`), comme l'Accueil.
        public static func statut(_ code: String) -> String {
            AccueilPresentation.statut(code)
        }

        /// Date de validation d'une présence validée récemment (`d MMM yyyy 'à' HH:mm`, l.635).
        public static func dateValidation(_ valideLe: String?) -> String? {
            lire(valideLe).map { DateHeureParis.format($0, "d MMM yyyy 'à' HH:mm") }
        }
    }

    /// Motifs du bloc de pointage (`BlocPointageMission.tsx` l.72-127).
    public enum Bloc {
        // source: src/components/pointage/BlocPointageMission.tsx:105 (vouvoyé : « Contacte », « te déplacer »)
        public static let aucunHoraire = "Aucun horaire de présence n'est enregistré pour cette mission. Contactez l'établissement avant de vous déplacer."

        /// Titre en gras puis lignes d'explication, dans l'ordre du web.
        public struct Textes: Equatable, Sendable {
            public let titre: String
            public let details: [String]

            public init(titre: String, details: [String]) { self.titre = titre; self.details = details }
        }

        /// Textes d'un bloc non pointable ; nil pour un bloc pointable (la zone de pointage de T4b les remplace).
        public static func textes(_ affichage: BlocPointageAffichage) -> Textes? {
            let web = LibellesWeb.BlocPointage.self
            switch affichage {
            case .pointable:
                return nil
            case let .contratNonSigne(_, prochainAutreJour):
                var details = [web.contratDoitEtreSigne]
                if let prochainAutreJour {
                    details.append(web.prochainCreneauAutreJour + " " + jourEtHeure(prochainAutreJour) + web.point)
                }
                return Textes(titre: web.contratNonSigne, details: details)
            case .aucunCreneau:
                return Textes(titre: web.aucunCreneauPlanifie, details: [aucunHoraire])
            case let .pasEncoreOuvert(debut):
                return Textes(titre: web.pasEncoreOuvert, details: [
                    web.ouvrira + " " + String(DisponibilitePointage.fenetreOuvertureMinutes) + " " + web.minutesAvant + " "
                        + DateHeureParis.format(debut, "HH'h'mm") + web.point,
                ])
            case let .aucunAujourdhui(prochain):
                let detail = prochain.map { web.prochainCreneau + " " + jourEtHeure($0) + web.point } ?? web.tousTermines
                return Textes(titre: web.aucunCreneauAujourdhui, details: [detail])
            }
        }

        /// `formatParis(date, "EEEE d MMMM 'à' HH'h'mm")` (l.87, l.119).
        static func jourEtHeure(_ date: Date) -> String {
            DateHeureParis.format(date, "EEEE d MMMM 'à' HH'h'mm")
        }
    }

    /// Ligne de l'onglet Historique (`PresencesSoignant.tsx` l.486-491, l.684-758).
    public enum Ligne {
        /// `getMethodeLabel` (l.486-491) : vide → « — », GPS, code (rotatif ou QR), sinon la valeur telle quelle.
        public static func methode(_ code: String?) -> String {
            let web = LibellesWeb.LignePresence.self
            guard let code, !code.isEmpty else { return web.aucuneValeur }
            switch code {
            case "GPS": return web.methodeGps
            case "CODE", "CODE_ROTATIF", "QR": return web.methodeCode
            default: return code
            }
        }

        /// Arrivée ou départ (`d MMM · HH'h'mm`, l.710, l.715), « — » sans date.
        public static func horodatage(_ date: Date?) -> String {
            date.map { DateHeureParis.format($0, "d MMM · HH'h'mm") } ?? LibellesWeb.LignePresence.aucuneValeur
        }

        /// Heures travaillées (l.680-682, l.720) : `toFixed(1)` puis « h », « — » sans valeur.
        public static func heures(_ heures: Double?) -> String {
            guard let heures else { return LibellesWeb.LignePresence.aucuneValeur }
            return toFixed1(heures) + LibellesWeb.LignePresence.uniteHeures
        }

        /// Date de la mission (`d MMM yyyy`, l.692) ; nil sans date lisible.
        public static func dateMission(_ debutLe: String?) -> String? {
            lire(debutLe).map { DateHeureParis.format($0, "d MMM yyyy") }
        }

        /// `Number.prototype.toFixed(1)` : l'entier n le plus proche de 10 × la valeur binaire exacte, le plus grand en
        /// cas d'égalité (ECMA-262), signe à part. `printf` arrondit au pair aux seules égalités exactes, c'est-à-dire
        /// quand 4 × |x| est un entier impair (0,25, 0,75, 1,25…) : ces cas sont arrondis vers le haut ici.
        static func toFixed1(_ valeur: Double) -> String {
            guard valeur.isFinite else { return String(valeur) }
            let absolu = abs(valeur)
            let quart = absolu * 4
            if quart == quart.rounded(.towardZero), quart.truncatingRemainder(dividingBy: 2) == 1 {
                let arrondi = (absolu * 10).rounded(.up) / 10
                return (valeur < 0 ? "-" : "") + String(format: "%.1f", arrondi)
            }
            return String(format: "%.1f", valeur)
        }
    }

    /// Section « Mon espace » du Profil (décision 24 du lot 2).
    public enum EspaceSoignant {
        /// Texte opérationnel (aucun équivalent web : le web n'a pas de section qui regroupe ces pages), inventorié.
        public static let titreSection = "Mon espace"
    }

    /// Zone de pointage d'une mission (lot 2, T4b ; `PointageRotatifSoignant.tsx`). Libellés repris tels quels :
    /// `LibellesWeb.Pointage` ; ici la surcharge vouvoyée du code inconnu (décision 6), les textes opérationnels
    /// inventoriés dans `docs/mobile-swift/DECISIONS_LOT2.md` (« Textes opérationnels hors web (T4b) ») et les
    /// assemblages (issues du modèle, segments, « En service depuis »). Les textes de consentement viennent de `TextesWeb`
    /// (HARD STOP n°4), par `retourConsentement(_:)`. Les textes provisoires de T4a (`Provisoire`) sont retirés.
    public enum Pointage {
        // source: src/components/pointage/PointageRotatifSoignant.tsx:136 (vouvoyé : « Demande », décision 6)
        public static let codeInvalide = "Code de pointage invalide ou expiré. Demandez le code actuel à l’établissement."

        /// Texte opérationnel (`PointageModel.Issue.verification` : réponse perdue, réconciliation par relecture en cours).
        public static let verification = "Vérification du pointage…"

        /// Texte opérationnel (`.nonRecu` : relecture prouvant l'absence du scan ; le code a pu tourner).
        public static let nonRecu = "Le pointage n'a pas été reçu. Saisissez le code actuellement affiché par l'établissement."

        /// Texte opérationnel (`.horsLigne` : aucun appel, reçu `not_sent`, décision 2 ; blueprint §2.5).
        public static let horsLigne = "Pointage impossible sans connexion."

        /// Texte opérationnel (`.enregistreSurAutreMission` : le code saisi désignait une autre mission, revue de T3 M-A).
        public static let autreMission = "Ce code était celui d'une autre de vos missions : le pointage y a été enregistré."

        /// Texte opérationnel (décision 5 : précision réduite, aucune coordonnée envoyée, encart « Position exacte »).
        public static let positionApproximative = "Position approximative : le pointage a été envoyé sans position. Pour la joindre, activez « Position exacte » pour Jolene dans les réglages de localisation de l'appareil."

        /// Texte opérationnel : fermeture de la feuille du scanner de QR (le dialogue web se ferme par sa croix).
        public static let fermer = "Fermer"

        /// Renvoi web d'un suivi non vérifiable (`PresencesRenvois.presences`), texte du lot 1 (`AccueilScreen.swift`).
        public static let voirSurJolene = "Voir sur jolene.app"

        /// Bloc de session expirée de la zone (`AffichageZonePointage.sessionAVerifier`, revue fraîche de T4b, M1) : textes
        /// du lot 1 (`MissionsListScreen.swift` l.107-108, `PresencesScreen`), repris tels quels, comme T7
        /// (`LibellesJustificatifs.sessionAVerifier`).
        public static let sessionAVerifier = "Session à vérifier"
        public static let verifierMaSession = "Vérifier ma session"
        public static let messageSessionExpiree = SessionController.sessionExpiredMessage

        /// Ton d'un retour, porté par l'icône de l'encart (jamais par la couleur seule).
        public enum Ton: Equatable, Sendable {
            case succes, info, attention, erreur
        }

        /// Retour affiché sous le bouton d'action.
        public struct Message: Equatable, Sendable {
            public let texte: String
            public let ton: Ton
            /// Précision opérationnelle (scan enregistré sur une autre mission).
            public let detail: String?
            /// Bouton de renvoi web `/soignant/presences` (suivi non vérifiable, consigne T3).
            public let renvoiWeb: Bool

            public init(texte: String, ton: Ton, detail: String? = nil, renvoiWeb: Bool = false) {
                self.texte = texte; self.ton = ton; self.detail = detail; self.renvoiWeb = renvoiWeb
            }
        }

        /// Texte de chaque issue du modèle (consigne T4b de `DECISIONS_LOT2.md`) : succès du web (l.164), refus serveur
        /// verbatim sauf la surcharge du code inconnu, textes des reçus (`RecuScan`), textes opérationnels ci-dessus.
        public static func message(_ issue: PointageModel.Issue) -> Message {
            let web = LibellesWeb.Pointage.self
            switch issue {
            case let .enregistre(type):
                return Message(texte: type == .ouverture ? web.enregistreOuvert : web.enregistreFerme, ton: .succes)
            case let .enregistreSurAutreMission(type, _):
                return Message(texte: type == .ouverture ? web.enregistreOuvert : web.enregistreFerme, ton: .succes,
                               detail: autreMission)
            case let .refuse(message, codeInvalide):
                return Message(texte: codeInvalide ? self.codeInvalide : message, ton: .erreur)
            case .horsLigne:
                return Message(texte: horsLigne, ton: .attention)
            case .verification:
                return Message(texte: verification, ton: .info)
            case .nonRecu:
                return Message(texte: nonRecu, ton: .attention)
            case .recuEnCours:
                return Message(texte: RecuScan.messageRecuEnCours, ton: .attention)
            case .suiviIllisible:
                return Message(texte: RecuScan.messageIllisible, ton: .erreur, renvoiWeb: true)
            case let .erreur(message):
                return Message(texte: message, ton: .erreur)
            }
        }

        /// Libellé du bouton (l.106-108).
        public static func action(_ action: PointageRules.ActionAffichee) -> String {
            let web = LibellesWeb.Pointage.self
            switch action {
            case .departOuPause: return web.pointerDepartOuPause
            case .arriveeOuReprise: return web.pointerArriveeOuReprise
            case .arrivee: return web.pointerArrivee
            }
        }

        /// Consigne sous le titre (l.210-212).
        public static func consigne(segmentOuvert: Bool) -> String {
            segmentOuvert ? LibellesWeb.Pointage.consigneDepart : LibellesWeb.Pointage.consigne
        }

        /// « En service depuis 23h00 » (l.204) ; nil si le début du segment est illisible.
        public static func enService(depuis debut: String) -> String? {
            lire(debut).map { LibellesWeb.Pointage.enServiceDepuis + " " + DateHeureParis.format($0, "HH'h'mm") }
        }

        /// Ligne d'un segment (l.259-269).
        public struct LigneSegment: Equatable, Sendable {
            public let titre: String
            public let horaire: String

            public init(titre: String, horaire: String) { self.titre = titre; self.horaire = horaire }
        }

        /// « Segment n » puis le début (`d MMM · HH'h'mm` sur plusieurs jours, sinon `HH'h'mm`) et « → fin » ou
        /// « → en cours » ; nil si une borne est illisible (le web lèverait).
        public static func segment(numero: Int, _ segment: SegmentPointage, plusieursJours: Bool) -> LigneSegment? {
            let web = LibellesWeb.Pointage.self
            guard let debut = lire(segment.debut) else { return nil }
            var horaire = DateHeureParis.format(debut, plusieursJours ? "d MMM · HH'h'mm" : "HH'h'mm") + " "
            if let finTexte = segment.fin, !finTexte.isEmpty {
                guard let fin = lire(finTexte) else { return nil }
                horaire += LibellesWeb.ListePresences.fleche + " " + DateHeureParis.format(fin, "HH'h'mm")
            } else {
                horaire += web.enCours
            }
            return LigneSegment(titre: web.segment + " " + String(numero), horaire: horaire)
        }

        /// Retour de la feuille de consentement et de l'interrupteur du Profil : textes de `TextesWeb` (HARD STOP n°4),
        /// ou message levé par le port.
        public static func retourConsentement(_ retour: ConsentementGpsModel.Retour) -> String {
            switch retour {
            case .enregistre: return TextesWeb.Presences.consentementGpsEnregistre
            case .sansGps: return TextesWeb.Presences.pointageSansGpsActive
            case let .bascule(actif): return TextesWeb.ProfilConsentementGps.retourBascule(consentementActif: actif)
            case let .echec(message): return message
            }
        }

        /// Ton du retour : notifications du web (`succes` / `info`, `PresencesSoignant.tsx` l.76, l.95 ;
        /// `SectionPreferences.tsx` l.159), erreur pour un échec.
        public static func tonConsentement(_ retour: ConsentementGpsModel.Retour) -> Ton {
            switch retour {
            case .enregistre: return .succes
            case .sansGps: return .info
            case let .bascule(actif): return actif ? .succes : .info
            case .echec: return .erreur
            }
        }

        /// Encart après un pointage dont la position n'a pas pu être jointe faute de précision (décision 5).
        public static func encartPosition(_ observation: ObservationGps?) -> String? {
            observation == .precisionReduite ? positionApproximative : nil
        }
    }

    /// `String(n)` de JavaScript pour une durée : entier sans décimale, sinon l'écriture la plus courte qui relit la
    /// même valeur (même règle que `Double.description` pour les ordres de grandeur d'une durée).
    static func nombreJS(_ valeur: Double) -> String {
        if valeur == valeur.rounded(), abs(valeur) < 1e15 { return String(Int64(valeur)) }
        return String(valeur)
    }

    private static func lire(_ valeur: String?) -> Date? {
        guard let valeur, !valeur.isEmpty else { return nil }
        return try? DateHeureParis.instantJolene(valeur)
    }
}
