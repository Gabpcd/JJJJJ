import JoleneCore

/// Issue d'un sélecteur de média (appareil photo, photothèque, Fichiers ou variante démo), remise à la feuille de
/// téléversement. Les octets ne vivent qu'en mémoire (décision 14).
enum IssueSelection: Sendable {
    case choisi(FichierSelectionne)
    /// Sélection fermée sans fichier : aucun envoi, aucun message.
    case annule
    /// Sélecteur inaccessible ou fichier illisible : message du web de la source (`ModalTeleversement.tsx` l.106, l.158).
    case echec
}

/// Variante démo des sélecteurs (blueprint §2.2, §2.8) : rend, sans interface système, le fichier fictif choisi par
/// `-JOLENE_DEMO_SOURCE_DOC` (DEBUG), comme l'aurait rendu le sélecteur touché (`origine` décide de la normalisation).
/// Posée par `AppContainer` en mode démo seulement ; l'appareil photo, la photothèque et Fichiers ne sont pas pilotables
/// en XCUITest et sont prouvés sur appareil (P8).
struct DemoMediaPicker: Sendable {
    let source: SourceDocumentDemo

    func choisir(_ origine: SourceFichier) -> IssueSelection {
        source.fichier(origine: origine).map(IssueSelection.choisi) ?? .annule
    }
}
