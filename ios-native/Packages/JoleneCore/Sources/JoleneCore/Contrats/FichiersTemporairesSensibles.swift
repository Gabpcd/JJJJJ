import Foundation

/// Copies temporaires sensibles écrites pour le partage ou l'impression : contrats (`FichierContratTemporaire`) et
/// copies de bulletins (`FichierCopieBulletinTemporaire`). Revue B8 sécurité de l'intégration de la vague D (m6) : les
/// deux dossiers sont purgés au lancement (un arrêt brutal pendant un partage laisse sa copie), à la disparition de
/// l'espace soignant comme de l'espace établissement, donc à la déconnexion et à tout changement d'epoch. Les copies
/// restent par ailleurs effacées à la fermeture de leur feuille ou de leur lecteur.
public enum FichiersTemporairesSensibles {
    /// Dossiers purgés.
    public static func dossiers() -> [URL] {
        [FichierContratTemporaire.dossier(), FichierCopieBulletinTemporaire.dossier()]
    }

    /// Efface toutes les copies des deux dossiers ; sans effet si elles n'existent pas.
    public static func purger() {
        FichierContratTemporaire.effacerTout()
        FichierCopieBulletinTemporaire.effacerTout()
    }
}
