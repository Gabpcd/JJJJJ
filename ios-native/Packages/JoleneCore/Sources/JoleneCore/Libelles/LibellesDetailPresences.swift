import Foundation

/// Textes du détail des présences, de la notation rapide et des points d'entrée (lot 2, T5a) qui ne peuvent pas être
/// repris tels quels dans `LibellesWeb` : textes que le web tutoie, vouvoyés (décision 9 du lot 1 : seule la personne
/// change), formats numériques du rendu React et textes opérationnels inventoriés dans
/// `docs/mobile-swift/DECISIONS_LOT2.md` (« Textes opérationnels hors web (T5a) »). Garde : `LibellesDetailPresencesTests`
/// relit les sources web. Aucun texte juridique ici (garde `check-textes-juridiques-ios`, `DOSSIERS_LOT2`) : la relance
/// vient de `TextesWeb.Presences`.
public enum LibellesDetailPresences {
    /// Notation rapide au départ final (`NotationRapide.tsx`, `PointageRotatifSoignant.tsx` l.274-281).
    public enum Notation {
        // source: src/components/pointage/PointageRotatifSoignant.tsx:280 (vouvoyé : « ta note »)
        public static let description = "Un tap suffit — votre note aide les autres soignants à choisir leurs missions."

        // source: src/components/NotationRapide.tsx:162 (vouvoyé : « ta note »)
        public static let remerciement = "Merci pour votre note ⭐"

        /// Texte opérationnel (inventorié) : échec d'envoi hors refus serveur. Le web (l.55) ajoute « tu pourras noter
        /// depuis la mission », promesse sans chemin dans l'application (aucune notation depuis le détail natif d'une
        /// mission) ; la feuille reste ouverte, « Envoyer ma note » réessaie.
        public static let erreurEnregistrement = "La note n'a pas pu être enregistrée. Réessayez."

        /// `CRITERES_LABELS.SOIGNANT_VERS_ETAB` (l.31), dans l'ordre de `p_critere_1` … `p_critere_4`.
        public static let criteres = [LibellesWeb.Notation.critereAccueil, LibellesWeb.Notation.critereEncadrement,
                                      LibellesWeb.Notation.critereConsignes, LibellesWeb.Notation.critereAdministratif]

        /// `aria-label` d'une étoile (l.88) : « 1 étoile », « 4 étoiles ».
        public static func etoiles(_ n: Int) -> String {
            String(n) + " " + LibellesWeb.Notation.etoile + (n > 1 ? LibellesWeb.Notation.etoilePluriel : "")
        }
    }

    /// Renvoi web du récapitulatif financier (montants calculés côté client sur le web, non portés : LOT2_PLAN §1.2) :
    /// libellé du lot 1, repris tel quel (`AccueilScreen`, « Voir sur jolene.app »).
    public static let voirSurLeWeb = "Voir sur jolene.app"

    // MARK: - Formats du rendu React

    /// `value.toLocaleString('fr-FR', { minimumFractionDigits: 0, maximumFractionDigits: 2 })` (l.43-45) : deux
    /// décimales au plus, arrondi au plus proche (demi vers le haut, en valeur absolue), zéros finaux retirés, virgule
    /// décimale, groupes de milliers séparés par l'espace fine insécable de la locale `fr-FR`.
    public static func heures(_ valeur: Double) -> String {
        guard valeur.isFinite else { return String(valeur) }
        let centiemes = Int64((abs(valeur) * 100).rounded(.toNearestOrAwayFromZero))
        let entier = centiemes / 100
        let reste = centiemes % 100
        var texte = groupes(entier)
        if reste != 0 {
            var decimales = reste < 10 ? "0" + String(reste) : String(reste)
            while decimales.hasSuffix("0") { decimales.removeLast() }
            texte += "," + decimales
        }
        return (valeur < 0 && centiemes != 0 ? "-" : "") + texte
    }

    /// `Math.round` du web pour un nombre de minutes ou de mètres (demi vers +∞).
    public static func arrondi(_ valeur: Double) -> String {
        String(Int64(SynthesePresence.arrondiJS(valeur)))
    }

    private static func groupes(_ entier: Int64) -> String {
        let chiffres = Array(String(entier))
        var texte = ""
        for (index, chiffre) in chiffres.enumerated() {
            if index > 0, (chiffres.count - index) % 3 == 0 { texte.append("\u{202F}") }
            texte.append(chiffre)
        }
        return texte
    }
}
