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

    /// Textes provisoires, inventoriés : retirés par la tranche qui livre l'écran (T4b pointage, T7 justificatifs —
    /// retiré à l'intégration de T7 —, T9a contrats), qui migre aussi les identifiants des XCUITest. Même forme que
    /// l'onglet provisoire du lot 0.
    public enum Provisoire {
        public static let etat = "Disponible au lot 2"
        public static let contrats = "Vos contrats arrivent dans l'application avec la suite du lot 2."
        public static let pointage = "Le pointage dans l'application arrive avec la suite du lot 2."
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
