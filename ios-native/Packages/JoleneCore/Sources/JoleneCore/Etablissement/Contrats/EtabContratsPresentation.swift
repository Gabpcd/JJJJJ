import Foundation

/// Textes et renvois des contrats de l'espace établissement (lot 5, T10 ; `LOT5_PLAN.md` §3 T10, D16, D18). La liste
/// et la page du contrat réemploient les règles et les textes du lot 2 (`ContratRules`, `ContratPresentation`,
/// `TextesWeb`, `LibellesWeb`), lus pour la partie établissement ; ne vivent ici que les libellés propres à
/// l'établissement et les renvois vers jolene.app de ce que le natif ne porte pas (§1.2) : préparation du CDD par
/// l'employeur, page du certificat. Aucun texte juridique (garde `DOSSIERS_LOT2`) : les textes natifs ci-dessous sont
/// des libellés de navigation, sur le modèle de ceux des candidatures (T6).
public enum EtabContratsPresentation {
    // MARK: - Liste

    /// Titre de la page (`ListeContrats.tsx` l.103).
    public static var titre: String { LibellesWeb.Contrats.titreEtablissement }

    /// État vide de la liste pour le filtre courant (l.126-145, branches `isEtab`).
    public static func etatVide(_ filtre: FiltreContrat) -> (titre: String, message: String) {
        (LibellesWeb.Contrats.titreVide(filtre), LibellesWeb.Contrats.descriptionVideEtablissement(filtre))
    }

    /// Carte d'un contrat vu par l'établissement : « Signer le contrat » tant que l'établissement n'a pas signé.
    public static func carte(_ contrat: ContratResume) -> ContratPresentation.Carte {
        ContratPresentation.carte(contrat, partie: .etablissement)
    }

    /// Entrée « Contrats » de l'onglet Missions (libellé du menu web, `BarreNavigation.tsx` l.117) : aucun onglet
    /// « Contrats » dans la barre (D13) ; masquée sans la permission `contrats` (§2.7).
    public static var entree: String { LibellesWeb.Contrats.titreEtablissement }

    // MARK: - Renvois web (D16 : Safari, reconnexion annoncée)

    /// CDD sans original : la préparation par l'employeur (`PreparationCddEmployeur`) n'est pas portée (§1.2).
    public static let preparerSurJolene = "Préparer le contrat sur jolene.app"
    public static let preparerSurJoleneMessage =
        "La préparation de ce contrat se fait sur jolene.app, où une nouvelle connexion peut vous être demandée."
    /// Page du certificat (`/contrat/:id/certificat`, §1.2) : renvoi web, le résumé reste affiché sur le contrat.
    public static let certificatSurJolene = "Certificat sur jolene.app"

    /// Page web du contrat (`/contrat/:id`) : préparation du CDD, et signature d'un compte TEST sans admission.
    public static func urlContrat(id: String) -> URL? {
        guard identifiantSur(id) else { return nil }
        return EtabDestination.contrat(id: id).urlWeb
    }

    /// Page web du certificat (`/contrat/:id/certificat`).
    public static func urlCertificat(id: String) -> URL? {
        urlContrat(id: id)?.appendingPathComponent("certificat")
    }

    /// Identifiant de contrat présentable dans une URL de renvoi (`[A-Za-z0-9-]`, comme `ContratPresentation.renvoi`).
    private static func identifiantSur(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "-"
        }
    }
}
