import Foundation

/// Section « Adresse » de « Mon profil » (lot 3, T10) : port de `demanderGeolocalisation` et de son bloc
/// (`src/components/profil-soignant/SectionProfilPrincipal.tsx` l.625-643, l.859-877). La position renseigne la ville
/// de recherche (géocodage inverse best-effort, D15) ; elle est enregistrée avec le reste du profil par « Enregistrer
/// les modifications », comme le web. Écart assumé (blueprint §2.6) : les « coordonnées techniques » du web (l.875)
/// ne sont jamais affichées.
public enum ProfilLocalisation {
    /// Textes affichés. Verbatim web (source en commentaire, garde `AvatarLocalisationVerbatimTests`) ; les textes
    /// tutoyés du web, non juridiques, passent au vouvoiement (décision 9 du lot 1, `vouvoiements`) ; pictogrammes
    /// décoratifs (« 📍 ») retirés comme en T9.
    public enum Textes {
        /// l.861.
        public static let titre = "Adresse"
        /// l.871.
        public static let utiliserPosition = "Utiliser ma position actuelle"
        public static let recuperationEnCours = "Récupération en cours…"
        /// l.876, vouvoyé.
        public static let aide = "Utilisez votre position pour renseigner automatiquement votre ville."
        /// l.875, vouvoyé, sans les coordonnées techniques.
        public static let positionEnregistree = "Position enregistrée — votre ville est renseignée ci-dessous."
        /// l.637 (géocodage sans résultat).
        public static let positionRecuperee = "Position récupérée."
        /// l.640, vouvoyé.
        public static let refusee = "Localisation refusée ou indisponible. Vous pouvez saisir votre adresse manuellement."
    }

    /// Textes tutoyés du web et leur forme vouvoyée (décision 9 du lot 1 ; aucun n'est juridique).
    public static let vouvoiements: [(web: String, natif: String)] = [
        ("Utilise ta position pour renseigner automatiquement ta ville.", Textes.aide),
        ("Position enregistrée — ta ville est renseignée ci-dessous.", Textes.positionEnregistree),
        ("Localisation refusée ou indisponible. Tu peux saisir ton adresse manuellement.", Textes.refusee),
    ]

    /// Avis de la localisation : libellé de l'adresse trouvée (`📍 ${adr.label}`, l.635, pictogramme retiré), sinon
    /// « Position récupérée. » ; refus ou indisponibilité → message d'erreur du web.
    public enum Avis: Equatable, Sendable {
        case succes(String)
        case erreur(String)
    }

    /// Avis d'une position obtenue : `adr` présent avec un libellé → le libellé ; sinon « Position récupérée. ».
    /// (Le web afficherait « 📍 » seul pour un libellé vide ; le natif retombe sur le texte sans adresse.)
    public static func avis(adresse: AdresseGeocodee?) -> Avis {
        guard let libelle = adresse?.libelle.trimmingCharacters(in: .whitespacesAndNewlines), !libelle.isEmpty else {
            return .succes(Textes.positionRecuperee)
        }
        return .succes(libelle)
    }
}
