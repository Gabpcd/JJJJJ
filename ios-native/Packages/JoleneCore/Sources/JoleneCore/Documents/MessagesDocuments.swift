import Foundation

/// Messages des justificatifs levés par les ports (lot 2 T6). Aucun texte nouveau : chaque message est celui du web,
/// repris tel quel ou vouvoyé quand le web tutoie (décision 9 du lot 1 ; seule la personne du verbe change, comme la
/// décision 6 du lot 2). Garde : `MessagesDocumentsTests` relit les sources web. Les libellés d'écran (statuts, badges,
/// bandeaux) relèvent de T7 ; les textes juridiques (attestation) de `Legal/TextesWeb.swift`.
public enum MessagesDocuments {
    // source: src/pages/DocumentsSoignant.tsx:218 (tel quel)
    public static let chargementImpossible = "Vos documents sont temporairement indisponibles. Vérifiez votre connexion puis réessayez."

    // source: src/pages/DocumentsSoignant.tsx:402 (vouvoyé : « Vérifie », « réessaie »)
    public static let enregistrementImpossible = "Le document ne peut pas être enregistré. Vérifiez son format puis réessayez."

    // source: src/pages/DocumentsSoignant.tsx:315 (vouvoyé : « Vérifie ») ; repli de `messageErreurEdgeFn` sans `error`
    public static let verificationImpossible = "Le document n'a pas pu être vérifié. Vérifiez le type de document et sa lisibilité."

    // source: src/pages/DocumentsSoignant.tsx:329 (tel quel)
    public static let reverificationErreur = "Erreur lors de la revérification."

    // source: src/pages/DocumentsSoignant.tsx:347 (vouvoyé : « Actualise », « réessaie »), `DOCUMENT_INTROUVABLE`
    public static let revueDocumentIntrouvable = "Ce document a été remplacé ou supprimé. Actualisez la page puis réessayez avec le document actif."

    // source: src/pages/DocumentsSoignant.tsx:349 (tel quel), `MOTIF_INVALIDE`
    public static let revueMotifInvalide = "Le motif de la demande est trop court."

    /// Motif envoyé à `fn_demander_revue_document` (jamais affiché). source: src/pages/DocumentsSoignant.tsx:342
    public static let motifRevue = "Contestation du verdict automatique depuis l’espace Documents"

    // source: src/pages/DocumentsSoignant.tsx:52 (tel quel)
    public static let signatureAttestationErreur = "Erreur lors de la signature. Veuillez réessayer."

    // source: src/pages/DocumentsSoignant.tsx:459 (tel quel)
    public static let consultationImpossible = "Impossible d’ouvrir le document"

    // source: src/lib/erreurs.ts:571 (repli de `messageErreurEdgeFn`, tel quel)
    public static let erreurGenerique = "Une erreur est survenue. Veuillez réessayer."
}
